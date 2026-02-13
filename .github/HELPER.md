# HELPER.md

## Cel dokumentu
Ten dokument opisuje **dokladnie aktualny stan wdrozenia helpera uprzywilejowanego** w projekcie `macUSB`.
Celem jest to, aby nowa sesja Codex mogla odtworzyc to wdrozenie od zera (z punktu startowego: stary tryb terminalowy) bez zgadywania i bez petli prob i bledow.

Dokument obejmuje:
- architekture helpera,
- konfiguracje `macUSB.xcodeproj` (targety, build phases, signing, entitlements),
- implementacje IPC i workflow,
- integracje UI,
- lifecycle helpera (install/register/status/repair/unregister),
- diagnostyke i checklisty,
- znane ograniczenia na obecnym etapie.

---

## Aktualny stan (na teraz)
1. Workflow helpera dziala poprawnie dla scenariuszy `createinstallmedia` (przyklad: Yosemite).
2. Helper jest pakietowany i uruchamiany jako LaunchDaemon przez `SMAppService`.
3. Dziala obsluga statusu helpera i naprawy helpera z GUI.
4. Dziala nowe okno postepu naprawy helpera z live logiem krokow naprawczych.
5. Live-log techniczny z workflow helpera nie jest renderowany jako osobny panel na ekranie instalacji; jest logowany do `AppLogging` (kategoria `HelperLiveLog`) i trafia do eksportu logow.
6. Pozostaje otwarty temat: Tiger (PPC/asr) potrafi wywalic sie na etapie walidacji `asr`.

---

## Architektura: co zostalo wdrozone

### 1) Model runtime
Aplikacja (`macUSB`) jest procesem UI. Operacje uprzywilejowane wykonuje osobny proces helpera (`macUSBHelper`) uruchamiany przez `launchd` jako LaunchDaemon.

Komunikacja app <-> helper odbywa sie przez XPC (Mach service):
- nazwa Mach service: `com.kruszoneq.macusb.helper`
- protokol RPC helpera: `PrivilegedHelperToolXPCProtocol`
- callback do aplikacji: `PrivilegedHelperClientXPCProtocol`

### 2) SMAppService + LaunchDaemon
Rejestracja helpera odbywa sie przez:
- `SMAppService.daemon(plistName: "com.kruszoneq.macusb.helper.plist")`
- `register()` / `unregister()`
- statusy: `.enabled`, `.requiresApproval`, `.notRegistered`, `.notFound`

Plik LaunchDaemon jest w app bundle:
- `Contents/Library/LaunchDaemons/com.kruszoneq.macusb.helper.plist`

Binarna helpera jest w app bundle:
- `Contents/Library/Helpers/macUSBHelper`

### 3) Integracja UI
UI instalacji pokazuje:
- pasek postepu,
- procent,
- nazwe etapu,
- status etapu.

Nie ma osobnego panelu live-log dla workflow instalacyjnego na ekranie instalacji.
Logi techniczne ida do `AppLogging`.

Dodatkowo jest GUI do operacji serwisowych helpera w menu Narzedzia:
- `Status helpera`
- `Napraw helpera`
- `Usun helpera`

---

## Mapa plikow helpera i ich rola

### Pliki projektu i konfiguracji
1. `macUSB.xcodeproj/project.pbxproj`
- definicja targetu `macUSBHelper` (tool),
- target dependency app -> helper,
- copy phases dla helper binary i launchdaemon plist,
- ustawienia signing/entitlements/debug/release dla app i helpera.

2. `macUSB/Resources/LaunchDaemons/com.kruszoneq.macusb.helper.plist`
- deklaracja Label, MachServices, BundleProgram,
- powiazanie z `com.kruszoneq.macUSB`.

3. `macUSBHelper/macUSBHelper.debug.entitlements`
- helper Debug: `com.apple.security.get-task-allow = true`.

4. `macUSBHelper/macUSBHelper.release.entitlements`
- helper Release: `com.apple.security.get-task-allow = false`.
- bardzo wazne: **brak restricted entitlements** typu `com.apple.application-identifier` i `com.apple.developer.team-identifier`.

