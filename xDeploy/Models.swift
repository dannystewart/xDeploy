import Foundation

// MARK: - Project

struct Project: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var projectPath: String
    var scheme: String
    var bundleID: String

    /// Computed path to the .app bundle in the Build folder.
    /// The Build folder is expected to be in the same directory as the .xcodeproj file.
    /// Example: ~/Developer/PrismApp/Build/Products/Debug-iphoneos/Prism.app
    var appBundlePath: String {
        let projectURL = URL(fileURLWithPath: (projectPath as NSString).expandingTildeInPath)
        let projectDirectory = projectURL.deletingLastPathComponent()
        let appName = self.scheme // Usually the scheme name matches the app name
        return projectDirectory
            .appendingPathComponent("Build")
            .appendingPathComponent("Products")
            .appendingPathComponent("Debug-iphoneos")
            .appendingPathComponent("\(appName).app")
            .path
    }

    init(
        id: UUID = UUID(),
        name: String,
        projectPath: String,
        scheme: String,
        bundleID: String,
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.scheme = scheme
        self.bundleID = bundleID
    }
}

// MARK: - DeviceConfig

struct DeviceConfig: Codable {
    static let `default`: DeviceConfig = .init(
        iPhoneName: "Danny's iPhone",
        iPadName: "Danny's iPad",
    )

    var iPhoneName: String
    var iPadName: String
}

// MARK: - AppData

struct AppData: Codable {
    static let empty: AppData = .init(projects: [], deviceConfig: .default, selectedProjectID: nil)

    var projects: [Project]
    var deviceConfig: DeviceConfig

    /// The ID of the most recently selected project, restored on launch.
    var selectedProjectID: UUID?
}
