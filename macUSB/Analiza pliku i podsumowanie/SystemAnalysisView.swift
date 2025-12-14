import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

struct SystemAnalysisView: View {
    
    @Binding var isTabLocked: Bool
    
    @State private var selectedFilePath: String = ""
    @State private var selectedFileUrl: URL?
    @State private var recognizedVersion: String = ""
    @State private var sourceAppURL: URL?
    @State private var mountedDMGPath: String? = nil
    
    @State private var isAnalyzing: Bool = false
    @State private var isSystemDetected: Bool = false
    @State private var showUSBSection: Bool = false
    @State private var showUnsupportedMessage: Bool = false
    
    // Flagi logiki systemowej
    @State private var needsCodesign: Bool = true
    @State private var isLegacyDetected: Bool = false
    @State private var isRestoreLegacy: Bool = false
    // NOWOŚĆ: Flaga dla Cataliny
    @State private var isCatalina: Bool = false
    
    @State private var availableDrives: [USBDrive] = []
    @State private var selectedDrive: USBDrive?
    
    let driveRefreshTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    @State private var isCapacitySufficient: Bool = false
    @State private var capacityCheckFinished: Bool = false
    @State private var navigateToInstall: Bool = false
    
    @State private var isDragTargeted: Bool = false
    @State private var analysisWindowHandler: AnalysisWindowHandler?
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        
                        Text("Wybór systemu macOS")
                            .font(.title)
                            .bold()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 5)
                        
                        // ETAP 1: PLIK
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Wybierz plik .dmg").font(.headline)
                            
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle.fill").font(.title2).foregroundColor(.secondary).frame(width: 32)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Wymagania").font(.headline).foregroundColor(.primary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("• Plik .dmg musi zawierać instalator systemu macOS lub Mac OS X")
                                        Text("• Wymagane jest co najmniej 15 GB wolnego miejsca na dysku")
                                    }
                                    .font(.subheadline).foregroundColor(.secondary)
                                }
                            }
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1)).cornerRadius(8)
                            
                            HStack {
                                TextField(String(localized: "Ścieżka..."), text: $selectedFilePath).textFieldStyle(.roundedBorder).disabled(true)
                                Button(String(localized: "Wybierz")) { selectDMGFile() }
                                Button(String(localized: "Analizuj")) { startAnalysis() }
                                    .buttonStyle(.borderedProminent).tint(.accentColor)
                                    .disabled(selectedFilePath.isEmpty || isAnalyzing)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isDragTargeted ? Color.accentColor : Color.clear, lineWidth: isDragTargeted ? 3 : 0)
                                .background(isDragTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                        .cornerRadius(12)
                        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in return handleDrop(providers: providers) }
                        
                        if selectedFilePath.isEmpty {
                            HStack(alignment: .center) {
                                Image(systemName: "doc.badge.plus").font(.title2).foregroundColor(.secondary).frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Oczekiwanie na plik .dmg...").font(.subheadline).foregroundColor(.secondary)
                                    Text("Wybierz go ręcznie lub przeciągnij powyżej").font(.caption).foregroundColor(.secondary.opacity(0.8))
                                }
                                Spacer()
                            }
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.05)).cornerRadius(8).transition(.opacity)
                        } else {
                            if isAnalyzing {
                                VStack(alignment: .leading, spacing: 20) {
                                    HStack(spacing: 15) {
                                        Image(systemName: "internaldrive").font(.title2).foregroundColor(.accentColor).frame(width: 32)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("Analizowanie").font(.headline)
                                            HStack(spacing: 8) {
                                                Text("Trwa analizowanie pliku .dmg, proszę czekać").font(.subheadline).foregroundColor(.secondary)
                                                ProgressView().controlSize(.small)
                                            }
                                        }
                                    }
                                }
                                .padding().frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.1)).cornerRadius(10).transition(.opacity)
                            }
                            
                            if !recognizedVersion.isEmpty && !isAnalyzing {
                                VStack(alignment: .leading, spacing: 20) {
                                    let isValid = sourceAppURL != nil
                                    if isValid {
                                        HStack(alignment: .center) {
                                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green).frame(width: 32)
                                            VStack(alignment: .leading) {
                                                Text("Pomyślnie wykryto system").font(.caption).foregroundColor(.secondary)
                                                Text(recognizedVersion).font(.headline).foregroundColor(.green)
                                            }
                                        }
                                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.green.opacity(0.1)).cornerRadius(8)
                                    } else {
                                        HStack(alignment: .center) {
                                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red).frame(width: 32)
                                            VStack(alignment: .leading) {
                                                Text("Błąd analizy").font(.caption).foregroundColor(.secondary)
                                                Text("Nie znaleziono instalatora systemu macOS").font(.headline).foregroundColor(.red)
                                            }
                                        }
                                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.red.opacity(0.1)).cornerRadius(8)
                                    }
                                    
                                    if isValid {
                                        if isSystemDetected {
                                            if showUSBSection {
                                                Spacer().frame(height: 12)
                                                usbSelectionSection
                                                    .id("usbSection")
                                                    .transition(.opacity)
                                            }
                                        } else {
                                            if showUnsupportedMessage {
                                                HStack(alignment: .center) {
                                                    Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundColor(.orange).frame(width: 32)
                                                    Text("Wybrany system nie jest wspierany przez aplikację").foregroundColor(.orange).font(.headline)
                                                }
                                                .padding().frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color.orange.opacity(0.1)).cornerRadius(8).transition(.opacity)
                                            }
                                        }
                                    }
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: showUSBSection) { show in
                    if show { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.easeOut(duration: 0.5)) { proxy.scrollTo("usbSection", anchor: .top) } } }
                }
            }
            
            if selectedDrive != nil && capacityCheckFinished && isCapacitySufficient {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Button(action: { isTabLocked = true; navigateToInstall = true }) {
                            HStack { Text("Przejdź dalej"); Image(systemName: "arrow.right.circle.fill") }
                                .frame(maxWidth: .infinity).padding(8)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).tint(Color.accentColor)
                    }
                    .padding().background(Color(NSColor.windowBackgroundColor))
                }
                .transition(.move(edge: .bottom))
            }
        }
        .background(
            Group {
                if let appURL = sourceAppURL {
                    NavigationLink(
                        destination: UniversalInstallationView(
                            sourceAppURL: appURL,
                            targetDrive: selectedDrive,
                            systemName: recognizedVersion,
                            needsCodesign: needsCodesign,
                            isLegacySystem: isLegacyDetected,
                            isRestoreLegacy: isRestoreLegacy,
                            // PRZEKAZANIE FLAGI CATALINA
                            isCatalina: isCatalina,
                            rootIsActive: $navigateToInstall,
                            isTabLocked: $isTabLocked
                        ),
                        isActive: $navigateToInstall
                    ) { EmptyView() }
                    .hidden()
                }
            }
        )
        .background(
            WindowAccessor_System { window in
                if self.analysisWindowHandler == nil {
                    let handler = AnalysisWindowHandler(
                        onCleanup: {
                            if let path = self.mountedDMGPath {
                                let task = Process(); task.launchPath = "/usr/bin/hdiutil"; task.arguments = ["detach", path, "-force"]; try? task.run(); task.waitUntilExit()
                            }
                        }
                    )
                    window.delegate = handler
                    self.analysisWindowHandler = handler
                }
            }
        )
        .onReceive(driveRefreshTimer) { _ in if isSystemDetected { refreshDrives() } }
        .onAppear { refreshDrives() }
        .navigationTitle("macUSB")
        .navigationBarBackButtonHidden(true)
    }
    
    var usbSelectionSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Wybór dysku USB").font(.headline)
            HStack(alignment: .top) {
                Image(systemName: "externaldrive.fill").font(.title2).foregroundColor(.secondary).frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Wymagania sprzętowe").font(.headline)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("• Do utworzenia instalatora potrzebny jest dysk USB o pojemności minimum 16 GB").font(.subheadline).foregroundColor(.secondary)
                        Text("• Zalecane jest użycie dysku w standardzie USB 3.0 lub szybszym").font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.gray.opacity(0.1)).cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Wybierz docelowy dysk USB:").font(.subheadline)
                if availableDrives.isEmpty {
                    HStack {
                        Image(systemName: "externaldrive.badge.xmark").font(.title2).foregroundColor(.red).frame(width: 32)
                        VStack(alignment: .leading) {
                            Text("Nie wykryto dysku USB").font(.headline).foregroundColor(.red)
                            Text("Podłącz dysk USB i poczekaj na wykrycie...").font(.caption).foregroundColor(.red.opacity(0.8))
                        }
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.1)).cornerRadius(8)
                } else {
                    HStack {
                        Picker("", selection: $selectedDrive) {
                            Text("Wybierz...").tag(nil as USBDrive?)
                            ForEach(availableDrives) { drive in Text(drive.displayName).tag(drive as USBDrive?) }
                        }
                        .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .onChange(of: selectedDrive) { _ in checkCapacity() }
            
            if selectedDrive == nil {
                HStack(alignment: .center) {
                    Image(systemName: "externaldrive").font(.title2).foregroundColor(.secondary).frame(width: 32)
                    Text("Oczekiwanie na wybór docelowego dysku USB...").font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.gray.opacity(0.05)).cornerRadius(8).transition(.opacity)
            } else {
                if capacityCheckFinished && !isCapacitySufficient {
                    HStack {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red).frame(width: 32)
                        VStack(alignment: .leading) {
                            Text("Wybrany dysk USB ma za małą pojemność").font(.headline).foregroundColor(.red)
                            Text("Wymagane jest minimum 16 GB.").font(.caption).foregroundColor(.red.opacity(0.8))
                        }
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.1)).cornerRadius(8).transition(.opacity)
                }
                if capacityCheckFinished && isCapacitySufficient {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack(alignment: .center) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundColor(.orange).frame(width: 32)
                            VStack(alignment: .leading) {
                                Text("UWAGA!").font(.headline).foregroundColor(.orange)
                                Text("Wszystkie pliki na wybranym dysku USB zostaną bezpowrotnie usunięte!").font(.subheadline).foregroundColor(.orange.opacity(0.8))
                            }
                        }
                        .padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.1)).cornerRadius(8)
                    }
                    .transition(.opacity)
                }
            }
        }
    }
    
    // --- FUNKCJE LOGIKI ---
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { processDroppedURL(url) }
                else if let url = item as? URL { processDroppedURL(url) }
            }
            return true
        }
        return false
    }
    
    func processDroppedURL(_ url: URL) {
        DispatchQueue.main.async {
            if url.pathExtension.lowercased() == "dmg" {
                withAnimation {
                    self.selectedFilePath = url.path; self.selectedFileUrl = url
                    self.recognizedVersion = ""; self.isSystemDetected = false; self.sourceAppURL = nil
                    self.selectedDrive = nil; self.capacityCheckFinished = false
                    self.showUSBSection = false; self.showUnsupportedMessage = false
                }
            }
        }
    }
    
    func selectDMGFile() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.diskImage]; p.allowsMultipleSelection = false
        p.begin { if $0 == .OK, let url = p.url {
            withAnimation {
                selectedFilePath = url.path; selectedFileUrl = url
                recognizedVersion = ""; isSystemDetected = false; sourceAppURL = nil
                selectedDrive = nil; capacityCheckFinished = false
                showUSBSection = false; showUnsupportedMessage = false
            }
        }}
    }
    
    func startAnalysis() {
        guard let url = selectedFileUrl else { return }
        withAnimation { isAnalyzing = true }
        selectedDrive = nil; capacityCheckFinished = false
        showUSBSection = false; showUnsupportedMessage = false
        let oldMountPath = self.mountedDMGPath
        DispatchQueue.global(qos: .userInitiated).async {
            if let path = oldMountPath {
                let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil"); task.arguments = ["detach", path, "-force"]; try? task.run(); task.waitUntilExit()
            }
            let result = mountAndReadInfo(dmgUrl: url)
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    self.isAnalyzing = false
                    if let (_, _, _, mp) = result { self.mountedDMGPath = mp } else { self.mountedDMGPath = nil }
                    if let (name, rawVer, appURL, _) = result {
                        let friendlyVer = formatMarketingVersion(raw: rawVer, name: name)
                        var cleanName = name
                        cleanName = cleanName.replacingOccurrences(of: "Install ", with: "")
                        cleanName = cleanName.replacingOccurrences(of: "macOS ", with: "")
                        cleanName = cleanName.replacingOccurrences(of: "Mac OS X ", with: "")
                        cleanName = cleanName.replacingOccurrences(of: "OS X ", with: "")
                        let prefix = name.contains("macOS") ? "macOS" : (name.contains("OS X") ? "OS X" : "macOS")
                        
                        self.recognizedVersion = "\(prefix) \(cleanName) \(friendlyVer)"
                        self.sourceAppURL = appURL
                        
                        let nameLower = name.lowercased()
                        
                        // Systemy niewspierane (Explicit) - USUNIĘTO CATALINĘ
                        let isExplicitlyUnsupported = nameLower.contains("sierra") && !nameLower.contains("high")
                        
                        // Catalina detection
                        let isCatalina = nameLower.contains("catalina") || rawVer.starts(with: "10.15")
                        
                        // Modern (Big Sur+)
                        let isModern =
                            nameLower.contains("sur") ||
                            nameLower.contains("monterey") ||
                            nameLower.contains("ventura") ||
                            nameLower.contains("sonoma") ||
                            nameLower.contains("sequoia") ||
                            rawVer.starts(with: "11.") ||
                            (rawVer.starts(with: "12.") && !isExplicitlyUnsupported) ||
                            (rawVer.starts(with: "13.") && !nameLower.contains("high")) ||
                            (rawVer.starts(with: "14.") && !nameLower.contains("mojave")) ||
                            (rawVer.starts(with: "15.") && !isExplicitlyUnsupported)
                        
                        // Old Supported (Mojave + High Sierra)
                        let isOldSupported =
                            nameLower.contains("mojave") ||
                            nameLower.contains("high sierra") ||
                            rawVer.starts(with: "10.14") ||
                            rawVer.starts(with: "10.13") ||
                            (rawVer.starts(with: "14.") && nameLower.contains("mojave")) ||
                            (rawVer.starts(with: "13.") && nameLower.contains("high"))

                        // Legacy No Codesign (Yosemite + El Capitan)
                        let isLegacyDetected =
                            nameLower.contains("yosemite") ||
                            nameLower.contains("el capitan") ||
                            rawVer.starts(with: "10.10") ||
                            rawVer.starts(with: "10.11")
                        
                        // Legacy Restore (Lion + Mountain Lion)
                        let isRestoreLegacy =
                            nameLower.contains("mountain lion") ||
                            nameLower.contains("lion") ||
                            rawVer.starts(with: "10.8") ||
                            rawVer.starts(with: "10.7")
                        
                        // ZMIANA: Dodanie isCatalina do isSystemDetected
                        self.isSystemDetected = isModern || isOldSupported || isLegacyDetected || isRestoreLegacy || isCatalina
                        
                        // Catalina ma swój własny codesign, więc tu wyłączamy standardowy 'needsCodesign'
                        self.needsCodesign = isOldSupported && !isModern && !isLegacyDetected
                        self.isLegacyDetected = isLegacyDetected
                        self.isRestoreLegacy = isRestoreLegacy
                        self.isCatalina = isCatalina
                        
                        if self.isSystemDetected {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUSBSection = true } }
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUnsupportedMessage = true } }
                        }
                    } else {
                        // Użyto String(localized:) aby ten ciąg został wykryty, mimo że jest przypisywany do zmiennej
                        self.recognizedVersion = String(localized: "Nie rozpoznano instalatora")
                    }
                }
            }
        }
    }
    
    func formatMarketingVersion(raw: String, name: String) -> String {
        let n = name.lowercased()
        if n.contains("sequoia") { return "15" }
        if n.contains("sonoma") { return "14" }
        if n.contains("ventura") { return "13" }
        if n.contains("monterey") { return "12" }
        if n.contains("big sur") { return "11" }
        if n.contains("catalina") { return "10.15" }
        if n.contains("mojave") { return "10.14" }
        if n.contains("high sierra") { return "10.13" }
        if n.contains("sierra") && !n.contains("high") { return "10.12" }
        if n.contains("el capitan") { return "10.11" }
        if n.contains("yosemite") { return "10.10" }
        if n.contains("mavericks") { return "10.9" }
        if n.contains("mountain lion") { return "10.8" }
        if n.contains("lion") { return "10.7" }
        return raw
    }
    
    func mountAndReadInfo(dmgUrl: URL) -> (String, String, URL, String)? {
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", dmgUrl.path, "-plist", "-nobrowse", "-readonly"]
        let pipe = Pipe(); task.standardOutput = pipe; try? task.run(); task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any], let entities = plist["system-entities"] as? [[String: Any]] else { return nil }
        for e in entities {
            if let mp = e["mount-point"] as? String {
                let mUrl = URL(fileURLWithPath: mp)
                if let item = try? FileManager.default.contentsOfDirectory(at: mUrl, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) {
                    let plistUrl = item.appendingPathComponent("Contents/Info.plist")
                    if let d = try? Data(contentsOf: plistUrl), let dict = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] {
                        let name = (dict["CFBundleDisplayName"] as? String) ?? item.lastPathComponent
                        let ver = (dict["CFBundleShortVersionString"] as? String) ?? "?"
                        return (name, ver, item, mp)
                    }
                }
            }
        }
        return nil
    }
    func refreshDrives() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeTotalCapacityKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: .skipHiddenVolumes) else { return }
        let currentSelectedURL = selectedDrive?.url
        let foundDrives = urls.compactMap { url -> USBDrive? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), let isRemovable = v.volumeIsRemovable, isRemovable, let isInternal = v.volumeIsInternal, !isInternal, let name = v.volumeName else { return nil }
            let size = ByteCountFormatter.string(fromByteCount: Int64(v.volumeTotalCapacity ?? 0), countStyle: .file)
            let deviceName = getBSDName(from: url)
            return USBDrive(name: name, device: deviceName, size: size, url: url)
        }
        self.availableDrives = foundDrives
        if let currentURL = currentSelectedURL {
            if let stillConnectedDrive = foundDrives.first(where: { $0.url == currentURL }) { selectedDrive = stillConnectedDrive } else { selectedDrive = nil; capacityCheckFinished = false }
        } else { if selectedDrive != nil { selectedDrive = nil; capacityCheckFinished = false } }
    }
    func checkCapacity() {
        guard let drive = selectedDrive else { capacityCheckFinished = false; return }
        if let values = try? drive.url.resourceValues(forKeys: [.volumeTotalCapacityKey]), let capacity = values.volumeTotalCapacity {
            let minCapacity: Int = 15_000_000_000
            withAnimation { isCapacitySufficient = capacity >= minCapacity; capacityCheckFinished = true }
        } else { isCapacitySufficient = false; capacityCheckFinished = true }
    }
    func getBSDName(from url: URL) -> String {
        return url.withUnsafeFileSystemRepresentation { ptr in
            guard let ptr = ptr else { return "unknown" }
            var stat = statfs(); if statfs(ptr, &stat) == 0 { var raw = stat.f_mntfromname; return withUnsafePointer(to: &raw) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0).replacingOccurrences(of: "/dev/", with: "") } } }
            return "unknown"
        } ?? "unknown"
    }
}
struct WindowAccessor_System: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView { let view = NSView(); DispatchQueue.main.async { if let window = view.window { context.coordinator.callback(window) } }; return view }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(callback: callback) }
    class Coordinator { let callback: (NSWindow) -> Void; init(callback: @escaping (NSWindow) -> Void) { self.callback = callback } }
}
class AnalysisWindowHandler: NSObject, NSWindowDelegate {
    let onCleanup: () -> Void; init(onCleanup: @escaping () -> Void) { self.onCleanup = onCleanup }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onCleanup(); return true }
}