5. `macUSB/macUSB.debug.entitlements`
- app Debug: `com.apple.security.automation.apple-events = true`, `get-task-allow = true`.

6. `macUSB/macUSB.release.entitlements`
- app Release: `com.apple.security.automation.apple-events = true`, `get-task-allow = false`.

### Pliki kodu helpera i klienta
7. `macUSB/Shared/Services/Helper/HelperIPC.swift`
- wspolne typy IPC,
- `HelperWorkflowRequestPayload`,
- `HelperProgressEventPayload`,
- `HelperWorkflowResultPayload`,
- protokoly XPC,
- codec JSON ISO8601.

8. `macUSB/Shared/Services/Helper/PrivilegedOperationClient.swift`
- klient NSXPC,
- start/cancel workflow,
- health-check,
- timeouty,
- mapowanie eventow i completion,
- logowanie `logLine` do `AppLogging` (`HelperLiveLog`).

9. `macUSB/Shared/Services/Helper/HelperServiceManager.swift`
- bootstrap startup,
- ensure-ready flow,
- register/unregister/recover,
- status helpera,
- naprawa helpera,
- nowe okno postepu naprawy (spinner + log).

10. `macUSBHelper/main.swift`
- serwis helpera,
- listener XPC,
- wykonawca workflow etapowego,
- uruchamianie `diskutil`, `asr`, `createinstallmedia`, `ditto`, `xattr`, itp,
- progres + logLine,
- cancel i raport wyniku.

11. `macUSB/Features/Installation/CreatorHelperLogic.swift`
- wejscie z UI do trybu helper,
- przygotowanie request payload,
- aktualizacja postepu UI,
- anulowanie workflow helpera,
- fallback do starego terminal flow w Debug kill-switch.

12. `macUSB/Features/Installation/UniversalInstallationView.swift`
- stany UI helpera:
  - `isTerminalWorking`
  - `helperProgressPercent`
  - `helperStageTitle`
  - `helperStatusText`
- UI z paskiem postepu/procentem/etapem/status.

13. `macUSB/App/macUSBApp.swift`
- bootstrap helper readiness przy starcie app,
- pozycje menu: status/napraw/usun helpera.

14. `macUSB/Shared/Services/Logging.swift`
- bufor logow,
- eksport logow,
- kategorie m.in. `HelperLiveLog`, `HelperService`, `Installation`.

---

## Konfiguracja `project.pbxproj` (dokladnie)

## 1) Target graph
App target `macUSB` ma dependency na `macUSBHelper`:
- `PBXTargetDependency` app -> helper

Znaczy to, ze helper buduje sie razem z app i trafia do bundla app.

## 2) Copy phases w app target
W `macUSB` sa 2 istotne `PBXCopyFilesBuildPhase`:

1. `dstPath = Contents/Library/Helpers`
- kopiuje produkt helpera `macUSBHelper` do app bundle.

2. `dstPath = Contents/Library/LaunchDaemons`
- kopiuje `com.kruszoneq.macusb.helper.plist` do app bundle.

To jest krytyczne dla `SMAppService.daemon(plistName:)`.

## 3) Target `macUSBHelper`
- `productType = com.apple.product-type.tool`
- `PRODUCT_BUNDLE_IDENTIFIER = com.kruszoneq.macusb.helper`
- `GENERATE_INFOPLIST_FILE = YES`
- `CREATE_INFOPLIST_SECTION_IN_BINARY = YES`
- `MACOSX_DEPLOYMENT_TARGET = 14.6`
- `ENABLE_HARDENED_RUNTIME = YES`
- `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`
- `ENTITLEMENTS_REQUIRED = NO`
- `SKIP_INSTALL = YES`

### Signing helpera Debug
- `CODE_SIGN_STYLE = Automatic`
- `CODE_SIGN_IDENTITY = Apple Development`
- `CODE_SIGN_ENTITLEMENTS = macUSBHelper/macUSBHelper.debug.entitlements`
- `DEVELOPMENT_TEAM = 27NC66L8P2`

