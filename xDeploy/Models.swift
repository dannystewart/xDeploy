import Foundation

// MARK: - Project

struct Project: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var projectPath: String
    var scheme: String
    var bundleID: String

    /// The derived data path for this project's build products.
    /// Example: ~/Library/Developer/Xcode/DerivedData/PrismApp-eifcozscykfhnudgtuedxokctbvf
    var derivedDataPath: String

    /// Computed path to the .app bundle in the derived data.
    var appBundlePath: String {
        let appName = scheme // Usually the scheme name matches the app name
        return "\(derivedDataPath)/Build/Products/Debug-iphoneos/\(appName).app"
    }

    init(
        id: UUID = UUID(),
        name: String,
        projectPath: String,
        scheme: String,
        bundleID: String,
        derivedDataPath: String,
    ) {
        self.id = id
        self.name = name
        self.projectPath = projectPath
        self.scheme = scheme
        self.bundleID = bundleID
        self.derivedDataPath = derivedDataPath
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
