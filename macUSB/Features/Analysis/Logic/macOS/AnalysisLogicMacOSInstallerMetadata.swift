import Foundation

extension AnalysisLogic {
    func updateRequiredUSBCapacity(rawVersion: String, name: String) {
        guard let majorVersion = marketingMajorVersion(raw: rawVersion, name: name) else {
            requiredUSBCapacityGB = nil
            return
        }
        requiredUSBCapacityGB = (majorVersion >= 15) ? 32 : 16
    }

    func marketingMajorVersion(raw: String, name: String) -> Int? {
        let marketingVersion = formatMarketingVersion(raw: raw, name: name)
        guard let majorToken = marketingVersion.split(separator: ".").first else { return nil }
        return Int(majorToken)
    }

    func formatMarketingVersion(raw: String, name: String) -> String {
        let n = name.lowercased()
        if n.contains("golden gate") { return "27" }
        if n.contains("tahoe") { return "26" }
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
        if n.contains("snow leopard") { return "10.6" }
        if n.contains("panther") { return "10.3" }
        return raw
    }

    func formatDetectedMacOSName(rawVersion: String, name: String) -> String {
        if name.localizedCaseInsensitiveContains("golden gate") {
            return "macOS 27 Golden Gate"
        }

        var cleanName = name
        cleanName = cleanName.replacingOccurrences(of: "Install ", with: "")
        cleanName = cleanName.replacingOccurrences(of: "macOS ", with: "")
        cleanName = cleanName.replacingOccurrences(of: "Mac OS X ", with: "")
        cleanName = cleanName.replacingOccurrences(of: "OS X ", with: "")
        cleanName = cleanName.replacingOccurrences(
            of: #"\s+(?:(?:Public|Developer)\s+)?(?:Beta|Seed|Preview)(?:\s+\d+)?$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleanName = cleanName.replacingOccurrences(
            of: #"\s+(?:Release Candidate|RC)(?:\s+\d+)?$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleanName = cleanName.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefix = name.contains("macOS") ? "macOS" : (name.contains("OS X") ? "OS X" : "macOS")
        let marketingVersion = formatMarketingVersion(raw: rawVersion, name: name)
        return "\(prefix) \(cleanName) \(marketingVersion)"
    }

    func detectBetaInstaller(name: String, appURL: URL) -> Bool {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        var bundleIdentifier = ""

        if let data = try? Data(contentsOf: infoPlistURL),
           let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            bundleIdentifier = dictionary["CFBundleIdentifier"] as? String ?? ""
        }

        let normalizedName = name.lowercased()
        let normalizedBundleIdentifier = bundleIdentifier.lowercased()
        let nameSignals = [
            "beta",
            "seed",
            "release candidate",
            " preview"
        ]
        let detectedFromName = nameSignals.contains { normalizedName.contains($0) }
            || normalizedName.range(of: #"\brc(?:\s+\d+)?\b"#, options: .regularExpression) != nil
        let detectedFromBundleIdentifier = normalizedBundleIdentifier.contains(".seed.")
            || normalizedBundleIdentifier.hasSuffix(".seed")

        let isBeta = detectedFromName || detectedFromBundleIdentifier
        log(
            "Klasyfikacja prerelease instalatora: beta=\(isBeta), name_signal=\(detectedFromName), seed_bundle_id=\(detectedFromBundleIdentifier), bundle_id=\(bundleIdentifier.isEmpty ? "brak" : bundleIdentifier)"
        )
        return isBeta
    }

    func readAppInfo(appUrl: URL) -> (String, String, URL)? {
        let plistUrl = appUrl.appendingPathComponent("Contents/Info.plist")
        self.log("Odczyt Info.plist: \(plistUrl.path)")
        if let d = try? Data(contentsOf: plistUrl),
           let dict = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] {
            let name = (dict["CFBundleDisplayName"] as? String) ?? appUrl.lastPathComponent
            let ver = (dict["CFBundleShortVersionString"] as? String) ?? "?"
            self.log("Odczytano Info.plist: name=\(name), version=\(ver)")
            return (name, ver, appUrl)
        }
        self.logError("Nie udało się odczytać Info.plist")
        return nil
    }
}
