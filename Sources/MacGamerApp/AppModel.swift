import AppKit
import Foundation
import LauncherCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var doctorText: String = ""
    @Published var games: [GameEntry] = []
    @Published var bottles: [BottleConfig] = []
    @Published var status: String = ""
    @Published var selectedLogSummary: String = ""
    @Published var steamPathInput: String = ""
    @Published var errorText: String = ""
    @Published var selectedGameId: String?
    @Published var setupStatus = SetupStatus(step: .runtime, title: "", detail: "")
    @Published var serviceStatuses: [ServiceStatus] = []
    @Published var isBusy = false
    @Published var progressText = ""

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
        let doctor = Doctor(paths: paths)
        doctorText = doctor.formattedReport()
        bottles = (try? bottleStore.list()) ?? []
        games = (try? libraryStore.load().games) ?? []
        let report = doctor.report()
        setupStatus = SetupGuide.status(doctor: report, bottles: bottles)
        serviceStatuses = SetupGuide.services(doctor: report, bottles: bottles)
        if let steam = bottles.first(where: { $0.role == .steam }), let path = steam.steamExePath {
            steamPathInput = path
        }
    }

    func useSteamPath() {
        do {
            let bottle = try steamLibrary.use(path: steamPathInput)
            status = "Steam сохранён"
            errorText = ""
            _ = bottle
            refresh()
            startWatching()
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    func chooseSteamFile() {
        let panel = NSOpenPanel()
        panel.title = "Выберите SteamSetup.exe или steam.exe"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        if let exe = UTType(filenameExtension: "exe") {
            panel.allowedContentTypes = [exe]
        }
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        steamPathInput = url.path
        useSteamPath()
    }

    func installRosetta() {
        guard !isBusy else { return }
        isBusy = true
        progressText = "Установка Rosetta…"
        errorText = ""
        Task {
            do {
                try await Task.detached {
                    try RosettaInstaller.install()
                }.value
                isBusy = false
                progressText = ""
                refresh()
            } catch {
                isBusy = false
                progressText = ""
                errorText = Diagnostics.explain(error)
            }
        }
    }

    func installRuntime() {
        guard !isBusy else { return }
        isBusy = true
        progressText = "Установка среды запуска…"
        errorText = ""
        let paths = self.paths
        Task {
            do {
                try await Self.runInstall(paths: paths) { text in
                    await self.updateProgress(text)
                }
                isBusy = false
                progressText = ""
                status = "Среда запуска установлена"
                refresh()
            } catch {
                isBusy = false
                progressText = ""
                errorText = Diagnostics.explain(error)
            }
        }
    }

    func openSteam() {
        do {
            let command = try planner.planSteamOpen()
            _ = try ProcessLauncher().run(command, wait: false)
            status = "Steam запущен"
            errorText = ""
            selectedLogSummary = (try? Diagnostics.summarizeLog(at: command.logPath)) ?? ""
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    func syncSteam() {
        do {
            games = try steamLibrary.sync()
            status = "Библиотека обновлена: \(games.count)"
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
            let command = try planner.planSteamLaunch(appId: appId, bottleId: game.bottleId)
            _ = try ProcessLauncher().run(command, wait: false)
            status = "Запуск \(game.name)"
            errorText = ""
            selectedLogSummary = (try? Diagnostics.summarizeLog(at: command.logPath)) ?? ""
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    func setBackend(_ backend: GraphicsBackend) {
        guard let steam = bottles.first(where: { $0.role == .steam }) else {
            errorText = "Сначала укажите Steam"
            return
        }
        do {
            try bottleStore.setBackend(id: steam.id, backend: backend)
            status = "\(backend.displayName) применится после перезапуска Steam"
            errorText = ""
            refresh()
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    var selectedGame: GameEntry? {
        games.first(where: { $0.id == selectedGameId })
    }

    func isServiceBusy(_ service: ServiceStatus) -> Bool {
        guard isBusy else { return false }
        switch service.id {
        case "rosetta":
            return setupStatus.step == .rosetta
        case "runtime":
            return setupStatus.step == .runtime
        case "steam":
            return setupStatus.step == .steam
        default:
            return false
        }
    }

    func effectiveBackend(for game: GameEntry) -> GraphicsBackend {
        if let backend = game.backend {
            return backend
        }
        let bottleBackend = bottles.first(where: { $0.id == game.bottleId })?.backend ?? .dxmt
        return bottleBackend == .wined3d ? .dxmt : bottleBackend
    }

    func setGameBackend(_ backend: GraphicsBackend?, for game: GameEntry) {
        do {
            _ = try libraryStore.updateLaunchSettings(
                id: game.id,
                backend: backend,
                resetBackend: backend == nil
            )
            errorText = ""
            status = "Настройки \(game.name) сохранены"
            refresh()
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    func setGameHud(_ hud: Bool, for game: GameEntry) {
        do {
            _ = try libraryStore.updateLaunchSettings(id: game.id, hud: hud)
            errorText = ""
            status = "Настройки \(game.name) сохранены"
            refresh()
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    func setGameDesktop(_ desktop: VirtualDesktop?, for game: GameEntry) {
        do {
            _ = try libraryStore.updateLaunchSettings(
                id: game.id,
                virtualDesktop: desktop,
                resetDesktop: desktop == nil
            )
            errorText = ""
            status = "Настройки \(game.name) сохранены"
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
        } catch let error as MacGamerError {
            switch error {
            case .steamPathMissing, .bottleNotFound:
                break
            default:
                errorText = Diagnostics.explain(error)
            }
        } catch {
            errorText = Diagnostics.explain(error)
        }
    }

    private func updateProgress(_ text: String) {
        progressText = text
    }

    nonisolated private static func runInstall(
        paths: AppPaths,
        onProgress: @escaping @Sendable (String) async -> Void
    ) async throws {
        try await RuntimeStore(paths: paths).install { message in
            let text = friendlyProgress(message)
            Task {
                await onProgress(text)
            }
        }
    }

    nonisolated private static func friendlyProgress(_ message: String) -> String {
        if message.contains("download dxmt") {
            return "Загрузка Metal (DXMT)…"
        }
        if message.contains("download dxvk") {
            return "Загрузка Vulkan (DXVK)…"
        }
        if message.contains("extracted dxmt") {
            return "Распаковка Metal (DXMT)…"
        }
        if message.contains("extracted dxvk") {
            return "Распаковка Vulkan (DXVK)…"
        }
        if message.contains("merged dxmt") {
            return "Подключение графики…"
        }
        if message.contains("extracted wine") || message.contains("wine from") {
            return "Распаковка Wine…"
        }
        if message.contains("runtime installed") {
            return "Среда запуска установлена"
        }
        if message.contains("already installed") {
            return "Среда запуска уже установлена"
        }
        return message
    }
}
