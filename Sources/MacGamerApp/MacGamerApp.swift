import SwiftUI

@main
struct MacGamerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MacGamer") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 520)
        }
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
