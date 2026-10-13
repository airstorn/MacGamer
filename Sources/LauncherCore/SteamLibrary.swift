import Foundation

public final class SteamLibrary: @unchecked Sendable {
    private let paths: AppPaths
    private let bottleStore: BottleStore
    private let libraryStore: LibraryStore
    private let watchQueue = DispatchQueue(label: "MacGamer.SteamLibrary.watch")
    private var watchTimer: DispatchSourceTimer?
    private var watchedBottleId: String?

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        self.bottleStore = BottleStore(paths: paths)
        self.libraryStore = LibraryStore(paths: paths)
    }

    deinit {
        stopWatching()
    }

    public func use(path: String, bottleName: String = "Steam") throws -> BottleConfig {
        var bottle = try bottleStore.steamBottle() ?? bottleStore.create(
            name: bottleName,
            role: .steam,
            backend: .dxmt,
            runWineboot: true
        )
        try bottleStore.setSteamPath(id: bottle.id, path: path)
        bottle = try bottleStore.load(id: bottle.id)
        return bottle
    }

    public func sync(bottleId: String? = nil) throws -> [GameEntry] {
        let bottle = try resolveBottle(id: bottleId)
        let manifests = try scanManifests(bottle: bottle)
        var present = Set<Int>()
        var updated: [GameEntry] = []
        for manifest in manifests {
            present.insert(manifest.appId)
            let state = SteamVDF.installState(for: manifest.stateFlags)
            let entry = GameEntry(
                name: manifest.name,
                bottleId: bottle.id,
                source: .steam,
                steamAppId: manifest.appId,
                installState: state
            )
            try libraryStore.upsert(entry)
            updated.append(entry)
        }
        try libraryStore.markMissing(steamAppIds: present, bottleId: bottle.id)
        return try libraryStore.load().games.filter { $0.bottleId == bottle.id && $0.source == .steam }
    }

    public func startWatching(bottleId: String? = nil, onChange: (@Sendable () -> Void)? = nil) throws {
        stopWatching()
        let bottle = try resolveBottle(id: bottleId)
        watchedBottleId = bottle.id
        _ = try sync(bottleId: bottle.id)

        let timer = DispatchSource.makeTimerSource(queue: watchQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.5)
        timer.setEventHandler { [weak self] in
            guard let self, let id = self.watchedBottleId else { return }
            _ = try? self.sync(bottleId: id)
            if let onChange {
                DispatchQueue.main.async(execute: onChange)
            }
        }
        watchTimer = timer
        timer.resume()
    }

    public func stopWatching() {
        watchTimer?.cancel()
        watchTimer = nil
        watchedBottleId = nil
    }

    public func scanManifests(bottle: BottleConfig) throws -> [AppManifest] {
        var manifests: [AppManifest] = []
        for folder in try libraryFolders(bottle: bottle) {
            let steamapps = folder.path.hasSuffix("steamapps")
                ? folder
                : folder.appendingPathComponent("steamapps", isDirectory: true)
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil) else {
                continue
            }
            for file in files where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                if let manifest = try SteamVDF.parseAppManifest(at: file) {
                    manifests.append(manifest)
                }
            }
        }
        return manifests
    }

    private func resolveBottle(id: String?) throws -> BottleConfig {
        if let id {
            return try bottleStore.load(id: id)
        }
        guard let bottle = try bottleStore.steamBottle() else {
            throw MacGamerError.bottleNotFound("steam")
        }
        return bottle
    }

    private func libraryFolders(bottle: BottleConfig) throws -> [URL] {
        let prefix = paths.bottlePrefix(id: bottle.id)
        let defaultSteamapps = prefix.appendingPathComponent(
            "drive_c/Program Files (x86)/Steam/steamapps",
            isDirectory: true
        )
        var folders: [URL] = [defaultSteamapps]
        let vdf = defaultSteamapps.appendingPathComponent("libraryfolders.vdf")
        let extras = try SteamVDF.libraryFolders(from: vdf)
        folders.append(contentsOf: extras)
        if let steamPath = bottle.steamExePath {
            let steamDir = URL(fileURLWithPath: steamPath).deletingLastPathComponent()
            folders.append(steamDir.appendingPathComponent("steamapps", isDirectory: true))
        }
        var unique: [URL] = []
        var seen = Set<String>()
        for folder in folders {
            let path = folder.standardizedFileURL.path
            if seen.insert(path).inserted {
                unique.append(folder.standardizedFileURL)
            }
        }
        return unique
    }
}
