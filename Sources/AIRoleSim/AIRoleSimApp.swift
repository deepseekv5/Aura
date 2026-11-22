import SwiftUI

@main
struct AIRoleSimApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("Aura") {
            RootView()
                .environmentObject(store)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建角色") { store.beginNewCharacter() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("新建对话") { store.newConversationForSelection() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("新建多人对话") { store.showGroupSetup = true }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandMenu("查看") {
                Button("记忆面板") { store.showMemoryInspector.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("全局搜索") { store.showSearch = true }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu("帮助") {
                Button("检查更新…") { NotificationCenter.default.post(name: .showUpdateView, object: nil) }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
