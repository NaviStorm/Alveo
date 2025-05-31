import SwiftUI
import SwiftData

@Model
final class AlveoPane {
    var id: UUID
    var name: String?
    var creationDate: Date
    var lastAccessed: Date?
    var currentTabID: UUID?
    
    @Relationship(deleteRule: .cascade, inverse: \Tab.pane)
    var tabs: [Tab] = []

    init(id: UUID = UUID(), name: String? = nil, creationDate: Date = Date(), initialTabURLString: String? = nil) {
        self.id = id
        self.name = name
        self.creationDate = creationDate
        self.lastAccessed = creationDate
        
        if let urlString = initialTabURLString, !urlString.isEmpty {
            // CORRECTION: Supprimer l'argument 'pane: self'
            let initialTab = Tab(urlString: urlString)
            self.tabs.append(initialTab)
            self.currentTabID = initialTab.id
        } else {
            // CORRECTION: Supprimer l'argument 'pane: self'
            let defaultTab = Tab(urlString: "about:blank")
            self.tabs.append(defaultTab)
            self.currentTabID = defaultTab.id
        }
    }

    var currentTab: Tab? {
        guard let currentTabID = self.currentTabID else { return nil }
        return self.tabs.first(where: { $0.id == currentTabID })
    }

    var tabsForDisplay: [Tab] {
        tabs.sorted { $0.creationDate < $1.creationDate }
    }
    
    func addTab(urlString: String) {
        // CORRECTION: Supprimer l'argument 'pane: self'
        let newTab = Tab(urlString: urlString.isEmpty ? "about:blank" : urlString)
        self.tabs.append(newTab) // SwiftData assignera `newTab.pane = self` ici
        self.currentTabID = newTab.id
        self.lastAccessed = Date()
        print("[AlveoPane ADD_TAB] Espace '\(self.name ?? "")' Nouvel onglet ajouté: \(newTab.displayTitle), ID: \(newTab.id). currentTabID est maintenant: \(String(describing: self.currentTabID))")
    }

    // La fonction removeTab reste inchangée par rapport à la version précédente que vous aviez,
    // mais assurez-vous que la suppression de l'objet Tab lui-même (modelContext.delete(tab))
    // est gérée au bon endroit (probablement dans la vue qui appelle cette suppression, comme SidebarView).
    // Si vous supprimez juste de la collection `tabs` ici, la cascade devrait fonctionner,
    // mais une suppression explicite avec modelContext est souvent plus claire.
    func removeTab(tab: Tab) {
        // (Logique existante ici)
        if let indexToRemove = self.tabs.firstIndex(where: { $0.id == tab.id }) {
            let wasSelected = (self.currentTabID == tab.id)
            
            // La suppression de la collection `tabs` dans un modèle @Model qui a une relation
            // @Relationship(deleteRule: .cascade) devrait normalement entraîner la suppression
            // de l'objet Tab de la base de données.
            // Si vous voulez être explicite, vous devriez faire `modelContext.delete(tab)`
            // AVANT de le retirer de la collection, ou au lieu de le retirer manuellement
            // si SwiftData gère la mise à jour de la collection après la suppression.
            // Pour la clarté, la suppression via modelContext est souvent faite par la vue
            // qui a accès au modelContext.
            
            self.tabs.remove(at: indexToRemove)
            // Si `modelContext.delete(tab)` n'a pas été appelé avant, SwiftData devrait
            // supprimer l'objet `tab` de la persistance à cause de la règle de cascade
            // lorsque le `AlveoPane` est sauvegardé sans `tab` dans sa collection `tabs`.
            
            if wasSelected {
                if self.tabs.isEmpty {
                    self.currentTabID = nil
                    // Optionnel : ajouter un nouvel onglet vide si c'était le dernier
                    // addTab(urlString: "about:blank")
                } else {
                    let newIndex = min(indexToRemove, self.tabs.count - 1)
                    if newIndex >= 0 && newIndex < self.tabs.count { // S'assurer que l'index est valide
                        self.currentTabID = self.tabs[newIndex].id
                    } else if !self.tabs.isEmpty { // Fallback pour prendre le premier
                        self.currentTabID = self.tabs.first!.id
                    } else {
                        self.currentTabID = nil
                    }
                }
            }
        }
        self.lastAccessed = Date()
        print("[AlveoPane REMOVE_TAB] Espace '\(self.name ?? "")' Onglet supprimé. currentTabID: \(String(describing: self.currentTabID))")
    }
}
