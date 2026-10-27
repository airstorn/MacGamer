import AppKit
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
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            library
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        List {
            Section("Система") {
                ForEach(model.serviceStatuses) { service in
                    ServiceStatusRow(service: service, busy: model.isServiceBusy(service))
                }
            }
            Section("Steam") {
                if !model.steamPathInput.isEmpty {
                    Text(model.steamPathInput)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Выбрать файл…") { model.chooseSteamFile() }
                Button("Открыть Steam") { model.openSteam() }
                Button("Синхронизировать") { model.syncSteam() }
                if let steam = model.bottles.first(where: { $0.role == .steam }) {
                    Picker("Графика", selection: Binding(
                        get: { steam.backend },
                        set: { model.setBackend($0) }
                    )) {
                        ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .navigationTitle("MacGamer")
    }

    private var library: some View {
        VStack(spacing: 0) {
            if !model.errorText.isEmpty {
                Text(model.errorText)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            if !model.status.isEmpty {
                Text(model.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, model.errorText.isEmpty ? 10 : 6)
            }
            List(model.games, selection: $model.selectedGameId) { game in
                gameRow(game)
                    .tag(game.id)
            }
            .listStyle(.inset)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .overlay {
                if model.games.isEmpty {
                    ContentUnavailableView(
                        "Библиотека пуста",
                        systemImage: "gamecontroller",
                        description: Text("Откройте Steam, установите игру и нажмите «Синхронизировать».")
                    )
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomPanel
        }
        .navigationTitle("Библиотека")
    }

    private func gameRow(_ game: GameEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            GameIconView(game: game)
            Image(systemName: game.installState.symbol)
                .foregroundStyle(gameStatusColor(game.installState))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(statusLine(game))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button("Лог") { model.showLatestLog(for: game) }
                Button("Играть") { model.play(game) }
                    .disabled(game.installState != .ready || game.steamAppId == nil)
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if model.selectedGame != nil || !model.selectedLogSummary.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                if let game = model.selectedGame {
                    DisclosureGroup("Дополнительно") {
                        GameLaunchSettingsView(game: game)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                if !model.selectedLogSummary.isEmpty {
                    ScrollView {
                        Text(model.selectedLogSummary)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 120)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .background(.bar)
        }
    }

    private func statusLine(_ game: GameEntry) -> String {
        let app = game.steamAppId.map(String.init) ?? "-"
        var parts = [
            game.installState.displayName,
            "Steam \(app)",
            model.effectiveBackend(for: game).displayName
        ]
        if game.hud {
            parts.append("HUD")
        }
        if let desktop = game.virtualDesktop {
            parts.append(desktop.spec)
        }
        return parts.joined(separator: " · ")
    }

    private func gameStatusColor(_ state: InstallState) -> Color {
        switch state {
        case .ready:
            return .green
        case .installing, .updating:
            return .orange
        case .missing:
            return .red
        }
    }
}

private struct GameIconView: View {
    @EnvironmentObject private var model: AppModel
    let game: GameEntry
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: iconSize.width, height: iconSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
        .task(id: iconTaskID) {
            image = await model.icon(for: game)
        }
    }

    private var showsPortrait: Bool {
        guard let image else { return false }
        return image.size.height > image.size.width * 1.15
    }

    private var iconSize: CGSize {
        showsPortrait ? CGSize(width: 36, height: 54) : CGSize(width: 40, height: 40)
    }

    private var iconTaskID: String {
        "\(game.steamAppId ?? 0)-\(model.iconEpoch)"
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
        VStack(alignment: .leading, spacing: 10) {
            Picker("Бэкенд", selection: backendBinding) {
                Text("как у бутылки").tag(GameBackendOption.bottle)
                ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                    Text(backend.displayName).tag(GameBackendOption.value(backend))
                }
            }
            .pickerStyle(.menu)
            Toggle("HUD", isOn: hudBinding)
            Picker("Виртуальный стол", selection: desktopBinding) {
                Text("выключен").tag(DesktopOption.off)
                ForEach(Self.presets, id: \.0) { width, height in
                    Text("\(width)×\(height)").tag(DesktopOption.preset(width, height))
                }
                Text("свой размер").tag(DesktopOption.custom)
            }
            .pickerStyle(.menu)
            if desktopSelection == .custom {
                HStack {
                    TextField("Ширина", text: $customWidth)
                        .frame(width: 80)
                    Text("×")
                    TextField("Высота", text: $customHeight)
                        .frame(width: 80)
                    Button("Применить") { applyCustomDesktop() }
                    Spacer(minLength: 0)
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
