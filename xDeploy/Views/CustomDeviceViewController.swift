import AppKit

final class CustomDeviceViewController: NSViewController {
    private var customDeviceName: String?
    private let isRunMode: Bool
    private let onDeploy: (String) -> Void

    // MARK: - UI Elements

    private let deviceNameField: NSTextField = .init()

    // MARK: - Init

    init(customDeviceName: String?, isRunMode: Bool, onDeploy: @escaping (String) -> Void) {
        self.customDeviceName = customDeviceName
        self.isRunMode = isRunMode
        self.onDeploy = onDeploy
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 160))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.populateField()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Make the text field first responder when the sheet appears
        view.window?.makeFirstResponder(self.deviceNameField)
    }

    // MARK: - UI Setup

    private func setupUI() {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        // Title
        let titleLabel = NSTextField(labelWithString: "Custom Device")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        stackView.addArrangedSubview(titleLabel)

        // Info
        let infoLabel = NSTextField(wrappingLabelWithString: "Enter a device name as it appears in Xcode.")
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(infoLabel)

        // Form field
        stackView.addArrangedSubview(self.createFormRow(label: "Device Name:", field: self.deviceNameField))

        // Buttons
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"

        let actionLabel = self.isRunMode ? "Run Now" : "Install Only"
        let deployButton = NSButton(title: actionLabel, target: self, action: #selector(deploy))
        deployButton.keyEquivalent = "\r"
        deployButton.bezelStyle = .rounded

        buttonStack.addArrangedSubview(NSView())
        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(deployButton)

        stackView.addArrangedSubview(buttonStack)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            buttonStack.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            infoLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor),
        ])
    }

    private func createFormRow(label: String, field: NSTextField) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 13)
        labelView.alignment = .right
        labelView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        field.placeholderString = "Device Name"
        field.font = .systemFont(ofSize: 13)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(labelView)
        row.addArrangedSubview(field)

        NSLayoutConstraint.activate([
            labelView.widthAnchor.constraint(equalToConstant: 100),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])

        return row
    }

    private func populateField() {
        self.deviceNameField.stringValue = self.customDeviceName ?? ""
    }

    @objc private func cancel() {
        dismiss(nil)
    }

    @objc private func deploy() {
        let deviceName = self.deviceNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceName.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Missing Device Name"
            alert.informativeText = "Please enter a device name."
            alert.runModal()
            return
        }

        self.onDeploy(deviceName)
        dismiss(nil)
    }
}
