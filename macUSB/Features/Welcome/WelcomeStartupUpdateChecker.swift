import Foundation
import AppKit

enum WelcomeStartupUpdateResult: String {
    case upToDate
    case updateAvailable
    case failed
}

final class WelcomeStartupUpdateChecker {
    private let versionCheckURL = URL(string: "https://raw.githubusercontent.com/Kruszoneq/macUSB/main/version.json")!

    func check(completion: @escaping (WelcomeStartupUpdateResult) -> Void) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              isValidVersion(currentVersion) else {
            AppLogging.error("Update check failed: trigger=startup, current application version unavailable or invalid.", stage: .app)
            completion(.failed)
            return
        }
        AppLogging.info("Update check started: trigger=startup, currentVersion=\(currentVersion).", stage: .app)

        URLSession.shared.dataTask(with: versionCheckURL) { data, response, error in
            let finishOnMain: (WelcomeStartupUpdateResult) -> Void = { result in
                DispatchQueue.main.async {
                    completion(result)
                }
            }

            guard let data = data, error == nil,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                AppLogging.error("Update check failed: trigger=startup, details=\(error?.localizedDescription ?? "missing response data or unsuccessful HTTP response").", stage: .app)
                finishOnMain(.failed)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String],
                   let remoteVersion = json["version"],
                   let downloadLink = json["url"],
                   self.isValidVersion(remoteVersion),
                   let downloadURL = URL(string: downloadLink),
                   downloadURL.scheme == "https", downloadURL.host != nil {

                    if remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                        AppLogging.info("Update check completed: trigger=startup, newerVersion=\(remoteVersion), currentVersion=\(currentVersion).", stage: .app)
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
                            completion(.updateAvailable)
                        }
                    } else {
                        AppLogging.info("Update check completed: trigger=startup, no newer version found, currentVersion=\(currentVersion), remoteVersion=\(remoteVersion).", stage: .app)
                        finishOnMain(.upToDate)
                    }
                } else {
                    AppLogging.error("Update check failed: trigger=startup, invalid update metadata.", stage: .app)
                    finishOnMain(.failed)
                }
            } catch {
                AppLogging.error("Update check failed: trigger=startup, details=\(error.localizedDescription).", stage: .app)
                finishOnMain(.failed)
            }
        }.resume()
    }

    private func isValidVersion(_ version: String) -> Bool {
        version.range(of: #"^[0-9]+(?:\.[0-9]+)*$"#, options: .regularExpression) != nil
    }
}
