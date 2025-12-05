import Foundation

// MARK: - DeploymentManager

/// Handles the actual build and deployment operations.
final class DeploymentManager {
    static let shared: DeploymentManager = .init()

    private init() {}

    /// Builds the project for the specified device.
    func build(project: Project, deviceName: String) async throws -> String {
        let args = [
            "-scheme",
            project.scheme,
            "-project",
            (project.projectPath as NSString).expandingTildeInPath,
            "build",
            "-destination",
            "platform=iOS,name=\(deviceName)",
        ]

        return try await runCommand("/usr/bin/xcodebuild", arguments: args)
    }

    /// Installs the app on the specified device.
    func install(project: Project, deviceName: String) async throws -> String {
        let appPath = (project.appBundlePath as NSString).expandingTildeInPath
        let args = [
            "devicectl",
            "device",
            "install",
            "app",
            "--device",
            deviceName,
            appPath,
        ]

        return try await runCommand("/usr/bin/xcrun", arguments: args)
    }

    /// Launches the app on the specified device.
    func launch(project: Project, deviceName: String) async throws -> String {
        let args = [
            "devicectl",
            "device",
            "process",
            "launch",
            "--device",
            deviceName,
            project.bundleID,
        ]

        return try await runCommand("/usr/bin/xcrun", arguments: args)
    }

    /// Full deployment: build + install.
    func deployInstall(
        project: Project,
        deviceName: String,
        progressHandler: @escaping (String) -> Void,
    ) async throws {
        progressHandler("Building \(project.name) for \(deviceName)...")
        _ = try await build(project: project, deviceName: deviceName)

        progressHandler("Installing on \(deviceName)...")
        _ = try await install(project: project, deviceName: deviceName)

        progressHandler("✓ Installed \(project.name) on \(deviceName)")
    }

    /// Full deployment: build + install + launch.
    func deployRun(
        project: Project,
        deviceName: String,
        progressHandler: @escaping (String) -> Void,
    ) async throws {
        progressHandler("Building \(project.name) for \(deviceName)...")
        _ = try await build(project: project, deviceName: deviceName)

        progressHandler("Installing on \(deviceName)...")
        _ = try await install(project: project, deviceName: deviceName)

        progressHandler("Launching on \(deviceName)...")
        _ = try await launch(project: project, deviceName: deviceName)

        progressHandler("✓ Running \(project.name) on \(deviceName)")
    }

    /// Runs a shell command and returns the output.
    @discardableResult
    private func runCommand(_ command: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw DeploymentError.commandFailed(
                command: "\(command) \(arguments.joined(separator: " "))",
                exitCode: process.terminationStatus,
                output: output,
                error: errorOutput,
            )
        }

        return output + errorOutput
    }
}

// MARK: - DeploymentError

enum DeploymentError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32, output: String, error: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, exitCode, _, error):
            "Command failed (exit \(exitCode)): \(command)\n\(error)"
        }
    }
}
