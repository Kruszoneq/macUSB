import SwiftUI
import AppKit

// Logic extracted from UniversalInstallationView without changing behavior or UI
extension UniversalInstallationView {
    // --- POMOCNIK LOGOWANIA ---
    func log(_ message: String, category: String = "Installation") {
        AppLogging.info(message, category: category)
    }

    func logError(_ message: String, category: String = "Installation") {
        AppLogging.error(message, category: category)
    }

    func stage(_ title: String) {
        AppLogging.stage(title)
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

    func startTerminalCompletionTimer(completionURL: URL, activeURL: URL, errorURL: URL) {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if self.isCancelled || !self.errorMessage.isEmpty {
                timer.invalidate()
                return
            }
            let fileManager = FileManager.default
            // 1. Sukces: Plik done istnieje
            if fileManager.fileExists(atPath: completionURL.path) {
                self.log("TERMINAL: Wykryto zakończenie operacji (terminal_done)")

                let failed = fileManager.fileExists(atPath: errorURL.path)
                self.terminalFailed = failed

                timer.invalidate()
                withAnimation { self.navigateToFinish = true }
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
        self.log("Uruchamiam lokalny codesign (bez sudo) na pliku w TEMP...")
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
                    self.logError("Błąd codesign dla \(component) (kod: \(task.terminationStatus)) - kontynuuję mimo to.")
                }
            }
        }

