import AppKit
import PolyKit

// MARK: - MainViewController

final class MainViewController: NSViewController {
    private enum DeviceType {
        case iPhone
        case iPad
    }

    private static let projectDragType = NSPasteboard.PasteboardType("com.dannystewart.xDeploy.project-row")

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
        self.loadData()
        self.setupUI()
        self.reloadProjects()
        self.restoreSelectedProject()
        self.updateButtonStates()

        // Add keyboard shortcut monitoring for ⌘+Backspace
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if
                event.modifierFlags.contains(.command),
                event.keyCode == 51 // Backspace
            {
                if
                    view.window?.firstResponder === self.projectTableView,
                    self.selectedProjectIndex != nil
                {
                    self.removeSelectedProject()
                    return nil
                }
            }
            return event
        }
    }

    // MARK: - Keyboard Shortcuts

    @objc func switchToInstallMode() {
        self.isRunMode = false
        self.actionModeControl?.selectedSegment = 1
        self.updateButtonStates()
    }

    @objc func switchToRunMode() {
        self.isRunMode = true
        self.actionModeControl?.selectedSegment = 0
        self.updateButtonStates()
    }

    @objc func performActionForPhone() {
        guard self.selectedProjectIndex != nil else { return }
        self.performDeploymentToDevice(.iPhone)
    }

    @objc func performActionForPad() {
        guard self.selectedProjectIndex != nil else { return }
        self.performDeploymentToDevice(.iPad)
    }

    @objc func showCustomDeviceSheet() {
        self.showCustomDeviceDialog()
    }

    @objc func addProject() {
        self.showProjectEditor(project: nil)
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
        self.consoleTextView.string = ""
    }

    func appendToConsole(_ text: String) {
        guard isViewLoaded else { return }

        // Parse ANSI color codes and create attributed string
        let attributedString = self.parseANSIColors(text)
        self.consoleTextView.textStorage?.append(attributedString)

        // Auto-scroll to bottom only if window is visible
        if view.window?.isVisible == true {
            self.consoleTextView.scrollToEndOfDocument(nil)
        }
    }

    @objc func editSelectedProject() {
        // Only edit if double-clicked on an actual row
        let clickedRow = self.projectTableView.clickedRow
        guard clickedRow >= 0, clickedRow < self.appData.projects.count else { return }
        let project = self.appData.projects[clickedRow]
        self.showProjectEditor(project: project)
    }

    @objc func editCurrentlySelectedProject() {
        // Edit the currently selected project (for keyboard shortcut)
        guard let index = selectedProjectIndex, index < appData.projects.count else { return }
        let project = self.appData.projects[index]
        self.showProjectEditor(project: project)
    }

    /// Parses ANSI color codes and returns an attributed string with colors applied.
    private func parseANSIColors(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = PolyFont.jetBrainsMono.font(size: 10, weight: .light)
        let boldFont = PolyFont.jetBrainsMono.font(size: 10, weight: .medium)
        var currentColor = NSColor.textColor
        var currentBold = false

        // ANSI escape pattern: ESC[...m
        // Use "\u{001B}" outside of raw string to get actual ESC character
        let pattern = "\u{001B}\\[([0-9;]+)m"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            // Fallback if regex fails
            return NSAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.textColor,
            ])
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var lastIndex = text.startIndex

        for match in matches {
            // Add text before this escape code
            if let range = Range(match.range, in: text) {
                let beforeText = String(text[lastIndex ..< range.lowerBound])
                if !beforeText.isEmpty {
                    let font = currentBold ? boldFont : baseFont
                    result.append(NSAttributedString(string: beforeText, attributes: [
                        .font: font,
                        .foregroundColor: currentColor,
                    ]))
                }

                // Parse the ANSI code
                if let codeRange = Range(match.range(at: 1), in: text) {
                    let codes = text[codeRange].split(separator: ";").compactMap { Int($0) }

                    for code in codes {
                        switch code {
                        case 0: // Reset
                            currentColor = .textColor
                            currentBold = false

                        case 1: // Bold
                            currentBold = true

                        case 22: // Normal intensity
                            currentBold = false

                        case 30: currentColor = .black

                        case 31: currentColor = .systemRed

                        case 32: currentColor = .systemGreen

                        case 33: currentColor = .systemYellow

                        case 34: currentColor = .systemBlue

                        case 35: currentColor = .systemPurple

                        case 36: currentColor = .systemCyan

                        case 37: currentColor = .textColor

                        case 90: currentColor = .systemGray

                        case 91: currentColor = .systemRed

                        case 92: currentColor = .systemGreen

                        case 93: currentColor = .systemYellow

                        case 94: currentColor = .systemBlue

                        case 95: currentColor = .systemPurple

                        case 96: currentColor = .systemCyan

                        case 97: currentColor = .white

                        default: break
                        }
                    }
                }

                lastIndex = range.upperBound
            }
        }

        // Add any remaining text after the last escape code
        let remainingText = String(text[lastIndex...])
        if !remainingText.isEmpty {
            let font = currentBold ? boldFont : baseFont
            result.append(NSAttributedString(string: remainingText, attributes: [
                .font: font,
                .foregroundColor: currentColor,
            ]))
        }

        return result
    }

    // MARK: - Data

    private func loadData() {
        self.appData = DataManager.shared.load()
    }

    private func saveData() {
        DataManager.shared.save(self.appData)
    }

    private func restoreSelectedProject() {
        guard
            let savedID = appData.selectedProjectID,
            let index = appData.projects.firstIndex(where: { $0.id == savedID }) else { return }

        self.selectedProjectIndex = index
        self.projectTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.wantsLayer = true

        // Project list (fixed width, full height on left)
        let projectScrollView = self.createProjectListScrollView()
        projectScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(projectScrollView)

        // Button grid (top-right area)
        let buttonGrid = self.createButtonGrid()
        buttonGrid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonGrid)

        // Console (below buttons, to the right of project list)
        self.createConsoleView()
        self.consoleScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self.consoleScrollView)

        // Status bar at very bottom
        self.statusLabel.font = .systemFont(ofSize: 12)
        self.statusLabel.textColor = .secondaryLabelColor
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self.statusLabel)

        // Layout constants
        let padding: CGFloat = 20
        let projectListWidth: CGFloat = 240
        let buttonGridHeight: CGFloat = 80

        NSLayoutConstraint.activate([
            // Project list: fixed width, full height
            projectScrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: padding),
            projectScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            projectScrollView.widthAnchor.constraint(equalToConstant: projectListWidth),
            projectScrollView.bottomAnchor.constraint(equalTo: self.statusLabel.topAnchor, constant: -8),

            // Button grid: top-right, fixed height
            buttonGrid.topAnchor.constraint(equalTo: view.topAnchor, constant: padding),
            buttonGrid.leadingAnchor.constraint(equalTo: projectScrollView.trailingAnchor, constant: padding),
            buttonGrid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            buttonGrid.heightAnchor.constraint(equalToConstant: buttonGridHeight),

            // Console: below buttons, from project list edge to window edge
            self.consoleScrollView.topAnchor.constraint(equalTo: buttonGrid.bottomAnchor, constant: padding),
            self.consoleScrollView.leadingAnchor.constraint(equalTo: projectScrollView.trailingAnchor, constant: padding),
            self.consoleScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            self.consoleScrollView.bottomAnchor.constraint(equalTo: self.statusLabel.topAnchor, constant: -8),

            // Status bar
            self.statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            self.statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            self.statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
    }

    private func createProjectListScrollView() -> NSScrollView {
        // Table view for projects
        self.projectTableView.delegate = self
        self.projectTableView.dataSource = self
        self.projectTableView.headerView = nil
        self.projectTableView.rowHeight = 48
        self.projectTableView.selectionHighlightStyle = .regular
        self.projectTableView.allowsEmptySelection = true
        self.projectTableView.usesAlternatingRowBackgroundColors = true
        self.projectTableView.gridStyleMask = []
        self.projectTableView.doubleAction = #selector(self.editSelectedProject)
        self.projectTableView.target = self

        // Enable drag-and-drop reordering
        self.projectTableView.registerForDraggedTypes([Self.projectDragType])

        // Context menu for rows
        let menu = NSMenu()
        menu.delegate = self

        let editItem = NSMenuItem(title: "Edit", action: #selector(editClickedProject), keyEquivalent: "")
        editItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        menu.addItem(editItem)

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteClickedProject), keyEquivalent: "")
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(deleteItem)

        self.projectTableView.menu = menu

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ProjectColumn"))
        column.title = "Projects"
        self.projectTableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.documentView = self.projectTableView
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
        deviceRow.spacing = 16
        deviceRow.distribution = .fillEqually
        deviceRow.translatesAutoresizingMaskIntoConstraints = false

        self.iPhoneButton = DeviceButtonView(title: "iPhone", symbolName: "iphone")
        self.iPhoneButton.onClick = { [weak self] in
            self?.performDeploymentToDevice(.iPhone)
        }

        self.iPadButton = DeviceButtonView(title: "iPad", symbolName: "ipad.landscape")
        self.iPadButton.onClick = { [weak self] in
            self?.performDeploymentToDevice(.iPad)
        }

        deviceRow.addArrangedSubview(self.iPhoneButton)
        deviceRow.addArrangedSubview(self.iPadButton)

        container.addSubview(deviceRow)

        // Fill the container edge to edge, buttons fill height
        NSLayoutConstraint.activate([
            deviceRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            deviceRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            deviceRow.topAnchor.constraint(equalTo: container.topAnchor),
            deviceRow.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func createConsoleView() {
        self.consoleTextView = NSTextView()
        self.consoleTextView.isEditable = false
        self.consoleTextView.isSelectable = true
        self.consoleTextView.font = PolyFont.jetBrainsMono.font(size: 10)
        self.consoleTextView.backgroundColor = NSColor.textBackgroundColor
        self.consoleTextView.textColor = .textColor
        self.consoleTextView.autoresizingMask = [.width]
        self.consoleTextView.isVerticallyResizable = true
        self.consoleTextView.isHorizontallyResizable = false
        self.consoleTextView.textContainer?.widthTracksTextView = true
        self.consoleTextView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude,
        )

        self.consoleScrollView = NSScrollView()
        self.consoleScrollView.documentView = self.consoleTextView
        self.consoleScrollView.hasVerticalScroller = true
        self.consoleScrollView.hasHorizontalScroller = false
        self.consoleScrollView.autohidesScrollers = true
        self.consoleScrollView.borderType = .bezelBorder

        // Prevent console from forcing window to expand when content is added
        self.consoleScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.consoleScrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    // MARK: - Projects

    private func reloadProjects() {
        self.projectTableView.reloadData()
        self.updateButtonStates()
    }

    private func updateButtonStates() {
        let hasSelection = self.selectedProjectIndex != nil && self.selectedProjectIndex! < self.appData.projects.count

        // Update toolbar segmented control
        self.actionModeControl?.selectedSegment = self.isRunMode ? 0 : 1

        // Device buttons enabled only when a project is selected
        self.iPhoneButton.isEnabled = hasSelection
        self.iPadButton.isEnabled = hasSelection

        // Update deploying state
        self.iPhoneButton.isDeploying = self.deployingDevice == .iPhone
        self.iPadButton.isDeploying = self.deployingDevice == .iPad

        // Update status
        if !hasSelection {
            self.statusLabel.stringValue = self.appData.projects.isEmpty ? "Add a project to get started" : "Select a project"
        } else {
            let project = self.appData.projects[self.selectedProjectIndex!]
            let action = self.isRunMode ? "run" : "install"
            self.statusLabel.stringValue = "Select a device to \(action) \(project.name)"
        }
    }

    private func performDeploymentToDevice(_ deviceType: DeviceType) {
        guard let index = selectedProjectIndex, index < appData.projects.count else { return }
        let project = self.appData.projects[index]

        let deviceName: String
        let deviceLabel: String
        switch deviceType {
        case .iPhone:
            deviceName = self.appData.deviceConfig.iPhoneName
            deviceLabel = "iPhone"

        case .iPad:
            deviceName = self.appData.deviceConfig.iPadName
            deviceLabel = "iPad"
        }

        self.deployingDevice = deviceType
        self.setUIEnabled(false)
        self.clearConsole()

        Task {
            do {
                if self.isRunMode {
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
                    let action = self.isRunMode ? "running" : "installed"
                    self.statusLabel.stringValue = "✓ \(project.name) \(action) on \(deviceLabel)"
                    self.deployingDevice = nil
                    self.setUIEnabled(true)
                }
            } catch {
                await MainActor.run {
                    self.appendToConsole("\n✗ Error: \(error.localizedDescription)\n")
                    self.statusLabel.stringValue = "✗ Error: \(error.localizedDescription)"
                    self.deployingDevice = nil
                    self.setUIEnabled(true)

                    let alert = NSAlert()
                    alert.messageText = "Deployment Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }

    private func performDeploymentToCustomDevice(deviceName: String) {
        guard let index = selectedProjectIndex, index < appData.projects.count else { return }
        let project = self.appData.projects[index]

        self.deployingDevice = nil // Custom device doesn't use the DeviceType enum
        self.setUIEnabled(false)
        self.clearConsole()

        Task {
            do {
                if self.isRunMode {
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
                    let action = self.isRunMode ? "running" : "installed"
                    self.statusLabel.stringValue = "✓ \(project.name) \(action) on \(deviceName)"
                    self.deployingDevice = nil
                    self.setUIEnabled(true)
                }
            } catch {
                await MainActor.run {
                    self.appendToConsole("\n✗ Error: \(error.localizedDescription)\n")
                    self.statusLabel.stringValue = "✗ Error: \(error.localizedDescription)"
                    self.deployingDevice = nil
                    self.setUIEnabled(true)

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
        self.iPhoneButton.isEnabled = enabled
        self.iPadButton.isEnabled = enabled
        // Action buttons always stay enabled for mode switching
        self.projectTableView.isEnabled = enabled
        self.updateButtonStates()
    }

    @objc private func removeSelectedProject() {
        guard let index = selectedProjectIndex, index < appData.projects.count else { return }

        let project = self.appData.projects[index]

        let alert = NSAlert()
        alert.messageText = "Delete \(project.name)?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            self.appData.projects.remove(at: index)
            self.selectedProjectIndex = nil
            self.appData.selectedProjectID = nil
            self.saveData()
            self.reloadProjects()
        }
    }

    private func showProjectEditor(project: Project?) {
        let editor = ProjectEditorViewController(project: project) { [weak self] updatedProject in
            guard let self else { return }

            if
                let existing = project,
                let index = appData.projects.firstIndex(where: { $0.id == existing.id })
            {
                self.appData.projects[index] = updatedProject
            } else {
                self.appData.projects.append(updatedProject)
            }

            self.saveData()
            self.reloadProjects()

            // Select newly added project
            if project == nil {
                self.selectedProjectIndex = self.appData.projects.count - 1
                self.projectTableView.selectRowIndexes(IndexSet(integer: self.selectedProjectIndex!), byExtendingSelection: false)
                self.updateButtonStates()
            }
        }

        presentAsSheet(editor)
    }
}

// MARK: NSTableViewDataSource

extension MainViewController: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        self.appData.projects.count
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
        guard info.draggingSource as? NSTableView === self.projectTableView else { return [] }
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
        let project = self.appData.projects.remove(at: sourceRow)
        let destinationRow = sourceRow < row ? row - 1 : row
        self.appData.projects.insert(project, at: destinationRow)

        // Animate the row move
        tableView.moveRow(at: sourceRow, to: destinationRow)

        // Update selection to follow the moved item
        self.selectedProjectIndex = destinationRow

        self.saveData()

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

        let project = self.appData.projects[row]
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
        let selectedRow = self.projectTableView.selectedRow
        self.selectedProjectIndex = selectedRow >= 0 ? selectedRow : nil

        // Remember the selected project for next launch
        if let index = selectedProjectIndex, index < appData.projects.count {
            self.appData.selectedProjectID = self.appData.projects[index].id
        } else {
            self.appData.selectedProjectID = nil
        }
        self.saveData()

        self.updateButtonStates()
    }
}

// MARK: NSMenuDelegate

extension MainViewController: NSMenuDelegate {
    private static var clickedRow: Int = -1

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard
            menu === self.projectTableView.menu,
            let window = projectTableView.window else { return }

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let tablePoint = self.projectTableView.convert(windowPoint, from: nil)
        Self.clickedRow = self.projectTableView.row(at: tablePoint)

        // Only enable menu items if clicking on a valid row
        let hasClickedRow = Self.clickedRow >= 0 && Self.clickedRow < self.appData.projects.count
        for item in menu.items {
            item.isEnabled = hasClickedRow
            // Make items hidden when clicking on blank rows to prevent empty menu
            item.isHidden = !hasClickedRow
        }
    }

    @objc func editClickedProject() {
        guard Self.clickedRow >= 0, Self.clickedRow < self.appData.projects.count else { return }
        let project = self.appData.projects[Self.clickedRow]
        self.showProjectEditor(project: project)
    }

    @objc func deleteClickedProject() {
        guard Self.clickedRow >= 0, Self.clickedRow < self.appData.projects.count else { return }
        let project = self.appData.projects[Self.clickedRow]

        let alert = NSAlert()
        alert.messageText = "Delete \(project.name)?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let deletedProjectID = self.appData.projects[Self.clickedRow].id
            self.appData.projects.remove(at: Self.clickedRow)
            if self.selectedProjectIndex == Self.clickedRow {
                self.selectedProjectIndex = nil
                self.appData.selectedProjectID = nil
            } else if let selected = selectedProjectIndex, selected > Self.clickedRow {
                self.selectedProjectIndex = selected - 1
            }
            // Clear selectedProjectID if the deleted project was the remembered one
            if self.appData.selectedProjectID == deletedProjectID {
                self.appData.selectedProjectID = nil
            }
            self.saveData()
            self.reloadProjects()
        }
    }
}

// MARK: NSToolbarDelegate

extension MainViewController: NSToolbarDelegate {
    private static let addProjectIdentifier = NSToolbarItem.Identifier("addProject")
    private static let settingsIdentifier = NSToolbarItem.Identifier("settings")
    private static let actionModeIdentifier = NSToolbarItem.Identifier("actionMode")
    private static let alwaysOnTopIdentifier = NSToolbarItem.Identifier("alwaysOnTop")
    private static let customDeviceIdentifier = NSToolbarItem.Identifier("customDevice")

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.addProjectIdentifier,
            .flexibleSpace,
            Self.actionModeIdentifier,
            Self.customDeviceIdentifier,
            Self.alwaysOnTopIdentifier,
            .flexibleSpace,
            Self.settingsIdentifier,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        self.toolbarDefaultItemIdentifiers(toolbar)
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
            item.action = #selector(self.addProject)
            item.isNavigational = true
            return item

        case Self.settingsIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Settings"
            item.paletteLabel = "Settings"
            item.toolTip = "Device Settings"
            item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
            item.target = self
            item.action = #selector(self.showSettings)
            item.isNavigational = true
            return item

        case Self.actionModeIdentifier:
            let segmentedControl = NSSegmentedControl(labels: ["Run Now", "Install Only"], trackingMode: .selectOne, target: self, action: #selector(actionModeChanged(_:)))
            segmentedControl.selectedSegment = self.isRunMode ? 0 : 1
            segmentedControl.segmentStyle = .automatic
            self.actionModeControl = segmentedControl

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
            item.image = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: "Always on Top")
            item.target = self
            item.action = #selector(self.toggleAlwaysOnTop)
            self.alwaysOnTopButton = item
            return item

        case Self.customDeviceIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Custom Device"
            item.paletteLabel = "Custom Device"
            item.toolTip = "Deploy to a custom device"
            item.image = NSImage(systemSymbolName: "ipad.landscape.and.iphone", accessibilityDescription: "Custom Device")
            item.target = self
            item.action = #selector(self.showCustomDeviceDialog)
            return item

        default:
            return nil
        }
    }

    @objc private func actionModeChanged(_ sender: NSSegmentedControl) {
        self.isRunMode = sender.selectedSegment == 0
        self.updateButtonStates()
    }

    @objc func toggleAlwaysOnTop() {
        self.isAlwaysOnTop.toggle()

        if self.isAlwaysOnTop {
            view.window?.level = .floating
            self.alwaysOnTopButton?.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Always on Top (Active)")
        } else {
            view.window?.level = .normal
            self.alwaysOnTopButton?.image = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: "Always on Top")
        }
    }

    @objc private func showCustomDeviceDialog() {
        guard self.selectedProjectIndex != nil else { return }

        let editor = CustomDeviceViewController(
            customDeviceName: self.appData.customDeviceName,
            isRunMode: self.isRunMode,
        ) { [weak self] deviceName in
            guard let self else { return }

            // Save the custom device name
            self.appData.customDeviceName = deviceName
            self.saveData()

            // Perform deployment with custom device
            self.performDeploymentToCustomDevice(deviceName: deviceName)
        }

        presentAsSheet(editor)
    }
}
