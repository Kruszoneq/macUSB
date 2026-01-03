import SwiftUI
import AppKit
import Foundation

final class UpdateChecker {
    static let shared = UpdateChecker()
    private init() {}

    private let versionURL = URL(string: "https://raw.githubusercontent.com/Kruszoneq/macUSB/main/version.json")!

    public func checkFromMenu() {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            presentNoUpdateAlert()
            return
        }

        URLSession.shared.dataTask(with: versionURL) { data, response, error in
            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let remoteVersion = json["version"] as? String,
                  let downloadURLString = json["url"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                self.presentNoUpdateAlert()
                return
            }

            if remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                self.presentUpdateAlert(remoteVersion: remoteVersion, downloadURL: downloadURL)
            } else {
                self.presentNoUpdateAlert()
            }
        }.resume()
    }

    private func presentUpdateAlert(remoteVersion: String, downloadURL: URL) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.icon = NSApplication.shared.applicationIconImage
            alert.alertStyle = .informational
            alert.messageText = String(localized: "Dostępna aktualizacja!")
            alert.informativeText = String(localized: "Dostępna jest nowa wersja: \(remoteVersion). Zalecamy aktualizację!")
            alert.addButton(withTitle: String(localized: "Pobierz"))
            alert.addButton(withTitle: String(localized: "Ignoruj"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }

    private func presentNoUpdateAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.icon = NSApplication.shared.applicationIconImage
            alert.alertStyle = .informational
            alert.messageText = String(localized: "Brak dostępnych aktualizacji")
            alert.informativeText = String(localized: "Korzystasz z najnowszej dostępnej wersji aplikacji")
            alert.addButton(withTitle: String(localized: "Zamknij"))
            alert.runModal()
        }
    }
}

