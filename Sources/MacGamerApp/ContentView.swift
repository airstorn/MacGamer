import LauncherCore
import SwiftUI

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
                List(model.games) { game in
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
        return "\(game.installState.rawValue) · app \(app)"
    }
}
