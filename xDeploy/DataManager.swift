import Foundation

/// Manages persistence of app data to a JSON file in Application Support.
final class DataManager {
    static let shared: DataManager = .init()

    private let fileManager: FileManager = .default

    private var dataFileURL: URL {
        let appSupport = self.fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("xDeploy", isDirectory: true)

        // Ensure directory exists
        if !self.fileManager.fileExists(atPath: appFolder.path) {
            try? self.fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }

        return appFolder.appendingPathComponent("data.json")
    }

    private init() {}

    func load() -> AppData {
        guard self.fileManager.fileExists(atPath: self.dataFileURL.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: dataFileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(AppData.self, from: data)
        } catch {
            print("Failed to load data: \(error)")
            return .empty
        }
    }

    func save(_ appData: AppData) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(appData)
            try data.write(to: self.dataFileURL, options: .atomic)
        } catch {
            print("Failed to save data: \(error)")
        }
    }
}
