import SwiftData
import SwiftUI // Inclus pour référence, si vous utilisez des types SwiftUI à l'avenir

@Model
final class HistoryItem {
    var id: UUID
    var urlString: String
    var title: String?
    var lastVisitedDate: Date?
    
    // *** NOUVELLE PROPRIÉTÉ AJOUTÉE ***
    var visitCount: Int = 0 // Nombre de fois que cet item a été visité

    // Relation vers Tab (si un HistoryItem appartient à un Tab spécifique)
    // L'attribut 'inverse' pointe vers la propriété dans Tab qui gère la collection d'HistoryItems
    // J'ai enlevé @Relationship pour l'instant suite aux erreurs précédentes,
    // en supposant que Tab.historyItems le gère avec l'inverse.
    // Si vous remettez @Relationship ici, assurez-vous qu'il est correct.
    var tab: Tab?

    init(id: UUID = UUID(),
         urlString: String,
         title: String? = nil,
         lastVisitedDate: Date? = Date(),
         visitCount: Int = 1, // *** NOUVEAU PARAMÈTRE DANS L'INIT, avec valeur par défaut à 1 ***
         tab: Tab? = nil) {
        
        self.id = id
        self.urlString = urlString
        self.title = title
        self.lastVisitedDate = lastVisitedDate
        self.visitCount = visitCount // *** ASSIGNATION DE LA NOUVELLE PROPRIÉTÉ ***
        self.tab = tab
    }
    
    // Méthode pratique pour incrémenter le compteur de visites et mettre à jour la date
    func didVisitAgain() {
        self.visitCount += 1
        self.lastVisitedDate = Date()
    }
}