### Signing helpera Release
- `CODE_SIGN_STYLE = Manual`
- `CODE_SIGN_IDENTITY = Developer ID Application`
- `CODE_SIGN_ENTITLEMENTS = macUSBHelper/macUSBHelper.release.entitlements`
- `DEVELOPMENT_TEAM = 27NC66L8P2`
- `PROVISIONING_PROFILE_SPECIFIER = ""`

## 4) Target `macUSB` (app)
- `PRODUCT_BUNDLE_IDENTIFIER = com.kruszoneq.macUSB`
- `ENABLE_APP_SANDBOX = NO`
- `ENABLE_HARDENED_RUNTIME = YES`
- `MACOSX_DEPLOYMENT_TARGET = 14.6`

### Signing app Debug
- `CODE_SIGN_STYLE = Automatic`
- `CODE_SIGN_IDENTITY = Apple Development`
- `CODE_SIGN_ENTITLEMENTS = macUSB/macUSB.debug.entitlements`
- `DEVELOPMENT_TEAM = 27NC66L8P2`
- `PROVISIONING_PROFILE_SPECIFIER = ""`

### Signing app Release
- `CODE_SIGN_STYLE = Manual`
- `CODE_SIGN_IDENTITY = Developer ID Application`
- `CODE_SIGN_ENTITLEMENTS = macUSB/macUSB.release.entitlements`
- `DEVELOPMENT_TEAM = 27NC66L8P2`
- `PROVISIONING_PROFILE_SPECIFIER = ""`

## 5) Spojnosc podpisywania
Spojnosc opiera sie na:
- wspolnym Team ID (`27NC66L8P2`) dla app i helper,
- zgodnym trybie certyfikatow per konfiguracja:
  - Debug: Apple Development,
  - Release: Developer ID Application,
- braku restricted entitlements w helperze.

To eliminuje klase bledow AMFI typu:
- `No matching profile found`
- `Restricted entitlements not validated`
- `OS_REASON_EXEC` przy starcie helpera.

## 6) Surowe fragmenty `project.pbxproj` (referencja 1:1)
Ponizej sa najwazniejsze wpisy, ktore musza istniec po migracji.

### Copy phases app target
```pbxproj
A10000012F00000100000008 /* CopyFiles */ = {
    isa = PBXCopyFilesBuildPhase;
    dstPath = Contents/Library/Helpers;
    dstSubfolderSpec = 1;
    files = (
        A10000012F00000100000002 /* macUSBHelper in CopyFiles */,
    );
};
A10000012F00000100000009 /* CopyFiles */ = {
    isa = PBXCopyFilesBuildPhase;
    dstPath = Contents/Library/LaunchDaemons;
    dstSubfolderSpec = 1;
    files = (
        A10000012F00000100000003 /* ...com.kruszoneq.macusb.helper.plist in CopyFiles */,
    );
};
```

### Build phases app target
```pbxproj
buildPhases = (
    0F94F4A12EDE3E510019F69A /* Sources */,
    0F94F4A22EDE3E510019F69A /* Frameworks */,
    0F94F4A32EDE3E510019F69A /* Resources */,
    A10000012F00000100000008 /* CopyFiles */,
    A10000012F00000100000009 /* CopyFiles */,
);
dependencies = (
    A10000012F0000010000000F /* PBXTargetDependency */,
);
```

### Build settings helper Debug
```pbxproj
CODE_SIGN_ENTITLEMENTS = macUSBHelper/macUSBHelper.debug.entitlements;
CODE_SIGN_IDENTITY = "Apple Development";
"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";
CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;
CODE_SIGN_STYLE = Automatic;
CREATE_INFOPLIST_SECTION_IN_BINARY = YES;
DEVELOPMENT_TEAM = 27NC66L8P2;
ENABLE_HARDENED_RUNTIME = YES;
ENTITLEMENTS_REQUIRED = NO;
GENERATE_INFOPLIST_FILE = YES;
MACOSX_DEPLOYMENT_TARGET = 14.6;
PRODUCT_BUNDLE_IDENTIFIER = com.kruszoneq.macusb.helper;
SKIP_INSTALL = YES;
```

