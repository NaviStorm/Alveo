import SwiftUI // Si vous utilisez des types SwiftUI, sinon pas nécessaire ici
import SwiftData

@Model
final class Tab {
    var id: UUID
    var urlString: String
    var title: String?
    var lastAccessed: Date
    var creationDate: Date
    
    var pane: AlveoPane? // Relation inverse avec AlveoPane (supposée correcte)

    // *** DÉFINITION CORRECTE DE LA RELATION INVERSE ***
    // Cette relation dit : "Mes 'historyItems' sont l'inverse de la propriété 'tab' dans HistoryItem."
    // La deleteRule ici (.cascade) signifie que si ce Tab est supprimé, tous ses HistoryItems seront aussi supprimés.
    @Relationship(deleteRule: .cascade, inverse: \HistoryItem.tab)
    var historyItems: [HistoryItem] = [] // Doit être une collection, initialisée vide.

    init(id: UUID = UUID(),
         urlString: String = "about:blank",
         title: String? = nil,
         lastAccessed: Date = Date(),
         creationDate: Date = Date()) {
        
        self.id = id
        self.urlString = urlString
        self.title = title ?? (urlString.isEmpty || urlString == "about:blank" ? nil : urlString)
        self.lastAccessed = lastAccessed
        self.creationDate = creationDate
        // historyItems est initialisée à [] et sera gérée par SwiftData.
    }

    // Propriétés calculées et méthodes (displayTitle, displayURL, getSortedHistory)
    // ... (votre code existant pour ces méthodes, qui semble correct) ...
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        } else if let url = URL(string: urlString), let host = url.host, !host.isEmpty, urlString != "about:blank" {
            return host.starts(with: "www.") ? String(host.dropFirst(4)) : host
        } else if urlString == "about:blank" || urlString.isEmpty {
            return "Nouvel onglet"
        } else {
            return urlString
        }
    }

    var displayURL: URL? {
        return URL(string: urlString)
    }

    func getSortedHistory(context: ModelContext) -> [HistoryItem] {
        let currentTabInstanceID = self.id
        let predicate = #Predicate<HistoryItem> { historyItem in
            historyItem.tab?.id == currentTabInstanceID
        }
        let fetchDescriptor = FetchDescriptor(predicate: predicate)
        do {
            let items = try context.fetch(fetchDescriptor)
            return items.sorted { (item1, item2) -> Bool in
                guard let date1 = item1.lastVisitedDate else { return false }
                guard let date2 = item2.lastVisitedDate else { return true }
                return date1 > date2
            }
        } catch {
            print("Erreur lors de la récupération de l'historique pour l'onglet ID \(self.id): \(error)")
            return []
        }
    }
}
