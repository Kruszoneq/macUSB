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
            alert.messageText = String(localized: "Dostępna aktualizacja!")
            let remoteVersionLine = String(localized: "Dostępna jest nowa wersja: \(remoteVersion). Zalecamy aktualizację!")
            let currentVersionLine = String(localized: "Aktualnie uruchomiona wersja: \(currentVersion)")
            alert.informativeText = "\(remoteVersionLine)\n\(currentVersionLine)"
            alert.addButton(withTitle: String(localized: "Pobierz"))
            alert.addButton(withTitle: String(localized: "Ignoruj"))
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
            alert.messageText = String(localized: "Brak dostępnych aktualizacji")
            let baseLine = String(localized: "Korzystasz z najnowszej dostępnej wersji aplikacji")
            if let currentVersion {
                let currentVersionLine = String(localized: "Aktualnie uruchomiona wersja: \(currentVersion)")
                alert.informativeText = "\(baseLine)\n\(currentVersionLine)"
            } else {
                alert.informativeText = baseLine
            }
            alert.addButton(withTitle: String(localized: "Zamknij"))
            alert.runModal()
        }
    }
}
