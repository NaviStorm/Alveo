import SwiftUI
import SwiftData

@Model
final class Tab {
    var id: UUID = UUID()
    var urlString: String
    var title: String?
    var lastAccessed: Date? // CHANGÉ: Date -> Date?
    var creationDate: Date
    
    var pane: AlveoPane?
    
    // Emoji personnalisé pour remplacer la favicon
    var customEmojiIcon: String? = nil

    init(id: UUID = UUID(),
         urlString: String = "about:blank",
         title: String? = nil,
         lastAccessed: Date? = Date(), // CHANGÉ: Date -> Date?
         creationDate: Date = Date()) {
        self.id = id
        self.urlString = urlString
        self.title = title ?? (urlString.isEmpty || urlString == "about:blank" ? nil : urlString)
        self.lastAccessed = lastAccessed
        self.creationDate = creationDate
    }

    // Propriété calculée pour la favicon
    var faviconURL: URL? {
        guard customEmojiIcon == nil,
              let url = URL(string: urlString),
              let host = url.host,
              !host.isEmpty,
              urlString != "about:blank" else { return nil }
        
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.path = "/favicon.ico"
        return components.url
    }

    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        } else if let url = URL(string: urlString),
                  let host = url.host,
                  !host.isEmpty,
                  urlString != "about:blank" {
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
