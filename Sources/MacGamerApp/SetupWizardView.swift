import LauncherCore
import SwiftUI

struct SetupWizardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Настройка MacGamer")
                        .font(.largeTitle.bold())
                    Text(model.setupStatus.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                VStack(spacing: 0) {
                    ForEach(Array(model.serviceStatuses.enumerated()), id: \.element.id) { index, service in
                        ServiceStatusRow(service: service, busy: model.isServiceBusy(service))
                            .padding(.vertical, 10)
                        if index < model.serviceStatuses.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.setupStatus.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    if !model.errorText.isEmpty {
                        Text(model.errorText)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                    if model.isBusy {
                        ProgressView(model.progressText.isEmpty ? "Подождите…" : model.progressText)
                    }
                    actions
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(model.isBusy)
    }

    @ViewBuilder
    private var actions: some View {
        switch model.setupStatus.step {
        case .unsupportedChip:
            EmptyView()
        case .rosetta:
            Button("Установить Rosetta") {
                model.installRosetta()
            }
            .keyboardShortcut(.defaultAction)
        case .runtime:
            Button("Установить") {
                model.installRuntime()
            }
            .keyboardShortcut(.defaultAction)
        case .steam:
            VStack(alignment: .leading, spacing: 12) {
                Link("Скачать Windows Steam", destination: URL(string: "https://store.steampowered.com/about/")!)
                Button("Выбрать SteamSetup.exe") {
                    model.chooseSteamFile()
                }
                .keyboardShortcut(.defaultAction)
                if !model.steamPathInput.isEmpty {
                    Text(model.steamPathInput)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Button("Открыть Steam") {
                        model.openSteam()
                    }
                }
            }
        case .ready:
            EmptyView()
        }
    }
}
