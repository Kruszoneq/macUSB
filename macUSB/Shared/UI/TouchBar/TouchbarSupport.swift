import AppKit

final class TouchbarSupport: NSObject, NSTouchBarDelegate {
    static let shared = TouchbarSupport()

    private let brandingItemIdentifier = NSTouchBarItem.Identifier("com.kruszoneq.macusb.touchbar.branding")

    private override init() {
        super.init()
    }

    func install(on window: NSWindow) {
        window.touchBar = makeTouchBar()
    }

    func makeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("com.kruszoneq.macusb.touchbar")
        touchBar.defaultItemIdentifiers = [brandingItemIdentifier, .flexibleSpace]
        touchBar.customizationAllowedItemIdentifiers = []
        return touchBar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == brandingItemIdentifier else { return nil }

        let item = NSCustomTouchBarItem(identifier: brandingItemIdentifier)
        item.customizationLabel = "macUSB Branding"
        item.view = makeBrandingView()
        return item
    }

    private func makeBrandingView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8

        let imageView = NSImageView()
        imageView.image = NSApplication.shared.applicationIconImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20)
        ])

        let label = NSTextField(labelWithAttributedString: makeBrandingText())
        label.lineBreakMode = .byTruncatingTail

        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(label)
        return stack
    }

    private func makeBrandingText() -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: MacUSBBranding.appName,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        let suffix = NSAttributedString(
            string: " - \(MacUSBBranding.touchBarSlogan)",
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        text.append(suffix)
        return text
    }
}