### Build settings helper Release
```pbxproj
CODE_SIGN_ENTITLEMENTS = macUSBHelper/macUSBHelper.release.entitlements;
CODE_SIGN_IDENTITY = "Developer ID Application";
"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Developer ID Application";
CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;
CODE_SIGN_STYLE = Manual;
CREATE_INFOPLIST_SECTION_IN_BINARY = YES;
DEVELOPMENT_TEAM = 27NC66L8P2;
ENABLE_HARDENED_RUNTIME = YES;
ENTITLEMENTS_REQUIRED = NO;
GENERATE_INFOPLIST_FILE = YES;
MACOSX_DEPLOYMENT_TARGET = 14.6;
PRODUCT_BUNDLE_IDENTIFIER = com.kruszoneq.macusb.helper;
PROVISIONING_PROFILE_SPECIFIER = "";
SKIP_INSTALL = YES;
```

### Build settings app Debug
```pbxproj
CODE_SIGN_ENTITLEMENTS = macUSB/macUSB.debug.entitlements;
CODE_SIGN_IDENTITY = "Apple Development";
"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";
CODE_SIGN_STYLE = Automatic;
DEVELOPMENT_TEAM = 27NC66L8P2;
ENABLE_APP_SANDBOX = NO;
ENABLE_HARDENED_RUNTIME = YES;
INFOPLIST_FILE = macUSB/Info.plist;
MACOSX_DEPLOYMENT_TARGET = 14.6;
PRODUCT_BUNDLE_IDENTIFIER = com.kruszoneq.macUSB;
PROVISIONING_PROFILE_SPECIFIER = "";
```

### Build settings app Release
```pbxproj
CODE_SIGN_ENTITLEMENTS = macUSB/macUSB.release.entitlements;
CODE_SIGN_IDENTITY = "Developer ID Application";
"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Developer ID Application";
CODE_SIGN_STYLE = Manual;
DEVELOPMENT_TEAM = 27NC66L8P2;
ENABLE_APP_SANDBOX = NO;
ENABLE_HARDENED_RUNTIME = YES;
INFOPLIST_FILE = macUSB/Info.plist;
MACOSX_DEPLOYMENT_TARGET = 14.6;
PRODUCT_BUNDLE_IDENTIFIER = com.kruszoneq.macUSB;
PROVISIONING_PROFILE_SPECIFIER = "";
```

---

## LaunchDaemon plist (co i dlaczego)
Plik: `macUSB/Resources/LaunchDaemons/com.kruszoneq.macusb.helper.plist`

Wazne klucze:
- `Label = com.kruszoneq.macusb.helper`
- `AssociatedBundleIdentifiers = [com.kruszoneq.macUSB]`
- `BundleProgram = Contents/Library/Helpers/macUSBHelper`
- `MachServices/com.kruszoneq.macusb.helper = true`
- `RunAtLoad = true`
- `KeepAlive = false`

Znaczenie:
- launchd wie jak uruchomic helpera z bundla aplikacji,
- XPC laczy sie po nazwie Mach service,
- helper nie musi byc stale keep-alive (startuje na zadanie).

---

## IPC kontrakt (dokladnie)
Plik: `macUSB/Shared/Services/Helper/HelperIPC.swift`

### Request: `HelperWorkflowRequestPayload`
Pola:
- `workflowKind`: `standard | legacyRestore | mavericks | ppc`
- `systemName`
- `sourcePath`
- `targetVolumePath`
- `targetBSDName`
- `targetLabel`
- `needsPreformat`
- `isCatalina`
- `requiresApplicationPathArg`
- `postInstallSourceAppPath`
- `requesterUID`

### Event: `HelperProgressEventPayload`
- `workflowID`
- `stageKey`
- `stageTitle`
- `percent`
- `statusText`
- `logLine` (zostaje w IPC, ale nie jest renderowany jako osobna lista logow na ekranie instalacji)
- `timestamp`

### Result: `HelperWorkflowResultPayload`
- `workflowID`
- `success`
- `failedStage`
- `errorCode`
- `errorMessage`
- `isUserCancelled`

### Protokoly
- app -> helper: `startWorkflow`, `cancelWorkflow`, `queryHealth`
- helper -> app: `receiveProgressEvent`, `finishWorkflow`

