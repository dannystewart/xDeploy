import AppKit
import UniformTypeIdentifiers

final class ProjectEditorViewController: NSViewController {
    private var project: Project?
    private let onSave: (Project) -> Void

    // MARK: - UI Elements

    private let nameField: NSTextField = .init()
    private let projectPathField: NSTextField = .init()
    private let schemeField: NSTextField = .init()
    private let bundleIDField: NSTextField = .init()
    private let derivedDataField: NSTextField = .init()

    // MARK: - Init

    init(project: Project?, onSave: @escaping (Project) -> Void) {
        self.project = project
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 320))
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
        let titleLabel = NSTextField(labelWithString: project == nil ? "Add Project" : "Edit Project")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        stackView.addArrangedSubview(titleLabel)

        // Form fields
        stackView.addArrangedSubview(createFormRow(label: "Name:", field: nameField, placeholder: "My App"))
        stackView.addArrangedSubview(
            createFormRow(
                label: "Project Path:",
                field: projectPathField,
                placeholder: "~/Developer/MyApp/MyApp.xcodeproj",
                withBrowse: true,
            ),
        )
        stackView.addArrangedSubview(createFormRow(label: "Scheme:", field: schemeField, placeholder: "MyApp"))
        stackView.addArrangedSubview(
            createFormRow(
                label: "Bundle ID:",
                field: bundleIDField,
                placeholder: "com.example.MyApp",
            ),
        )
        stackView.addArrangedSubview(
            createFormRow(
                label: "Derived Data:",
                field: derivedDataField,
                placeholder: "~/Library/Developer/Xcode/DerivedData/MyApp-abc123",
                withBrowse: true,
            ),
        )

        // Buttons
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}" // Escape

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r" // Enter
        saveButton.bezelStyle = .rounded

        buttonStack.addArrangedSubview(NSView()) // Spacer
        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(saveButton)

        stackView.addArrangedSubview(buttonStack)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            buttonStack.widthAnchor.constraint(equalTo: stackView.widthAnchor),
        ])
    }

    private func createFormRow(
        label: String,
        field: NSTextField,
        placeholder: String,
        withBrowse: Bool = false,
    ) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 13)
        labelView.alignment = .right
        labelView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        // Configure field for single-line, horizontal scrolling
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(labelView)
        row.addArrangedSubview(field)

        if withBrowse {
            let browseButton = NSButton(title: "Browse...", target: self, action: #selector(browseForPath(_:)))
            browseButton.tag = field == projectPathField ? 0 : 1
            row.addArrangedSubview(browseButton)
        }

        NSLayoutConstraint.activate([
            labelView.widthAnchor.constraint(equalToConstant: 100),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])

        return row
    }

    private func populateFields() {
        guard let project else { return }

        nameField.stringValue = project.name
        projectPathField.stringValue = project.projectPath
        schemeField.stringValue = project.scheme
        bundleIDField.stringValue = project.bundleID
        derivedDataField.stringValue = project.derivedDataPath
    }

    @objc private func browseForPath(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false

        if sender.tag == 0 {
            // .xcodeproj is a package (directory bundle). With treatsFilePackagesAsDirectories = false,
            // packages appear as opaque items (like files) in the browser, so we need canChooseFiles = true.
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.treatsFilePackagesAsDirectories = false
            // Use the system-defined UTType for Xcode projects
            if let xcodeprojType = UTType("com.apple.xcode.project") {
                panel.allowedContentTypes = [xcodeprojType]
            }
            panel.message = "Select the .xcodeproj project"
            panel.directoryURL = URL(fileURLWithPath: NSString("~/Developer").expandingTildeInPath)
        } else {
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.message = "Select the DerivedData folder for this project"
            panel.directoryURL = URL(fileURLWithPath: NSString("~/Library/Developer/Xcode/DerivedData").expandingTildeInPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            let field = sender.tag == 0 ? projectPathField : derivedDataField
            field.stringValue = url.path
        }
    }

    @objc private func cancel() {
        dismiss(nil)
    }

    @objc private func save() {
        // Validate
        guard
            !nameField.stringValue.isEmpty,
            !projectPathField.stringValue.isEmpty,
            !schemeField.stringValue.isEmpty,
            !bundleIDField.stringValue.isEmpty,
            !derivedDataField.stringValue.isEmpty else
        {
            let alert = NSAlert()
            alert.messageText = "Missing Fields"
            alert.informativeText = "Please fill in all fields."
            alert.runModal()
            return
        }

        let updatedProject = Project(
            id: project?.id ?? UUID(),
            name: nameField.stringValue,
            projectPath: projectPathField.stringValue,
            scheme: schemeField.stringValue,
            bundleID: bundleIDField.stringValue,
            derivedDataPath: derivedDataField.stringValue,
        )

        onSave(updatedProject)
        dismiss(nil)
    }
}
