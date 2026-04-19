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
        if n.contains("tahoe") { return "26" } // Dodano Tahoe
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