Codec:
- JSONEncoder/Decoder,
- daty ISO8601.

---

## Helper runtime (`macUSBHelper/main.swift`) - szczegoly

## 1) Listener XPC
Helper uruchamia:
- `NSXPCListener(machServiceName: "com.kruszoneq.macusb.helper")`
- `dispatchMain()`

## 2) Serwis helpera
`PrivilegedHelperService` trzyma:
- jeden aktywny workflow (`activeWorkflowID`, `activeExecutor`),
- serial queue `macUSB.helper.service`.

Reguly:
- tylko 1 workflow naraz (kolejny dostaje `409`).
- `queryHealth` zwraca `uid/euid/pid` helpera.

## 3) Budowanie etapow
`HelperWorkflowExecutor.buildStages()` tworzy pipeline zaleznie od `workflowKind`:

### `standard`
- opcjonalnie preformat (`diskutil partitionDisk ... GPT HFS+`),
- `createinstallmedia --volume ... [--applicationpath ...] --nointeraction`,
- dla Cataliny dodatkowo:
  - cleanup (`rm -rf`),
  - copy (`ditto`),
  - usuniecie kwarantanny (`xattr -dr ...`),
- finalizacja (`/usr/bin/true`).

### `legacyRestore`
- `asr imagescan --source ...`
- `asr restore --source ... --target ... --erase --noprompt --noverify`

### `mavericks`
- analogicznie do legacyRestore.

### `ppc`
- `diskutil partitionDisk ... APM HFS+ PPC 100%`
- `asr restore --source ... --target /Volumes/PPC --erase --noverify --noprompt --verbose`

## 4) Uruchamianie polecen i kontekst usera
W `runStage`:
- jezeli `requesterUID > 0`, helper uruchamia komendy jako:
  - `/bin/launchctl asuser <uid> <cmd> ...`
- inaczej bezposrednio.

## 5) Parsowanie postepu
- helper czyta stdout+stderr z `Pipe`,
- szuka procentow regexem `([0-9]{1,3}(?:\.[0-9]+)?)%`,
- mapuje procent narzedzia do przedzialu etapu (`startPercent..endPercent`).

## 6) Blad i diagnostyka
Na niezerowym exit code:
- blad zawiera ostatnia linie output,
- jezeli wykryje "operation not permitted" / "operacja nie jest dozwolona", dopisuje wskazowke o podpisie/team/install.

## 7) Cancel
- `terminate()` procesu,
- po 5s fallback `kill(SIGKILL)` jesli proces nadal zyje.

---

## Klient XPC (`PrivilegedOperationClient`) - szczegoly

## 1) Polaczenie
- `NSXPCConnection(machServiceName: ..., options: .privileged)`
- ustawione `remoteObjectInterface` + `exportedInterface` + `exportedObject`

## 2) Timeouty
- start reply timeout: 10s,
- health timeout: domyslnie 5s (mozliwy custom timeout).

## 3) Recovery
- `resetConnectionForRecovery()` invaliduje i czyisci connection.

## 4) Invalidation/interruption
Gdy polaczenie zrywa sie:
- aktywne workflow dostaje synthetic result:
  - `success = false`,
  - `failedStage = xpc_connection`,
  - `errorMessage = ...`.

## 5) Logowanie live-log
`receiveProgressEvent`:
- jesli event ma `logLine`, trafia do:
  - `AppLogging.info(..., category: "HelperLiveLog")`.

To zapewnia eksport logow technicznych bez panelu live-log w UI instalacji.

---

## Menedzer helpera (`HelperServiceManager`) - szczegoly

## 1) Startup bootstrap
`bootstrapIfNeededAtStartup`:
- Debug + Xcode dev build => bypass `true` (nie blokuje startu app),
- w innych scenariuszach odpala ensure-ready non-interactive.

Wywolanie startupu:
- `macUSB/App/macUSBApp.swift` -> `applicationDidFinishLaunching`.

