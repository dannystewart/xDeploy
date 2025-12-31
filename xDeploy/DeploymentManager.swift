import Foundation

// MARK: - DeploymentManager

/// Handles the actual build and deployment operations.
final class DeploymentManager: @unchecked Sendable {
    static let shared: DeploymentManager = .init()

    private init() {}

    /// Builds the project for the specified device.
    func build(
        project: Project,
        deviceName: String,
        outputHandler: @escaping @Sendable (String) -> Void,
    ) async throws {
        let args = [
            "-scheme",
            project.scheme,
            "-project",
            (project.projectPath as NSString).expandingTildeInPath,
            "build",
            "-destination",
            "platform=iOS,name=\(deviceName)",
        ]

        try await self.runCommandWithBeautifier("/usr/bin/xcodebuild", arguments: args, outputHandler: outputHandler)
    }

    /// Installs the app on the specified device.
    func install(
        project: Project,
        deviceName: String,
        outputHandler: @escaping @Sendable (String) -> Void,
    ) async throws {
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

        try await runCommand("/usr/bin/xcrun", arguments: args, outputHandler: outputHandler)
    }

    /// Launches the app on the specified device.
    func launch(
        project: Project,
        deviceName: String,
        outputHandler: @escaping @Sendable (String) -> Void,
    ) async throws {
        let args = [
            "devicectl",
            "device",
            "process",
            "launch",
            "--device",
            deviceName,
            project.bundleID,
        ]

        try await self.runCommand("/usr/bin/xcrun", arguments: args, outputHandler: outputHandler)
    }

    /// Full deployment: build + install.
    func deployInstall(
        project: Project,
        deviceName: String,
        statusHandler: @escaping @Sendable (String) -> Void,
        outputHandler: @escaping @Sendable (String) -> Void,
    ) async throws {
        statusHandler("Building \(project.name) for \(deviceName)...")
        outputHandler("=== Building \(project.name) for \(deviceName) ===\n")
        try await self.build(project: project, deviceName: deviceName, outputHandler: outputHandler)

        statusHandler("Installing on \(deviceName)...")
        outputHandler("\n=== Installing on \(deviceName) ===\n")
        try await self.install(project: project, deviceName: deviceName, outputHandler: outputHandler)

        statusHandler("✓ Installed \(project.name) on \(deviceName)")
        outputHandler("\n✓ Installation complete\n")
    }

    /// Full deployment: build + install + launch.
    func deployRun(
        project: Project,
        deviceName: String,
        statusHandler: @escaping @Sendable (String) -> Void,
        outputHandler: @escaping @Sendable (String) -> Void,
    ) async throws {
        statusHandler("Building \(project.name) for \(deviceName)...")
        outputHandler("=== Building \(project.name) for \(deviceName) ===\n")
        try await self.build(project: project, deviceName: deviceName, outputHandler: outputHandler)

        statusHandler("Installing on \(deviceName)...")
        outputHandler("\n=== Installing on \(deviceName) ===\n")
        try await self.install(project: project, deviceName: deviceName, outputHandler: outputHandler)

        statusHandler("Launching on \(deviceName)...")
        outputHandler("\n=== Launching on \(deviceName) ===\n")
        try await self.launch(project: project, deviceName: deviceName, outputHandler: outputHandler)

        statusHandler("✓ Running \(project.name) on \(deviceName)")
        outputHandler("\n✓ Launch complete\n")
    }

