import Foundation

public struct LaunchPlanner: Sendable {
    private let paths: AppPaths
    private let runtimeStore: RuntimeStore
    private let bottleStore: BottleStore

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        self.runtimeStore = RuntimeStore(paths: paths)
        self.bottleStore = BottleStore(paths: paths, runtimeStore: runtimeStore)
    }

    public func planManual(
        bottleId: String,
        exe: String,
        arguments: [String] = [],
        workdir: String? = nil,
        env: [String: String] = [:],
        backend: GraphicsBackend? = nil,
        hud: Bool = false,
        gameId: String = "manual"
    ) throws -> LaunchCommand {
        let bottle = try bottleStore.load(id: bottleId)
        guard bottleStore.isHealthy(id: bottleId) else {
            throw MacGamerError.bottleBroken(bottleId)
        }
        let selected = backend ?? bottle.backend
        return try makeCommand(
            bottle: bottle,
            windowsArgs: [exe] + arguments,
            workdir: workdir,
            extraEnv: env,
            backend: selected,
            hud: hud || bottle.hud,
            gameId: gameId
        )
    }

    public func planSteamOpen(bottleId: String? = nil) throws -> LaunchCommand {
        let bottle = try resolveSteamBottle(id: bottleId)
        guard let steamPath = bottle.steamExePath else {
            throw MacGamerError.steamPathMissing
        }
        let resolved = try resolveSteamExecutable(path: steamPath, bottle: bottle)
        let steamDir = URL(fileURLWithPath: resolved).deletingLastPathComponent()
        try SteamWebHelperFix.apply(steamDirectory: steamDir)
        let backend = preferredGraphicsBackend(bottle.backend)
        return try makeCommand(
            bottle: bottle,
            windowsArgs: [resolved],
            workdir: steamDir.path,
            extraEnv: [:],
            backend: backend,
            hud: bottle.hud,
            gameId: "steam-client"
        )
    }

    public func planSteamLaunch(appId: Int, bottleId: String? = nil, hud: Bool = false) throws -> LaunchCommand {
        let bottle = try resolveSteamBottle(id: bottleId)
        guard let steamPath = bottle.steamExePath else {
            throw MacGamerError.steamPathMissing
        }
        let resolved = try resolveSteamExecutable(path: steamPath, bottle: bottle)
        let steamDir = URL(fileURLWithPath: resolved).deletingLastPathComponent()
        try SteamWebHelperFix.apply(steamDirectory: steamDir)
        let backend = preferredGraphicsBackend(bottle.backend)
        return try makeCommand(
            bottle: bottle,
            windowsArgs: [resolved, "-applaunch", "\(appId)"],
            workdir: steamDir.path,
            extraEnv: [:],
            backend: backend,
            hud: hud || bottle.hud,
            gameId: "steam-\(appId)"
        )
    }

    private func preferredGraphicsBackend(_ configured: GraphicsBackend) -> GraphicsBackend {
        if configured == .wined3d {
            return .dxmt
        }
        return configured
    }

    public func describe(_ command: LaunchCommand) -> String {
        let interesting = command.environment.keys.sorted().filter { key in
            key.hasPrefix("WINE") || key.hasPrefix("DXMT") || key.hasPrefix("DXVK")
                || key.hasPrefix("CX_") || key == "ROSETTA_ADVERTISE_AVX"
        }
        var lines = [
            "backend: \(command.backend.rawValue)",
            "prefix: \(command.winePrefix)",
            "log: \(command.logPath)",
            "cmd: /usr/bin/arch -x86_64 \(command.executable) \(command.arguments.joined(separator: " "))"
        ]
        if let cwd = command.workingDirectory {
            lines.insert("cwd: \(cwd)", at: 2)
        }
        lines.append("env:")
        lines.append(contentsOf: interesting.map { "  \($0)=\(command.environment[$0] ?? "")" })
        return lines.joined(separator: "\n")
    }

    private func resolveSteamBottle(id: String?) throws -> BottleConfig {
        if let id {
            return try bottleStore.load(id: id)
        }
        guard let bottle = try bottleStore.steamBottle() else {
            throw MacGamerError.bottleNotFound("steam")
        }
        return bottle
    }

    private func resolveSteamExecutable(path: String, bottle: BottleConfig) throws -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent.lowercased()
        if name == "steam.exe" {
            guard FileManager.default.fileExists(atPath: path) else {
                throw MacGamerError.steamPathInvalid(path)
            }
            return path
        }
        if name == "steamsetup.exe" {
            let prefixSteam = paths.bottlePrefix(id: bottle.id)
                .appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
            if FileManager.default.fileExists(atPath: prefixSteam.path) {
                return prefixSteam.path
            }
            throw MacGamerError.steamPathInvalid(
                "указан SteamSetup.exe, но steam.exe ещё не установлен пользователем в бутылке"
            )
        }
        throw MacGamerError.steamPathInvalid(path)
    }

    private func makeCommand(
        bottle: BottleConfig,
        windowsArgs: [String],
        workdir: String?,
        extraEnv: [String: String],
        backend: GraphicsBackend,
        hud: Bool,
        gameId: String
    ) throws -> LaunchCommand {
        let report = Doctor(paths: paths).report()
        if report.chip == "arm64" && !report.rosettaInstalled {
            throw MacGamerError.rosettaMissing
        }
        let wineBinary = try runtimeStore.wine64URL()
        let info = try runtimeStore.installedInfo()
        let overlay = try runtimeStore.overlayURL(for: backend)
        if backend == .dxmt, let overlay {
            try runtimeStore.deployDxmtNativeDLLs(overlayRoot: overlay, bottleId: bottle.id)
        }
        let backendEnv = try BackendOverlay.environment(
            backend: backend,
            overlayURL: overlay,
            hud: hud,
            gptkCapable: info.gptkCapable,
            gptkImported: report.gptkImported
        )

        let logDir = paths.logDirectory(gameId: gameId)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let logPath = logDir.appendingPathComponent("\(stamp).log").path

        let runtimeRoot = paths.runtimeDirectory(id: info.id)
        var environment: [String: String] = [
            "WINEPREFIX": paths.bottlePrefix(id: bottle.id).path,
            "WINEDEBUG": "-all",
            "WINEDLLOVERRIDES": backendEnv.overrides,
            "CX_ROOT": runtimeRoot.path
        ]
        if let server = try runtimeStore.wineServerURL() {
            environment["WINESERVER"] = server.path
        }
        environment["WINELOADER"] = wineBinary.path
        let runtimeLib = runtimeRoot.appendingPathComponent("lib", isDirectory: true)
        let runtimeLib64 = runtimeRoot.appendingPathComponent("lib64", isDirectory: true)
        var fallbackParts: [String] = []
        if FileManager.default.fileExists(atPath: runtimeLib64.path) { fallbackParts.append(runtimeLib64.path) }
        if FileManager.default.fileExists(atPath: runtimeLib.path) { fallbackParts.append(runtimeLib.path) }
        fallbackParts.append("/usr/local/lib")
        if let existing = ProcessInfo.processInfo.environment["DYLD_FALLBACK_LIBRARY_PATH"], !existing.isEmpty {
            fallbackParts.append(existing)
        }
        if !fallbackParts.isEmpty {
            environment["DYLD_FALLBACK_LIBRARY_PATH"] = fallbackParts.joined(separator: ":")
        }
        if let wineDll = try runtimeStore.wineDllPath() {
            let prepend = backendEnv.dllPathPrepend.map { "\($0):" } ?? ""
            environment["WINEDLLPATH"] = prepend + wineDll
        } else if let prepend = backendEnv.dllPathPrepend {
            environment["WINEDLLPATH_PREPEND"] = prepend
        }
        for (key, value) in backendEnv.extra {
            environment[key] = value
        }
        for (key, value) in extraEnv {
            environment[key] = value
        }

        return LaunchCommand(
            executable: wineBinary.path,
            arguments: windowsArgs,
            environment: environment,
            workingDirectory: workdir,
            backend: backend,
            winePrefix: paths.bottlePrefix(id: bottle.id).path,
            logPath: logPath
        )
    }
}
