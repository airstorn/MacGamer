import Foundation

public struct DependencyInstaller: Sendable {
    private let paths: AppPaths
    private let runtimeStore: RuntimeStore
    private let bottleStore: BottleStore

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        self.runtimeStore = RuntimeStore(paths: paths)
        self.bottleStore = BottleStore(paths: paths, runtimeStore: runtimeStore)
    }

    public func installVCRUN2022(bottleId: String, installerPath: String? = nil) throws {
        _ = try bottleStore.load(id: bottleId)
        guard bottleStore.isHealthy(id: bottleId) else {
            throw MacGamerError.bottleBroken(bottleId)
        }
        let wine64 = try runtimeStore.wine64URL()
        let prefix = paths.bottlePrefix(id: bottleId)

        if let installerPath {
            guard FileManager.default.fileExists(atPath: installerPath) else {
                throw MacGamerError.missingExecutable(installerPath)
            }
            try runWine(
                wine64: wine64,
                prefix: prefix,
                args: [installerPath, "/install", "/quiet", "/norestart"]
            )
            return
        }

        if let winetricks = resolveWinetricks() {
            let process = Process()
            process.executableURL = winetricks
            process.arguments = ["vcrun2022"]
            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = prefix.path
            env["WINE"] = wine64.path
            env["WINE64"] = wine64.path
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw MacGamerError.dependencyFailed(text)
            }
            return
        }

        throw MacGamerError.dependencyFailed(
            "укажите путь к VC_redist.x64.exe или установите winetricks: macgamer deps vcrun2022 --bottle <id> --installer <path>"
        )
    }

    public func plannedCommand(bottleId: String, installerPath: String) throws -> LaunchCommand {
        let planner = LaunchPlanner(paths: paths)
        return try planner.planManual(
            bottleId: bottleId,
            exe: installerPath,
            arguments: ["/install", "/quiet", "/norestart"],
            gameId: "vcrun2022"
        )
    }

    private func runWine(wine64: URL, prefix: URL, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", wine64.path] + args
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw MacGamerError.dependencyFailed(text)
        }
    }

    private func resolveWinetricks() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/winetricks",
            "/usr/local/bin/winetricks",
            "/usr/bin/winetricks"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
