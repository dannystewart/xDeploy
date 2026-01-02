import AppKit
import PolyKit
import SwiftUI

// MARK: - xDeployApp

@main
struct xDeployApp: App {
    @StateObject private var appController: AppController = .init()
    @AppStorage("MenuBarExtraIsInserted") private var isMenuBarExtraInserted: Bool = true

    var body: some Scene {
        Window("xDeploy", id: "main") {
            MainWindowRootView()
                .environmentObject(self.appController)
        }
        .defaultSize(width: 660, height: 356)
        .windowToolbarStyle(.unified)
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
                Button {
                    NSApp.sendAction(#selector(MainViewController.showSettings), to: nil, from: nil)
                } label: {
                    Label("Settings…", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Toggle(isOn: self.$isMenuBarExtraInserted) {
                    Label("Show Menu Bar Item", systemImage: "menubar.rectangle")
                }
            }

            CommandGroup(replacing: .undoRedo) {
                Button {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)

                Button {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                } label: {
                    Label("Cut", systemImage: "scissors")
                }
                .keyboardShortcut("x", modifiers: .command)

                Button {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: .command)

                Button {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                } label: {
                    Label("Paste", systemImage: "clipboard")
                }
                .keyboardShortcut("v", modifiers: .command)

                Divider()

                Button {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                } label: {
                    Label("Select All", systemImage: "selection.pin.in.out")
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            CommandGroup(after: .windowArrangement) {
                Divider()

                Button {
                    self.appController.toggleAlwaysOnTop()
                } label: {
                    Label("Always on Top", systemImage: "macwindow.on.rectangle")
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandMenu("Project") {
                Button {
                    NSApp.sendAction(#selector(MainViewController.addProject), to: nil, from: nil)
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    NSApp.sendAction(#selector(MainViewController.editCurrentlySelectedProject), to: nil, from: nil)
                } label: {
                    Label("Edit Project", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)

                Divider()

                Button {
                    self.appController.setActionMode(.installOnly)
                } label: {
                    Label("Install Only", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("i", modifiers: .command)

                Button {
                    self.appController.setActionMode(.runNow)
                } label: {
                    Label("Run Now", systemImage: "play.fill")
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button {
                    NSApp.sendAction(#selector(MainViewController.performActionForPhone), to: nil, from: nil)
                } label: {
                    Label("Deploy to iPhone", systemImage: "iphone")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button {
                    NSApp.sendAction(#selector(MainViewController.performActionForPad), to: nil, from: nil)
                } label: {
                    Label("Deploy to iPad", systemImage: "ipad.landscape")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button {
                    NSApp.sendAction(#selector(MainViewController.showCustomDeviceSheet), to: nil, from: nil)
                } label: {
                    Label("Custom Device…", systemImage: "ipad.and.iphone")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra(isInserted: self.$isMenuBarExtraInserted) {
            MenuBarExtraView()
                .environmentObject(self.appController)
        } label: {
            Image(systemName: "iphone")
                .renderingMode(.template)
                .font(.system(size: 18, weight: .medium))
                .accessibilityLabel(Text("xDeploy"))
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

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        self.onWindowChange?(newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.onWindowChange?(self.window)
    }
}

// MARK: - MainWindowRootView

struct MainWindowRootView: View {
    @EnvironmentObject private var appController: AppController
    @State private var actionModeSelection: AppController.ActionMode = .runNow

    var body: some View {
        ZStack {
            WindowAccessor { window in
                self.appController.attachMainWindowIfNeeded(window)
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)

            MainViewControllerHost(viewController: self.appController.mainViewController)
                .frame(minWidth: 660, minHeight: 356)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    self.appController.mainViewController.addProject()
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    self.appController.mainViewController.showSettings()
                } label: {
                    Image(systemName: "gear")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Picker(
                    "",
                    selection: self.$actionModeSelection,
                ) {
                    Text(AppController.ActionMode.runNow.displayName)
                        .tag(AppController.ActionMode.runNow)

                    Text(AppController.ActionMode.installOnly.displayName)
                        .tag(AppController.ActionMode.installOnly)
                }
                .pickerStyle(.segmented)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    self.appController.mainViewController.showCustomDeviceSheet()
                } label: {
                    Image(systemName: "ipad.landscape.and.iphone")
                }

                Button {
                    self.appController.toggleAlwaysOnTop()
                } label: {
                    Image(systemName: self.appController.isAlwaysOnTop ? "pin.fill" : "pin.slash")
                }
            }
        }
        .onAppear {
            self.actionModeSelection = self.appController.actionMode
        }
        .onChange(of: self.appController.actionMode) { _, newValue in
            if self.actionModeSelection != newValue {
                self.actionModeSelection = newValue
            }
        }
        .onChange(of: self.actionModeSelection) { _, newValue in
            if self.appController.actionMode != newValue {
                DispatchQueue.main.async {
                    self.appController.setActionMode(newValue)
                }
            }
        }
    }
}
