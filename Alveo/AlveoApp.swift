import SwiftUI
import SwiftData

@main
struct AlveoApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            AlveoPane.self,
            Tab.self,
            HistoryItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Impossible de créer ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
        }
        .commands {
            // Menu Fichier
            CommandGroup(after: .newItem) {
                Button("Nouvel Onglet") {
                    NotificationCenter.default.post(name: .createNewTabFromMenu, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("Fermer l'Onglet") {
                    NotificationCenter.default.post(name: .closeTabOrWindowFromMenu, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
                
                Divider()
            }
            
            // Nouveau menu Affichage
            CommandMenu("Affichage") {
                Button("Vue fractionnée") {
                    NotificationCenter.default.post(name: .enableSplitViewFromMenu, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                
                Button("Fermer Vue fractionnée") {
                    NotificationCenter.default.post(name: .disableSplitViewFromMenu, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift, .option])
            }
        }
    }
}

// Extensions pour les notifications
extension Notification.Name {
    static let createNewTabFromMenu = Notification.Name("createNewTabFromMenuNotification")
    static let closeTabOrWindowFromMenu = Notification.Name("closeTabOrWindowFromMenuNotification")
    static let enableSplitViewFromMenu = Notification.Name("enableSplitViewFromMenuNotification")
    static let disableSplitViewFromMenu = Notification.Name("disableSplitViewFromMenuNotification")
    // ✅ Nouvelle notification
    static let enableSplitViewWithSelection = Notification.Name("enableSplitViewWithSelectionNotification")
}
