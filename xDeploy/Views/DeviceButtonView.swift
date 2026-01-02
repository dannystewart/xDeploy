import AppKit

/// A large button with an icon and label, used for device selection.
/// Lights up blue when `isDeploying` is true.
final class DeviceButtonView: NSView {
    var isDeploying: Bool = false {
        didSet { self.updateAppearance() }
    }

    var isEnabled: Bool = true {
        didSet { self.updateAppearance() }
    }

    var onClick: (() -> Void)?

    private let iconView: NSImageView
    private let label: NSTextField
    private var trackingArea: NSTrackingArea?

    private var isHovered = false
    private var isPressed = false

    init(title: String, symbolName: String) {
        self.iconView = NSImageView()
        self.label = NSTextField(labelWithString: title)

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8

        // Configure icon
        let config = NSImage.SymbolConfiguration(pointSize: 36, weight: .light)
        self.iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        self.iconView.imageScaling = .scaleProportionallyUpOrDown
        self.iconView.translatesAutoresizingMaskIntoConstraints = false

        // Configure label
        self.label.font = .systemFont(ofSize: 16, weight: .medium)
        self.label.alignment = .left
        self.label.isBezeled = false
        self.label.isBordered = false
        self.label.drawsBackground = false
        self.label.translatesAutoresizingMaskIntoConstraints = false

        // Use a stack view to group icon and label, then center the stack
        let contentStack = NSStackView(views: [iconView, label])
        contentStack.orientation = .horizontal
        contentStack.spacing = 10
        contentStack.alignment = .centerY
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        // Center the content stack within the button (with slight left offset for visual balance)
        NSLayoutConstraint.activate([
            self.iconView.widthAnchor.constraint(equalToConstant: 42),
            self.iconView.heightAnchor.constraint(equalToConstant: 42),

            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -4),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])

        self.updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        self.trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil,
        )
        addTrackingArea(self.trackingArea!)
    }

    override func mouseEntered(with _: NSEvent) {
        guard self.isEnabled else { return }
        self.isHovered = true
        self.updateAppearance()
    }

    override func mouseExited(with _: NSEvent) {
        self.isHovered = false
        self.isPressed = false
        self.updateAppearance()
    }

    override func mouseDown(with _: NSEvent) {
        guard self.isEnabled else { return }
        self.isPressed = true
        self.updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard self.isEnabled, self.isPressed else { return }
        self.isPressed = false

        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            self.onClick?()
        }

        self.updateAppearance()
    }

    private func updateAppearance() {
        let backgroundColor: NSColor
        let contentColor: NSColor

        if !self.isEnabled {
            backgroundColor = .secondarySystemFill
            contentColor = .disabledControlTextColor
        } else if self.isDeploying {
            // Blue highlight while deploying
            if self.isPressed {
                backgroundColor = NSColor.controlAccentColor.blended(withFraction: 0.2, of: .black) ?? .controlAccentColor
            } else if self.isHovered {
                backgroundColor = NSColor.controlAccentColor.blended(withFraction: 0.1, of: .white) ?? .controlAccentColor
            } else {
                backgroundColor = .controlAccentColor
            }
            contentColor = .white
        } else {
            if self.isPressed {
                backgroundColor = NSColor.gray.withAlphaComponent(0.45)
            } else if self.isHovered {
                backgroundColor = NSColor.gray.withAlphaComponent(0.35)
            } else {
                backgroundColor = NSColor.gray.withAlphaComponent(0.25)
            }
            contentColor = .labelColor
        }

        layer?.backgroundColor = backgroundColor.cgColor
        self.iconView.contentTintColor = contentColor
        self.label.textColor = contentColor
    }
}
