import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var mainViewController: MainViewController?
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_: Notification) {
        self.setupMainMenu()
        self.setupMainWindow()
        if let viewController = mainViewController {
            self.menuBarManager = MenuBarManager(mainViewController: viewController)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false // Keep running for menu bar access even when window is closed/hidden
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu Responder Actions

    /// Show About panel (App menu)
    @objc func showAbout(_: Any?) {
        let credits = NSAttributedString(
            string: "by Danny Stewart",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.secondaryLabelColor,
            ],
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "xDeploy",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            .credits: credits,
        ])
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let aboutItem = NSMenuItem(title: "About xDeploy", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(MainViewController.showSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide xDeploy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit xDeploy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (for copy/paste/select all)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: nil)
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())

        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cutItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        pasteItem.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil)
        editMenu.addItem(pasteItem)

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.image = NSImage(systemSymbolName: "selection.pin.in.out", accessibilityDescription: nil)
        editMenu.addItem(selectAllItem)

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        let alwaysOnTopItem = NSMenuItem(title: "Always on Top", action: #selector(MainViewController.toggleAlwaysOnTop), keyEquivalent: "t")
        alwaysOnTopItem.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)
        windowMenu.addItem(alwaysOnTopItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu

        // Add Project menu with keyboard shortcuts
        self.addProjectMenu(to: mainMenu)
    }

    private func addProjectMenu(to mainMenu: NSMenu) {
        let projectMenuItem = NSMenuItem()
        let projectMenu = NSMenu(title: "Project")

        let newProjectItem = NSMenuItem(title: "New Project", action: #selector(MainViewController.addProject), keyEquivalent: "n")
        newProjectItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        projectMenu.addItem(newProjectItem)

        let editProjectItem = NSMenuItem(title: "Edit Project", action: #selector(MainViewController.editCurrentlySelectedProject), keyEquivalent: "e")
        editProjectItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        projectMenu.addItem(editProjectItem)

        projectMenu.addItem(.separator())

        let installItem = NSMenuItem(title: "Install Only", action: #selector(MainViewController.switchToInstallMode), keyEquivalent: "i")
        installItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        projectMenu.addItem(installItem)

        let runItem = NSMenuItem(title: "Run Now", action: #selector(MainViewController.switchToRunMode), keyEquivalent: "r")
        runItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        projectMenu.addItem(runItem)

        projectMenu.addItem(.separator())

        let iPhoneItem = NSMenuItem(title: "Deploy to iPhone", action: #selector(MainViewController.performActionForPhone), keyEquivalent: "i")
        iPhoneItem.keyEquivalentModifierMask = [.command, .shift]
        iPhoneItem.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: nil)
        projectMenu.addItem(iPhoneItem)

        let iPadItem = NSMenuItem(title: "Deploy to iPad", action: #selector(MainViewController.performActionForPad), keyEquivalent: "p")
        iPadItem.keyEquivalentModifierMask = [.command, .shift]
        iPadItem.image = NSImage(systemSymbolName: "ipad.landscape", accessibilityDescription: nil)
        projectMenu.addItem(iPadItem)

        projectMenu.addItem(.separator())

        let customDeviceItem = NSMenuItem(title: "Custom Device…", action: #selector(MainViewController.showCustomDeviceSheet), keyEquivalent: "d")
        customDeviceItem.keyEquivalentModifierMask = [.command, .shift]
        customDeviceItem.image = NSImage(systemSymbolName: "ipad.and.iphone", accessibilityDescription: nil)
        projectMenu.addItem(customDeviceItem)

        projectMenuItem.submenu = projectMenu
        mainMenu.insertItem(projectMenuItem, at: 1)
    }

    private func setupMainWindow() {
        let viewController = MainViewController()
        self.mainViewController = viewController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 356),
            styleMask: [.titled, .closable, .miniaturizable, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false,
        )
        window.title = "xDeploy"
        window.contentViewController = viewController
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.minSize = NSSize(width: 660, height: 356)

        // Set up toolbar
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = viewController
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        window.makeKeyAndOrderFront(nil)
        self.mainWindow = window
    }
}
