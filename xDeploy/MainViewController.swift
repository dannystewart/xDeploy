import AppKit

// MARK: - DeviceButtonView

final class DeviceButtonView: NSView {
    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    var isEnabled: Bool = true {
        didSet { updateAppearance() }
    }

    var onToggle: ((Bool) -> Void)?

    private let iconView: NSImageView
    private let label: NSTextField
    private var trackingArea: NSTrackingArea?

    private var isHovered = false
    private var isPressed = false

    init(title: String, symbolName: String) {
        iconView = NSImageView()
        label = NSTextField(labelWithString: title)

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 10

        // Configure icon
        let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .ultraLight)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Configure label
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        // Center the icon+label group vertically
        // Icon is 60pt, gap is 8pt, label is ~19pt = ~87pt total
        // Offset icon center up by half the (gap + label height) to center the group
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -14),
            iconView.widthAnchor.constraint(equalToConstant: 60),
            iconView.heightAnchor.constraint(equalToConstant: 60),

            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
        ])

        updateAppearance()
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
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil,
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with _: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with _: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, isPressed else { return }
        isPressed = false

        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            isSelected.toggle()
            onToggle?(isSelected)
        }

        updateAppearance()
    }

    private func updateAppearance() {
        let backgroundColor: NSColor
        let contentColor: NSColor

        if !isEnabled {
            backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.3)
            contentColor = .tertiaryLabelColor
        } else if isSelected {
            if isPressed {
                backgroundColor = NSColor.controlAccentColor.blended(withFraction: 0.2, of: .black) ?? .controlAccentColor
            } else if isHovered {
                backgroundColor = NSColor.controlAccentColor.blended(withFraction: 0.1, of: .white) ?? .controlAccentColor
            } else {
                backgroundColor = .controlAccentColor
            }
            contentColor = .white
        } else {
            if isPressed {
                backgroundColor = NSColor.gray.withAlphaComponent(0.45)
            } else if isHovered {
                backgroundColor = NSColor.gray.withAlphaComponent(0.35)
            } else {
                backgroundColor = NSColor.gray.withAlphaComponent(0.25)
            }
            contentColor = .labelColor
        }

        layer?.backgroundColor = backgroundColor.cgColor
        iconView.contentTintColor = contentColor
        label.textColor = contentColor
    }
}

// MARK: - MainViewController

final class MainViewController: NSViewController {
    private var appData: AppData = .empty
    private var selectedProjectIndex: Int?
    private var iPhoneSelected = true
    private var iPadSelected = false

    // MARK: - UI Elements

    private let projectTableView: NSTableView = .init()
    private let statusLabel: NSTextField = .init(labelWithString: "Select a project")

    // Left side buttons
    private var addButton: NSButton!
    private var editButton: NSButton!
    private var deleteButton: NSButton!

