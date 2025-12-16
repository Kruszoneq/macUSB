import SwiftUI
import AppKit

struct UniversalInstallationView: View {
    let sourceAppURL: URL
    let targetDrive: USBDrive?
    let systemName: String
    
    // Flagi
    let needsCodesign: Bool
    let isLegacySystem: Bool // Yosemite/El Capitan
    let isRestoreLegacy: Bool // Lion/Mountain Lion
    // Flaga Catalina
    let isCatalina: Bool
    
    @Binding var rootIsActive: Bool
    @Binding var isTabLocked: Bool
    
    @State private var isProcessing: Bool = false
    @State private var processingTitle: String = ""
    @State private var processingSubtitle: String = ""
    @State private var processingIcon: String = "doc.on.doc.fill"
    
    // NOWE STANY UI DLA AUTH
    @State private var showAuthWarning: Bool = false
    @State private var isRollingBack: Bool = false
    
    @State private var errorMessage: String = ""
    @State private var isTerminalWorking: Bool = false
    @State private var showFinishButton: Bool = false
    @State private var processSuccess: Bool = false
    @State private var navigateToFinish: Bool = false
    @State private var isCancelled: Bool = false
    @State private var isUSBDisconnectedLock: Bool = false
    @State private var usbCheckTimer: Timer?
    
    // Stan rozruchowy dla monitoringu
    @State private var monitoringWarmupCounter: Int = 0
    
    @State private var windowHandler: UniversalWindowHandler?
    
