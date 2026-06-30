import Foundation

enum HelperConnectionSecurityPolicy {
    static let trustVerificationFailureMarker = "macusb_helper_trust_verification_failed"
    private static let teamIdentifier = "27NC66L8P2"

    #if DEBUG
    static let expectedHelperBundleIdentifier = "com.kruszoneq.macusb.helper.debug"
    #else
    static let expectedHelperBundleIdentifier = "com.kruszoneq.macusb.helper"
    #endif

    static let trustedHelperRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and identifier \"\(expectedHelperBundleIdentifier)\""

    static var localizedFailureTitle: String {
        String(localized: "Nie można zweryfikować helpera macUSB")
    }

    static var localizedFailureMessage: String {
        String(localized: "macUSB nie może potwierdzić, że komunikuje się z zaufanym, podpisanym helperem. Operacja została przerwana. Uruchom aktualną aplikację macUSB z katalogu Applications, a następnie wybierz Narzędzia → Napraw helpera.")
    }

    static func configure(_ connection: NSXPCConnection, machServiceName: String) {
        AppLogging.info(
            "Rozpoczynam konfigurację weryfikacji podpisu helpera XPC: machService=\(machServiceName), expectedHelperBundleID=\(expectedHelperBundleIdentifier).",
            category: "HelperService"
        )

        connection.setCodeSigningRequirement(trustedHelperRequirement)

        AppLogging.info(
            "Weryfikacja podpisu helpera XPC skonfigurowana: machService=\(machServiceName), status=OK.",
            category: "HelperService"
        )
    }

    static func isCodeSigningRequirementFailure(_ error: Error) -> Bool {
        var currentError: NSError? = error as NSError
        while let nsError = currentError {
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSXPCConnectionCodeSigningRequirementFailure {
                return true
            }
            currentError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    static func isTrustVerificationFailureMessage(_ message: String) -> Bool {
        message.contains(trustVerificationFailureMarker)
    }

    static func diagnosticSummary(for error: Error) -> String {
        let nsError = error as NSError
        var details = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)"
        ]

        if let debugDescription = nsError.userInfo["NSDebugDescription"] as? String,
           !debugDescription.isEmpty {
            details.append("debug=\(debugDescription)")
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("underlying=\(underlyingError.domain):\(underlyingError.code)")
        }

        return details.joined(separator: ", ")
    }

    static func diagnosticFailureDescription(for error: Error) -> String {
        "\(localizedFailureMessage) [\(trustVerificationFailureMarker), \(diagnosticSummary(for: error))]"
    }
}