## 2) Wymaganie lokalizacji app
`ensureReadyForPrivilegedWork`:
- Release: wymaga `/Applications/...`.
- Debug: bypass gdy uruchomione z Xcode (`DerivedData/.../Build/Products`).

Komunikat ostrzegawczy:
- tytul zawiera `/Applications`,
- opis mowi o katalogu `Applications` (bez ukosnika w tresci).

## 3) Status helpera
`presentStatusAlert()`:
- blokuje rownolegly check,
- pokazuje mini panel "Sprawdzanie statusu...",
- czyta status SMAppService i health XPC,
- pokazuje alert z wynikiem.

## 4) Ensure-ready flow
- kolejkuje requesty i deduplikuje rownolegly ensure,
- obsluguje statusy `enabled/requiresApproval/notRegistered/notFound`.

### `enabled`
- robi health-check XPC,
- gdy fail: reset XPC + retry,
- gdy nadal fail: procedura `recoverRegistrationAfterHealthFailure`.

### `notRegistered/notFound`
- `register()` + walidacja statusu + health.

### `requiresApproval`
- alert + opcja otwarcia settings (`SMAppService.openSystemSettingsLoginItems()`).

## 5) Naprawa helpera (menu)
`repairRegistrationFromMenu()`:
- blokuje rownolegle naprawy,
- otwiera panel postepu naprawy (nowe GUI),
- resetuje lokalne polaczenie XPC,
- uruchamia ensure-ready interactive,
- zamyka etap i finalizuje panel (status success/error).

## 6) Usuwanie helpera
`unregisterFromMenu()`:
- gdy helper nieaktywny -> informacja "juz usuniety",
- inaczej `unregister()` + podsumowanie.

## 7) Logowanie serwisowe helpera
Kazdy krok ensure/register/recovery/status trafia do:
- `AppLogging` kategoria `HelperService`,
- oraz do panelu naprawy (jesli jest aktywny).

---

## Nowe GUI naprawy helpera

W `HelperServiceManager` dodano panel `NSPanel`:
- tytul: "Naprawa helpera",
- ikona `lock.shield.fill`,
- status line (kolor neutral/green/red),
- spinner podczas pracy,
- scrollowany log (monospace, timestampy),
- przycisk "Zamknij" aktywny dopiero po zakonczeniu.

Panel jest celowo odseparowany od glownego UI instalacji i sluzy diagnostyce operacji serwisowej helpera.

---

## Integracja z flow tworzenia USB

Plik: `macUSB/Features/Installation/CreatorHelperLogic.swift`

## 1) Wejscie do flow
`startCreationProcessEntry()`:
- Debug kill-switch:
  - klucz: `Debug.UseLegacyTerminalFlow`
  - jesli `true` -> stary `startCreationProcess()` (terminal).
- domyslnie -> `startCreationProcessWithHelper()`.

## 2) Start helper workflow
Sekwencja:
1. preflight write access do woluminu docelowego (`preflightTargetVolumeWriteAccess`).
2. `HelperServiceManager.ensureReadyForPrivilegedWork`.
3. przygotowanie request payload.
4. `PrivilegedOperationClient.startWorkflow`.
5. aktualizacja stanu UI z eventow.

## 3) UI status i progres
- `helperStageTitle` + `helperStatusText` + `helperProgressPercent`.
- fallback tekstow gdy puste:
  - etap: "Rozpoczynanie..."
  - status: "Nawiazywanie polaczenia XPC..."

## 4) Logline z helpera
- pozostaje w IPC,
- trafia do logow (`HelperLiveLog`),
- nie tworzy osobnego panelu w `UniversalInstallationView`.

## 5) Cancel
- `cancelHelperWorkflowIfNeeded` wysyla cancel do helpera,
- czysci handlery i resetuje `activeHelperWorkflowID`.

---

## Ustawienia podpisywania i dlaczego sa takie

## Debug (lokalne testy Xcode)
App:
- Apple Development,
- Automatic,
- debug entitlements app.

Helper:
- Apple Development,
- Automatic,
- debug entitlements helpera (`get-task-allow = true`).

Cel:
- szybkie testy z Xcode,
- mozliwosc debugowania,
- brak wymagania eksportu kazdego builda.

