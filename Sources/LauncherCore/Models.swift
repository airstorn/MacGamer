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

public struct VirtualDesktop: Codable, Equatable, Sendable {
    public static let minimum = 640
    public static let maximum = 7680

    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var spec: String { "\(width)x\(height)" }

    public func validate() throws {
        let range = Self.minimum...Self.maximum
        guard range.contains(width), range.contains(height) else {
            throw MacGamerError.invalidDesktopSize(spec)
        }
    }

    public static func parse(_ spec: String) throws -> VirtualDesktop {
        let parts = spec.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]) else {
            throw MacGamerError.invalidDesktopSize(spec)
        }
        let desktop = VirtualDesktop(width: width, height: height)
        try desktop.validate()
        return desktop
    }
}

public enum DesktopOverride: Equatable, Sendable {
    case inherit
    case disabled
    case enabled(VirtualDesktop)

    public static func parse(_ spec: String) throws -> DesktopOverride {
        if spec.lowercased() == "off" {
            return .disabled
        }
        return .enabled(try VirtualDesktop.parse(spec))
    }
}

public struct GameEntry: Equatable, Identifiable, Sendable {
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
    public var virtualDesktop: VirtualDesktop?

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
        hud: Bool = false,
        virtualDesktop: VirtualDesktop? = nil
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
        self.virtualDesktop = virtualDesktop
    }
}

extension GameEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, bottleId, source, steamAppId, installState
        case exe, workdir, arguments, env, backend, hud, virtualDesktop
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bottleId = try container.decode(String.self, forKey: .bottleId)
        source = try container.decode(GameSource.self, forKey: .source)
        steamAppId = try container.decodeIfPresent(Int.self, forKey: .steamAppId)
        installState = try container.decode(InstallState.self, forKey: .installState)
        exe = try container.decodeIfPresent(String.self, forKey: .exe)
        workdir = try container.decodeIfPresent(String.self, forKey: .workdir)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        backend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .backend)
        hud = try container.decodeIfPresent(Bool.self, forKey: .hud) ?? false
        virtualDesktop = try container.decodeIfPresent(VirtualDesktop.self, forKey: .virtualDesktop)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(bottleId, forKey: .bottleId)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(steamAppId, forKey: .steamAppId)
        try container.encode(installState, forKey: .installState)
        try container.encodeIfPresent(exe, forKey: .exe)
        try container.encodeIfPresent(workdir, forKey: .workdir)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(env, forKey: .env)
        try container.encodeIfPresent(backend, forKey: .backend)
        try container.encode(hud, forKey: .hud)
        try container.encodeIfPresent(virtualDesktop, forKey: .virtualDesktop)
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
    public var virtualDesktop: VirtualDesktop?
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
