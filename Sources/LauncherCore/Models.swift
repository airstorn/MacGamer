import Foundation

public enum GraphicsBackend: String, Codable, CaseIterable, Sendable {
    case dxmt
    case dxvk
    case d3dmetal
    case wined3d
}

public enum BottleRole: String, Codable, Sendable {
    case generic
    case steam
}

public enum GameSource: String, Codable, Sendable {
    case steam
    case manual
}

public enum InstallState: String, Codable, Sendable {
    case installing
    case ready
    case updating
    case missing
}

public struct BottleConfig: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var role: BottleRole
    public var windowsVersion: String
    public var backend: GraphicsBackend
    public var hud: Bool
    public var steamExePath: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        role: BottleRole = .generic,
        windowsVersion: String = "win10",
        backend: GraphicsBackend = .dxmt,
        hud: Bool = false,
        steamExePath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.windowsVersion = windowsVersion
        self.backend = backend
        self.hud = hud
        self.steamExePath = steamExePath
        self.createdAt = createdAt
    }
}

public struct GameEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var bottleId: String
    public var source: GameSource
    public var steamAppId: Int?
    public var installState: InstallState
    public var exe: String?
    public var workdir: String?
    public var arguments: [String]
    public var env: [String: String]
    public var backend: GraphicsBackend?
    public var hud: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        bottleId: String,
        source: GameSource,
        steamAppId: Int? = nil,
        installState: InstallState = .ready,
        exe: String? = nil,
        workdir: String? = nil,
        arguments: [String] = [],
        env: [String: String] = [:],
        backend: GraphicsBackend? = nil,
        hud: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bottleId = bottleId
        self.source = source
        self.steamAppId = steamAppId
        self.installState = installState
        self.exe = exe
        self.workdir = workdir
        self.arguments = arguments
        self.env = env
        self.backend = backend
        self.hud = hud
    }
}

public struct LibraryDocument: Codable, Equatable, Sendable {
    public var games: [GameEntry]

    public init(games: [GameEntry] = []) {
        self.games = games
    }
}

public struct RuntimeComponent: Codable, Equatable, Sendable {
    public var version: String
    public var url: String
    public var sha256: String
    public var archive: String
}

public struct RuntimeManifest: Codable, Equatable, Sendable {
    public var id: String
    public var gptkCapable: Bool
    public var components: RuntimeComponents
}

public struct RuntimeComponents: Codable, Equatable, Sendable {
    public var wine: RuntimeComponent
    public var dxmt: RuntimeComponent
    public var dxvk: RuntimeComponent
}

public struct InstalledRuntimeInfo: Codable, Equatable, Sendable {
    public var id: String
    public var gptkCapable: Bool
    public var wineVersion: String
    public var dxmtVersion: String
    public var dxvkVersion: String
    public var installedAt: Date
}

public struct LaunchCommand: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: String?
    public var backend: GraphicsBackend
    public var winePrefix: String
    public var logPath: String
}

public struct LaunchResult: Equatable, Sendable {
    public var exitCode: Int32
    public var logPath: String
}

public struct DoctorReport: Equatable, Sendable {
    public var chip: String
    public var macOSVersion: String
    public var rosettaInstalled: Bool
    public var runtimeInstalled: Bool
    public var runtimeId: String?
    public var gptkCapable: Bool
    public var gptkImported: Bool
    public var issues: [String]
}
