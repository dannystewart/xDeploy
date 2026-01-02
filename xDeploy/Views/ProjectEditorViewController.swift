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
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 260))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
        self.populateFields()
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
        stackView.addArrangedSubview(self.createFormRow(label: "Name:", field: self.nameField, placeholder: "My App"))
        stackView.addArrangedSubview(
            self.createFormRow(
                label: "Project Path:",
                field: self.projectPathField,
                placeholder: "~/Developer/MyApp/MyApp.xcodeproj",
                withBrowse: true,
            ),
        )
        stackView.addArrangedSubview(self.createFormRow(label: "Scheme:", field: self.schemeField, placeholder: "MyApp"))
        stackView.addArrangedSubview(
            self.createFormRow(
                label: "Bundle ID:",
                field: self.bundleIDField,
                placeholder: "com.example.MyApp",
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
            let browseButton = NSButton(title: "Browse...", target: self, action: #selector(browseForPath))
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

        self.nameField.stringValue = project.name
        self.projectPathField.stringValue = project.projectPath
        self.schemeField.stringValue = project.scheme
        self.bundleIDField.stringValue = project.bundleID
    }

    @objc private func browseForPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false

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

        if panel.runModal() == .OK, let url = panel.url {
            self.projectPathField.stringValue = url.path
        }
    }

    @objc private func cancel() {
        dismiss(nil)
    }

    @objc private func save() {
        // Validate
        guard
            !self.nameField.stringValue.isEmpty,
            !self.projectPathField.stringValue.isEmpty,
            !self.schemeField.stringValue.isEmpty,
            !self.bundleIDField.stringValue.isEmpty else
        {
            let alert = NSAlert()
            alert.messageText = "Missing Fields"
            alert.informativeText = "Please fill in all fields."
            alert.runModal()
            return
        }

        let updatedProject = Project(
            id: project?.id ?? UUID(),
            name: self.nameField.stringValue,
            projectPath: self.projectPathField.stringValue,
            scheme: self.schemeField.stringValue,
            bundleID: self.bundleIDField.stringValue,
        )

        self.onSave(updatedProject)
        dismiss(nil)
    }
}
