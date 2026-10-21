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
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 520)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandMenu("Steam") {
                Button("Открыть Steam") {
                    model.openSteam()
                }
                .keyboardShortcut("s", modifiers: [.command])
                Button("Синхронизировать библиотеку") {
                    model.syncSteam()
                }
            }
        }
    }
}
