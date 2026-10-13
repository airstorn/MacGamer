import CryptoKit
import Foundation

public final class RuntimeStore: @unchecked Sendable {
    private let paths: AppPaths
    private let session: URLSession

    public init(paths: AppPaths = AppPaths(), session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    public func loadManifest() throws -> RuntimeManifest {
        if let url = Bundle.module.url(forResource: "runtime", withExtension: "json") {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(RuntimeManifest.self, from: data)
        }
        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("manifest/runtime.json")
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            throw MacGamerError.manifestMissing
        }
        let data = try Data(contentsOf: fallback)
        return try JSONDecoder().decode(RuntimeManifest.self, from: data)
    }

    public func installedInfo() throws -> InstalledRuntimeInfo {
        let manifest = try loadManifest()
        let infoURL = paths.runtimeDirectory(id: manifest.id).appendingPathComponent("runtime-info.json")
        guard FileManager.default.fileExists(atPath: infoURL.path) else {
            throw MacGamerError.runtimeNotInstalled
        }
        let data = try Data(contentsOf: infoURL)
        return try JSONCoding.decoder.decode(InstalledRuntimeInfo.self, from: data)
    }

    public func wine64URL() throws -> URL {
        let info = try installedInfo()
        let root = paths.runtimeDirectory(id: info.id)
        let candidates = [
            root.appendingPathComponent("bin/wine64"),
            root.appendingPathComponent("bin/wine"),
            root.appendingPathComponent("bin/wineloader"),
            root.appendingPathComponent("usr/local/bin/wine64"),
            root.appendingPathComponent("usr/local/bin/wine"),
            root.appendingPathComponent("usr/local/bin/wineloader"),
            root.appendingPathComponent("Wine Staging.app/Contents/Resources/wine/bin/wine64"),
            root.appendingPathComponent("Wine Staging.app/Contents/Resources/wine/bin/wine"),
            root.appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin/wine64"),
            root.appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin/wine"),
            root.appendingPathComponent("Wine Stable.app/Contents/Resources/wine/bin/wine64"),
            root.appendingPathComponent("Wine Stable.app/Contents/Resources/wine/bin/wine"),
            root.appendingPathComponent("wine/bin/wine64"),
            root.appendingPathComponent("wine/bin/wine")
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        if let found = Self.findExecutable(named: "wine64", under: root) {
            return found
        }
        if let found = Self.findExecutable(named: "wine", under: root) {
            return found
        }
        throw MacGamerError.wineBinaryMissing
    }

    public func wineServerURL() throws -> URL? {
        let wine64 = try wine64URL()
        let sibling = wine64.deletingLastPathComponent().appendingPathComponent("wineserver")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }
        return nil
    }

