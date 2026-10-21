import LauncherCore
import SwiftUI

private enum GameBackendOption: Hashable {
    case bottle
    case value(GraphicsBackend)
}

private enum DesktopOption: Hashable {
    case off
    case preset(Int, Int)
    case custom
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List {
                Section("Система") {
                    Text(model.doctorText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                Section("Steam") {
                    TextField("Путь к steam.exe или SteamSetup.exe", text: $model.steamPathInput)
                    Button("Сохранить путь") { model.useSteamPath() }
                    Button("Открыть Steam") { model.openSteam() }
                    Button("Синхронизировать") { model.syncSteam() }
                    if let steam = model.bottles.first(where: { $0.role == .steam }) {
                        Picker("Бэкенд бутылки", selection: Binding(
                            get: { steam.backend },
                            set: { model.setBackend($0) }
                        )) {
                            ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                                Text(backend.rawValue).tag(backend)
                            }
                        }
                    }
                }
            }
            .navigationTitle("MacGamer")
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                if !model.errorText.isEmpty {
                    Text(model.errorText)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if !model.status.isEmpty {
                    Text(model.status)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                List(model.games, selection: $model.selectedGameId) { game in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.name).font(.headline)
                            Text(statusLine(game))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Лог") { model.showLatestLog(for: game) }
                        Button("Играть") { model.play(game) }
                            .disabled(game.installState != .ready || game.steamAppId == nil)
                    }
                    .tag(game.id)
                }
                if let game = model.selectedGame {
                    GameLaunchSettingsView(game: game)
                }
                if !model.selectedLogSummary.isEmpty {
                    ScrollView {
                        Text(model.selectedLogSummary)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                }
            }
            .padding()
            .navigationTitle("Библиотека")
        }
    }

    private func statusLine(_ game: GameEntry) -> String {
        let app = game.steamAppId.map(String.init) ?? "-"
        var parts = [
            game.installState.rawValue,
            "app \(app)",
            model.effectiveBackend(for: game).rawValue
        ]
        if game.hud {
            parts.append("hud")
        }
        if let desktop = game.virtualDesktop {
            parts.append(desktop.spec)
        }
        return parts.joined(separator: " · ")
    }
}

private struct GameLaunchSettingsView: View {
    @EnvironmentObject private var model: AppModel
    let game: GameEntry
    @State private var customWidth: String = "1920"
    @State private var customHeight: String = "1080"

    private static let presets: [(Int, Int)] = [
        (1280, 720),
        (1600, 900),
        (1920, 1080),
        (2560, 1440)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Настройки запуска")
                .font(.headline)
            Picker("Бэкенд", selection: backendBinding) {
                Text("как у бутылки").tag(GameBackendOption.bottle)
                ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                    Text(backend.rawValue).tag(GameBackendOption.value(backend))
                }
            }
            Toggle("HUD", isOn: hudBinding)
            Picker("Виртуальный стол", selection: desktopBinding) {
                Text("выключен").tag(DesktopOption.off)
                ForEach(Self.presets, id: \.0) { width, height in
                    Text("\(width)×\(height)").tag(DesktopOption.preset(width, height))
                }
                Text("свой размер").tag(DesktopOption.custom)
            }
            if desktopSelection == .custom {
                HStack {
                    TextField("Ширина", text: $customWidth)
                        .frame(width: 80)
                    Text("×")
                    TextField("Высота", text: $customHeight)
                        .frame(width: 80)
                    Button("Применить") { applyCustomDesktop() }
                }
            }
        }
        .onAppear { syncCustomDesktop() }
        .onChange(of: game.id) { _, _ in syncCustomDesktop() }
    }

    private var backendBinding: Binding<GameBackendOption> {
        Binding(
            get: {
                if let backend = game.backend {
                    return .value(backend)
                }
                return .bottle
            },
            set: { option in
                switch option {
                case .bottle:
                    model.setGameBackend(nil, for: game)
                case .value(let backend):
                    model.setGameBackend(backend, for: game)
                }
            }
        )
    }

    private var hudBinding: Binding<Bool> {
        Binding(
            get: { game.hud },
            set: { model.setGameHud($0, for: game) }
        )
    }

    private var desktopSelection: DesktopOption {
        guard let desktop = game.virtualDesktop else {
            return .off
        }
        if Self.presets.contains(where: { $0.0 == desktop.width && $0.1 == desktop.height }) {
            return .preset(desktop.width, desktop.height)
        }
        return .custom
    }

    private var desktopBinding: Binding<DesktopOption> {
        Binding(
            get: { desktopSelection },
            set: { option in
                switch option {
                case .off:
                    model.setGameDesktop(nil, for: game)
                case .preset(let width, let height):
                    model.setGameDesktop(VirtualDesktop(width: width, height: height), for: game)
                case .custom:
                    if let desktop = game.virtualDesktop {
                        customWidth = String(desktop.width)
                        customHeight = String(desktop.height)
                    }
                    applyCustomDesktop()
                }
            }
        )
    }

    private func syncCustomDesktop() {
        if let desktop = game.virtualDesktop {
            customWidth = String(desktop.width)
            customHeight = String(desktop.height)
        }
    }

    private func applyCustomDesktop() {
        guard let width = Int(customWidth), let height = Int(customHeight) else {
            model.errorText = Diagnostics.explain(MacGamerError.invalidDesktopSize("\(customWidth)x\(customHeight)"))
            return
        }
        model.setGameDesktop(VirtualDesktop(width: width, height: height), for: game)
    }
}