## Release (dystrybucja)
App:
- Developer ID Application,
- Manual,
- release entitlements app.

Helper:
- Developer ID Application,
- Manual,
- release entitlements helpera (`get-task-allow = false`).

Cel:
- poprawny podpis do eksportu/notaryzacji,
- zgodnosc app + helper pod tym samym Team ID,
- hardened runtime wlaczony po obu stronach.

## Krytyczne ograniczenie
Helper **nie moze** miec restricted entitlements wymagajacych provisioning profile, jezeli nie masz odpowiedniego profilu dopasowanego do tego modelu uruchamiania.

Objaw zlej konfiguracji:
- launchd: `xpcproxy exited due to OS_REASON_EXEC`
- amfid: `No matching profile found`, `Restricted entitlements not validated`
- app: timeout/brak polaczenia XPC.

W obecnym stanie ten problem jest usuniety przez minimalne entitlements helpera.

---

## Jak helper jest instalowany, zarzadzany i naprawiany

## Instalacja/rejestracja
1. app posiada w bundlu:
- helper binary (`Contents/Library/Helpers/macUSBHelper`)
- launchdaemon plist (`Contents/Library/LaunchDaemons/com.kruszoneq.macusb.helper.plist`)

2. `HelperServiceManager` wywoluje `register()` przez `SMAppService`.

3. System moze wymagac approval background item (w zaleznosci od stanu systemu i polityki).

## Dzialanie
- app laczy sie do Mach service `com.kruszoneq.macusb.helper` przez NSXPC.
- helper startuje workflow i zwraca eventy + final result.

## Status
- menu "Status helpera" pokazuje:
  - status SMAppService,
  - Mach service,
  - lokalizacje app,
  - health XPC + szczegoly.

## Naprawa
- menu "Napraw helpera":
  - reset connection,
  - ensure/register/recover,
  - log krokow na zywo w dedykowanym oknie,
  - finalny status sukces/blad.

## Usuwanie
- menu "Usun helpera" -> `unregister()`.

---

## Wazne scenariusze i edge-case

## 1) Xcode vs /Applications
- Release runtime oczekuje app z `/Applications`.
- Debug ma bypass dla uruchomien z Xcode (`DerivedData`).

## 2) Rownolegle operacje
- ensure-ready jest kolejkowany,
- status-check ma lock,
- repair ma lock (`repairInProgress`).

## 3) Timeout XPC
Timeout nie musi znaczyc, ze helper "zawiesil RPC".
Czesto oznacza, ze helper nie wystartowal (np. podpis/AMFI).

## 4) Export logow
`AppLogging.exportedLogText()` zawiera:
- `HelperLiveLog` (stdout/stderr workflow helpera),
- `HelperService` (kroki ensure/register/recover),
- inne kategorie aplikacyjne.

## 5) Najwazniejsze pulapki, ktore juz wystapily w tej historii
1. Konflikt signing helpera:
   - objaw build-time:
     - `macUSBHelper has conflicting provisioning settings`
   - przyczyna:
     - mieszanka automatycznego podpisu i recznie wymuszonej tozsamosci.
   - naprawa:
     - Debug helper: `Automatic + Apple Development`,
     - Release helper: `Manual + Developer ID Application`.

2. Hardened runtime:
   - export/notaryzacja helpera i app wymagaly `ENABLE_HARDENED_RUNTIME = YES`.
   - obecnie jest wlaczone po obu stronach.

3. Timeout XPC bez realnego crasha RPC:
   - objaw:
     - app widzi `Timeout polaczenia XPC z helperem`.
   - realna przyczyna (historycznie):
     - helper nie przechodzil walidacji AMFI i nawet nie startowal (`OS_REASON_EXEC`).

4. Restricted entitlements helpera:
   - gdy helper mial `com.apple.application-identifier` / `com.apple.developer.team-identifier`,
     system odrzucal uruchomienie helpera (`No matching profile found`).
   - docelowa naprawa:
     - minimalne entitlements helpera (`get-task-allow` true/false zaleznie od config).

