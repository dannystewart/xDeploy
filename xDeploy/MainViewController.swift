import AppKit

// MARK: - DeviceButtonView

/// A large button with an icon and label, used for device selection.
/// Lights up blue when `isDeploying` is true.
final class DeviceButtonView: NSView {
    var isDeploying: Bool = false {
        didSet { updateAppearance() }
    }

    var isEnabled: Bool = true {
        didSet { updateAppearance() }
    }

    var onClick: (() -> Void)?

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
            onClick?()
        }

        updateAppearance()
    }

    private func updateAppearance() {
        let backgroundColor: NSColor
        let contentColor: NSColor

        if !isEnabled {
            backgroundColor = .secondarySystemFill
            contentColor = .disabledControlTextColor
        } else if isDeploying {
            // Blue highlight while deploying
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
    private enum DeviceType {
        case iPhone
        case iPad
    }

    private static let projectDragType = NSPasteboard.PasteboardType("com.xdeploy.project-row")

    private var appData: AppData = .empty
    private var selectedProjectIndex: Int?
    private var isRunMode = true // true = Run, false = Install

    // MARK: - UI Elements

    private let projectTableView: NSTableView = .init()
    private let statusLabel: NSTextField = .init(labelWithString: "Select a project")

    // Right side buttons
    private var iPhoneButton: DeviceButtonView!
    private var iPadButton: DeviceButtonView!

    /// Toolbar segmented control for action mode
    private var actionModeControl: NSSegmentedControl!

    /// Toolbar button for always-on-top toggle
    private var alwaysOnTopButton: NSToolbarItem?
    private var isAlwaysOnTop = false

    // Console output
    private var consoleTextView: NSTextView!
    private var consoleScrollView: NSScrollView!

    private var deployingDevice: DeviceType?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 356))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadData()
        setupUI()
        reloadProjects()
        restoreSelectedProject()
        updateButtonStates()

        // Add keyboard shortcut monitoring for ⌘+Backspace
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if
                event.modifierFlags.contains(.command),
                event.keyCode == 51 // Backspace
            {
                if
                    view.window?.firstResponder === projectTableView,
                    selectedProjectIndex != nil
                {
                    removeSelectedProject()
                    return nil
                }
            }
            return event
        }
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

    func clearConsole() {
        guard isViewLoaded else { return }
        consoleTextView.string = ""
    }

    func appendToConsole(_ text: String) {
        guard isViewLoaded else { return }
        consoleTextView.textStorage?.append(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.textColor,
            ],
        ))

        // Auto-scroll to bottom only if window is visible
        if view.window?.isVisible == true {
            consoleTextView.scrollToEndOfDocument(nil)
        }
    }

    // MARK: - Data

    private func loadData() {
        appData = DataManager.shared.load()
    }

    private func saveData() {
        DataManager.shared.save(appData)
    }

    private func restoreSelectedProject() {
        guard
            let savedID = appData.selectedProjectID,
            let index = appData.projects.firstIndex(where: { $0.id == savedID }) else { return }

        selectedProjectIndex = index
        projectTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.wantsLayer = true

        // Project list (fixed width, full height on left)
        let projectScrollView = createProjectListScrollView()
        projectScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(projectScrollView)

        // Button grid (top-right area)
        let buttonGrid = createButtonGrid()
        buttonGrid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonGrid)

        // Console (below buttons, to the right of project list)
        createConsoleView()
        consoleScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(consoleScrollView)

        // Status bar at very bottom
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Layout constants
        let padding: CGFloat = 20
        let projectListWidth: CGFloat = 240
        let buttonGridHeight: CGFloat = 160

        NSLayoutConstraint.activate([
            // Project list: fixed width, full height
            projectScrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: padding),
            projectScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            projectScrollView.widthAnchor.constraint(equalToConstant: projectListWidth),
            projectScrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            // Button grid: top-right, fixed height
            buttonGrid.topAnchor.constraint(equalTo: view.topAnchor, constant: padding),
            buttonGrid.leadingAnchor.constraint(equalTo: projectScrollView.trailingAnchor, constant: padding),
            buttonGrid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            buttonGrid.heightAnchor.constraint(equalToConstant: buttonGridHeight),

            // Console: below buttons, from project list edge to window edge
            consoleScrollView.topAnchor.constraint(equalTo: buttonGrid.bottomAnchor, constant: padding),
            consoleScrollView.leadingAnchor.constraint(equalTo: projectScrollView.trailingAnchor, constant: padding),
            consoleScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            consoleScrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            // Status bar
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
    }

    private func createProjectListScrollView() -> NSScrollView {
        // Table view for projects
        projectTableView.delegate = self
        projectTableView.dataSource = self
        projectTableView.headerView = nil
        projectTableView.rowHeight = 48
        projectTableView.selectionHighlightStyle = .regular
        projectTableView.allowsEmptySelection = true
        projectTableView.usesAlternatingRowBackgroundColors = true
        projectTableView.gridStyleMask = []
        projectTableView.doubleAction = #selector(editSelectedProject)
        projectTableView.target = self

        // Enable drag-and-drop reordering
        projectTableView.registerForDraggedTypes([Self.projectDragType])

        // Context menu for rows
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Edit", action: #selector(editClickedProject), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Delete", action: #selector(deleteClickedProject), keyEquivalent: ""))
        projectTableView.menu = menu

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ProjectColumn"))
        column.title = "Projects"
        projectTableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.documentView = projectTableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        return scrollView
    }

    private func createButtonGrid() -> NSView {
        let container = NSView()

        // Device row (iPhone / iPad) - triggers the action
        let deviceRow = NSStackView()
        deviceRow.orientation = .horizontal
        deviceRow.spacing = 20
        deviceRow.translatesAutoresizingMaskIntoConstraints = false

        iPhoneButton = DeviceButtonView(title: "iPhone", symbolName: "iphone")
        iPhoneButton.onClick = { [weak self] in
            self?.performDeploymentToDevice(.iPhone)
        }

        iPadButton = DeviceButtonView(title: "iPad", symbolName: "ipad.landscape")
        iPadButton.onClick = { [weak self] in
            self?.performDeploymentToDevice(.iPad)
        }

        deviceRow.addArrangedSubview(iPhoneButton)
        deviceRow.addArrangedSubview(iPadButton)

        container.addSubview(deviceRow)

        // Button sizes
        let deviceSize: CGFloat = 160

        NSLayoutConstraint.activate([
            deviceRow.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            deviceRow.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            iPhoneButton.widthAnchor.constraint(equalToConstant: deviceSize),
            iPhoneButton.heightAnchor.constraint(equalToConstant: deviceSize),
            iPadButton.widthAnchor.constraint(equalToConstant: deviceSize),
            iPadButton.heightAnchor.constraint(equalToConstant: deviceSize),
        ])

        return container
    }

    private func createConsoleView() {
        consoleTextView = NSTextView()
        consoleTextView.isEditable = false
        consoleTextView.isSelectable = true
        consoleTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        consoleTextView.backgroundColor = NSColor.textBackgroundColor
        consoleTextView.textColor = .textColor
        consoleTextView.autoresizingMask = [.width]
        consoleTextView.isVerticallyResizable = true
        consoleTextView.isHorizontallyResizable = false
        consoleTextView.textContainer?.widthTracksTextView = true
        consoleTextView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude,
        )

        consoleScrollView = NSScrollView()
        consoleScrollView.documentView = consoleTextView
        consoleScrollView.hasVerticalScroller = true
        consoleScrollView.hasHorizontalScroller = false
        consoleScrollView.autohidesScrollers = true
        consoleScrollView.borderType = .bezelBorder

        // Prevent console from forcing window to expand when content is added
        consoleScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        consoleScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    // MARK: - Projects

    private func reloadProjects() {
        projectTableView.reloadData()
        updateButtonStates()
    }

    private func updateButtonStates() {
        let hasSelection = selectedProjectIndex != nil && selectedProjectIndex! < appData.projects.count

        // Update toolbar segmented control
        actionModeControl?.selectedSegment = isRunMode ? 0 : 1

        // Device buttons enabled only when a project is selected
        iPhoneButton.isEnabled = hasSelection
        iPadButton.isEnabled = hasSelection

        // Update deploying state
        iPhoneButton.isDeploying = deployingDevice == .iPhone
        iPadButton.isDeploying = deployingDevice == .iPad

        // Update status
        if !hasSelection {
            statusLabel.stringValue = appData.projects.isEmpty ? "Add a project to get started" : "Select a project"
        } else {
            let project = appData.projects[selectedProjectIndex!]
            let action = isRunMode ? "Run" : "Install"
            statusLabel.stringValue = "\(action) \(project.name) on..."
        }
    }

    private func performDeploymentToDevice(_ deviceType: DeviceType) {
        guard let index = selectedProjectIndex, index < appData.projects.count else { return }
        let project = appData.projects[index]

        let deviceName: String
        let deviceLabel: String
        switch deviceType {
        case .iPhone:
            deviceName = appData.deviceConfig.iPhoneName
            deviceLabel = "iPhone"

        case .iPad:
            deviceName = appData.deviceConfig.iPadName
            deviceLabel = "iPad"
        }

        deployingDevice = deviceType
        setUIEnabled(false)
        clearConsole()

        Task {
            do {
                if isRunMode {
                    try await DeploymentManager.shared.deployRun(
                        project: project,
                        deviceName: deviceName,
                        statusHandler: { [weak self] status in
                            guard let self else { return }
                            Task { @MainActor in
                                self.statusLabel.stringValue = status
                            }
                        },
                        outputHandler: { [weak self] output in
                            guard let self else { return }
                            Task { @MainActor in
                                self.appendToConsole(output)
                            }
                        },
                    )
                } else {
                    try await DeploymentManager.shared.deployInstall(
                        project: project,
                        deviceName: deviceName,
                        statusHandler: { [weak self] status in
                            guard let self else { return }
                            Task { @MainActor in
                                self.statusLabel.stringValue = status
                            }
                        },
                        outputHandler: { [weak self] output in
                            guard let self else { return }
                            Task { @MainActor in
                                self.appendToConsole(output)
                            }
                        },
                    )
                }

                await MainActor.run {
                    let action = isRunMode ? "running" : "installed"
                    statusLabel.stringValue = "✓ \(project.name) \(action) on \(deviceLabel)"
                    deployingDevice = nil
                    setUIEnabled(true)
                }
            } catch {
                await MainActor.run {
                    appendToConsole("\n✗ Error: \(error.localizedDescription)\n")
                    statusLabel.stringValue = "✗ Error: \(error.localizedDescription)"
                    deployingDevice = nil
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
        iPhoneButton.isEnabled = enabled
        iPadButton.isEnabled = enabled
        // Action buttons always stay enabled for mode switching
        projectTableView.isEnabled = enabled
        updateButtonStates()
    }

    @objc private func editSelectedProject() {
        // Only edit if double-clicked on an actual row
        let clickedRow = projectTableView.clickedRow
        guard clickedRow >= 0, clickedRow < appData.projects.count else { return }
        let project = appData.projects[clickedRow]
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
            appData.selectedProjectID = nil
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

    // MARK: Drag and Drop

    func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.projectDragType)
        return item
    }

    func tableView(
        _: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow _: Int,
        proposedDropOperation operation: NSTableView.DropOperation,
    ) -> NSDragOperation {
        // Only allow drops between rows (not on rows)
        guard operation == .above else { return [] }
        // Only allow internal drags
        guard info.draggingSource as? NSTableView === projectTableView else { return [] }
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation _: NSTableView.DropOperation,
    ) -> Bool {
        guard
            let item = info.draggingPasteboard.pasteboardItems?.first,
            let rowString = item.string(forType: Self.projectDragType),
            let sourceRow = Int(rowString) else { return false }

        // Don't move if dropping in the same position
        guard sourceRow != row, sourceRow + 1 != row else { return false }

        // Move the project in our data
        let project = appData.projects.remove(at: sourceRow)
        let destinationRow = sourceRow < row ? row - 1 : row
        appData.projects.insert(project, at: destinationRow)

        // Animate the row move
        tableView.moveRow(at: sourceRow, to: destinationRow)

        // Update selection to follow the moved item
        selectedProjectIndex = destinationRow

        saveData()

        return true
    }
}

// MARK: NSTableViewDelegate

extension MainViewController: NSTableViewDelegate {
    private static let pathTagBase = 1000

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ProjectCell")

        var cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = identifier

            // Icon view
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(imageView)
            cellView?.imageView = imageView

            // Title label
            let titleField = NSTextField(labelWithString: "")
            titleField.font = .systemFont(ofSize: 13, weight: .regular)
            titleField.lineBreakMode = .byTruncatingTail
            titleField.translatesAutoresizingMaskIntoConstraints = false
            cellView?.addSubview(titleField)
            cellView?.textField = titleField

            // Path label
            let pathField = NSTextField(labelWithString: "")
            pathField.font = .systemFont(ofSize: 11)
            pathField.textColor = .secondaryLabelColor
            pathField.lineBreakMode = .byTruncatingMiddle
            pathField.translatesAutoresizingMaskIntoConstraints = false
            pathField.tag = Self.pathTagBase
            cellView?.addSubview(pathField)

            let iconSize: CGFloat = 32

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 6),
                imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: iconSize),
                imageView.heightAnchor.constraint(equalToConstant: iconSize),

                titleField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                titleField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -8),
                titleField.bottomAnchor.constraint(equalTo: cellView!.centerYAnchor),

                pathField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                pathField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
                pathField.topAnchor.constraint(equalTo: cellView!.centerYAnchor, constant: 1),
            ])
        }

        let project = appData.projects[row]
        cellView?.textField?.stringValue = project.name

        // Set folder path with ~ abbreviation
        if let pathField = cellView?.viewWithTag(Self.pathTagBase) as? NSTextField {
            let folderPath = URL(fileURLWithPath: project.projectPath)
                .deletingLastPathComponent()
                .path
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let displayPath = folderPath.hasPrefix(homeDir)
                ? "~" + folderPath.dropFirst(homeDir.count)
                : folderPath
            pathField.stringValue = displayPath
        }

        // Get icon for .xcodeproj or .xcworkspace
        let url = URL(fileURLWithPath: project.projectPath)
        cellView?.imageView?.image = NSWorkspace.shared.icon(forFile: url.path)

        return cellView
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        // Prevent deselection once a project is selected
        if proposedSelectionIndexes.isEmpty, tableView.selectedRow >= 0 {
            return tableView.selectedRowIndexes
        }
        return proposedSelectionIndexes
    }

    func tableViewSelectionDidChange(_: Notification) {
        let selectedRow = projectTableView.selectedRow
        selectedProjectIndex = selectedRow >= 0 ? selectedRow : nil

        // Remember the selected project for next launch
        if let index = selectedProjectIndex, index < appData.projects.count {
            appData.selectedProjectID = appData.projects[index].id
        } else {
            appData.selectedProjectID = nil
        }
        saveData()

        updateButtonStates()
    }
}

