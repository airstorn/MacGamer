import Foundation

public enum SteamWebHelperFix {
    private static let shimResourceName = "steamwebhelper_shim"
    private static let maxShimBytes = 500_000

    public static func apply(steamDirectory: URL) throws {
        guard let shim = shimURL() else {
            throw MacGamerError.io("не найден steamwebhelper_shim.exe в ресурсах MacGamer")
        }
        let cefRoots = [
            steamDirectory.appendingPathComponent("bin/cef/cef.win64", isDirectory: true),
            steamDirectory.appendingPathComponent("bin/cef/cef.win7x64", isDirectory: true)
        ]
        let fm = FileManager.default
        for root in cefRoots {
            let helper = root.appendingPathComponent("steamwebhelper.exe")
            let real = root.appendingPathComponent("steamwebhelper.real.exe")
            guard fm.fileExists(atPath: helper.path) || fm.fileExists(atPath: real.path) else {
                continue
            }
            if fm.fileExists(atPath: helper.path), !fm.fileExists(atPath: real.path) {
                let size = (try? helper.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > maxShimBytes {
                    try fm.moveItem(at: helper, to: real)
                }
            }
            if fm.fileExists(atPath: helper.path) {
                let size = (try? helper.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > maxShimBytes {
                    try fm.removeItem(at: helper)
                }
            }
            if fm.fileExists(atPath: helper.path) {
                try fm.removeItem(at: helper)
            }
            try fm.copyItem(at: shim, to: helper)
        }

        let cfg = steamDirectory.appendingPathComponent("Steam.cfg")
        let body = "BootStrapperInhibitAll=Enable\nBootStrapperForceSelfUpdate=Disable\n"
        try body.write(to: cfg, atomically: true, encoding: .utf8)
    }

    private static func shimURL() -> URL? {
        if let bundled = Bundle.module.url(forResource: shimResourceName, withExtension: "exe") {
            return bundled
        }
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("tools/steamwebhelper-shim/steamwebhelper_shim.exe"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("tools/steamwebhelper-shim/steamwebhelper_shim.exe"),
            Bundle.module.bundleURL
                .appendingPathComponent("Contents/Resources/steamwebhelper_shim.exe")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}
