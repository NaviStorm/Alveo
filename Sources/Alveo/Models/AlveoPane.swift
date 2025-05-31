import SwiftUI // Ou import Foundation si pas de types SwiftUI spécifiques
import SwiftData

@Model
final class AlveoPane {
    @Attribute(.unique) var id: UUID
    var name: String? // Nom optionnel pour le panneau
    var creationDate: Date // Date de création pour le tri

    // Relation avec les onglets. 'tabs' est optionnel et initialisé à un tableau vide.
    // La règle de suppression .cascade signifie que si un AlveoPane est supprimé,
    // tous ses onglets associés seront également supprimés.
    @Relationship(deleteRule: .cascade) // Pas de 'inverse' spécifié explicitement ici à l'origine
    var tabs: [Tab] = [] // Array non-optionnel d'onglets
    
    var currentTabID: UUID? // ID de l'onglet actuellement sélectionné dans ce panneau

    // Initialiseur
    init(id: UUID = UUID(), name: String? = nil, creationDate: Date = Date(), initialTabURLString: String? = nil) {
        self.id = id
        self.name = name
        self.creationDate = creationDate
        
        if let urlString = initialTabURLString, !urlString.isEmpty {
            // Créer un onglet initial si une URL est fournie
            let initialTab = Tab(urlString: urlString) // Utilise l'init original de Tab
            // self.tabs.append(initialTab) // Ajoute à l'array optionnel
            // Si tabs est nil, il faut d'abord l'initialiser :
            self.tabs.append(initialTab)
            self.currentTabID = initialTab.id
        } else {
            // Si pas d'URL initiale, tabs reste ce qu'il est (nil ou []) et pas d'onglet courant
            // Pour être sûr, on pourrait faire :
            // self.tabs = []
            self.currentTabID = nil
        }
    }

    // Propriété calculée pour obtenir les onglets triés (si nécessaire, mais l'ordre n'était pas géré par Tab à l'origine)
    // Si Tab n'a pas de propriété 'order', on ne peut pas trier par 'order'.
    // On pourrait trier par un autre critère si besoin, ou simplement retourner les onglets.
    var sortedTabs: [Tab] {
        // À l'origine, si Tab n'avait pas de propriété 'order', on ne pouvait pas trier ainsi.
        // On retourne simplement le tableau, ou on le trie par un autre critère (ex: titre, si pertinent).
        // Pour un affichage simple dans une barre d'onglets horizontale, l'ordre d'ajout est souvent suffisant.
        return tabs // Retourne un tableau vide si tabs est nil
    }

    // Méthode pour ajouter un nouvel onglet (version originale simple)
    func addTab(urlString: String) {
        let finalURL = urlString.isEmpty ? "about:blank" : urlString
        let newTab = Tab(urlString: finalURL)
        self.tabs.append(newTab)
        self.currentTabID = newTab.id
        print("Nouvel onglet créé avec URL: \(finalURL)")
    }

    // Méthode pour supprimer un onglet (logique de base)
    // Note : La suppression effective se fait souvent via modelContext.delete(tab) dans la vue.
    // Cette méthode pourrait être utilisée pour la logique interne du modèle si nécessaire.
    func removeTab(_ tabToRemove: Tab) {
        tabs.removeAll { $0.id == tabToRemove.id }
        // Logique additionnelle si l'onglet supprimé était le currentTabID
        if currentTabID == tabToRemove.id {
            currentTabID = tabs.first?.id // Sélectionne le premier onglet restant, ou nil
        }
    }
}