    public func wineDllPath() throws -> String? {
        let info = try installedInfo()
        let root = paths.runtimeDirectory(id: info.id)
        let candidates = [
            root.appendingPathComponent("lib/wine", isDirectory: true),
            root.appendingPathComponent("usr/local/lib/wine", isDirectory: true),
            root.appendingPathComponent("Wine Staging.app/Contents/Resources/wine/lib/wine", isDirectory: true)
        ]
        guard let wineLib = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            return nil
        }
        let parts = [
            wineLib.appendingPathComponent("x86_64-windows").path,
            wineLib.appendingPathComponent("i386-windows").path,
            wineLib.path
        ].filter { FileManager.default.fileExists(atPath: $0) }
        return parts.isEmpty ? nil : parts.joined(separator: ":")
    }

    public func overlayURL(for backend: GraphicsBackend) throws -> URL? {
        let info = try installedInfo()
        let root = paths.runtimeDirectory(id: info.id)
        switch backend {
        case .dxmt:
            return Self.resolveDLLPathRoot(root.appendingPathComponent("overlays/dxmt", isDirectory: true))
        case .dxvk:
            return Self.resolveDLLPathRoot(root.appendingPathComponent("overlays/dxvk", isDirectory: true))
        case .d3dmetal:
            return paths.gptkStore
        case .wined3d:
            return nil
        }
    }

    static func resolveDLLPathRoot(_ overlayRoot: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: overlayRoot.path) else { return nil }
        let direct = overlayRoot.appendingPathComponent("x86_64-windows", isDirectory: true)
        if fm.fileExists(atPath: direct.path) {
            return overlayRoot
        }
        let children = (try? fm.contentsOfDirectory(
            at: overlayRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in children {
            let candidate = child.appendingPathComponent("x86_64-windows", isDirectory: true)
            if fm.fileExists(atPath: candidate.path) {
                return child
            }
        }
        return overlayRoot
    }

    public func install(wineArchive: URL? = nil, progress: ((String) -> Void)? = nil) async throws {
        try paths.ensureLayout()
        let report = Doctor(paths: paths).report()
        if report.chip == "arm64" && !report.rosettaInstalled {
            throw MacGamerError.rosettaMissing
        }

        let manifest = try loadManifest()
        let dest = paths.runtimeDirectory(id: manifest.id)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.appendingPathComponent("runtime-info.json").path) {
            progress?("runtime already installed: \(manifest.id)")
            return
        }

        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let staging = paths.downloads.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try await installWine(
            component: manifest.components.wine,
            archiveOverride: wineArchive,
            staging: staging,
            into: dest,
            progress: progress
        )
        try await downloadAndExtract(
            component: manifest.components.dxmt,
            name: "dxmt",
            staging: staging,
            into: dest.appendingPathComponent("overlays/dxmt", isDirectory: true),
            progress: progress
        )
        try await downloadAndExtract(
            component: manifest.components.dxvk,
            name: "dxvk",
            staging: staging,
            into: dest.appendingPathComponent("overlays/dxvk", isDirectory: true),
            progress: progress
        )

        try Self.mergeDxmtBuiltinIntoWine(runtimeRoot: dest, progress: progress)
        try Self.verifyMacdrvFunctions(runtimeRoot: dest)

        let info = InstalledRuntimeInfo(
            id: manifest.id,
            gptkCapable: manifest.gptkCapable,
            wineVersion: manifest.components.wine.version,
            dxmtVersion: manifest.components.dxmt.version,
            dxvkVersion: manifest.components.dxvk.version,
            installedAt: Date()
        )
        let data = try JSONCoding.encoder.encode(info)
        try data.write(to: dest.appendingPathComponent("runtime-info.json"))
        progress?("runtime installed: \(manifest.id)")
    }

    private func installWine(
        component: RuntimeComponent,
        archiveOverride: URL?,
        staging: URL,
        into destination: URL,
        progress: ((String) -> Void)?
    ) async throws {
        let fm = FileManager.default
        let archiveURL: URL
        if let archiveOverride {
            guard fm.fileExists(atPath: archiveOverride.path) else {
                throw MacGamerError.runtimeDownloadFailed("archive not found: \(archiveOverride.path)")
            }
            archiveURL = archiveOverride
            progress?("wine from archive \(archiveOverride.lastPathComponent)")
        } else if component.url.hasPrefix("local://") || component.sha256 == "local" {
            let local = paths.downloads.appendingPathComponent(component.archive)
            guard fm.fileExists(atPath: local.path) else {
                throw MacGamerError.runtimeDownloadFailed(
                    "wine archive missing. Run tools/build-winecx.sh then: macgamer runtime install --archive \"\(local.path)\""
                )
            }
            archiveURL = local
            progress?("wine from \(local.path)")
        } else {
            progress?("download wine \(component.version)")
            guard let remote = URL(string: component.url) else {
                throw MacGamerError.runtimeDownloadFailed("bad url for wine")
            }
            let downloaded = staging.appendingPathComponent(component.archive)
            let (temp, response) = try await session.download(from: remote)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw MacGamerError.runtimeDownloadFailed("HTTP \(http.statusCode) for wine")
            }
            if fm.fileExists(atPath: downloaded.path) {
                try fm.removeItem(at: downloaded)
            }
            try fm.moveItem(at: temp, to: downloaded)
            archiveURL = downloaded
        }

        if component.sha256 != "local" {
            let digest = try Self.sha256(of: archiveURL)
            guard digest == component.sha256.lowercased() else {
                throw MacGamerError.runtimeHashMismatch(component: "wine")
            }
        }

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try Self.extract(archive: archiveURL, to: destination)
        progress?("extracted wine")
    }

    private func downloadAndExtract(
        component: RuntimeComponent,
        name: String,
        staging: URL,
        into destination: URL,
        progress: ((String) -> Void)?
    ) async throws {
        progress?("download \(name) \(component.version)")
        guard let remote = URL(string: component.url) else {
            throw MacGamerError.runtimeDownloadFailed("bad url for \(name)")
        }
        let archiveURL = staging.appendingPathComponent(component.archive)
        let (temp, response) = try await session.download(from: remote)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MacGamerError.runtimeDownloadFailed("HTTP \(http.statusCode) for \(name)")
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: archiveURL.path) {
            try fm.removeItem(at: archiveURL)
        }
        try fm.moveItem(at: temp, to: archiveURL)
        let digest = try Self.sha256(of: archiveURL)
        guard digest == component.sha256.lowercased() else {
            throw MacGamerError.runtimeHashMismatch(component: name)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try Self.extract(archive: archiveURL, to: destination)
        progress?("extracted \(name)")
    }

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func extract(archive: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archive.path, "-C", destination.path]
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw MacGamerError.processFailed("tar failed: \(message)")
        }
    }

    public func deployDxmtNativeDLLs(overlayRoot: URL, bottleId: String) throws {
        let fm = FileManager.default
        let system32 = paths.bottlePrefix(id: bottleId)
            .appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        try fm.createDirectory(at: system32, withIntermediateDirectories: true)
        let windows = overlayRoot.appendingPathComponent("x86_64-windows", isDirectory: true)
        guard fm.fileExists(atPath: windows.path) else { return }
        for name in ["d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll"] {
            let src = windows.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = system32.appendingPathComponent(name)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
        }
        if let wineUnix = [
            paths.runtimeDirectory(id: try installedInfo().id).appendingPathComponent("lib/wine/x86_64-unix", isDirectory: true),
            paths.runtimeDirectory(id: try installedInfo().id).appendingPathComponent("usr/local/lib/wine/x86_64-unix", isDirectory: true)
        ].first(where: { fm.fileExists(atPath: $0.path) }) {
            let so = overlayRoot.appendingPathComponent("x86_64-unix/winemetal.so")
            if fm.fileExists(atPath: so.path) {
                let dst = wineUnix.appendingPathComponent("winemetal.so")
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.copyItem(at: so, to: dst)
            }
        }
    }

    public static func mergeDxmtBuiltinIntoWine(runtimeRoot: URL, progress: ((String) -> Void)? = nil) throws {
        let fm = FileManager.default
        guard let dxmtRoot = resolveDLLPathRoot(runtimeRoot.appendingPathComponent("overlays/dxmt", isDirectory: true)) else {
            return
        }
        let wineLib = [
            runtimeRoot.appendingPathComponent("lib/wine", isDirectory: true),
            runtimeRoot.appendingPathComponent("usr/local/lib/wine", isDirectory: true)
        ].first(where: { fm.fileExists(atPath: $0.path) })
        guard let wineLib else { return }

        let pairs: [(String, String)] = [
            ("x86_64-windows", "x86_64-windows"),
            ("i386-windows", "i386-windows"),
            ("x86_64-unix", "x86_64-unix")
        ]
        for (srcName, dstName) in pairs {
            let src = dxmtRoot.appendingPathComponent(srcName, isDirectory: true)
            let dst = wineLib.appendingPathComponent(dstName, isDirectory: true)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            let files = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
            for file in files {
                let target = dst.appendingPathComponent(file.lastPathComponent)
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
                try fm.copyItem(at: file, to: target)
            }
        }
        progress?("merged dxmt into wine lib")
    }

    public static func verifyMacdrvFunctions(runtimeRoot: URL) throws {
        guard let winemac = findExecutable(named: "winemac.so", under: runtimeRoot) else {
            throw MacGamerError.wineMacdrvMissing
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
        process.arguments = ["-gU", winemac.path]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard text.contains("macdrv_functions") else {
            throw MacGamerError.wineMacdrvMissing
        }
    }

    private static func findExecutable(named name: String, under root: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        for case let url as URL in enumerator {
            guard url.lastPathComponent == name else { continue }
            if name.hasSuffix(".so") {
                if fm.fileExists(atPath: url.path) { return url }
            } else if fm.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
