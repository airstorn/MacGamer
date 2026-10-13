import Foundation

public struct AppManifest: Equatable, Sendable {
    public var appId: Int
    public var name: String
    public var installDir: String
    public var stateFlags: Int
    public var path: URL
}

public enum SteamVDF {
    public static func parseKeyValues(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #"\"([^\"]+)\"\s+\"([^\"]*)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match,
                  let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else { return }
            result[String(text[keyRange])] = String(text[valueRange])
        }
        return result
    }

    public static func parseAppManifest(at url: URL) throws -> AppManifest? {
        let text = try String(contentsOf: url, encoding: .utf8)
        let values = parseKeyValues(text)
        guard let appIdString = values["appid"] ?? values["AppID"],
              let appId = Int(appIdString) else { return nil }
        let name = values["name"] ?? "App \(appId)"
        let installDir = values["installdir"] ?? ""
        let stateFlags = Int(values["StateFlags"] ?? "0") ?? 0
        return AppManifest(
            appId: appId,
            name: name,
            installDir: installDir,
            stateFlags: stateFlags,
            path: url
        )
    }

    public static func installState(for flags: Int) -> InstallState {
        let updatingBits = 2 | 1024 | 2048 | 4096
        if flags & updatingBits != 0 {
            return .updating
        }
        let installingBits = 1 | 8 | 16 | 32 | 64 | 512
        if flags & installingBits != 0 {
            return .installing
        }
        if flags & 4 != 0 {
            return .ready
        }
        return .installing
    }

    public static func libraryFolders(from vdfURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: vdfURL.path) else { return [] }
        let text = try String(contentsOf: vdfURL, encoding: .utf8)
        var folders: [URL] = []
        let pattern = #"\"path\"\s+\"([^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return folders }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, let valueRange = Range(match.range(at: 1), in: text) else { return }
            let raw = String(text[valueRange]).replacingOccurrences(of: "\\\\", with: "/")
            folders.append(URL(fileURLWithPath: raw))
        }
        return folders
    }
}
