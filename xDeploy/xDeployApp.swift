import AppKit
import PolyKit
import SwiftUI

// MARK: - xDeployApp

@main
struct xDeployApp: App {
    @StateObject private var appController: AppController = .init()
    @AppStorage("MenuBarExtraIsInserted") private var isMenuBarExtraInserted: Bool = true

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowRootView()
                .environmentObject(self.appController)
        }
        .defaultSize(width: 660, height: 356)
        .commands {
            // xDeploy is a single-window app; remove SwiftUI's default “New Window” item.
            CommandGroup(replacing: .newItem) {}

            // Use PolyAbout for standardized About panel.
            CommandGroup(replacing: .appInfo) {
                Button {
                    PolyAbout.show(info: PolyAbout.Info(appName: "xDeploy"))
                } label: {
                    Label("About xDeploy", systemImage: "info.circle")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }

            // Route Settings… to the existing AppKit sheet.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NSApp.sendAction(#selector(MainViewController.showSettings), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Toggle("Show Menu Bar Item", systemImage: "macwindow", isOn: self.$isMenuBarExtraInserted)
            }

            CommandMenu("Project") {
                Button("New Project") {
                    NSApp.sendAction(#selector(MainViewController.addProject), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Edit Project") {
                    NSApp.sendAction(#selector(MainViewController.editCurrentlySelectedProject), to: nil, from: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Divider()

                Button("Install Only") {
                    NSApp.sendAction(#selector(MainViewController.switchToInstallMode), to: nil, from: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Run Now") {
                    NSApp.sendAction(#selector(MainViewController.switchToRunMode), to: nil, from: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Deploy to iPhone") {
                    NSApp.sendAction(#selector(MainViewController.performActionForPhone), to: nil, from: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Deploy to iPad") {
                    NSApp.sendAction(#selector(MainViewController.performActionForPad), to: nil, from: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("Custom Device…") {
                    NSApp.sendAction(#selector(MainViewController.showCustomDeviceSheet), to: nil, from: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("xDeploy", systemImage: "iphone", isInserted: self.$isMenuBarExtraInserted) {
            MenuBarExtraView()
                .environmentObject(self.appController)
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - MainViewControllerHost

struct MainViewControllerHost: NSViewControllerRepresentable {
    let viewController: MainViewController

    func makeNSViewController(context _: Context) -> MainViewController {
        self.viewController
    }

    func updateNSViewController(_: MainViewController, context _: Context) {}
}

// MARK: - WindowAccessor

/// An invisible view that notifies when it becomes attached to an `NSWindow`.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = WindowObservingView()
        view.onWindowChange = { window in
            guard let window else { return }
            Task { @MainActor in
                self.onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        guard let view = nsView as? WindowObservingView else { return }
        view.onWindowChange = { window in
            guard let window else { return }
            Task { @MainActor in
                self.onWindow(window)
            }
        }
    }
}

// MARK: - WindowObservingView

private final class WindowObservingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.onWindowChange?(self.window)
    }
}

// MARK: - MainWindowRootView

struct MainWindowRootView: View {
    @EnvironmentObject private var appController: AppController

    var body: some View {
        MainViewControllerHost(viewController: self.appController.mainViewController)
            .frame(minWidth: 660, minHeight: 356)
            .background(
                WindowAccessor { window in
                    self.appController.attachMainWindowIfNeeded(window)
                }
                .allowsHitTesting(false),
            )
    }
}
