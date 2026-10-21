import AppKit
import SwiftUI

@main
struct MacGamerApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("MacGamer") {
            Group {
                if model.setupStatus.step == .ready {
                    ContentView()
                } else {
                    SetupWizardView()
                }
            }
            .environmentObject(model)
            .frame(minWidth: 900, minHeight: 560)
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .defaultSize(width: 1040, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Steam") {
                Button("Открыть Steam") {
                    model.openSteam()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(model.setupStatus.step != .ready && model.steamPathInput.isEmpty)
                Button("Синхронизировать библиотеку") {
                    model.syncSteam()
                }
                .disabled(model.setupStatus.step != .ready)
            }
        }
    }
}