    /// Runs a shell command asynchronously with streaming output through xcbeautify.
    private func runCommandWithBeautifier(
        _ command: String,
        arguments: [String],
        outputHandler: @escaping @Sendable (String) -> Void,
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                // Set up xcodebuild process
                let xcodebuildProcess = Process()
                xcodebuildProcess.executableURL = URL(fileURLWithPath: command)
                xcodebuildProcess.arguments = arguments

                // Set up xcbeautify process with script to force unbuffered output
                // Using `script -q /dev/null` tricks xcbeautify into thinking it's writing to a TTY
                let beautifyProcess = Process()
                beautifyProcess.executableURL = URL(fileURLWithPath: "/usr/bin/script")
                beautifyProcess.arguments = ["-q", "/dev/null", "/opt/homebrew/bin/xcbeautify"]

                // Enable color output - xcbeautify respects these environment variables
                var environment = ProcessInfo.processInfo.environment
                environment["CLICOLOR_FORCE"] = "1"
                environment["TERM"] = "xterm-256color"
                beautifyProcess.environment = environment

                // Pipe xcodebuild output to xcbeautify
                let pipe = Pipe()
                xcodebuildProcess.standardOutput = pipe
                xcodebuildProcess.standardError = pipe
                beautifyProcess.standardInput = pipe

                // Capture beautified output
                let outputPipe = Pipe()
                beautifyProcess.standardOutput = outputPipe
                beautifyProcess.standardError = outputPipe

                var outputBuffer = Data()

                // Stream beautified output
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    outputBuffer.append(data)

                    // Process complete lines
                    while let newlineRange = outputBuffer.range(of: Data([0x0A])) {
                        let lineData = outputBuffer.subdata(in: 0 ..< newlineRange.upperBound)
                        outputBuffer.removeSubrange(0 ..< newlineRange.upperBound)
                        if let line = String(data: lineData, encoding: .utf8) {
                            outputHandler(line)
                        }
                    }
                }

                do {
                    try beautifyProcess.run()
                    try xcodebuildProcess.run()
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }

                xcodebuildProcess.waitUntilExit()

                // Close the pipe to signal EOF to xcbeautify
                try? pipe.fileHandleForWriting.close()

                beautifyProcess.waitUntilExit()

                // Clean up handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil

                // Flush any remaining buffered content
                if !outputBuffer.isEmpty, let remaining = String(data: outputBuffer, encoding: .utf8) {
                    outputHandler(remaining)
                }

                if xcodebuildProcess.terminationStatus != 0 {
                    continuation.resume(throwing: DeploymentError.commandFailed(
                        command: "\(command) \(arguments.joined(separator: " "))",
                        exitCode: xcodebuildProcess.terminationStatus,
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Runs a shell command asynchronously with streaming output.
    private func runCommand(
        _ command: String,
        arguments: [String],
        outputHandler: @escaping @Sendable (String) -> Void,
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                // Buffer for partial lines
                var outputBuffer = Data()
                var errorBuffer = Data()

                // Stream stdout
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    outputBuffer.append(data)

                    // Process complete lines
                    while let newlineRange = outputBuffer.range(of: Data([0x0A])) {
                        let lineData = outputBuffer.subdata(in: 0 ..< newlineRange.upperBound)
                        outputBuffer.removeSubrange(0 ..< newlineRange.upperBound)
                        if let line = String(data: lineData, encoding: .utf8) {
                            outputHandler(line)
                        }
                    }
                }

                // Stream stderr
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    errorBuffer.append(data)

                    // Process complete lines
                    while let newlineRange = errorBuffer.range(of: Data([0x0A])) {
                        let lineData = errorBuffer.subdata(in: 0 ..< newlineRange.upperBound)
                        errorBuffer.removeSubrange(0 ..< newlineRange.upperBound)
                        if let line = String(data: lineData, encoding: .utf8) {
                            outputHandler(line)
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }

                process.waitUntilExit()

                // Clean up handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                // Flush any remaining buffered content
                if !outputBuffer.isEmpty, let remaining = String(data: outputBuffer, encoding: .utf8) {
                    outputHandler(remaining)
                }
                if !errorBuffer.isEmpty, let remaining = String(data: errorBuffer, encoding: .utf8) {
                    outputHandler(remaining)
                }

                if process.terminationStatus != 0 {
                    continuation.resume(throwing: DeploymentError.commandFailed(
                        command: "\(command) \(arguments.joined(separator: " "))",
                        exitCode: process.terminationStatus,
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - DeploymentError

enum DeploymentError: LocalizedError {
    case commandFailed(command: String, exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, exitCode):
            "Command failed (exit \(exitCode)): \(command)"
        }
    }
}
