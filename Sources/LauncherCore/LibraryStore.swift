import Foundation

public final class LibraryStore: @unchecked Sendable {
    private let paths: AppPaths
    private let queue = DispatchQueue(label: "MacGamer.LibraryStore")

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    public func load() throws -> LibraryDocument {
        try paths.ensureLayout()
        let url = paths.libraryFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LibraryDocument()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LibraryDocument.self, from: data)
    }

    public func save(_ document: LibraryDocument) throws {
        try paths.ensureLayout()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: paths.libraryFile, options: .atomic)
    }

    public func upsert(_ game: GameEntry) throws {
        try queue.sync {
            var doc = try load()
            if let index = doc.games.firstIndex(where: { gameMatches($0, game) }) {
                var existing = doc.games[index]
                existing.name = game.name
                existing.installState = game.installState
                existing.steamAppId = game.steamAppId ?? existing.steamAppId
                existing.exe = game.exe ?? existing.exe
                existing.workdir = game.workdir ?? existing.workdir
                if !game.arguments.isEmpty {
                    existing.arguments = game.arguments
                }
                doc.games[index] = existing
            } else {
                doc.games.append(game)
            }
            try save(doc)
        }
    }

    public func markMissing(steamAppIds present: Set<Int>, bottleId: String) throws {
        try queue.sync {
            var doc = try load()
            var changed = false
            for index in doc.games.indices {
                let game = doc.games[index]
                guard game.source == .steam,
                      game.bottleId == bottleId,
                      let appId = game.steamAppId else { continue }
                if !present.contains(appId), game.installState != .missing {
                    doc.games[index].installState = .missing
                    changed = true
                }
            }
            if changed {
                try save(doc)
            }
        }
    }

    private func gameMatches(_ lhs: GameEntry, _ rhs: GameEntry) -> Bool {
        if lhs.id == rhs.id { return true }
        if let a = lhs.steamAppId, let b = rhs.steamAppId, a == b, lhs.bottleId == rhs.bottleId {
            return true
        }
        return false
    }
}
