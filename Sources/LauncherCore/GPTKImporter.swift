import Foundation

public struct GPTKImporter: Sendable {
    private let paths: AppPaths

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    public func importFromDMG(at dmgURL: URL) throws {
        try paths.ensureLayout()
        guard FileManager.default.fileExists(atPath: dmgURL.path) else {
            throw MacGamerError.gptkPayloadInvalid("DMG не найден")
        }

        let mountPoint = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macgamer-gptk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint.path, "-quiet"]
            try? detach.run()
            detach.waitUntilExit()
            try? FileManager.default.removeItem(at: mountPoint)
        }

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = [
            "attach", dmgURL.path,
            "-mountpoint", mountPoint.path,
            "-nobrowse",
            "-readonly",
            "-quiet"
        ]
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else {
            throw MacGamerError.gptkPayloadInvalid("не удалось смонтировать DMG")
        }

        guard let libRoot = findLibRoot(in: mountPoint) else {
            throw MacGamerError.gptkPayloadInvalid("не найден redist/lib с D3DMetal")
        }
        try validatePayload(libRoot: libRoot)
        try replaceStore(with: libRoot)
    }

    public func importFromLibRoot(_ libRoot: URL) throws {
        try paths.ensureLayout()
        try validatePayload(libRoot: libRoot)
        try replaceStore(with: libRoot)
    }

    public func validatePayload(libRoot: URL) throws {
        let framework = libRoot.appendingPathComponent("external/D3DMetal.framework")
        guard FileManager.default.fileExists(atPath: framework.path) else {
            throw MacGamerError.gptkPayloadInvalid("нет external/D3DMetal.framework")
        }
        let shared = libRoot.appendingPathComponent("external/libd3dshared.dylib")
        guard FileManager.default.fileExists(atPath: shared.path) else {
            throw MacGamerError.gptkPayloadInvalid("нет external/libd3dshared.dylib")
        }
        let forwarders = ["d3d11.dll", "d3d12.dll", "dxgi.dll"]
        let peDir = libRoot.appendingPathComponent("wine/x86_64-windows", isDirectory: true)
        for name in forwarders {
            let dll = peDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: dll.path) else {
                throw MacGamerError.gptkPayloadInvalid("нет \(name)")
            }
            if try isNativePE(dll) {
                throw MacGamerError.gptkPayloadInvalid("\(name) помечен как native PE, ожидается builtin")
            }
        }
    }

    public func isImported() -> Bool {
        FileManager.default.fileExists(
            atPath: paths.gptkStore.appendingPathComponent("external/D3DMetal.framework").path
        )
    }

    private func replaceStore(with libRoot: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.gptkStore.path) {
            try fm.removeItem(at: paths.gptkStore)
        }
        try fm.createDirectory(at: paths.gptkStore.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: libRoot, to: paths.gptkStore)
    }

    private func findLibRoot(in root: URL) -> URL? {
        let fm = FileManager.default
        let direct = root.appendingPathComponent("redist/lib")
        if fm.fileExists(atPath: direct.appendingPathComponent("external/D3DMetal.framework").path) {
            return direct
        }
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "lib",
               fm.fileExists(atPath: url.appendingPathComponent("external/D3DMetal.framework").path) {
                return url
            }
        }
        return nil
    }

    private func isNativePE(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 4096), data.count >= 0x40 else {
            return false
        }
        if data[0] != 0x4D || data[1] != 0x5A {
            return false
        }
        let peOffset = Int(data[0x3C]) | (Int(data[0x3D]) << 8) | (Int(data[0x3E]) << 16) | (Int(data[0x3F]) << 24)
        guard peOffset + 0x18 < data.count else { return false }
        let marker = Data("Wine builtin DLL".utf8)
        if data.range(of: marker) != nil {
            return false
        }
        return true
    }
}
