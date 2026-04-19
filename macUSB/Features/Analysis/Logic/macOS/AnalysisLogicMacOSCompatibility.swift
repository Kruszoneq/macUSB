import SwiftUI
import Foundation

extension AnalysisLogic {
    func applyMacosCompatibilityForMountedInstaller(name: String, rawVer: String, userVisibleVersionFromMounted: String?) -> Bool {
        // Use lowercase name for detection
        let nameLower = name.lowercased()

        // Leopard/Tiger detection (PowerPC) using name, raw version, or mounted SystemVersion.plist
        let isLeopard = nameLower.contains("leopard") || rawVer.starts(with: "10.5") || (userVisibleVersionFromMounted?.hasPrefix("10.5") ?? false)
        let isTiger = nameLower.contains("tiger") || rawVer.starts(with: "10.4") || (userVisibleVersionFromMounted?.hasPrefix("10.4") ?? false)
        let isPanther = nameLower.contains("panther") || rawVer.starts(with: "10.3") || (userVisibleVersionFromMounted?.hasPrefix("10.3") ?? false)
        let isSnowLeopard = nameLower.contains("snow leopard") || rawVer.starts(with: "10.6") || (userVisibleVersionFromMounted?.hasPrefix("10.6") ?? false)

        // Disable kernel arch detection for Panther (10.3), Tiger (10.4), Leopard (10.5) and Snow Leopard (10.6). Always mark PPC flow for legacy, but do not set legacyArchInfo.
        if (isLeopard || isTiger || isPanther || isSnowLeopard) {
            self.isPPC = true // niezależnie od architektury, proces USB taki sam
            self.legacyArchInfo = nil
        }

        // Legacy versions exact recognition for mounted userVisibleVersion or fallback for legacy systems
        if isLeopard {
            if let userVisible = userVisibleVersionFromMounted {
                self.recognizedVersion = "Mac OS X Leopard \(userVisible)"
            } else if rawVer.starts(with: "10.5") {
                self.recognizedVersion = "Mac OS X Leopard \(rawVer)"
            } else {
                self.recognizedVersion = "Mac OS X Leopard"
            }
        }
        if isTiger {
            if let userVisible = userVisibleVersionFromMounted {
                self.recognizedVersion = "Mac OS X Tiger \(userVisible)"
            } else if rawVer.starts(with: "10.4") {
                self.recognizedVersion = "Mac OS X Tiger \(rawVer)"
            } else {
                self.recognizedVersion = "Mac OS X Tiger"
            }
        }
        if isPanther {
            self.logError("Wykryto niewspierany system: Mac OS X Panther (10.3). Przerywam analizę.")
            if let userVisible = userVisibleVersionFromMounted {
                self.recognizedVersion = "Mac OS X Panther \(userVisible)"
            } else if rawVer.starts(with: "10.3") {
                self.recognizedVersion = "Mac OS X Panther \(rawVer)"
            } else {
                self.recognizedVersion = "Mac OS X Panther"
            }
        }
        if isSnowLeopard {
            if let userVisible = userVisibleVersionFromMounted {
                self.recognizedVersion = "Mac OS X Snow Leopard \(userVisible)"
            } else if rawVer.starts(with: "10.6") {
                self.recognizedVersion = "Mac OS X Snow Leopard \(rawVer)"
            } else {
                self.recognizedVersion = "Mac OS X Snow Leopard"
            }
        }

        // If Panther is detected, mark as unsupported and block further processing
        if isPanther {
            self.isSystemDetected = false
            self.showUSBSection = false
            self.isPPC = false
            self.legacyArchInfo = nil
            // Show unsupported message immediately
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                self.showUnsupportedMessage = true
            }
            self.needsCodesign = false
            self.isLegacyDetected = false
            self.isRestoreLegacy = false
            self.isCatalina = false
            self.isSierra = false
            self.isMavericks = false
            self.isUnsupportedSierra = false
            return false
        }

        // Systemy niewspierane (Explicit) - USUNIĘTO CATALINĘ
        let isExplicitlyUnsupported = nameLower.contains("sierra") && !nameLower.contains("high")

