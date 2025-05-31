import SwiftUI
import SwiftData

@main
struct AlveoApp: App {
    let modelContainer: ModelContainer

    init() {
        print("Debut du programme")
        do {
            // Les modèles AlveoPane et Tab seront persistés
            modelContainer = try ModelContainer(for: AlveoPane.self, Tab.self,HistoryItem.self)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer) // Fournit le conteneur de modèles à l'environnement
    }
}

