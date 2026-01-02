import AppKit
import Combine
import SwiftUI

// MARK: - AppController

/// App-wide coordinator shared between the main window and the menu bar.
///
/// `@MainActor` is required because this type owns and updates AppKit UI objects
/// (`MainViewController`, `NSWindow`), which must be interacted with on the main thread.
@MainActor
final class AppController: ObservableObject {
    enum Device: String, CaseIterable, Identifiable {
        case iPhone
        case iPad

        var id: String { self.rawValue }

        var displayName: String {
            switch self {
            case .iPhone:
                "iPhone"
            case .iPad:
                "iPad"
            }
        }
    }

    /// Owned here so menu bar actions can target the same UI instance.
    let mainViewController: MainViewController = .init()

    @Published var selectedDevice: Device = .iPhone

    private var mainWindow: NSWindow?
    private var mainWindowDelegate: MainWindowDelegate?

    func attachMainWindowIfNeeded(_ window: NSWindow) {
        if self.mainWindow === window {
            return
        }

        self.mainWindow = window

        // Mirror the old AppKit lifecycle defaults.
        window.title = "xDeploy"
        window.identifier = NSUserInterfaceItemIdentifier("MainWindow")

        self.attachToolbarIfNeeded(to: window)
        self.attachWindowDelegateIfNeeded(to: window)
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        self.mainWindow?.makeKeyAndOrderFront(nil)
    }

    func runProject(_ project: Project) {
        // Move this project to the top of the list (mirrors the legacy status-item behavior).
        var appData = DataManager.shared.load()
        if let index = appData.projects.firstIndex(where: { $0.id == project.id }), index > 0 {
            let movedProject = appData.projects.remove(at: index)
            appData.projects.insert(movedProject, at: 0)
            DataManager.shared.save(appData)
        }

        let deviceName = switch self.selectedDevice {
        case .iPhone:
            appData.deviceConfig.iPhoneName
        case .iPad:
            appData.deviceConfig.iPadName
        }

        let mainViewController = self.mainViewController
        mainViewController.clearConsole()

        Task {
            do {
                try await DeploymentManager.shared.deployRun(
                    project: project,
                    deviceName: deviceName,
                    statusHandler: { _ in },
                    outputHandler: { output in
                        Task { @MainActor in
                            mainViewController.appendToConsole(output)
                        }
                    },
                )
            } catch {
                await MainActor.run {
                    mainViewController.appendToConsole("\nError: \(error.localizedDescription)\n")

                    let alert = NSAlert()
                    alert.messageText = "Deployment Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }

    private func attachToolbarIfNeeded(to window: NSWindow) {
        let toolbarIdentifier = NSToolbar.Identifier("MainToolbar")

        if window.toolbar?.identifier == toolbarIdentifier {
            return
        }

        let toolbar = NSToolbar(identifier: toolbarIdentifier)
        toolbar.delegate = self.mainViewController
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    private func attachWindowDelegateIfNeeded(to window: NSWindow) {
        if self.mainWindowDelegate == nil {
            self.mainWindowDelegate = MainWindowDelegate()
        }
        window.delegate = self.mainWindowDelegate
    }
}

// MARK: - MainWindowDelegate

private final class MainWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Keep the scene alive so the AppKit view controller can be reused.
        sender.orderOut(nil)
        return false
    }
}