        // Catalina detection
        let isCatalina = nameLower.contains("catalina") || rawVer.starts(with: "10.15")

        // Sierra detection (supported only for installer version 12.6.06)
        let isSierra = (rawVer == "12.6.06")
        let isSierraName = nameLower.contains("sierra") && !nameLower.contains("high")
        let isUnsupportedSierraVersion = isSierraName && !isSierra
        self.isUnsupportedSierra = isUnsupportedSierraVersion
        if isUnsupportedSierraVersion { self.logError("Ta wersja systemu macOS Sierra nie jest wspierana (wymagana 12.6.06).") }

        let isMavericks = nameLower.contains("mavericks") || rawVer.starts(with: "10.9")

        // Modern (Big Sur+)
        let isModern =
            nameLower.contains("tahoe") || // Dodano Tahoe
            nameLower.contains("sur") ||
            nameLower.contains("monterey") ||
            nameLower.contains("ventura") ||
            nameLower.contains("sonoma") ||
            nameLower.contains("sequoia") ||
            rawVer.starts(with: "21.") || // Dodano Tahoe (v26/21.x)
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
        self.isSystemDetected = isModern || isOldSupported || isLegacyDetected || isRestoreLegacy || isCatalina || isSierra || isMavericks

        // Catalina ma swój własny codesign, więc tu wyłączamy standardowy 'needsCodesign'
        self.needsCodesign = isOldSupported && !isModern && !isLegacyDetected
        self.isLegacyDetected = isLegacyDetected
        self.isRestoreLegacy = isRestoreLegacy
        self.isCatalina = isCatalina
        self.isSierra = isSierra
        self.isMavericks = isMavericks
        if isMavericks {
            self.shouldShowMavericksDialog = true
        }
        if isSierra {
            self.recognizedVersion = "macOS Sierra 10.12"
            self.needsCodesign = false
        }
        // Dla Leoparda/Tigera już ustawione na true powyżej, pozostaw
        self.isPPC = self.isPPC || false

        let trueFlags = [
            self.isCatalina ? "isCatalina" : nil,
            self.isSierra ? "isSierra" : nil,
            self.isLegacyDetected ? "isLegacyDetected" : nil,
            self.isRestoreLegacy ? "isRestoreLegacy" : nil,
            self.isPPC ? "isPPC" : nil,
            self.isUnsupportedSierra ? "isUnsupportedSierra" : nil,
            self.isMavericks ? "isMavericks" : nil
        ].compactMap { $0 }.joined(separator: ", ")
        self.log("Analiza zakończona. Rozpoznano: \(self.recognizedVersion)")
        self.log("Przypisane flagi: \(trueFlags.isEmpty ? "brak" : trueFlags)")
        AppLogging.separator()

