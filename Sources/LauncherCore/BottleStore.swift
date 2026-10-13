import Foundation

public final class BottleStore: @unchecked Sendable {
    private let paths: AppPaths
    private let runtimeStore: RuntimeStore

    public init(paths: AppPaths = AppPaths(), runtimeStore: RuntimeStore? = nil) {
        self.paths = paths
        self.runtimeStore = runtimeStore ?? RuntimeStore(paths: paths)
    }

    public func list() throws -> [BottleConfig] {
        try paths.ensureLayout()
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: paths.bottles, includingPropertiesForKeys: nil)) ?? []
        return try urls.compactMap { url -> BottleConfig? in
            let configURL = url.appendingPathComponent("bottle.json")
            guard fm.fileExists(atPath: configURL.path) else { return nil }
            let data = try Data(contentsOf: configURL)
            return try JSONCoding.decoder.decode(BottleConfig.self, from: data)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    public func load(id: String) throws -> BottleConfig {
        let url = paths.bottleConfig(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MacGamerError.bottleNotFound(id)
        }
        let data = try Data(contentsOf: url)
        return try JSONCoding.decoder.decode(BottleConfig.self, from: data)
    }

    public func save(_ config: BottleConfig) throws {
        try paths.ensureLayout()
        let dir = paths.bottleDirectory(id: config.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONCoding.encoder.encode(config)
        try data.write(to: paths.bottleConfig(id: config.id), options: .atomic)
    }

    public func steamBottle() throws -> BottleConfig? {
        try list().first { $0.role == .steam }
    }

    public func create(
        name: String,
        role: BottleRole = .generic,
        backend: GraphicsBackend = .dxmt,
        runWineboot: Bool = true
    ) throws -> BottleConfig {
        try paths.ensureLayout()
        _ = try runtimeStore.wine64URL()

        if role == .steam, let existing = try steamBottle() {
            return existing
        }

        let config = BottleConfig(name: name, role: role, backend: backend)
        let prefix = paths.bottlePrefix(id: config.id)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try save(config)

        if runWineboot {
            try wineboot(bottleId: config.id)
            guard isHealthy(id: config.id) else {
                throw MacGamerError.bottleBroken(config.id)
            }
        }
        return config
    }

    public func setBackend(id: String, backend: GraphicsBackend) throws {
        var config = try load(id: id)
        if backend == .d3dmetal {
            let info = try runtimeStore.installedInfo()
            guard info.gptkCapable else { throw MacGamerError.gptkNotCapable }
            let framework = paths.gptkStore.appendingPathComponent("external/D3DMetal.framework")
            guard FileManager.default.fileExists(atPath: framework.path) else {
                throw MacGamerError.gptkNotImported
            }
        }
        config.backend = backend
        try save(config)
    }

    public func setSteamPath(id: String, path: String) throws {
        var config = try load(id: id)
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent.lowercased()
        guard FileManager.default.fileExists(atPath: path) else {
            throw MacGamerError.steamPathInvalid(path)
        }
        guard name == "steam.exe" || name == "steamsetup.exe" else {
            throw MacGamerError.steamPathInvalid(path)
        }
        config.steamExePath = path
        config.role = .steam
        try save(config)
    }

    public func wineboot(bottleId: String) throws {
        let wine64 = try runtimeStore.wine64URL()
        let prefix = paths.bottlePrefix(id: bottleId)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", wine64.path, "wineboot", "-u"]
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        process.waitUntilExit()
        if isHealthy(id: bottleId) {
            return
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        throw MacGamerError.processFailed("wineboot failed (\(process.terminationStatus)): \(text)")
    }

    public func isHealthy(id: String) -> Bool {
        let prefix = paths.bottlePrefix(id: id)
        let userreg = prefix.appendingPathComponent("user.reg")
        let driveC = prefix.appendingPathComponent("drive_c", isDirectory: true)
        let system32Lower = driveC.appendingPathComponent("windows/system32", isDirectory: true)
        let system32Mixed = driveC.appendingPathComponent("Windows/system32", isDirectory: true)
        let hasSystem32 = FileManager.default.fileExists(atPath: system32Lower.path)
            || FileManager.default.fileExists(atPath: system32Mixed.path)
        return FileManager.default.fileExists(atPath: userreg.path)
            && FileManager.default.fileExists(atPath: driveC.path)
            && hasSystem32
    }

    public func delete(id: String) throws {
        let dir = paths.bottleDirectory(id: id)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw MacGamerError.bottleNotFound(id)
        }
        try FileManager.default.removeItem(at: dir)
    }
}