        self.log("Lokalny codesign zakończony.")
    }

    func startCreationProcess() {
        guard let drive = targetDrive else {
            errorMessage = String(localized: "Błąd: Nie wybrano dysku.")
            return
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            isTabLocked = true
            isProcessing = true
        }
        isTerminalWorking = false
        showFinishButton = false
        processSuccess = false
        errorMessage = ""
        navigateToFinish = false
        terminalFailed = false
        stopUSBMonitoring()
        showAuthWarning = false
        isRollingBack = false
        monitoringWarmupCounter = 0
        self.processingIcon = "doc.on.doc.fill"

        let isFromMountedVolume = sourceAppURL.path.hasPrefix("/Volumes/")
        self.log("Źródło instalatora: \(sourceAppURL.path)")
        self.log("Źródło z zamontowanego woluminu: \(isFromMountedVolume ? "TAK" : "NIE")")
        self.log("Flagi: isCatalina=\(isCatalina), isSierra=\(isSierra), isMavericks=\(isMavericks), needsCodesign=\(needsCodesign), isLegacySystem=\(isLegacySystem), isRestoreLegacy=\(isRestoreLegacy), isPPC=\(isPPC)")
        self.log("Folder TEMP: \(tempWorkURL.path)")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileManager = FileManager.default
                if !fileManager.fileExists(atPath: tempWorkURL.path) {
                    try fileManager.createDirectory(at: tempWorkURL, withIntermediateDirectories: true)
                }

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

                let msgMavStage1 = String(localized: "ETAP: Skanowanie obrazu")
                let msgMavStage2 = String(localized: "ETAP: Przywracanie obrazu na USB")

                // --- TŁUMACZENIA DLA PPC ---
                let msgPPCStage1 = String(localized: "ETAP 1/2 - FORMATOWANIE DYSKU USB")
                let msgPPCStage2 = String(localized: "ETAP 2/2 - TWORZENIE USB")
                let msgPPCSource = String(localized: "ŹRÓDŁO:")
                let msgPPCTarget = String(localized: "CEL:")
                let msgPPCNote = String(localized: "Wolumin zostanie nazwany PPC (APM + HFS+).")

                let usbPath = drive.url.path
                var scriptCommand = ""

                let terminalDoneURL = tempWorkURL.appendingPathComponent("terminal_done")
                let terminalActiveURL = tempWorkURL.appendingPathComponent("terminal_running")
                let terminalSuccessURL = tempWorkURL.appendingPathComponent("terminal_success")
                let terminalErrorURL = tempWorkURL.appendingPathComponent("terminal_error")

                if fileManager.fileExists(atPath: terminalDoneURL.path) { try? fileManager.removeItem(at: terminalDoneURL) }
                if fileManager.fileExists(atPath: terminalActiveURL.path) { try? fileManager.removeItem(at: terminalActiveURL) }
                if fileManager.fileExists(atPath: terminalSuccessURL.path) { try? fileManager.removeItem(at: terminalSuccessURL) }
                if fileManager.fileExists(atPath: terminalErrorURL.path) { try? fileManager.removeItem(at: terminalErrorURL) }

                // Promote effectiveAppURL to outer scope so it can be used later
                var effectiveAppURL = self.sourceAppURL
                var didCopyToTemp = false

                if isRestoreLegacy {
                    // --- SEKCJA LEGACY RESTORE ---
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
                    AppLogging.separator()
                    DispatchQueue.main.async { self.processingSubtitle = String(localized: "Kopiowanie plików...") }
                    try fileManager.copyItem(at: sourceESD, to: targetESD)
                    self.log("Restore Legacy: kopiowanie zakończone.")
                    AppLogging.separator()

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
                        try self.runAdminCommand(combinedCommand)
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
                    if [ $EXIT_CODE -eq 0 ]; then
                        touch '\(terminalSuccessURL.path)'
                    else
                        touch '\(terminalErrorURL.path)'
                    fi

                    touch '\(terminalDoneURL.path)'
                    """
                    self.log("ASR restore: source='\(targetESD.path)' target='\(usbPath)'")

                } else if isMavericks {
                    // --- SEKCJA MAVERICKS: IMAGESCAN + RESTORE ---

                    let sourceImage = self.originalImageURL ?? self.sourceAppURL
                    self.log("Mavericks: źródło obrazu = \(sourceImage.path)")

                    DispatchQueue.main.async {
                        self.processingTitle = String(localized: "Przygotowanie plików")
                        self.processingSubtitle = String(localized: "Kopiowanie pliku obrazu...")
                    }

                    AppLogging.separator()
                    if !fileManager.fileExists(atPath: sourceImage.path) {
                        throw NSError(domain: "macUSB", code: 404, userInfo: [NSLocalizedDescriptionKey: String(localized: "Nie znaleziono pliku obrazu.")])
                    }

                    let targetESD = tempWorkURL.appendingPathComponent("InstallESD.dmg")
                    self.log("Mavericks: cel InstallESD.dmg w TEMP = \(targetESD.path)")
                    if fileManager.fileExists(atPath: targetESD.path) { try? fileManager.removeItem(at: targetESD) }

                    self.log("Mavericks: kopiuję obraz do TEMP...")
                    try fileManager.copyItem(at: sourceImage, to: targetESD)
                    self.log("Mavericks: kopiowanie zakończone.")
                    AppLogging.separator()

                    // Mavericks: oba kroki wykonujemy w Terminalu z sudo (imagescan, potem restore)
                    scriptCommand = """
                    touch '\(terminalActiveURL.path)'
                    trap "rm -f '\(terminalActiveURL.path)'" EXIT

                    # --- ETAP 1/2: IMAGESCAN ---
                    clear
                    echo "================================================================================"
                    echo "                                     macUSB"
                    echo "================================================================================"
                    echo "\(msgMavStage1)"
                    echo "\(msgSystemLabel) \(systemName)"
                    echo "--------------------------------------------------------------------------------"
                    echo ""

                    chmod u+w '\(targetESD.path)'
                    sudo /usr/sbin/asr imagescan --source '\(targetESD.path)'
                    EXIT_CODE=$?

                    # --- ETAP 2/2: RESTORE ---
                    if [ $EXIT_CODE -eq 0 ]; then
                        clear
                        echo "================================================================================"
                        echo "                                     macUSB"
                        echo "================================================================================"
                        echo "\(msgMavStage2)"
                        echo "\(msgSystemLabel) \(systemName)"
                        echo "--------------------------------------------------------------------------------"
                        echo "\(msgEraseWarning)"
                        echo "================================================================================"
                        echo ""
                        sudo /usr/sbin/asr restore --source '\(targetESD.path)' --target '\(usbPath)' --erase --noprompt
                        EXIT_CODE=$?
                    fi

                    if [ $EXIT_CODE -eq 0 ]; then
                        touch '\(terminalSuccessURL.path)'
                    else
                        touch '\(terminalErrorURL.path)'
                    fi

                    touch '\(terminalDoneURL.path)'
                    """
                    self.log("ASR Mavericks: source='\(targetESD.path)' (from original='\(sourceImage.path)') target='\(usbPath)'")

                } else if isPPC {
                    // --- SEKCJA PPC (PowerPC): FORMAT + RESTORE ---
                    let ppcSourceVolumePath = sourceAppURL.deletingLastPathComponent().path
                    self.log("PPC: Źródło woluminu = \(ppcSourceVolumePath)")
                    self.log("PPC: Cel USB (montowany) = \(usbPath)")

                    let selectedBSD = drive.device
                    let parentWholeDisk: String = selectedBSD.range(of: #"^disk\d+"#, options: .regularExpression).map { String(selectedBSD[$0]) } ?? selectedBSD
                    self.log("PPC: Wybrany dysk BSD = \(selectedBSD) -> Whole disk = /dev/\(parentWholeDisk)")

                    scriptCommand = """
                    touch '\(terminalActiveURL.path)'
                    trap "rm -f '\(terminalActiveURL.path)'" EXIT

                    USB_DEV="/dev/\(parentWholeDisk)"
                    echo "Docelowy dysk: $USB_DEV"

                    # --- ETAP 1/2: FORMATOWANIE ---
                    clear
                    echo "================================================================================"
                    echo "                                     macUSB"
                    echo "================================================================================"
                    echo "\(msgPPCStage1)"
                    echo "\(msgSystemLabel) \(systemName)"
                    echo "\(msgEraseWarning)"
                    echo "--------------------------------------------------------------------------------"
                    echo "\(msgPPCTarget) $USB_DEV"
                    echo "\(msgPPCNote)"
                    echo "================================================================================"
                    echo ""
                    sudo /usr/sbin/diskutil partitionDisk "$USB_DEV" APM HFS+ "PPC" 100%
                    EXIT_CODE=$?

                    # --- ETAP 2/2: TWORZENIE USB ---
                    if [ $EXIT_CODE -eq 0 ]; then
                        clear
                        echo "================================================================================"
                        echo "                                     macUSB"
                        echo "================================================================================"
                        echo "\(msgPPCStage2)"
                        echo "\(msgSystemLabel) \(systemName)"
                        echo "--------------------------------------------------------------------------------"
                        echo "\(msgPPCSource) \(ppcSourceVolumePath)"
                        echo "\(msgPPCTarget) /Volumes/PPC"
                        echo "================================================================================"
                        echo ""
                        sudo /usr/sbin/asr restore --source '\(ppcSourceVolumePath)' --target '/Volumes/PPC' --erase --noverify --noprompt
                        EXIT_CODE=$?
                    fi

                    if [ $EXIT_CODE -eq 0 ]; then
                        touch '\(terminalSuccessURL.path)'
                    else
                        touch '\(terminalErrorURL.path)'
                    fi

                    touch '\(terminalDoneURL.path)'
                    """
                } else {
                    // --- SEKCJA STANDARD (createinstallmedia) ---
                    // Ustal źródło: z /Volumes (DMG) czy lokalny .app
                    effectiveAppURL = sourceAppURL
                    didCopyToTemp = false

                    if isSierra {
                        // Tryb specjalny dla macOS Sierra: zawsze kopiujemy do TEMP i modyfikujemy
                        self.log("Kopiowanie .app do TEMP (Sierra)")
                        DispatchQueue.main.async {
                            self.processingTitle = String(localized: "Kopiowanie plików")
                            self.processingSubtitle = String(localized: "Trwa kopiowanie plików, proszę czekać.")
                        }
                        let destinationAppURL = tempWorkURL.appendingPathComponent(sourceAppURL.lastPathComponent)
                        if fileManager.fileExists(atPath: destinationAppURL.path) { try? fileManager.removeItem(at: destinationAppURL) }
                        AppLogging.separator()
                        self.log("Kopiowanie .app do TEMP (Sierra)")
                        self.log("   Źródło: \(sourceAppURL.path)")
                        self.log("   Cel: \(destinationAppURL.path)")
                        try fileManager.copyItem(at: sourceAppURL, to: destinationAppURL)
                        self.log("Kopiowanie do TEMP zakończone (Sierra).")
                        AppLogging.separator()

                        effectiveAppURL = destinationAppURL
                        didCopyToTemp = true

                        // --- Modyfikacje pliku (B) ---
                        DispatchQueue.main.async {
                            self.processingTitle = String(localized: "Modyfikowanie plików")
                            self.processingSubtitle = String(localized: "Aktualizacja wersji i podpisywanie...")
                        }

                        // 1) plutil: ustaw CFBundleShortVersionString na 12.6.03
                        let plistPath = destinationAppURL.appendingPathComponent("Contents/Info.plist").path
                        self.log("Sierra: plutil modyfikacja CFBundleShortVersionString -> 12.6.03 (\(plistPath))")
                        let plutilTask = Process()
                        plutilTask.launchPath = "/usr/bin/plutil"
                        plutilTask.arguments = ["-replace", "CFBundleShortVersionString", "-string", "12.6.03", plistPath]
                        try plutilTask.run()
                        plutilTask.waitUntilExit()

                        // 2) xattr: zdejmij kwarantannę z całej aplikacji
                        self.log("Sierra: zdejmowanie kwarantanny (xattr) z \(destinationAppURL.path)")
                        let xattrTask2 = Process()
                        xattrTask2.launchPath = "/usr/bin/xattr"
                        xattrTask2.arguments = ["-dr", "com.apple.quarantine", destinationAppURL.path]
                        try xattrTask2.run()
                        xattrTask2.waitUntilExit()

                        // 3) codesign: podpisz createinstallmedia w (B)
                        let cimPath = destinationAppURL.appendingPathComponent("Contents/Resources/createinstallmedia").path
                        self.log("Sierra: podpisywanie createinstallmedia (\(cimPath))")
                        let csTask2 = Process()
                        csTask2.launchPath = "/usr/bin/codesign"
                        csTask2.arguments = ["-s", "-", "-f", cimPath]
                        try csTask2.run()
                        csTask2.waitUntilExit()

                    } else {
                        if isFromMountedVolume || isCatalina || needsCodesign {
                            self.log("Tryb standardowy: kopiowanie do TEMP (powód: \(isFromMountedVolume ? "DMG" : (isCatalina ? "Catalina" : "wymaga podpisu")))")
                            DispatchQueue.main.async {
                                self.processingTitle = String(localized: "Kopiowanie plików")
                                self.processingSubtitle = String(localized: "Trwa kopiowanie plików, proszę czekać.")
                            }
                            let destinationAppURL = tempWorkURL.appendingPathComponent(sourceAppURL.lastPathComponent)
                            if fileManager.fileExists(atPath: destinationAppURL.path) { try? fileManager.removeItem(at: destinationAppURL) }

                            self.log("Rozpoczynam kopiowanie pliku .app do folderu TEMP...")
                            AppLogging.separator()
                            self.log("Rozpoczynam kopiowanie pliku .app do folderu TEMP...")
                            self.log("   Źródło: \(sourceAppURL.path)")
                            self.log("   Cel: \(destinationAppURL.path)")
                            try fileManager.copyItem(at: sourceAppURL, to: destinationAppURL)
                            self.log("Kopiowanie do TEMP zakończone.")
                            AppLogging.separator()

                            effectiveAppURL = destinationAppURL
                            didCopyToTemp = true

                            if isCatalina || needsCodesign {
                                DispatchQueue.main.async {
                                    self.processingTitle = String(localized: "Modyfikowanie plików")
                                    self.processingSubtitle = String(localized: "Podpisywanie instalatora...")
                                }
                                try self.performLocalCodesign(on: destinationAppURL)
                            }
                        } else {
                            effectiveAppURL = sourceAppURL
                            self.log("Tryb standardowy: praca na oryginalnym .app bez kopiowania: \(effectiveAppURL.path)")
                        }
                    }

                    var legacyArg = isLegacySystem ? "--applicationpath '\(effectiveAppURL.path)'" : ""
                    if isSierra { legacyArg = "--applicationpath '\(effectiveAppURL.path)'" }
                    if !legacyArg.isEmpty { self.log("Dodano argument legacy: \(legacyArg)") } else { self.log("Bez argumentu --applicationpath (nieniezbędny)") }

                    let createInstallMediaURL = effectiveAppURL.appendingPathComponent("Contents/Resources/createinstallmedia")
                    self.log("createinstallmedia: \(createInstallMediaURL.path)")

                    var bashLogic = """
                    sudo '\(createInstallMediaURL.path)' --volume '\(usbPath)' \(legacyArg) --nointeraction
                    EXIT_CODE=$?
                    """

                    if isCatalina {
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
                            echo "\(msgCatWarn1)"
                            echo "\(msgCatWarn2)"
                            echo "\(msgCatWarn3)"
                            echo "\(msgCatWarn4)"
                            echo "================================================================================"

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

                    if [ $EXIT_CODE -eq 0 ]; then
                        touch '\(terminalSuccessURL.path)'
                    else
                        touch '\(terminalErrorURL.path)'
                    fi

                    touch '\(terminalDoneURL.path)'
                    """
                }

                DispatchQueue.main.async {
                    withAnimation {
                        self.isProcessing = false
                        self.isTerminalWorking = true
                    }
                    self.log("Terminal: uruchomiono skrypt, monitoring rozpoczęty.")
                    self.startTerminalCompletionTimer(completionURL: terminalDoneURL, activeURL: terminalActiveURL, errorURL: terminalErrorURL)
                }

                let startHeader = isCatalina ? msgCatStage1 : (isMavericks ? msgMavStage1 : msgHeader)

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
                    osascript -e 'tell application "Terminal" to close front window' & exit
                fi
                """
                let scriptURL = tempWorkURL.appendingPathComponent("start_install.command")
                self.log("Zapis skryptu: \(scriptURL.path)")
                try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
                AppLogging.separator()
                NSWorkspace.shared.open(scriptURL)
                AppLogging.separator()
                self.log("Terminal otwarty ze skryptem: \(scriptURL.path)")
                AppLogging.separator()

            } catch {
                DispatchQueue.main.async {
                    withAnimation {
                        self.isProcessing = false
                        self.errorMessage = error.localizedDescription
                        self.isTabLocked = false
                        self.startUSBMonitoring()
                        self.isTerminalWorking = false
                        self.showFinishButton = false
                    }
                }
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
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(localized: "Czy na pewno chcesz przerwać?")
        alert.addButton(withTitle: String(localized: "Nie"))
        alert.addButton(withTitle: String(localized: "Tak"))
        let completionHandler = { (response: NSApplication.ModalResponse) in
            if response == .alertSecondButtonReturn {
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.isCancelling = true
                }
                performImmediateCancellation()
            }
        }
        if let window = NSApp.windows.first { alert.beginSheetModal(for: window, completionHandler: completionHandler) } else { let r = alert.runModal(); completionHandler(r) }
    }

    func performImmediateCancellation() {
        stopUSBMonitoring()
        DispatchQueue.global(qos: .userInitiated).async {
            self.unmountDMG()
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.isCancelled = true
                    self.navigateToFinish = false
                    self.isCancelling = false
                }
            }
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
        usbCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in self.checkDriveAvailability() }
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
        alert.icon = NSApp.applicationIconImage
        alert.messageText = String(localized: "Odłączono dysk USB")
        alert.informativeText = String(localized: "Dalsze działanie aplikacji zostanie zablokowane")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Kontynuuj"))
        let completionHandler = { (response: NSApplication.ModalResponse) in
            DispatchQueue.main.async {
                self.isTabLocked = false
                DispatchQueue.global(qos: .userInitiated).async { self.unmountDMG() }
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.isUSBDisconnectedLock = true
                    self.navigateToFinish = false
                }
            }
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
            self.logError("SHELL ERROR: \(msg)")
            throw NSError(domain: "macUSB", code: 999, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
}

