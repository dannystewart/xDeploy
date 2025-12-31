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
        // Run pre-build scripts (e.g., build number updates)
        try await self.runPreBuildScripts(for: project)

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

    /// Extracts and runs pre-build scripts from the project's scheme file.
    private func runPreBuildScripts(for project: Project) async throws {
        let expandedProjectPath = (project.projectPath as NSString).expandingTildeInPath
        let projectURL = URL(fileURLWithPath: expandedProjectPath)
        let projectDirectory = projectURL.deletingLastPathComponent()

        // Look for the scheme file
        let schemePath = projectURL
            .appendingPathComponent("xcshareddata")
            .appendingPathComponent("xcschemes")
            .appendingPathComponent("\(project.scheme).xcscheme")

        guard FileManager.default.fileExists(atPath: schemePath.path) else {
            // No scheme file found, nothing to run
            return
        }

        // Parse the XML to extract pre-build scripts
        guard let scripts = try self.extractPreBuildScripts(from: schemePath) else {
            // No pre-build scripts found
            return
        }

        // Run each script with appropriate environment
        for script in scripts {
            try await self.runPreBuildScript(script, projectDirectory: projectDirectory.path)
        }
    }

    /// Extracts pre-build scripts from an .xcscheme file.
    private func extractPreBuildScripts(from schemeURL: URL) throws -> [String]? {
        guard let data = try? Data(contentsOf: schemeURL) else {
            return nil
        }

        let parser = PreBuildScriptParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()

        return parser.scripts.isEmpty ? nil : parser.scripts
    }

    /// Runs a pre-build script with the necessary environment variables.
    private func runPreBuildScript(_ script: String, projectDirectory: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", script]

                // Set up environment variables that Xcode would provide
                var environment = ProcessInfo.processInfo.environment
                environment["PROJECT_DIR"] = projectDirectory

                process.environment = environment

                // Capture output (but discard it - we run silently)
                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        continuation.resume(throwing: DeploymentError.preBuildScriptFailed(
                            exitCode: process.terminationStatus,
                        ))
                    } else {
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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

                // Set up xcbeautify process
                let beautifyProcess = Process()
                beautifyProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/xcbeautify")

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
    case preBuildScriptFailed(exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, exitCode):
            "Command failed (exit \(exitCode)): \(command)"
        case let .preBuildScriptFailed(exitCode):
            "Pre-build script failed (exit \(exitCode))"
        }
    }
}

// MARK: - PreBuildScriptParser

/// XML parser for extracting pre-build scripts from .xcscheme files.
private class PreBuildScriptParser: NSObject, XMLParserDelegate {
    var scripts: [String] = []

    private var inPreActions = false
    private var inExecutionAction = false
    private var inActionContent = false
    private var currentScriptText: String?

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:],
    ) {
        switch elementName {
        case "PreActions":
            self.inPreActions = true

        case "ExecutionAction" where self.inPreActions:
            self.inExecutionAction = true

        case "ActionContent" where self.inExecutionAction:
            self.inActionContent = true
            if let scriptText = attributeDict["scriptText"] {
                // Decode XML entities
                self.currentScriptText = scriptText.decodingXMLEntities()
            }

        default:
            break
        }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
    ) {
        switch elementName {
        case "PreActions":
            self.inPreActions = false

        case "ExecutionAction":
            self.inExecutionAction = false

        case "ActionContent":
            self.inActionContent = false
            if let script = self.currentScriptText {
                self.scripts.append(script)
                self.currentScriptText = nil
            }

        default:
            break
        }
    }
}

// MARK: - String Extension

extension String {
    /// Decodes common XML entities.
    func decodingXMLEntities() -> String {
        var result = self
        result = result.replacingOccurrences(of: "&#10;", with: "\n")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        return result
    }
}