// MARK: NSMenuDelegate

extension MainViewController: NSMenuDelegate {
    private static var clickedRow: Int = -1

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard
            menu === projectTableView.menu,
            let window = projectTableView.window else { return }

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let tablePoint = projectTableView.convert(windowPoint, from: nil)
        Self.clickedRow = projectTableView.row(at: tablePoint)

        // Enable/disable menu items based on clicked row
        let hasClickedRow = Self.clickedRow >= 0
        for item in menu.items {
            item.isEnabled = hasClickedRow
        }
    }

    @objc func editClickedProject() {
        guard Self.clickedRow >= 0, Self.clickedRow < appData.projects.count else { return }
        let project = appData.projects[Self.clickedRow]
        showProjectEditor(project: project)
    }

    @objc func deleteClickedProject() {
        guard Self.clickedRow >= 0, Self.clickedRow < appData.projects.count else { return }
        let project = appData.projects[Self.clickedRow]

        let alert = NSAlert()
        alert.messageText = "Delete \(project.name)?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let deletedProjectID = appData.projects[Self.clickedRow].id
            appData.projects.remove(at: Self.clickedRow)
            if selectedProjectIndex == Self.clickedRow {
                selectedProjectIndex = nil
                appData.selectedProjectID = nil
            } else if let selected = selectedProjectIndex, selected > Self.clickedRow {
                selectedProjectIndex = selected - 1
            }
            // Clear selectedProjectID if the deleted project was the remembered one
            if appData.selectedProjectID == deletedProjectID {
                appData.selectedProjectID = nil
            }
            saveData()
            reloadProjects()
        }
    }
}

