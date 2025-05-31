import SwiftUI
import SwiftData


@Model
final class HistoryItem {
    var id: UUID
    var urlString: String
    var title: String?
    var lastVisitedDate: Date?

    // Relation simplifiée. SwiftData devrait inférer l'inverse depuis Tab.historyItems.
    // On ne spécifie PAS @Relationship ici si Tab.historyItems le fait avec l'inverse correct.
    var tab: Tab?

    init(id: UUID = UUID(),
         urlString: String,
         title: String? = nil,
         lastVisitedDate: Date? = Date(),
         tab: Tab? = nil) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.lastVisitedDate = lastVisitedDate
        self.tab = tab
    }
}
