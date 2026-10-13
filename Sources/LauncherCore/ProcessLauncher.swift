import Foundation

public final class ProcessLauncher: @unchecked Sendable {
    public init() {}

    public func run(_ command: LaunchCommand, wait: Bool = true) throws -> LaunchResult {
        let logURL = URL(fileURLWithPath: command.logPath)
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logURL.path, contents: nil)

        let header = """
        backend=\(command.backend.rawValue)
        prefix=\(command.winePrefix)
        cmd=/usr/bin/arch -x86_64 \(command.executable) \(command.arguments.joined(separator: " "))

        """
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            if let data = header.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", command.executable] + command.arguments
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in command.environment {
            environment[key] = value
        }
        process.environment = environment
        if let cwd = command.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let out = try FileHandle(forWritingTo: logURL)
        out.seekToEndOfFile()
        process.standardOutput = out
        process.standardError = out

        try process.run()
        if wait {
            process.waitUntilExit()
            try? out.close()
            let exitCode = process.terminationStatus
            let meta = logURL.deletingPathExtension().appendingPathExtension("exit")
            try "\(exitCode)".data(using: .utf8)?.write(to: meta)
            return LaunchResult(exitCode: exitCode, logPath: command.logPath)
        }
        try? out.close()
        return LaunchResult(exitCode: 0, logPath: command.logPath)
    }
}
