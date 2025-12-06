import AppKit

/// Manages the menu bar status item for quick project deployment.
final class MenuBarManager: NSObject, NSMenuDelegate {
    private enum Device {
        case iPhone
        case iPad
    }

    private var statusItem: NSStatusItem?
    private var selectedDevice: Device = .iPhone
    private weak var mainViewController: MainViewController?

    init(mainViewController: MainViewController) {
        self.mainViewController = mainViewController
        super.init()
        setupStatusItem()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let appData = DataManager.shared.load()

        // Project list
        if appData.projects.isEmpty {
            let emptyItem = NSMenuItem(title: "No Projects", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, project) in appData.projects.enumerated() {
                let item = NSMenuItem(
                    title: "Run \(project.name)",
                    action: #selector(runProject(_:)),
                    keyEquivalent: "",
                )
                item.target = self
                item.representedObject = project
                menu.addItem(item)

                // Add divider after the first (most recent) project
                if index == 0, appData.projects.count > 1 {
                    menu.addItem(.separator())
                }
            }
        }

        // Divider
        menu.addItem(.separator())

        // Device selection
        let iPhoneItem = NSMenuItem(
            title: "Run on iPhone",
            action: #selector(selectiPhone),
            keyEquivalent: "",
        )
        iPhoneItem.target = self
        iPhoneItem.state = selectedDevice == .iPhone ? .on : .off
        menu.addItem(iPhoneItem)

        let iPadItem = NSMenuItem(
            title: "Run on iPad",
            action: #selector(selectiPad),
            keyEquivalent: "",
        )
        iPadItem.target = self
        iPadItem.state = selectedDevice == .iPad ? .on : .off
        menu.addItem(iPadItem)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            button.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "xDeploy")?
                .withSymbolConfiguration(config)
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    @objc private func selectiPhone() {
        selectedDevice = .iPhone
    }

    @objc private func selectiPad() {
        selectedDevice = .iPad
    }

    @objc private func runProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }

        // Move this project to the top of the list (menu will rebuild on next open)
        var appData = DataManager.shared.load()
        if let index = appData.projects.firstIndex(where: { $0.id == project.id }), index > 0 {
            let movedProject = appData.projects.remove(at: index)
            appData.projects.insert(movedProject, at: 0)
            DataManager.shared.save(appData)
        }

        let deviceName = selectedDevice == .iPhone
            ? appData.deviceConfig.iPhoneName
            : appData.deviceConfig.iPadName

        let viewController = mainViewController
        viewController?.clearConsole()

        Task {
            do {
                try await DeploymentManager.shared.deployRun(
                    project: project,
                    deviceName: deviceName,
                    statusHandler: { _ in },
                    outputHandler: { output in
                        Task { @MainActor in
                            viewController?.appendToConsole(output)
                        }
                    },
                )
            } catch {
                await MainActor.run {
                    viewController?.appendToConsole("\n✗ Error: \(error.localizedDescription)\n")

                    let alert = NSAlert()
                    alert.messageText = "Deployment Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }
}
