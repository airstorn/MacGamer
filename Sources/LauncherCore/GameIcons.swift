import Foundation

public enum GameIcons {
    public static func clientRoots(bottle: BottleConfig, paths: AppPaths) -> [URL] {
        var roots: [URL] = []
        if let steamPath = bottle.steamExePath, !steamPath.isEmpty {
            roots.append(URL(fileURLWithPath: steamPath).deletingLastPathComponent())
        }
        let prefix = paths.bottlePrefix(id: bottle.id)
        roots.append(
            prefix
                .appendingPathComponent("drive_c", isDirectory: true)
                .appendingPathComponent("Program Files (x86)", isDirectory: true)
                .appendingPathComponent("Steam", isDirectory: true)
        )
        var unique: [URL] = []
        var seen = Set<String>()
        for root in roots {
            let path = root.standardizedFileURL.path
            if seen.insert(path).inserted {
                unique.append(root.standardizedFileURL)
            }
        }
        return unique
    }

    public static func existingLocal(appId: Int, steamRoots: [URL]) -> URL? {
        localCandidates(appId: appId, steamRoots: steamRoots).first
    }

    public static func localCandidates(appId: Int, steamRoots: [URL]) -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        var seen = Set<String>()
        for root in steamRoots {
            for url in collect(in: root, appId: appId, fm: fm) {
                let path = url.standardizedFileURL.path
                if seen.insert(path).inserted {
                    urls.append(url)
                }
            }
        }
        return urls.compactMap { url -> (Int, URL)? in
            guard let score = score(url) else { return nil }
            return (score, url)
        }
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 {
                return lhs.0 < rhs.0
            }
            return lhs.1.lastPathComponent < rhs.1.lastPathComponent
        }
        .map(\.1)
    }

    public static func remoteURLs(appId: Int) -> [URL] {
        let id = String(appId)
        return [
            "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/library_600x900.jpg",
            "https://cdn.akamai.steamstatic.com/steam/apps/\(id)/library_600x900.jpg"
        ].compactMap(URL.init(string:))
    }

    public static func fileExtension(for data: Data) -> String? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "gif"
        }
        if data.starts(with: [0x00, 0x00, 0x01, 0x00]) {
            return "ico"
        }
        if data.count >= 12,
           data.prefix(4).elementsEqual([0x52, 0x49, 0x46, 0x46]),
           data.subdata(in: 8..<12).elementsEqual([0x57, 0x45, 0x42, 0x50]) {
            return "webp"
        }
        return nil
    }

    public static func isImageData(_ data: Data) -> Bool {
        data.count >= 32 && fileExtension(for: data) != nil
    }

    public static func load(appId: Int, steamRoots: [URL], paths: AppPaths) async -> Data? {
        for local in localCandidates(appId: appId, steamRoots: steamRoots) {
            if let data = try? Data(contentsOf: local), isImageData(data) {
                return data
            }
        }
        let cache = GameIconCache(paths: paths)
        if let cached = cache.existing(appId: appId),
           let data = try? Data(contentsOf: cached),
           isImageData(data) {
            return data
        }
        guard let data = await fetchRemote(appId: appId) else {
            return nil
        }
        _ = try? cache.save(data, appId: appId)
        return data
    }

    public static func fetchRemote(appId: Int) async -> Data? {
        for url in remoteURLs(appId: appId) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("MacGamer", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    continue
                }
                guard isImageData(data) else {
                    continue
                }
                return data
            } catch {
                continue
            }
        }
        return nil
    }

    private static func collect(in root: URL, appId: Int, fm: FileManager) -> [URL] {
        let id = String(appId)
        let libraryCache = root
            .appendingPathComponent("appcache", isDirectory: true)
            .appendingPathComponent("librarycache", isDirectory: true)
        var urls: [URL] = []
        appendImages(in: libraryCache.appendingPathComponent(id, isDirectory: true), depth: 0, into: &urls, fm: fm)
        for name in ["\(id)_icon.jpg", "\(id)_icon.png", "\(id)_icon.ico", "\(id)_library_600x900.jpg", "\(id)p.jpg", "\(id)p.png"] {
            let url = libraryCache.appendingPathComponent(name)
            if isFile(url, fm: fm) {
                urls.append(url)
            }
        }
        let userdata = root.appendingPathComponent("userdata", isDirectory: true)
        guard let accounts = try? fm.contentsOfDirectory(
            at: userdata,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return urls
        }
        for account in accounts {
            let grid = account
                .appendingPathComponent("config", isDirectory: true)
                .appendingPathComponent("grid", isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(
                at: grid,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for file in files where gridNameMatches(file.lastPathComponent, appId: appId) && isFile(file, fm: fm) {
                urls.append(file)
            }
        }
        return urls
    }

    private static func appendImages(in folder: URL, depth: Int, into urls: inout [URL], fm: FileManager) {
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for entry in entries {
            if isFile(entry, fm: fm) {
                urls.append(entry)
            } else if depth < 1 {
                appendImages(in: entry, depth: depth + 1, into: &urls, fm: fm)
            }
        }
    }

    private static func score(_ url: URL) -> Int? {
        let name = url.lastPathComponent.lowercased()
        if name.contains("hero") || name.contains("blur") || name.contains("header")
            || name.contains("logo") || name.contains("screenshot") {
            return nil
        }
        let ext = url.pathExtension.lowercased()
        guard ["jpg", "jpeg", "png", "ico", "webp", "gif"].contains(ext) else {
            return nil
        }
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        let namedIcon = name.contains("icon") || ext == "ico"
        let namedCover = name.contains("capsule") || name.contains("600x900")
            || stem.hasSuffix("p")
        let hashed = isIconHash(stem)
        guard namedIcon || namedCover || hashed else {
            return nil
        }
        if let size = pixelSize(at: url) {
            let aspect = Double(size.width) / Double(max(size.height, 1))
            let side = max(size.width, size.height)
            if aspect >= 0.85 && aspect <= 1.18 && side >= 16 {
                var value = namedIcon ? -1000 : 0
                if side <= 512 {
                    value += 512 - side
                } else if side <= 1024 {
                    value += 2000 + side
                } else {
                    value += 8000 + min(side, 20000)
                }
                return value
            }
            let portrait = Double(size.height) / Double(max(size.width, 1))
            if namedCover && portrait >= 1.3 && portrait <= 1.8 {
                return 20_000
            }
            return nil
        }
        if namedIcon || hashed {
            return namedIcon ? -100 : 1_000
        }
        if namedCover {
            return 20_000
        }
        return nil
    }

    private static func isIconHash(_ stem: String) -> Bool {
        stem.count == 40 && stem.allSatisfy(\.isHexDigit)
    }

    private static func pixelSize(at url: URL) -> (width: Int, height: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256 * 1024) else {
            return nil
        }
        return pixelSize(of: data)
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]), data.count >= 24 {
            let width = int32(data, 16)
            let height = int32(data, 20)
            if width > 0, height > 0 {
                return (width, height)
            }
        }
        if data.count >= 8, data[0] == 0, data[1] == 0, data[2] == 1, data[3] == 0 {
            let width = data[6] == 0 ? 256 : Int(data[6])
            let height = data[7] == 0 ? 256 : Int(data[7])
            return (width, height)
        }
        guard data.starts(with: [0xFF, 0xD8]) else {
            return nil
        }
        var index = 2
        while index + 8 < data.count {
            if data[index] != 0xFF {
                index += 1
                continue
            }
            while index < data.count, data[index] == 0xFF {
                index += 1
            }
            if index >= data.count {
                break
            }
            let marker = data[index]
            index += 1
            if marker == 0xD8 || marker == 0xD9 || (0xD0...0xD7).contains(marker) {
                continue
            }
            if index + 1 >= data.count {
                break
            }
            let length = (Int(data[index]) << 8) | Int(data[index + 1])
            let startOfFrame = (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if startOfFrame, index + 6 < data.count {
                let height = (Int(data[index + 3]) << 8) | Int(data[index + 4])
                let width = (Int(data[index + 5]) << 8) | Int(data[index + 6])
                if width > 0, height > 0 {
                    return (width, height)
                }
            }
            if length < 2 {
                break
            }
            index += length
        }
        return nil
    }

    private static func int32(_ data: Data, _ offset: Int) -> Int {
        (Int(data[offset]) << 24) | (Int(data[offset + 1]) << 16) | (Int(data[offset + 2]) << 8) | Int(data[offset + 3])
    }

    private static func gridNameMatches(_ name: String, appId: Int) -> Bool {
        let id = String(appId)
        guard name.hasPrefix(id) else {
            return false
        }
        var rest = name.dropFirst(id.count)
        if rest.first == "p" {
            rest = rest.dropFirst()
        }
        guard let next = rest.first else {
            return false
        }
        return next == "." || next == "_"
    }

    private static func isFile(_ url: URL, fm: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}

public final class GameIconCache: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "MacGamer.GameIconCache")
    private let extensions = ["jpg", "jpeg", "png", "webp", "gif", "ico"]

    public init(paths: AppPaths) {
        directory = paths.icons
    }

    public func existing(appId: Int) -> URL? {
        queue.sync {
            let fm = FileManager.default
            for ext in extensions {
                let url = directory.appendingPathComponent("\(appId).\(ext)")
                if fm.fileExists(atPath: url.path) {
                    return url
                }
            }
            return nil
        }
    }

    public func save(_ data: Data, appId: Int) throws -> URL {
        guard let ext = GameIcons.fileExtension(for: data) else {
            throw MacGamerError.io("Некорректные данные иконки")
        }
        return try queue.sync {
            let fm = FileManager.default
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            for old in extensions where old != ext {
                let url = directory.appendingPathComponent("\(appId).\(old)")
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                }
            }
            let url = directory.appendingPathComponent("\(appId).\(ext)")
            try data.write(to: url, options: .atomic)
            return url
        }
    }
}
