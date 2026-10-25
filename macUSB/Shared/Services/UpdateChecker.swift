import SwiftUI
import AppKit
import Foundation

final class UpdateChecker {
    static let shared = UpdateChecker()
    private init() {}

    private let versionURL = URL(string: "https://raw.githubusercontent.com/Kruszoneq/macUSB/main/version.json")!

    public func checkFromMenu() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        AppLogging.info("Update check started: trigger=menu, currentVersion=\(currentVersion ?? "unknown").", stage: .app)

        URLSession.shared.dataTask(with: versionURL) { data, response, error in
            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let remoteVersion = json["version"] as? String,
                  let downloadURLString = json["url"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                AppLogging.error(
                    "Update check failed: trigger=menu, details=\(error?.localizedDescription ?? "invalid response or update metadata").",
                    stage: .app
                )
                self.presentNoUpdateAlert(currentVersion: currentVersion)
                return
            }

            if let currentVersion, remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                AppLogging.info("Update check completed: trigger=menu, newerVersion=\(remoteVersion), currentVersion=\(currentVersion).", stage: .app)
                self.presentUpdateAlert(remoteVersion: remoteVersion, downloadURL: downloadURL, currentVersion: currentVersion)
            } else if let currentVersion {
                AppLogging.info("Update check completed: trigger=menu, no newer version found, currentVersion=\(currentVersion), remoteVersion=\(remoteVersion).", stage: .app)
                self.presentNoUpdateAlert(currentVersion: currentVersion)
            } else {
                AppLogging.error("Update check failed: trigger=menu, current application version unavailable, remoteVersion=\(remoteVersion).", stage: .app)
                self.presentNoUpdateAlert(currentVersion: nil)
            }
        }.resume()
    }

    private func presentUpdateAlert(remoteVersion: String, downloadURL: URL, currentVersion: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.icon = NSApplication.shared.applicationIconImage
            alert.alertStyle = .informational
            alert.messageText = String(localized: "app.update.available.title", table: "App")
            let remoteVersionLine = String(format: String(localized: "app.update.available.message", table: "App"), remoteVersion)
            let currentVersionLine = String(format: String(localized: "app.update.current_version", table: "App"), currentVersion)
            alert.informativeText = "\(remoteVersionLine)\n\(currentVersionLine)"
            alert.addButton(withTitle: String(localized: "app.update.action.download", table: "App"))
            alert.addButton(withTitle: String(localized: "app.update.action.ignore", table: "App"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }

    private func presentNoUpdateAlert(currentVersion: String?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.icon = NSApplication.shared.applicationIconImage
            alert.alertStyle = .informational
            alert.messageText = String(localized: "app.update.unavailable.title", table: "App")
            let baseLine = String(localized: "app.update.unavailable.message", table: "App")
            if let currentVersion {
                let currentVersionLine = String(format: String(localized: "app.update.current_version", table: "App"), currentVersion)
                alert.informativeText = "\(baseLine)\n\(currentVersionLine)"
            } else {
                alert.informativeText = baseLine
            }
            alert.addButton(withTitle: String(localized: "app.action.close", table: "App"))
            alert.runModal()
        }
    }
}
