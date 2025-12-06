import AppKit

@main
struct xDeployApp {
    static let delegate: AppDelegate = .init()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
