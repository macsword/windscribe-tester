import SwiftUI

@main
struct WindscribeTesterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Test") {
                Button("Start Test") { model.startTesting() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(model.isTesting)
                Button("Cancel Test") { model.cancelTesting() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!model.isTesting)
                Divider()
                Button("Reload Servers") {
                    Task { await model.reloadServers() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("Select All Visible") { model.selectAllVisible() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Clear Queue") { model.clearQueue() }
                Divider()
                Button("Connect to Best") { model.connectToBest() }
                    .disabled(model.bestResult == nil)
                Button("Export Results…") { model.exportCSV() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.results.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