    var tempWorkURL: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("macUSB_temp")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // CZĘŚĆ PRZEWIJANA
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Kreator instalatora macOS")
                        .font(.title).bold()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 5)
                    
                    // RAMKA: System Info
                    HStack {
                        Image(systemName: "applelogo").font(.title2).foregroundColor(.green).frame(width: 32)
                        VStack(alignment: .leading) {
                            Text("Wybrana wersja systemu").font(.caption).foregroundColor(.secondary)
                            Text(systemName).font(.headline).foregroundColor(.green).bold()
                        }
                        Spacer()
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1)).cornerRadius(8)
                    
                    // RAMKA: Dysk USB
                    if let drive = targetDrive {
                        HStack {
                            Image(systemName: "externaldrive.fill").font(.title2).foregroundColor(.blue).frame(width: 32)
                            VStack(alignment: .leading) {
                                Text("Wybrany dysk USB").font(.caption).foregroundColor(.secondary)
                                Text(drive.displayName).font(.headline)
                            }
                            Spacer()
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1)).cornerRadius(8)
                    }
                    
                    // RAMKA: Przebieg
                    HStack(alignment: .top) {
                        Image(systemName: "gearshape.2").font(.title2).foregroundColor(.secondary).frame(width: 32)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Przebieg procesu").font(.headline)
                            VStack(alignment: .leading, spacing: 5) {
                                if isRestoreLegacy {
                                    Text("• Plik z systemem zostanie skopiowany i zweryfikowany")
                                    Text("• Pamięć USB zostanie wymazana")
                                    Text("• Obraz systemu zostanie przywrócony w Terminalu")
                                    Text("• Wymagane podanie hasła administratora")
                                } else {
                                    if isCatalina {
                                        Text("• Plik instalacyjny zostanie skopiowany oraz podpisany")
                                    } else {
                                        Text("• Plik instalacyjny zostanie skopiowany")
                                        if needsCodesign {
                                            Text("• Instalator zostanie zmodyfikowany (podpis cyfrowy)")
                                        }
                                    }
                                    
                                    Text("• Pamięć USB zostanie sformatowana (dane zostaną usunięte)")
                                    Text("• Zapis na USB odbędzie się w nowym oknie Terminala")
                                    if isCatalina {
                                        Text("• Terminal wykona końcową weryfikację i podmianę plików")
                                    }
                                }
                                Text("• Pliki tymczasowe zostaną automatycznie usunięte")
                            }
                            .font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1)).cornerRadius(8)
                    
                    // RAMKA: Czas trwania
                    HStack(alignment: .center, spacing: 15) {
                        Image(systemName: "clock").font(.title2).foregroundColor(.secondary).frame(width: 32)
                        Text("Cały proces może potrwać kilka minut.").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1)).cornerRadius(8)
                    
                    // RAMKA: Globalny Błąd
                    if !errorMessage.isEmpty {
                        HStack(alignment: .center) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Wystąpił błąd")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.scale)
                    }
                }
                .padding()
            }
            
            // STICKY FOOTER
            VStack(spacing: 0) {
                Divider()
                
                VStack(spacing: 15) {
                    
                    if !isProcessing && !isTerminalWorking && !processSuccess && !isCancelled && !isUSBDisconnectedLock && !isRollingBack {
                        VStack(spacing: 15) {
                            Button(action: startCreationProcess) {
                                HStack {
                                    Text("Rozpocznij")
                                    Image(systemName: "arrow.right.circle.fill")
                                }
                                .frame(maxWidth: .infinity).padding(8)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large).tint(Color.accentColor)
                            
                            Button(action: showCancelAlert) {
                                HStack {
                                    Text("Przerwij i zakończ")
                                    Image(systemName: "xmark.circle")
                                }
                                .frame(maxWidth: .infinity).padding(8)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large).tint(Color.gray.opacity(0.2))
                        }
                        .transition(.opacity)
                    }
                    
                    // RAMKA: Anulowano przez użytkownika
                    if isCancelled {
                        HStack(alignment: .center) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Proces przerwany")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text("Działanie przerwane przez użytkownika (zamknięto okno Terminala). Aby zacząć od początku, ponownie uruchom aplikację.")
                                    .font(.caption)
                                    .foregroundColor(.orange.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.opacity)
                    }
                    
                    // RAMKA: Odłączono USB
                    if isUSBDisconnectedLock {
                        HStack(alignment: .center) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Odłączono dysk USB")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text("Dalsze działanie aplikacji zostało zablokowane. Aby zacząć od nowa, uruchom ponownie aplikację.")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.opacity)
                    }
                    
                    // STATUS: Przetwarzanie / Ostrzeżenia
                    if isProcessing || isRollingBack {
                        VStack(spacing: 20) {
                            HStack(spacing: 15) {
                                if isRollingBack {
                                    Image(systemName: "xmark.octagon.fill").font(.largeTitle).foregroundColor(.red)
                                } else {
                                    Image(systemName: processingIcon).font(.largeTitle).foregroundColor(.accentColor)
                                }
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(processingTitle).font(.headline)
                                    Text(processingSubtitle).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            
                            // RAMKA: Autoryzacja
                            if showAuthWarning {
                                HStack(alignment: .center) {
                                    Image(systemName: "lock.fill")
                                        .font(.title2)
                                        .foregroundColor(.orange)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Wymagana autoryzacja")
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                        Text("Wprowadź hasło administratora, aby kontynuować.")
                                            .font(.caption)
                                            .foregroundColor(.orange.opacity(0.8))
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                                .transition(.scale)
                            }
                            
                            // RAMKA: Brak autoryzacji / Rollback
                            if isRollingBack {
                                HStack(alignment: .center) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Brak autoryzacji")
                                            .font(.headline)
                                            .foregroundColor(.red)
                                        Text("Operacja została anulowana przez użytkownika.")
                                            .font(.caption)
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                                .transition(.scale)
                            }
                            
                            Divider()
                            
                            if !isRollingBack {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Proces w toku...").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isRollingBack ? Color.red.opacity(0.05) : Color.accentColor.opacity(0.1))
                        .cornerRadius(10)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    if isTerminalWorking {
                        VStack(spacing: 20) {
                            HStack(spacing: 15) {
                                Image(systemName: "terminal.fill").font(.largeTitle).foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Uruchomiono Terminal").font(.headline)
                                    Text("Postępuj zgodnie z instrukcjami w oknie Terminala.").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            Divider()
                            if !showFinishButton {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Oczekiwanie na zakończenie operacji...").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                }
                            } else {
                                VStack(spacing: 10) {
                                    Text("Naciśnij poniższy przycisk, gdy Terminal zakończy pracę").font(.subheadline)
                                    Button(action: { navigateToFinish = true }) {
                                        HStack {
                                            Text("Przejdź dalej")
                                            Image(systemName: "arrow.right.circle.fill")
                                        }
                                        .frame(maxWidth: .infinity).padding(5)
                                    }
                                    .buttonStyle(.borderedProminent).controlSize(.large).tint(Color.accentColor)
                                }
                            }
                        }
                        .padding().frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(0.1)).cornerRadius(10)
                        .transition(.opacity)
                    }
                    
                    if processSuccess {
                         VStack(spacing: 20) {
                             HStack(spacing: 15) {
                                 Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundColor(.green)
                                 VStack(alignment: .leading, spacing: 5) {
                                     Text("Gotowe!").font(.headline)
                                     Text("Przejdź dalej, aby zakończyć proces...").font(.caption).foregroundColor(.secondary)
                                 }
                                 Spacer()
                             }
                             Divider()
                             VStack(spacing: 10) {
                                 Button(action: { navigateToFinish = true }) {
                                     HStack {
                                         Text("Zakończ")
                                         Image(systemName: "arrow.right.circle.fill")
                                     }
                                     .frame(maxWidth: .infinity).padding(5)
                                 }
                                 .buttonStyle(.borderedProminent).controlSize(.large).tint(Color.green)
                             }
                         }
                         .padding().frame(maxWidth: .infinity)
                         .background(Color.green.opacity(0.1)).cornerRadius(10)
                         .transition(.opacity)
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(width: 550, height: 750)
        .navigationTitle("macUSB")
        .navigationBarBackButtonHidden(isTabLocked)
        .background(
            WindowAccessor_Universal { window in
                window.styleMask.remove(NSWindow.StyleMask.resizable)
                
                if self.windowHandler == nil {
                    let handler = UniversalWindowHandler(
                        shouldClose: {
                            return self.showFinishButton || self.isCancelled || self.processSuccess
                        },
                        onCleanup: {
                            self.performEmergencyCleanup(mountPoint: sourceAppURL.deletingLastPathComponent(), tempURL: tempWorkURL)
                        }
                    )
                    window.delegate = handler
                    self.windowHandler = handler
                }
            }
        )
        .background(
            NavigationLink(
                destination: FinishUSBView(
                    systemName: systemName,
                    mountPoint: sourceAppURL.deletingLastPathComponent(),
                    onReset: {}
                ),
                isActive: $navigateToFinish
            ) { EmptyView() }
            .hidden()
        )
        .onAppear {
            if !isProcessing && !isTerminalWorking && !processSuccess && !isCancelled && !isUSBDisconnectedLock && !isRollingBack {
                startUSBMonitoring()
            }
        }
        .onDisappear { stopUSBMonitoring() }
    }
    
    // --- POMOCNIK LOGOWANIA ---
    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        print("[\(formatter.string(from: Date()))] \(message)")
    }
    
    // --- LOGIKA ---
    
    func startAuthSignalTimer(signalURL: URL) {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            if !self.isProcessing || !self.errorMessage.isEmpty {
                timer.invalidate()
                return
            }
            if FileManager.default.fileExists(atPath: signalURL.path) {
                self.log("AUTH: Odebrano sygnał autoryzacji (auth_ok)")
                withAnimation {
                    self.showAuthWarning = false
                    self.processingTitle = String(localized: "Weryfikowanie plików")
                    self.processingSubtitle = String(localized: "Weryfikacja sum kontrolnych...")
                }
                timer.invalidate()
            }
        }
    }
    
    func startTerminalCompletionTimer(completionURL: URL, activeURL: URL) {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if self.isCancelled || !self.errorMessage.isEmpty {
                timer.invalidate()
                return
            }
            let fileManager = FileManager.default
            // 1. Sukces: Plik done istnieje
            if fileManager.fileExists(atPath: completionURL.path) {
                self.log("TERMINAL: Wykryto zakończenie operacji (terminal_done)")
                timer.invalidate()
                withAnimation { self.showFinishButton = true }
                return
            }
            // 2. Monitoring okna (plik running)
            if self.monitoringWarmupCounter < 3 {
                self.monitoringWarmupCounter += 1
            } else {
                if !fileManager.fileExists(atPath: activeURL.path) {
                    self.log("Brak pliku running_signal - zakładam zamknięcie okna terminala.")
                    timer.invalidate()
                    self.handleTerminalClosedPrematurely()
                }
            }
        }
    }
    
    func handleTerminalClosedPrematurely() {
        stopUSBMonitoring()
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.isCancelled = true
                self.isTerminalWorking = false
                self.showFinishButton = false
            }
            DispatchQueue.global(qos: .userInitiated).async {
                self.performEmergencyCleanup(mountPoint: self.sourceAppURL.deletingLastPathComponent(), tempURL: self.tempWorkURL)
            }
        }
    }
    
    // Lokalna funkcja codesign (bez sudo, w aplikacji)
    func performLocalCodesign(on appURL: URL) throws {
        self.log("➡️ Uruchamiam lokalny codesign (bez sudo) na pliku w TEMP...")
        let path = appURL.path
        
        // 1. Zdejmij atrybuty kwarantanny/rozszerzone
        self.log("   xattr -cr ...")
        let xattrTask = Process()
        xattrTask.launchPath = "/usr/bin/xattr"
        xattrTask.arguments = ["-cr", path]
        try xattrTask.run()
        xattrTask.waitUntilExit()
        
        let componentsToSign = [
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/Frameworks/IAInstallerUtilities.framework/Versions/A/IAInstallerUtilities",
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/Frameworks/IAMiniSoftwareUpdate.framework/Versions/A/IAMiniSoftwareUpdate",
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/Frameworks/IAPackageKit.framework/Versions/A/IAPackageKit",
            "\(path)/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/Frameworks/IAESD.framework/Versions/A/IAESD",
            "\(path)/Contents/Resources/createinstallmedia"
        ]
        
        for component in componentsToSign {
            if FileManager.default.fileExists(atPath: component) {
                self.log("   Signing: \(URL(fileURLWithPath: component).lastPathComponent)")
                let task = Process()
                task.launchPath = "/usr/bin/codesign"
                task.arguments = ["-s", "-", "-f", component]
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    self.log("⚠️ Błąd codesign dla \(component) (kod: \(task.terminationStatus)) - kontynuuję mimo to.")
                }
            }
        }
        
        self.log("✅ Lokalny codesign zakończony.")
    }
    
    func startCreationProcess() {
        guard let drive = targetDrive else {
            errorMessage = String(localized: "Błąd: Nie wybrano dysku.")
            return
        }
        withAnimation(.easeInOut(duration: 0.4)) { isTabLocked = true; isProcessing = true }; isTerminalWorking = false; showFinishButton = false; processSuccess = false; errorMessage = ""; navigateToFinish = false; stopUSBMonitoring(); showAuthWarning = false; isRollingBack = false; monitoringWarmupCounter = 0
        self.processingIcon = "doc.on.doc.fill"
        
        let isFromMountedVolume = sourceAppURL.path.hasPrefix("/Volumes/")
        self.log("Źródło instalatora: \(sourceAppURL.path)")
        self.log("Źródło z zamontowanego woluminu: \(isFromMountedVolume ? "TAK" : "NIE")")
        self.log("Flagi: isCatalina=\(isCatalina), needsCodesign=\(needsCodesign), isLegacySystem=\(isLegacySystem), isRestoreLegacy=\(isRestoreLegacy)")
        self.log("Folder TEMP: \(tempWorkURL.path)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileManager = FileManager.default
                if !fileManager.fileExists(atPath: tempWorkURL.path) { try fileManager.createDirectory(at: tempWorkURL, withIntermediateDirectories: true) }
                
                // --- TŁUMACZENIA DO TERMINALA (STANDARD) ---
                let msgHeader = String(localized: "ETAP: Wgrywanie instalatora na dysk USB")
                let msgSystemLabel = String(localized: "WERSJA SYSTEMU:")
                let msgDuration = String(localized: "Proces może potrwać kilka minut.")
                let msgAdmin = String(localized: "Wymagane uprawnienia administratora.")
                let msgPass = String(localized: "Wpisz hasło i naciśnij Enter (hasła nie widać).")
                let msgSuccess = String(localized: "SUKCES! Instalator został utworzony.")
                let msgClose = String(localized: "Terminal zamknie się automatycznie za 3 sekundy.")
                let msgError = String(localized: "BŁĄD PROCESU: Nie udało się utworzyć instalatora.")
                let msgCheck = String(localized: "Sprawdź powyższe komunikaty błędów.")
                let msgEnter = String(localized: "Naciśnij Enter, aby zamknąć...")
                // NOWE DLA LEGACY RESTORE
                let msgRestoreStart = String(localized: "Rozpoczynanie przywracania na USB...")
                let msgEraseWarning = String(localized: "UWAGA: Wszystkie dane na USB zostaną usunięte!")
                
                // --- TŁUMACZENIA DO TERMINALA (CATALINA) ---
                let msgCatStage1 = String(localized: "ETAP: Wgrywanie instalatora na dysk USB - etap 1/2")
                let msgCatCleaning = String(localized: "ETAP: Czyszczenie dysku USB")
                let msgCatStage2 = String(localized: "ETAP: Wgrywanie instalatora na dysk USB - etap 2/2")
                
                let msgCatWarn1 = String(localized: "UWAGA: Ten etap jest najbardziej czasochłonny.")
                let msgCatWarn2 = String(localized: "Może potrwać od kilku do kilkunastu minut.")
                let msgCatWarn3 = String(localized: "Działanie wykonywane w tle, nie widać paska postępu!")
                let msgCatWarn4 = String(localized: "Proszę zachować cierpliwość i nie zamykać okna...")
                
                let msgCatDone = String(localized: "GOTOWE!")
                
                let usbPath = drive.url.path
                var scriptCommand = ""
                
                let terminalDoneURL = tempWorkURL.appendingPathComponent("terminal_done")
                let terminalActiveURL = tempWorkURL.appendingPathComponent("terminal_running")
                
                if fileManager.fileExists(atPath: terminalDoneURL.path) { try? fileManager.removeItem(at: terminalDoneURL) }
                if fileManager.fileExists(atPath: terminalActiveURL.path) { try? fileManager.removeItem(at: terminalActiveURL) }
                
                if isRestoreLegacy {
                    // --- SEKCJA LEGACY (bez zmian) ---
                    let sourceESD = sourceAppURL.appendingPathComponent("Contents/SharedSupport/InstallESD.dmg")
                    self.log("Restore Legacy: źródło InstallESD.dmg = \(sourceESD.path)")
                    
                    DispatchQueue.main.async {
                        self.processingTitle = String(localized: "Przygotowanie plików")
                        self.processingSubtitle = String(localized: "Szukanie pliku obrazu...")
                    }
                    
                    if !fileManager.fileExists(atPath: sourceESD.path) {
                        throw NSError(domain: "macUSB", code: 404, userInfo: [NSLocalizedDescriptionKey: String(localized: "Nie znaleziono pliku InstallESD.dmg.")])
                    }
                    
                    let targetESD = tempWorkURL.appendingPathComponent("InstallESD.dmg")
                    self.log("Restore Legacy: cel InstallESD.dmg w TEMP = \(targetESD.path)")
                    
                    if fileManager.fileExists(atPath: targetESD.path) { try? fileManager.removeItem(at: targetESD) }
                    
                    self.log("Restore Legacy: kopiuję InstallESD.dmg do TEMP...")
                    DispatchQueue.main.async { self.processingSubtitle = String(localized: "Kopiowanie plików...") }
                    try fileManager.copyItem(at: sourceESD, to: targetESD)
                    self.log("Restore Legacy: kopiowanie zakończone.")
                    
                    let authSignalURL = tempWorkURL.appendingPathComponent("auth_ok")
                    if fileManager.fileExists(atPath: authSignalURL.path) { try? fileManager.removeItem(at: authSignalURL) }
                    
                    DispatchQueue.main.async {
                        self.processingTitle = String(localized: "Autoryzacja")
                        self.processingSubtitle = String(localized: "Oczekiwanie na hasło administratora...")
                        withAnimation { self.showAuthWarning = true }
                        self.startAuthSignalTimer(signalURL: authSignalURL)
                    }
                    
                    do {
                        let combinedCommand = "touch '\(authSignalURL.path)' && chmod u+w '\(targetESD.path)' && /usr/sbin/asr imagescan --source '\(targetESD.path)'"
                        self.log("ASR imagescan command: \(combinedCommand)")
                        try runAdminCommand(combinedCommand)
                        self.log("ASR imagescan zakończony pomyślnie.")
                        DispatchQueue.main.async { withAnimation { self.showAuthWarning = false } }
                    } catch {
                        DispatchQueue.main.async {
                            withAnimation {
                                self.showAuthWarning = false
                                self.isProcessing = false
                                self.isTabLocked = false
                                self.startUSBMonitoring()
                                self.errorMessage = String(localized: "Autoryzacja anulowana. Możesz spróbować ponownie.")
                            }
                        }
                        return
                    }
                    
                    scriptCommand = """
                    touch '\(terminalActiveURL.path)'
                    trap "rm -f '\(terminalActiveURL.path)'" EXIT

                    echo "\(msgRestoreStart)"
                    echo "\(msgEraseWarning)"
                    sudo /usr/sbin/asr restore --source '\(targetESD.path)' --target '\(usbPath)' --erase --noprompt --noverify

                    EXIT_CODE=$?
                    touch '\(terminalDoneURL.path)'
                    """
                    self.log("ASR restore: source='\(targetESD.path)' target='\(usbPath)'")
                    
                } else {
                    // --- SEKCJA STANDARDOWA + CATALINA ---
                    // Ustal źródło: z /Volumes (DMG) czy lokalny .app
                    var effectiveAppURL = sourceAppURL
                    var didCopyToTemp = false

                    if isFromMountedVolume || isCatalina || needsCodesign {
                        self.log("Tryb standardowy: kopiowanie do TEMP (powód: \(isFromMountedVolume ? "DMG" : (isCatalina ? "Catalina" : "wymaga podpisu")))")
                        // DMG lub przypadki wymagające modyfikacji: kopiujemy do TEMP
                        DispatchQueue.main.async {
                            self.processingTitle = String(localized: "Kopiowanie plików")
                            self.processingSubtitle = String(localized: "Trwa kopiowanie plików, proszę czekać.")
                        }
                        let destinationAppURL = tempWorkURL.appendingPathComponent(sourceAppURL.lastPathComponent)
                        if fileManager.fileExists(atPath: destinationAppURL.path) { try? fileManager.removeItem(at: destinationAppURL) }

                        self.log("➡️ Rozpoczynam kopiowanie pliku .app do folderu TEMP...")
                        self.log("   Źródło: \(sourceAppURL.path)")
                        self.log("   Cel: \(destinationAppURL.path)")
                        try fileManager.copyItem(at: sourceAppURL, to: destinationAppURL)
                        self.log("✅ Kopiowanie do TEMP zakończone.")

                        effectiveAppURL = destinationAppURL
                        didCopyToTemp = true

                        // Codesign w Swift (In-App) dla Cataliny oraz Mojave/High Sierra
                        if isCatalina || needsCodesign {
                            DispatchQueue.main.async {
                                self.processingTitle = String(localized: "Modyfikowanie plików")
                                self.processingSubtitle = String(localized: "Podpisywanie instalatora...")
                            }
                            try performLocalCodesign(on: destinationAppURL)
                        }
                    } else {
                        // Lokalny .app dla Modern (Big Sur+) oraz Legacy (Yosemite/El Capitan): pracujemy na oryginale
                        effectiveAppURL = sourceAppURL
                        self.log("Tryb standardowy: praca na oryginalnym .app bez kopiowania: \(effectiveAppURL.path)")
                    }

                    // Ścieżka do createinstallmedia na efektywnym źródle
                    let createInstallMediaURL = effectiveAppURL.appendingPathComponent("Contents/Resources/createinstallmedia")
                    self.log("createinstallmedia: \(createInstallMediaURL.path)")

                    // Dla Legacy (Yosemite/El Capitan): dodaj --applicationpath do efektywnego źródła
                    let legacyArg = isLegacySystem ? "--applicationpath '\(effectiveAppURL.path)'" : ""
                    if !legacyArg.isEmpty { self.log("Dodano argument legacy: \(legacyArg)") } else { self.log("Bez argumentu --applicationpath (nieniezbędny)") }
                    
                    var bashLogic = """
                    sudo '\(createInstallMediaURL.path)' --volume '\(usbPath)' \(legacyArg) --nointeraction
                    EXIT_CODE=$?
                    """
                    
                    // --- CATALINA POST-PROCESS ---
                    if isCatalina {
                        // FIX: createinstallmedia zmienia nazwę woluminu na "Install macOS Catalina".
                        // Musimy użyć nowej ścieżki, a nie starej (usbPath), bo inaczej rm i ditto nie znajdą celu.
                        let catalinaVolumePath = "/Volumes/Install macOS Catalina"
                        let targetAppOnUSB = "\(catalinaVolumePath)/Install macOS Catalina.app"
                        let cleanAppSource = sourceAppURL.resolvingSymlinksInPath().path
                        self.log("Catalina post-install: źródło = \(cleanAppSource) -> cel = \(targetAppOnUSB)")
                        
                        let catalinaPostProcessBlock = """
                        if [ $EXIT_CODE -eq 0 ]; then
                            # --- ETAP: CZYSZCZENIE ---
                            clear
                            echo "================================================================================"
                            echo "                                     macUSB"
                            echo "================================================================================"
                            echo "\(msgCatCleaning)"
                            echo "\(msgSystemLabel) \(systemName)"
                            echo "--------------------------------------------------------------------------------"
                            echo ""
                            
                            # Używamy poprawnej ścieżki do usunięcia
                            rm -rf "\(targetAppOnUSB)"
                            
                            # --- ETAP: 2/2 (DITTO) ---
                            clear
                            echo "================================================================================"
                            echo "                                     macUSB"
                            echo "================================================================================"
                            echo "\(msgCatStage2)"
                            echo "\(msgSystemLabel) \(systemName)"
                            echo "--------------------------------------------------------------------------------"
                            # Usunięto pustą linię tutaj (Visual Fix)
                            echo "\(msgCatWarn1)"
                            echo "\(msgCatWarn2)"
                            echo "\(msgCatWarn3)"
                            echo "\(msgCatWarn4)"
                            echo "================================================================================" # Dodano separator
                            
                            ditto "\(cleanAppSource)" "\(targetAppOnUSB)"
                            EXIT_CODE=$?
                            xattr -dr com.apple.quarantine "\(targetAppOnUSB)"
                            
                            echo "\(msgCatDone)"
                        fi
                        """
                        bashLogic += "\n" + catalinaPostProcessBlock
                    }
                    
                    scriptCommand = """
                    touch '\(terminalActiveURL.path)'
                    trap "rm -f '\(terminalActiveURL.path)'" EXIT
                    
                    \(bashLogic)
                    
                    touch '\(terminalDoneURL.path)'
                    """
                }
                
                DispatchQueue.main.async {
                    withAnimation { 
                        self.isProcessing = false
                        self.isTerminalWorking = true 
                    }
                    self.log("Terminal: uruchomiono skrypt, monitoring rozpoczęty.")
                    self.startTerminalCompletionTimer(completionURL: terminalDoneURL, activeURL: terminalActiveURL)
                }
                
                // Wybór nagłówka startowego (dla Cataliny inny)
                let startHeader = isCatalina ? msgCatStage1 : msgHeader
                
                let scriptContent = """
                #!/bin/bash
                osascript -e 'tell application "Terminal" to set number of columns of front window to 80'
                osascript -e 'tell application "Terminal" to set number of rows of front window to 40'
                printf "\\e]0;macUSB\\a"
                
                clear
                echo "================================================================================"
                echo "                                     macUSB"
                echo "================================================================================"
                echo "\(startHeader)"
                echo "\(msgSystemLabel) \(systemName)"
                echo "\(msgDuration)"
                echo "--------------------------------------------------------------------------------"
                echo "\(msgAdmin)"
                echo "\(msgPass)"
                echo "================================================================================"
                echo ""
                
                \(scriptCommand)
                
                if [ $EXIT_CODE -eq 0 ]; then
                    echo ""
                    echo "================================================================================"
                    echo "\(msgSuccess)"
                    echo "\(msgClose)"
                    echo "================================================================================"
                    sleep 3
                    osascript -e 'tell application "Terminal" to close front window' & exit
                else
                    echo ""
                    echo "\(msgError)"
                    echo "\(msgCheck)"
                    read -p "\(msgEnter)"
                fi
                """
                let scriptURL = tempWorkURL.appendingPathComponent("start_install.command")
                self.log("Zapis skryptu: \(scriptURL.path)")
                try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
                NSWorkspace.shared.open(scriptURL)
                self.log("Terminal otwarty ze skryptem: \(scriptURL.path)")
                
            } catch {
                DispatchQueue.main.async { withAnimation { self.isProcessing = false; self.errorMessage = error.localizedDescription; self.isTabLocked = false; self.startUSBMonitoring(); self.isTerminalWorking = false; self.showFinishButton = false } }
            }
        }
    }
    
    // --- FUNKCJE POMOCNICZE ---
    
    func performEmergencyCleanup(mountPoint: URL, tempURL: URL) {
        self.log("Cleanup: odmontowuję \(mountPoint.path)")
        self.log("Cleanup: usuwam katalog TEMP \(tempURL.path)")
        
        let unmountTask = Process()
        unmountTask.launchPath = "/usr/bin/hdiutil"
        unmountTask.arguments = ["detach", mountPoint.path, "-force"]
        try? unmountTask.run()
        unmountTask.waitUntilExit()
        
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
    
    func showCancelAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Czy na pewno chcesz przerwać?")
        alert.addButton(withTitle: String(localized: "Nie"))
        alert.addButton(withTitle: String(localized: "Tak"))
        let completionHandler = { (response: NSApplication.ModalResponse) in if response == .alertSecondButtonReturn { performImmediateCancellation() } }
        if let window = NSApp.windows.first { alert.beginSheetModal(for: window, completionHandler: completionHandler) } else { let r = alert.runModal(); completionHandler(r) }
    }
    
    func performImmediateCancellation() {
        stopUSBMonitoring()
        DispatchQueue.global(qos: .userInitiated).async {
            self.unmountDMG()
            DispatchQueue.main.async { withAnimation(.easeInOut(duration: 0.5)) { self.isCancelled = true; self.navigateToFinish = false } }
        }
    }
    
    func unmountDMG() {
        let mountPoint = sourceAppURL.deletingLastPathComponent().path
        self.log("UnmountDMG: próba odmontowania \(mountPoint)")
        guard mountPoint.hasPrefix("/Volumes/") else { return }
        let task = Process()
        task.launchPath = "/usr/bin/hdiutil"
        task.arguments = ["detach", mountPoint, "-force"]
        try? task.run()
        task.waitUntilExit()
        self.log("UnmountDMG: polecenie zakończone")
    }
    
    func startUSBMonitoring() {
        guard !isProcessing && !isTerminalWorking && !isCancelled && !isUSBDisconnectedLock && !isRollingBack && !processSuccess else { return }
        usbCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in checkDriveAvailability() }
    }
    
    func stopUSBMonitoring() { usbCheckTimer?.invalidate(); usbCheckTimer = nil }
    
    func checkDriveAvailability() {
        if isProcessing || isTerminalWorking || processSuccess || isCancelled || isUSBDisconnectedLock || isRollingBack { stopUSBMonitoring(); return }
        guard let drive = targetDrive else { return }
        let isReachable = (try? drive.url.checkResourceIsReachable()) ?? false
        if !isReachable { stopUSBMonitoring(); showUSBDisconnectAlert() }
    }
    
    func showUSBDisconnectAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Odłączono dysk USB")
        alert.informativeText = String(localized: "Dalsze działanie aplikacji zostanie zablokowane")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Kontynuuj"))
        let completionHandler = { (response: NSApplication.ModalResponse) in
            DispatchQueue.main.async { self.isTabLocked = false; DispatchQueue.global(qos: .userInitiated).async { self.unmountDMG() }; withAnimation(.easeInOut(duration: 0.5)) { self.isUSBDisconnectedLock = true; self.navigateToFinish = false } }
        }
        if let window = NSApp.windows.first { alert.beginSheetModal(for: window, completionHandler: completionHandler) } else { alert.runModal(); completionHandler(.alertFirstButtonReturn) }
    }
    
    func runAdminCommand(_ command: String) throws {
        self.log("EXEC SHELL: \(command)")
        
        let script = "do shell script \"\(command)\" with administrator privileges"
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
        }
        
        if let err = error {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "Nieznany błąd AppleScript"
            self.log("SHELL ERROR: \(msg)")
            throw NSError(domain: "macUSB", code: 999, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}

// --- KLASY POMOCNICZE W TYM PLIKU ---

struct WindowAccessor_Universal: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { context.coordinator.callback(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(callback: callback) }
    class Coordinator {
        let callback: (NSWindow) -> Void
        init(callback: @escaping (NSWindow) -> Void) { self.callback = callback }
    }
}

class UniversalWindowHandler: NSObject, NSWindowDelegate {
    let shouldClose: () -> Bool
    let onCleanup: () -> Void
    init(shouldClose: @escaping () -> Bool, onCleanup: @escaping () -> Void) {
        self.shouldClose = shouldClose
        self.onCleanup = onCleanup
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if shouldClose() {
            onCleanup()
            return true
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "UWAGA!")
        alert.informativeText = String(localized: "Czy na pewno chcesz przerwać pracę?")
        alert.addButton(withTitle: String(localized: "Nie"))
        alert.addButton(withTitle: String(localized: "Tak"))
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            onCleanup()
            NSApplication.shared.terminate(nil)
            return true
        } else { return false }
    }
}

