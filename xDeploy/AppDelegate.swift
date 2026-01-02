import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // SwiftUI scenes manage windows and menus.
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            sender.activate(ignoringOtherApps: true)
            let mainWindow = sender.windows.first(where: { $0.identifier?.rawValue == "MainWindow" })
            (mainWindow ?? sender.windows.first)?.makeKeyAndOrderFront(nil)
        }
        return true
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
}
