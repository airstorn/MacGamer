import Foundation

public struct BackendEnvironment: Equatable, Sendable {
    public var overrides: String
    public var dllPathPrepend: String?
    public var extra: [String: String]
}

public enum BackendOverlay {
    public static func environment(
        backend: GraphicsBackend,
        overlayURL: URL?,
        hud: Bool,
        gptkCapable: Bool,
        gptkImported: Bool
    ) throws -> BackendEnvironment {
        switch backend {
        case .dxmt:
            guard let overlayURL else { throw MacGamerError.unsupportedBackend(.dxmt) }
            var extra: [String: String] = [
                "DXMT_CONFIG": "d3d11.relaxedCompiler=True",
                "ROSETTA_ADVERTISE_AVX": "1"
            ]
            if hud { extra["DXMT_DEBUG"] = "1" }
            return BackendEnvironment(
                overrides: "d3d11=n,b;d3d10core=n,b;dxgi=n,b;winemetal=n,b",
                dllPathPrepend: overlayURL.path,
                extra: extra
            )
        case .dxvk:
            guard let overlayURL else { throw MacGamerError.unsupportedBackend(.dxvk) }
            var extra: [String: String] = [:]
            if hud { extra["DXVK_HUD"] = "1" }
            return BackendEnvironment(
                overrides: "d3d11=b,d3d10=b,d3d10core=b,d3d10_1=b,d3d9=b,dxgi=b",
                dllPathPrepend: overlayURL.path,
                extra: extra
            )
        case .d3dmetal:
            guard gptkCapable else { throw MacGamerError.gptkNotCapable }
            guard gptkImported else { throw MacGamerError.gptkNotImported }
            guard let overlayURL else { throw MacGamerError.gptkNotImported }
            let wineRoot = overlayURL.appendingPathComponent("wine", isDirectory: true)
            let prepend = FileManager.default.fileExists(atPath: wineRoot.path) ? wineRoot.path : overlayURL.path
            var extra: [String: String] = ["ROSETTA_ADVERTISE_AVX": "1"]
            let libd3d = overlayURL.appendingPathComponent("external/libd3dshared.dylib")
            if FileManager.default.fileExists(atPath: libd3d.path) {
                extra["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = libd3d.path
            }
            return BackendEnvironment(
                overrides: "d3d11=b;d3d12=b;dxgi=b",
                dllPathPrepend: prepend,
                extra: extra
            )
        case .wined3d:
            return BackendEnvironment(
                overrides: "d3d11=b,d3d10=b,d3d9=b,dxgi=b",
                dllPathPrepend: nil,
                extra: [:]
            )
        }
    }
}
