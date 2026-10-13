import Foundation
import LauncherCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var doctorText: String = ""
    @Published var games: [GameEntry] = []
    @Published var bottles: [BottleConfig] = []
    @Published var status: String = ""
    @Published var selectedLogSummary: String = ""
    @Published var steamPathInput: String = ""
    @Published var errorText: String = ""

    let paths = AppPaths()
    private let libraryStore: LibraryStore
    private let bottleStore: BottleStore
    private let steamLibrary: SteamLibrary
    private let planner: LaunchPlanner

    init() {
        libraryStore = LibraryStore(paths: paths)
        bottleStore = BottleStore(paths: paths)
        steamLibrary = SteamLibrary(paths: paths)
        planner = LaunchPlanner(paths: paths)
        refresh()
        startWatching()
    }

    func refresh() {
        doctorText = Doctor(paths: paths).formattedReport()
        bottles = (try? bottleStore.list()) ?? []
        games = (try? libraryStore.load().games) ?? []
        if let steam = bottles.first(where: { $0.role == .steam }), let path = steam.steamExePath {
            steamPathInput = path
        }
    }

    func useSteamPath() {
        do {
            let bottle = try steamLibrary.use(path: steamPathInput)
            status = "Steam путь сохранён в бутылке \(bottle.id)"
            errorText = ""
            refresh()
            startWatching()
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    func openSteam() {
        do {
            let command = try planner.planSteamOpen()
            _ = try ProcessLauncher().run(command, wait: false)
            status = "Steam запущен, лог: \(command.logPath)"
            errorText = ""
            selectedLogSummary = (try? Diagnostics.summarizeLog(at: command.logPath)) ?? ""
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    func syncSteam() {
        do {
            games = try steamLibrary.sync()
            status = "Библиотека синхронизирована: \(games.count)"
            errorText = ""
            refresh()
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    func play(_ game: GameEntry) {
        guard let appId = game.steamAppId else {
            errorText = "У игры нет steamAppId"
            return
        }
        do {
            let command = try planner.planSteamLaunch(appId: appId, bottleId: game.bottleId, hud: game.hud)
            _ = try ProcessLauncher().run(command, wait: false)
            status = "Запуск \(game.name), лог: \(command.logPath)"
            errorText = ""
            selectedLogSummary = (try? Diagnostics.summarizeLog(at: command.logPath)) ?? ""
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    func setBackend(_ backend: GraphicsBackend) {
        guard let steam = bottles.first(where: { $0.role == .steam }) else {
            errorText = "Бутылка Steam не найдена"
            return
        }
        do {
            try bottleStore.setBackend(id: steam.id, backend: backend)
            status = "Бэкенд \(backend.rawValue) применится после перезапуска Steam"
            errorText = ""
            refresh()
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    func showLatestLog(for game: GameEntry) {
        let dir = paths.logDirectory(gameId: game.source == .steam
            ? "steam-\(game.steamAppId ?? 0)"
            : game.id)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let latest = files
            .filter { $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
            .first
        guard let latest else {
            selectedLogSummary = "Лог не найден"
            return
        }
        selectedLogSummary = (try? Diagnostics.summarizeLog(at: latest.path)) ?? "Не удалось прочитать лог"
    }

    private func startWatching() {
        steamLibrary.stopWatching()
        do {
            try steamLibrary.startWatching(onChange: { [weak self] in
                Task { @MainActor in
                    self?.refresh()
                }
            })
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }
}
