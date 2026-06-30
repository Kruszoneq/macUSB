import Foundation

struct MacOSInstallerAppInspection {
    let appURL: URL
    let displayName: String?
    let rawVersion: String?
    let bundleIdentifier: String?
    let createinstallmediaURL: URL
    let installESDURL: URL
    let hasCreateinstallmedia: Bool
    let hasInstallESD: Bool
    let isAccepted: Bool
    let decisionReason: String
}

extension MacOSInstallerAppInspection {
    var appInfo: (String, String, URL)? {
        guard isAccepted, let displayName, let rawVersion else { return nil }
        return (displayName, rawVersion, appURL)
    }

    var logSummary: String {
        let name = displayName ?? "brak"
        let version = rawVersion ?? "brak"
        let bundleID = bundleIdentifier ?? "brak"
        let decision = isAccepted ? "accepted" : "rejected"
        return "name=\(name), version=\(version), bundleID=\(bundleID), createinstallmedia=\(hasCreateinstallmedia), InstallESD=\(hasInstallESD), decision=\(decision), reason=\(decisionReason)"
    }
}

extension AnalysisLogic {
    func inspectMacOSInstallerApp(at appURL: URL) -> MacOSInstallerAppInspection {
        let fileManager = FileManager.default
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let createinstallmediaURL = appURL.appendingPathComponent("Contents/Resources/createinstallmedia")
        let installESDURL = appURL.appendingPathComponent("Contents/SharedSupport/InstallESD.dmg")

        let hasCreateinstallmedia = fileManager.isRegularFile(at: createinstallmediaURL)
        let hasInstallESD = fileManager.isRegularFile(at: installESDURL)

        guard let data = try? Data(contentsOf: infoPlistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return MacOSInstallerAppInspection(
                appURL: appURL,
                displayName: nil,
                rawVersion: nil,
                bundleIdentifier: nil,
                createinstallmediaURL: createinstallmediaURL,
                installESDURL: installESDURL,
                hasCreateinstallmedia: hasCreateinstallmedia,
                hasInstallESD: hasInstallESD,
                isAccepted: false,
                decisionReason: "missing_or_invalid_info_plist"
            )
        }

        let displayName = (dict["CFBundleDisplayName"] as? String) ?? appURL.lastPathComponent
        let rawVersion = (dict["CFBundleShortVersionString"] as? String) ?? "?"
        let bundleIdentifier = dict["CFBundleIdentifier"] as? String
        let isRestoreLegacy = isRestoreLegacyInstallerMetadata(name: displayName, rawVersion: rawVersion)
        let isPanther = isPantherInstallerMetadata(name: displayName, rawVersion: rawVersion)

        let isAccepted: Bool
        let decisionReason: String
        if hasCreateinstallmedia {
            isAccepted = true
            decisionReason = "createinstallmedia_present"
        } else if hasInstallESD && isRestoreLegacy {
            isAccepted = true
            decisionReason = "restore_legacy_installesd_present"
        } else if isPanther {
            isAccepted = true
            decisionReason = "panther_recognized_for_unsupported_routing"
        } else if hasInstallESD {
            isAccepted = false
            decisionReason = "installesd_without_restore_legacy_metadata"
        } else {
            isAccepted = false
            decisionReason = "missing_required_installer_payload"
        }

        return MacOSInstallerAppInspection(
            appURL: appURL,
            displayName: displayName,
            rawVersion: rawVersion,
            bundleIdentifier: bundleIdentifier,
            createinstallmediaURL: createinstallmediaURL,
            installESDURL: installESDURL,
            hasCreateinstallmedia: hasCreateinstallmedia,
            hasInstallESD: hasInstallESD,
            isAccepted: isAccepted,
            decisionReason: decisionReason
        )
    }

    func applyInvalidMacOSInstallerAppState(reason: String) {
        logError("Odrzucono aplikację .app jako instalator macOS: \(reason)")
        recognizedVersion = String(localized: "Nie rozpoznano instalatora")
        sourceAppURL = nil
        detectedSystemIcon = nil
        mountedDMGPath = nil
        isAnalyzing = false
        isSystemDetected = false
        showUSBSection = false
        showUnsupportedMessage = false
        needsCodesign = true
        isLegacyDetected = false
        isRestoreLegacy = false
        isCatalina = false
        isSierra = false
        isMavericks = false
        isUnsupportedSierra = false
        isPPC = false
        legacyArchInfo = nil
        userSkippedAnalysis = false
        shouldShowMavericksDialog = false
        shouldShowAlreadyMountedSourceAlert = false
        selectedDrive = nil
        selectedDriveSelectionID = nil
        isCapacitySufficient = false
        capacityCheckFinished = false
        requiredUSBCapacityGB = nil
        resetLinuxDetectionState()
        resetWindowsDetectionState()
        AppLogging.separator()
    }

    private func isRestoreLegacyInstallerMetadata(name: String, rawVersion: String) -> Bool {
        let nameLower = name.lowercased()
        return nameLower.contains("mountain lion") ||
            nameLower.contains("lion") ||
            rawVersion.starts(with: "10.8") ||
            rawVersion.starts(with: "10.7")
    }

    private func isPantherInstallerMetadata(name: String, rawVersion: String) -> Bool {
        let nameLower = name.lowercased()
        return nameLower.contains("panther") || rawVersion.starts(with: "10.3")
    }
}

private extension FileManager {
    func isRegularFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue
    }
}
