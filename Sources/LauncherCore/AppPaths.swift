import Foundation

public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.root = support.appendingPathComponent("MacGamer", isDirectory: true)
        }
    }

    public var runtimes: URL { root.appendingPathComponent("runtimes", isDirectory: true) }
    public var bottles: URL { root.appendingPathComponent("bottles", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
    public var icons: URL { root.appendingPathComponent("icons", isDirectory: true) }
    public var libraryFile: URL { root.appendingPathComponent("library.json") }
    public var downloads: URL { root.appendingPathComponent("downloads", isDirectory: true) }
    public var gptkStore: URL { root.appendingPathComponent("store/d3dmetal", isDirectory: true) }

    public func runtimeDirectory(id: String) -> URL {
        runtimes.appendingPathComponent(id, isDirectory: true)
    }

    public func bottleDirectory(id: String) -> URL {
        bottles.appendingPathComponent(id, isDirectory: true)
    }

    public func bottlePrefix(id: String) -> URL {
        bottleDirectory(id: id).appendingPathComponent("prefix", isDirectory: true)
    }

    public func bottleConfig(id: String) -> URL {
        bottleDirectory(id: id).appendingPathComponent("bottle.json")
    }

    public func logDirectory(gameId: String) -> URL {
        logs.appendingPathComponent(gameId, isDirectory: true)
    }

    public func ensureLayout() throws {
        let fm = FileManager.default
        for url in [root, runtimes, bottles, logs, icons, downloads, gptkStore] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
