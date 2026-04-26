enum MacUSBBranding {
    static let appName = "macUSB"
    static let sloganPrimary = "Download. Flash. Boot."
    static let sloganSecondary = "The all-in-one USB creator for Mac"

    static var welcomeSlogan: String {
        "\(sloganPrimary)\n\(sloganSecondary)"
    }

    static var touchBarSlogan: String {
        "\(sloganPrimary) \(sloganSecondary)"
    }
}
