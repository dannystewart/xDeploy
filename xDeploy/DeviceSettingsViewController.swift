import AppKit

final class DeviceSettingsViewController: NSViewController {
    private var deviceConfig: DeviceConfig
    private let onSave: (DeviceConfig) -> Void

    // MARK: - UI Elements

    private let iPhoneField: NSTextField = .init()
    private let iPadField: NSTextField = .init()

    // MARK: - Init

    init(deviceConfig: DeviceConfig, onSave: @escaping (DeviceConfig) -> Void) {
        self.deviceConfig = deviceConfig
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        populateFields()
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
        let titleLabel = NSTextField(labelWithString: "Device Settings")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        stackView.addArrangedSubview(titleLabel)

        // Info
        let infoLabel = NSTextField(wrappingLabelWithString: "Enter device names as they appear in Xcode. These are used with the devicectl command.")
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(infoLabel)

        // Form fields
        stackView.addArrangedSubview(createFormRow(label: "iPhone:", field: iPhoneField))
        stackView.addArrangedSubview(createFormRow(label: "iPad:", field: iPadField))

        // Buttons
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        buttonStack.addArrangedSubview(NSView())
        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(saveButton)

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

        field.font = .systemFont(ofSize: 13)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(labelView)
        row.addArrangedSubview(field)

        NSLayoutConstraint.activate([
            labelView.widthAnchor.constraint(equalToConstant: 60),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
        ])

        return row
    }

    private func populateFields() {
        iPhoneField.stringValue = deviceConfig.iPhoneName
        iPadField.stringValue = deviceConfig.iPadName
    }

    @objc private func cancel() {
        dismiss(nil)
    }

    @objc private func save() {
        guard !iPhoneField.stringValue.isEmpty, !iPadField.stringValue.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Missing Fields"
            alert.informativeText = "Please enter both device names."
            alert.runModal()
            return
        }

        let newConfig = DeviceConfig(
            iPhoneName: iPhoneField.stringValue,
            iPadName: iPadField.stringValue,
        )

        onSave(newConfig)
        dismiss(nil)
    }
}
