import Foundation
import LauncherCore

@main
struct MacGamerCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            try await run(args: args)
        } catch {
            fputs("error: \(Diagnostics.explain(error))\n", stderr)
            exit(1)
        }
    }

    static func run(args: [String]) async throws {
        guard let command = args.first else {
            print(usage())
            return
        }
        let rest = Array(args.dropFirst())
        let paths = AppPaths()
        switch command {
        case "doctor":
            print(Doctor(paths: paths).formattedReport())
        case "runtime":
            try await runtimeCommand(rest, paths: paths)
        case "bottle":
            try bottleCommand(rest, paths: paths)
        case "steam":
            try steamCommand(rest, paths: paths)
        case "run":
            try runCommand(rest, paths: paths)
        case "backend":
            try backendCommand(rest, paths: paths)
        case "deps":
            try depsCommand(rest, paths: paths)
        case "gptk":
            try gptkCommand(rest, paths: paths)
        case "log":
            try logCommand(rest)
        case "help", "-h", "--help":
            print(usage())
        default:
            throw MacGamerError.io("неизвестная команда: \(command)")
        }
    }

    static func usage() -> String {
        """
        macgamer doctor
        macgamer runtime install [--archive <winecx.tar.xz>]
        macgamer bottle create --name <name> [--role steam|generic]
        macgamer bottle list
        macgamer steam use <path-to-steam.exe|SteamSetup.exe>
        macgamer steam open [--dry-run]
        macgamer steam sync
        macgamer run --exe <path> --bottle <id> [--backend dxmt|dxvk|d3dmetal|wined3d] [--dry-run]
        macgamer run --app <steamAppId> [--dry-run]
        macgamer backend set --bottle <id> --backend <name>
        macgamer deps vcrun2022 --bottle <id> [--installer <path>] [--dry-run]
        macgamer gptk import <dmg-or-lib-root>
        macgamer log summarize <path>
        """
    }

    static func runtimeCommand(_ args: [String], paths: AppPaths) async throws {
        guard args.first == "install" else {
            throw MacGamerError.io("использование: macgamer runtime install [--archive <winecx.tar.xz>]")
        }
        let archive = value(for: "--archive", in: args).map { URL(fileURLWithPath: $0) }
        let store = RuntimeStore(paths: paths)
        try await store.install(wineArchive: archive) { print($0) }
    }

    static func bottleCommand(_ args: [String], paths: AppPaths) throws {
        let store = BottleStore(paths: paths)
        guard let sub = args.first else {
            throw MacGamerError.io("использование: macgamer bottle create|list")
        }
        switch sub {
        case "list":
            for bottle in try store.list() {
                print("\(bottle.id)\t\(bottle.name)\t\(bottle.role.rawValue)\t\(bottle.backend.rawValue)")
            }
        case "create":
            let name = value(for: "--name", in: args) ?? "Default"
            let roleRaw = value(for: "--role", in: args) ?? "generic"
            guard let role = BottleRole(rawValue: roleRaw) else {
                throw MacGamerError.io("неизвестная роль: \(roleRaw)")
            }
            let bottle = try store.create(name: name, role: role)
            print(bottle.id)
        default:
            throw MacGamerError.io("неизвестная подкоманда bottle: \(sub)")
        }
    }

    static func steamCommand(_ args: [String], paths: AppPaths) throws {
        let steam = SteamLibrary(paths: paths)
        let planner = LaunchPlanner(paths: paths)
        guard let sub = args.first else {
            throw MacGamerError.io("использование: macgamer steam use|open|sync")
        }
        switch sub {
        case "use":
            guard let path = args.dropFirst().first else {
                throw MacGamerError.io("использование: macgamer steam use <path>")
            }
            let bottle = try steam.use(path: path)
            print(bottle.id)
            print(bottle.steamExePath ?? "")
        case "open":
            let command = try planner.planSteamOpen()
            if args.contains("--dry-run") {
                print(planner.describe(command))
                return
            }
            let result = try ProcessLauncher().run(command, wait: false)
            print(result.logPath)
        case "sync":
            let games = try steam.sync()
            for game in games {
                let app = game.steamAppId.map(String.init) ?? "-"
                print("\(app)\t\(game.installState.rawValue)\t\(game.name)")
            }
        default:
            throw MacGamerError.io("неизвестная подкоманда steam: \(sub)")
        }
    }

    static func runCommand(_ args: [String], paths: AppPaths) throws {
        let planner = LaunchPlanner(paths: paths)
        let command: LaunchCommand
        if let app = value(for: "--app", in: args), let appId = Int(app) {
            command = try planner.planSteamLaunch(appId: appId, hud: args.contains("--hud"))
        } else if let exe = value(for: "--exe", in: args) {
            guard let bottleId = value(for: "--bottle", in: args) else {
                throw MacGamerError.io("для --exe нужен --bottle")
            }
            let backend = value(for: "--backend", in: args).flatMap(GraphicsBackend.init(rawValue:))
            command = try planner.planManual(
                bottleId: bottleId,
                exe: exe,
                backend: backend,
                hud: args.contains("--hud")
            )
        } else {
            throw MacGamerError.io("использование: macgamer run --exe|--app ...")
        }
        if args.contains("--dry-run") {
            print(planner.describe(command))
            return
        }
        let wait = value(for: "--exe", in: args) != nil
        let result = try ProcessLauncher().run(command, wait: wait)
        print("exit=\(result.exitCode)")
        print(result.logPath)
    }

    static func backendCommand(_ args: [String], paths: AppPaths) throws {
        guard args.first == "set",
              let bottleId = value(for: "--bottle", in: args),
              let backendRaw = value(for: "--backend", in: args),
              let backend = GraphicsBackend(rawValue: backendRaw) else {
            throw MacGamerError.io("использование: macgamer backend set --bottle <id> --backend <name>")
        }
        try BottleStore(paths: paths).setBackend(id: bottleId, backend: backend)
        let planner = LaunchPlanner(paths: paths)
        if let steam = try BottleStore(paths: paths).load(id: bottleId).steamExePath {
            let command = try planner.planSteamOpen(bottleId: bottleId)
            print(planner.describe(command))
            _ = steam
        } else {
            print("backend=\(backend.rawValue)")
        }
    }

    static func depsCommand(_ args: [String], paths: AppPaths) throws {
        guard args.first == "vcrun2022",
              let bottleId = value(for: "--bottle", in: args) else {
            throw MacGamerError.io("использование: macgamer deps vcrun2022 --bottle <id> [--installer <path>]")
        }
        let installer = value(for: "--installer", in: args)
        if args.contains("--dry-run") {
            guard let installer else {
                throw MacGamerError.io("--dry-run требует --installer")
            }
            let command = try DependencyInstaller(paths: paths).plannedCommand(
                bottleId: bottleId,
                installerPath: installer
            )
            print(LaunchPlanner(paths: paths).describe(command))
            return
        }
        try DependencyInstaller(paths: paths).installVCRUN2022(bottleId: bottleId, installerPath: installer)
        print("ok")
    }

    static func gptkCommand(_ args: [String], paths: AppPaths) throws {
        guard args.first == "import", let path = args.dropFirst().first else {
            throw MacGamerError.io("использование: macgamer gptk import <dmg-or-lib-root>")
        }
        let url = URL(fileURLWithPath: path)
        let importer = GPTKImporter(paths: paths)
        if path.lowercased().hasSuffix(".dmg") {
            try importer.importFromDMG(at: url)
        } else {
            try importer.importFromLibRoot(url)
        }
        print("imported")
        let info = try? RuntimeStore(paths: paths).installedInfo()
        if info?.gptkCapable != true {
            print("warning: runtime gptkCapable=false, бэкенд d3dmetal останется недоступен")
        }
    }

    static func logCommand(_ args: [String]) throws {
        guard args.first == "summarize", let path = args.dropFirst().first else {
            throw MacGamerError.io("использование: macgamer log summarize <path>")
        }
        print(try Diagnostics.summarizeLog(at: path))
    }

    static func value(for flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag) else { return nil }
        let next = args.index(after: index)
        guard next < args.endIndex else { return nil }
        return args[next]
    }
}