5. Prompty systemowe:
   - system moze pokazac approval background item zamiast \"klasycznego\" prompta install helpera.
   - dlatego status helpera i panel naprawy sa kluczowe diagnostycznie.

---

## Weryfikacja poprawnosci po wdrozeniu

## Build
1. Debug:
```bash
xcodebuild -project macUSB.xcodeproj -scheme macUSB -configuration Debug build
```

2. Release:
```bash
xcodebuild -project macUSB.xcodeproj -scheme macUSB -configuration Release build
```

## Entitlements
1. App:
```bash
codesign -d --entitlements - /Applications/macUSB.app
```

2. Helper:
```bash
codesign -d --entitlements - /Applications/macUSB.app/Contents/Library/Helpers/macUSBHelper
```

Oczekiwane minimum helper Release:
- tylko `com.apple.security.get-task-allow = false`

## Launchd status helpera
```bash
launchctl print system/com.kruszoneq.macusb.helper
```

## Logi systemowe helpera (gdy potrzeba)
```bash
/usr/bin/log show --last 40m --style compact --predicate '(process == "macUSBHelper") || (process == "macUSB") || (eventMessage CONTAINS[c] "com.kruszoneq.macusb.helper")'
```

---

## Procedura odtworzenia helpera od zera (dla nowej sesji)
Ponizsze kroki sa recepta migracji z wersji terminal-only do obecnego etapu.

1. Dodaj target `macUSBHelper` typu `tool`.
2. Dodaj wspolne IPC typy/protokoly do app (i analogiczne definicje w helperze).
3. Dodaj `LaunchDaemon plist` do `macUSB/Resources/LaunchDaemons`.
4. W app target dodaj:
- target dependency na helper,
- copy phase helper binary -> `Contents/Library/Helpers`,
- copy phase plist -> `Contents/Library/LaunchDaemons`.
5. Dodaj `HelperServiceManager` i `PrivilegedOperationClient`.
6. Podlacz menu Narzedzia:
- status,
- naprawa,
- usuniecie helpera.
7. Podlacz startup bootstrap helper readiness.
8. W `CreatorHelperLogic` dodaj helper workflow + request builder + cancel.
9. W `UniversalInstallationView` pokazuj progres helpera (bez panelu live-log).
10. Dodaj logowanie do `AppLogging`:
- `HelperLiveLog` dla workflow,
- `HelperService` dla rejestracji/naprawy.
11. Ustaw podpisywanie i entitlements dokladnie jak w tym dokumencie.
12. Upewnij sie, ze helper Release nie ma restricted entitlements.
13. Przetestuj Debug i Release.
14. Sprawdz status helpera i naprawe przez GUI.
15. Zweryfikuj scenariusz `createinstallmedia`.

---

## Znane problemy (otwarte)
1. Tiger/PPC (`asr`) moze nadal failowac na etapie walidacji (`Operation not permitted` podczas asr validation).
2. To jest osobny problem od rejestracji helpera/XPC.
3. Na obecnym etapie helper + createinstallmedia dziala poprawnie dla nowszych scenariuszy (np. Yosemite).

---

## Szybki runbook naprawczy (gdy status helpera jest zly)
1. Menu -> `Usun helpera`.
2. Zamknij app.
3. (Opcjonalnie) Clean Build Folder w Xcode dla testow Debug.
4. Uruchom app ponownie.
5. Menu -> `Napraw helpera`.
6. Obserwuj panel logow naprawy.
7. Sprawdz `Status helpera`.

Jesli nadal brak XPC:
- sprawdz entitlements helpera,
- sprawdz Team ID/certyfikat app+helper,
- sprawdz czy nie wrocil restricted entitlement,
- sprawdz logi launchd/amfid.

---

## Dlaczego ten dokument jest krytyczny
Najwieksze problemy w poprzednich iteracjach byly spowodowane nie kodem workflow, tylko kombinacja:
- packaging helpera,
- plist LaunchDaemona,
- podpisywanie,
- entitlements.

Bez 100% zgodnosci tych elementow XPC timeout jest objawem wtornym, a nie przyczyna.
Ten dokument ma zapobiec ponownemu wejsciu w petle "zmienmy cos i zobaczymy".