        if self.isSystemDetected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUSBSection = true } }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUnsupportedMessage = true } }
        }

        return true
    }

    func applyMacosCompatibilityForAppInstaller(name: String, rawVer: String) -> Bool {
        let nameLower = name.lowercased()

        // Leopard detection (PowerPC)
        let isLeopard = nameLower.contains("leopard") || rawVer.starts(with: "10.5")
        let isTiger = nameLower.contains("tiger") || rawVer.starts(with: "10.4")
        let isPanther = nameLower.contains("panther") || rawVer.starts(with: "10.3")
        let isSnowLeopard = nameLower.contains("snow leopard") || rawVer.starts(with: "10.6")

        self.legacyArchInfo = nil

        // Dla Snow Leoparda/Leoparda/Tigera zawsze traktujemy jako PPC flow
        if isLeopard || isTiger || isSnowLeopard {
            self.isPPC = true
        }

        // Ustal dokładną wersję dla Panther/Tiger/Leopard/Snow Leopard (dla .app)
        if isPanther || isTiger || isLeopard || isSnowLeopard {
            let isExact = rawVer.starts(with: "10.3") || rawVer.starts(with: "10.4") || rawVer.starts(with: "10.5") || rawVer.starts(with: "10.6")
            let exactSuffix = isExact ? " \(rawVer)" : ""
            if isPanther {
                self.logError("Wykryto niewspierany system: Mac OS X Panther (10.3). Przerywam analizę.")
                self.recognizedVersion = "Mac OS X Panther\(exactSuffix)"
            } else if isTiger {
                self.recognizedVersion = "Mac OS X Tiger\(exactSuffix)"
            } else if isLeopard {
                self.recognizedVersion = "Mac OS X Leopard\(exactSuffix)"
            } else if isSnowLeopard {
                self.recognizedVersion = "Mac OS X Snow Leopard\(exactSuffix)"
            }
        }

        // If Panther is detected, mark as unsupported and block further processing
        if isPanther {
            self.isSystemDetected = false
            self.showUSBSection = false
            self.isPPC = false
            self.legacyArchInfo = nil
            // Show unsupported message immediately
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                self.showUnsupportedMessage = true
            }
            self.needsCodesign = false
            self.isLegacyDetected = false
            self.isRestoreLegacy = false
            self.isCatalina = false
            self.isSierra = false
            self.isMavericks = false
            self.isUnsupportedSierra = false
            return false
        }

        // Systemy niewspierane (Explicit) - USUNIĘTO CATALINĘ
        let isExplicitlyUnsupported = nameLower.contains("sierra") && !nameLower.contains("high")

        // Catalina detection
        let isCatalina = nameLower.contains("catalina") || rawVer.starts(with: "10.15")

        // Sierra detection (supported only for installer version 12.6.06)
        let isSierra = (rawVer == "12.6.06")
        let isSierraName = nameLower.contains("sierra") && !nameLower.contains("high")
        let isUnsupportedSierraVersion = isSierraName && !isSierra
        self.isUnsupportedSierra = isUnsupportedSierraVersion
        if isUnsupportedSierraVersion { self.logError("Ta wersja systemu macOS Sierra nie jest wspierana (wymagana 12.6.06).") }

        let isMavericks = nameLower.contains("mavericks") || rawVer.starts(with: "10.9")

        // Modern (Big Sur+)
        let isModern =
            nameLower.contains("tahoe") || // Dodano Tahoe
            nameLower.contains("sur") ||
            nameLower.contains("monterey") ||
            nameLower.contains("ventura") ||
            nameLower.contains("sonoma") ||
            nameLower.contains("sequoia") ||
            rawVer.starts(with: "21.") || // Dodano Tahoe (v26/21.x)
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

        self.isSystemDetected = isModern || isOldSupported || isLegacyDetected || isRestoreLegacy || isCatalina || isSierra

        self.needsCodesign = isOldSupported && !isModern && !isLegacyDetected
        self.isLegacyDetected = isLegacyDetected
        self.isRestoreLegacy = isRestoreLegacy
        self.isCatalina = isCatalina
        self.isSierra = isSierra
        self.isMavericks = isMavericks
        if isMavericks {
            self.shouldShowMavericksDialog = true
        }
        if isSierra {
            self.recognizedVersion = "macOS Sierra 10.12"
            self.needsCodesign = false
        }
        // isPPC zostało ustawione wcześniej dla Snow Leoparda/Leoparda/Tigera; dla pozostałych pozostaje false
        self.isPPC = self.isPPC || false

        let trueFlags = [
            self.isCatalina ? "isCatalina" : nil,
            self.isSierra ? "isSierra" : nil,
            self.isLegacyDetected ? "isLegacyDetected" : nil,
            self.isRestoreLegacy ? "isRestoreLegacy" : nil,
            self.isPPC ? "isPPC" : nil,
            self.isUnsupportedSierra ? "isUnsupportedSierra" : nil,
            self.isMavericks ? "isMavericks" : nil
        ].compactMap { $0 }.joined(separator: ", ")
        self.log("Analiza zakończona. Rozpoznano: \(self.recognizedVersion)")
        self.log("Przypisane flagi: \(trueFlags.isEmpty ? "brak" : trueFlags)")
        AppLogging.separator()

        if self.isSystemDetected {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUSBSection = true } }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { self.showUnsupportedMessage = true } }
        }

        return true
    }
}