    // Right side buttons
    private var iPhoneButton: DeviceButtonView!
    private var iPadButton: DeviceButtonView!
    private var installButton: NSButton!
    private var runButton: NSButton!

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadData()
        setupUI()
        reloadProjects()
        updateButtonStates()
    }

    @objc func addProject() {
        showProjectEditor(project: nil)
    }

    @objc func showSettings() {
        let editor = DeviceSettingsViewController(deviceConfig: appData.deviceConfig) { [weak self] newConfig in
            self?.appData.deviceConfig = newConfig
            self?.saveData()
        }
        presentAsSheet(editor)
    }

    // MARK: - Data

    private func loadData() {
        appData = DataManager.shared.load()
    }

    private func saveData() {
        DataManager.shared.save(appData)
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.wantsLayer = true

        // Main horizontal split
        let mainStack = NSStackView()
        mainStack.orientation = .horizontal
        mainStack.spacing = 0
        mainStack.distribution = .fill
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        // Left pane (project list)
        let leftPane = createProjectListPane()
        leftPane.translatesAutoresizingMaskIntoConstraints = false

        // Right pane (button grid)
        let rightPane = createButtonPane()
        rightPane.translatesAutoresizingMaskIntoConstraints = false

        mainStack.addArrangedSubview(leftPane)
        mainStack.addArrangedSubview(rightPane)

        // Status bar at very bottom
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            leftPane.widthAnchor.constraint(equalTo: mainStack.widthAnchor, multiplier: 0.45),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
    }

    private func createProjectListPane() -> NSView {
        let container = NSView()

        // Table view for projects
        projectTableView.delegate = self
        projectTableView.dataSource = self
        projectTableView.headerView = nil
        projectTableView.rowHeight = 32
        projectTableView.selectionHighlightStyle = .regular
        projectTableView.allowsEmptySelection = true
        projectTableView.usesAlternatingRowBackgroundColors = true
        projectTableView.gridStyleMask = []

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ProjectColumn"))
        column.title = "Projects"
        projectTableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.documentView = projectTableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        // Bottom button row: Add, Edit, Delete
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        addButton = NSButton(title: "Add", target: self, action: #selector(addProject))
        addButton.bezelStyle = .rounded

        editButton = NSButton(title: "Edit", target: self, action: #selector(editSelectedProject))
        editButton.bezelStyle = .rounded

        deleteButton = NSButton(title: "Delete", target: self, action: #selector(removeSelectedProject))
        deleteButton.bezelStyle = .rounded

        buttonRow.addArrangedSubview(addButton)
        buttonRow.addArrangedSubview(editButton)
        buttonRow.addArrangedSubview(deleteButton)

        container.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -16),

            buttonRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            buttonRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        return container
    }

    private func createButtonPane() -> NSView {
        let container = NSView()

        // 2x2 grid
        let gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.alignment = .centerX
        gridStack.spacing = 20
        gridStack.translatesAutoresizingMaskIntoConstraints = false

        // Device row (iPhone / iPad) - big square buttons
        let deviceRow = NSStackView()
        deviceRow.orientation = .horizontal
        deviceRow.spacing = 20

        iPhoneButton = DeviceButtonView(title: "iPhone", symbolName: "iphone")
        iPhoneButton.onToggle = { [weak self] selected in
            self?.iPhoneSelected = selected
            self?.updateButtonStates()
        }

        iPadButton = DeviceButtonView(title: "iPad", symbolName: "ipad.landscape")
        iPadButton.onToggle = { [weak self] selected in
            self?.iPadSelected = selected
            self?.updateButtonStates()
        }

        deviceRow.addArrangedSubview(iPhoneButton)
        deviceRow.addArrangedSubview(iPadButton)

        // Action row (Install / Run) - shorter, text only
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.spacing = 20

        installButton = createActionButton(title: "Install", action: #selector(performInstall))
        runButton = createActionButton(title: "Run", action: #selector(performRun))

        actionRow.addArrangedSubview(installButton)
        actionRow.addArrangedSubview(runButton)

        gridStack.addArrangedSubview(deviceRow)
        gridStack.addArrangedSubview(actionRow)

        container.addSubview(gridStack)

        // Button sizes - big squares for devices, shorter rectangles for actions
        let deviceSize: CGFloat = 160
        let actionHeight: CGFloat = 60

        NSLayoutConstraint.activate([
            gridStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            gridStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            iPhoneButton.widthAnchor.constraint(equalToConstant: deviceSize),
            iPhoneButton.heightAnchor.constraint(equalToConstant: deviceSize),
            iPadButton.widthAnchor.constraint(equalToConstant: deviceSize),
            iPadButton.heightAnchor.constraint(equalToConstant: deviceSize),

            installButton.widthAnchor.constraint(equalToConstant: deviceSize),
            installButton.heightAnchor.constraint(equalToConstant: actionHeight),
            runButton.widthAnchor.constraint(equalToConstant: deviceSize),
            runButton.heightAnchor.constraint(equalToConstant: actionHeight),
        ])

        return container
    }

    private func createActionButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .texturedSquare
        button.font = .systemFont(ofSize: 20, weight: .regular)
        return button
    }

    // MARK: - Projects

    private func reloadProjects() {
        projectTableView.reloadData()
        updateButtonStates()
    }

    private func updateButtonStates() {
        let hasSelection = selectedProjectIndex != nil && selectedProjectIndex! < appData.projects.count
        let hasDevice = iPhoneSelected || iPadSelected

        // Left side buttons
        editButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection

        // Right side buttons
        installButton.isEnabled = hasSelection && hasDevice
        runButton.isEnabled = hasSelection && hasDevice

        // Update device button states
        iPhoneButton.isSelected = iPhoneSelected
        iPadButton.isSelected = iPadSelected

        // Update status
        if !hasSelection {
            statusLabel.stringValue = appData.projects.isEmpty ? "Add a project to get started" : "Select a project"
        } else if !hasDevice {
            statusLabel.stringValue = "Select at least one device"
        } else {
            let project = appData.projects[selectedProjectIndex!]
            var devices = [String]()
            if iPhoneSelected { devices.append("iPhone") }
            if iPadSelected { devices.append("iPad") }
            statusLabel.stringValue = "\(project.name) → \(devices.joined(separator: " & "))"
        }
    }

    @objc private func performInstall() {
        guard let index = selectedProjectIndex, index < appData.projects.count else { return }
        let project = appData.projects[index]
        performDeployment(project: project, includeRun: false)
    }

    @objc private func performRun() {
        guard let index = selectedProjectIndex, index < appData.projects.count else { return }
        let project = appData.projects[index]
        performDeployment(project: project, includeRun: true)
    }

    private func performDeployment(project: Project, includeRun: Bool) {
        var devices = [String]()
        if iPhoneSelected { devices.append(appData.deviceConfig.iPhoneName) }
        if iPadSelected { devices.append(appData.deviceConfig.iPadName) }

        guard !devices.isEmpty else { return }

        setUIEnabled(false)

        Task {
            do {
                for device in devices {
                    if includeRun {
                        try await DeploymentManager.shared.deployRun(
                            project: project,
                            deviceName: device,
                        ) { [weak self] status in
                            Task { @MainActor in
                                self?.statusLabel.stringValue = status
                            }
                        }
                    } else {
                        try await DeploymentManager.shared.deployInstall(
                            project: project,
                            deviceName: device,
                        ) { [weak self] status in
                            Task { @MainActor in
                                self?.statusLabel.stringValue = status
                            }
                        }
                    }
                }

                await MainActor.run {
                    let action = includeRun ? "running" : "installed"
                    statusLabel.stringValue = "✓ \(project.name) \(action) on \(devices.joined(separator: " & "))"
                    setUIEnabled(true)
                }
            } catch {
                await MainActor.run {
                    statusLabel.stringValue = "✗ Error: \(error.localizedDescription)"
                    setUIEnabled(true)

                    let alert = NSAlert()
                    alert.messageText = "Deployment Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }

    private func setUIEnabled(_ enabled: Bool) {
        addButton.isEnabled = enabled
        editButton.isEnabled = enabled
        deleteButton.isEnabled = enabled
        iPhoneButton.isEnabled = enabled
        iPadButton.isEnabled = enabled
        installButton.isEnabled = enabled
        runButton.isEnabled = enabled
        projectTableView.isEnabled = enabled
    }

    @objc private func editSelectedProject() {
        guard let index = selectedProjectIndex, index < appData.projects.count else { return }
        let project = appData.projects[index]
        showProjectEditor(project: project)
    }

    @objc private func removeSelectedProject() {
        guard let index = selectedProjectIndex, index < appData.projects.count else { return }

        let project = appData.projects[index]

        let alert = NSAlert()
        alert.messageText = "Delete \(project.name)?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            appData.projects.remove(at: index)
            selectedProjectIndex = nil
            saveData()
            reloadProjects()
        }
    }

    private func showProjectEditor(project: Project?) {
        let editor = ProjectEditorViewController(project: project) { [weak self] updatedProject in
            guard let self else { return }

            if
                let existing = project,
                let index = appData.projects.firstIndex(where: { $0.id == existing.id })
            {
                appData.projects[index] = updatedProject
            } else {
                appData.projects.append(updatedProject)
            }

            saveData()
            reloadProjects()

            // Select newly added project
            if project == nil {
                selectedProjectIndex = appData.projects.count - 1
                projectTableView.selectRowIndexes(IndexSet(integer: selectedProjectIndex!), byExtendingSelection: false)
                updateButtonStates()
            }
        }

        presentAsSheet(editor)
    }
}

// MARK: NSTableViewDataSource

extension MainViewController: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        appData.projects.count
    }
}

// MARK: NSTableViewDelegate

extension MainViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ProjectCell")

        var cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.font = .systemFont(ofSize: 13)
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(textField)
            cellView?.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
            ])
        }

        let project = appData.projects[row]
        cellView?.textField?.stringValue = project.name

        return cellView
    }

    func tableViewSelectionDidChange(_: Notification) {
        let selectedRow = projectTableView.selectedRow
        selectedProjectIndex = selectedRow >= 0 ? selectedRow : nil
        updateButtonStates()
    }
}

// MARK: NSToolbarDelegate

extension MainViewController: NSToolbarDelegate {
    private static let addProjectIdentifier = NSToolbarItem.Identifier("addProject")
    private static let settingsIdentifier = NSToolbarItem.Identifier("settings")

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.addProjectIdentifier,
            .flexibleSpace,
            Self.settingsIdentifier,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool,
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.addProjectIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Add Project"
            item.paletteLabel = "Add Project"
            item.toolTip = "Add a new project"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Project")
            item.target = self
            item.action = #selector(addProject)
            return item

        case Self.settingsIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Settings"
            item.paletteLabel = "Settings"
            item.toolTip = "Device Settings"
            item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
            item.target = self
            item.action = #selector(showSettings)
            return item

        default:
            return nil
        }
    }
}