// MARK: NSToolbarDelegate

extension MainViewController: NSToolbarDelegate {
    private static let addProjectIdentifier = NSToolbarItem.Identifier("addProject")
    private static let settingsIdentifier = NSToolbarItem.Identifier("settings")
    private static let actionModeIdentifier = NSToolbarItem.Identifier("actionMode")
    private static let alwaysOnTopIdentifier = NSToolbarItem.Identifier("alwaysOnTop")

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.addProjectIdentifier,
            .flexibleSpace,
            Self.alwaysOnTopIdentifier,
            Self.actionModeIdentifier,
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
            item.isNavigational = true
            return item

        case Self.settingsIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Settings"
            item.paletteLabel = "Settings"
            item.toolTip = "Device Settings"
            item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
            item.target = self
            item.action = #selector(showSettings)
            item.isNavigational = true
            return item

        case Self.actionModeIdentifier:
            let segmentedControl = NSSegmentedControl(labels: ["Run Now", "Install Only"], trackingMode: .selectOne, target: self, action: #selector(actionModeChanged(_:)))
            segmentedControl.selectedSegment = isRunMode ? 0 : 1
            segmentedControl.segmentStyle = .automatic
            actionModeControl = segmentedControl

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Action"
            item.paletteLabel = "Action Mode"
            item.toolTip = "Choose whether to run the app or just install it"
            item.view = segmentedControl
            return item

        case Self.alwaysOnTopIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Pin"
            item.paletteLabel = "Always on Top"
            item.toolTip = "Keep window above other windows"
            item.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Always on Top")
            item.target = self
            item.action = #selector(toggleAlwaysOnTop)
            alwaysOnTopButton = item
            return item

        default:
            return nil
        }
    }

    @objc private func actionModeChanged(_ sender: NSSegmentedControl) {
        isRunMode = sender.selectedSegment == 0
        updateButtonStates()
    }

    @objc private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()

        if isAlwaysOnTop {
            view.window?.level = .floating
            alwaysOnTopButton?.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: "Always on Top (Active)")
        } else {
            view.window?.level = .normal
            alwaysOnTopButton?.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Always on Top")
        }
    }
}
