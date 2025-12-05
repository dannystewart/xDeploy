import AppKit

/// Manages the menu bar status item for quick project deployment.
final class MenuBarManager {
    private enum Device {
        case iPhone
        case iPad
    }

    private var statusItem: NSStatusItem?
    private var selectedDevice: Device = .iPhone
    private weak var mainViewController: MainViewController?

    init(mainViewController: MainViewController) {
        self.mainViewController = mainViewController
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            button.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "xDeploy")?
                .withSymbolConfiguration(config)
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let appData = DataManager.shared.load()

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

        // Divider
        menu.addItem(.separator())

        // Project list
        if appData.projects.isEmpty {
            let emptyItem = NSMenuItem(title: "No Projects", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for project in appData.projects {
                let item = NSMenuItem(
                    title: "Run \(project.name)",
                    action: #selector(runProject(_:)),
                    keyEquivalent: "",
                )
                item.target = self
                item.representedObject = project
                menu.addItem(item)
            }
        }

        statusItem?.menu = menu
    }

    @objc private func selectiPhone() {
        selectedDevice = .iPhone
        rebuildMenu()
    }

    @objc private func selectiPad() {
        selectedDevice = .iPad
        rebuildMenu()
    }

    @objc private func runProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? Project else { return }

        let appData = DataManager.shared.load()
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
