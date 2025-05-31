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
            // Ajouter nos commandes personnalisées dans le menu Fichier
            CommandGroup(after: .newItem) {
                Button("Nouvel Onglet") {
                    print("Menu: Nouvel Onglet cliqué")
                    NotificationCenter.default.post(name: .createNewTabFromMenu, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
                
                Button("Fermer l'Onglet") {
                    print("Menu: Fermer l'Onglet cliqué")
                    NotificationCenter.default.post(name: .closeTabOrWindowFromMenu, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
                
                Divider()
            }
        }
    }
}

// Extensions pour les notifications
extension Notification.Name {
    static let createNewTabFromMenu = Notification.Name("createNewTabFromMenuNotification")
    static let closeTabOrWindowFromMenu = Notification.Name("closeTabOrWindowFromMenuNotification")
}
