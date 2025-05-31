import SwiftUI // Ou import Foundation si aucun type SwiftUI n'est utilisé
import SwiftData
import UniformTypeIdentifiers // Pour la conformité Transferable de base

struct TransferableTab: Codable, Identifiable {
    let id: UUID
    let urlString: String
    let title: String?
    let order: Int
    let lastAccessed: Date?
}

@Model
final class Tab {
    @Attribute(.unique) var id: UUID
    var urlString: String
    var title: String?
    var order: Int
    var lastAccessed: Date?
    
    
    // Relation inverse vers AlveoPane.
    // À l'origine, si AlveoPane avait `@Relationship(inverse: \Tab.pane)`,
    // cette propriété était nécessaire ici, même sans la macro @Relationship explicite dessus.
    // Si AlveoPane n'avait PAS `inverse` sur sa relation `tabs`, alors cette propriété
    // `pane` pouvait même être absente à l'origine (relation unidirectionnelle).
    // Pour une restauration à un état fonctionnel simple avec relation bidirectionnelle implicite :
    var pane: AlveoPane? // Laissée ici pour la relation inverse de base. SwiftData peut la déduire.
    // Si vous êtes SÛR qu'elle n'existait pas, vous pouvez la commenter.
    
    // Initialiseur simple
    init(id: UUID = UUID(), urlString: String, title: String? = nil, order: Int = 0, lastAccessed: Date? = Date()) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.order = order
        self.lastAccessed = lastAccessed
    }
    
    
    // Propriétés calculées pour l'affichage (probablement présentes à l'origine)
    var displayURL: URL? {
        URL(string: urlString)
    }
    
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        if let host = self.displayURL?.host?.replacingOccurrences(of: "www.", with: "") {
            return host
        }
        // Cas pour "about:blank" ou une URL vide
        if urlString.lowercased() == "about:blank" {
            return "Nouvel Onglet" // Ou un titre par défaut
        }
        if urlString.isEmpty {
            return "Onglet Vide"
        }
        return "Chargement..." // Titre par défaut pendant le chargement
    }
    
    // Méthode pour créer une représentation transférable
    func toTransferable() -> TransferableTab {
        return TransferableTab(id: self.id,
                               urlString: self.urlString,
                               title: self.title,
                               order: self.order, // Assurez-vous que 'order' est une propriété de Tab
                               lastAccessed: self.lastAccessed) // Assurez-vous que 'lastAccessed' est une propriété de Tab
    }
}

// Extension pour rendre Tab conforme à Transferable pour le drag & drop
// Version originale simple utilisant la conformité Codable implicite de @Model
// pour ses propriétés persistées.
extension Tab: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(
            contentType: .alveoTab, // Label CORRECT : contentType
            exporting: { tabModel in
                // Convertir le Tab en TransferableTab
                let transferableRepresentation = tabModel.toTransferable()
                // Encoder TransferableTab en Data (JSON)
                let encoder = JSONEncoder()
                return try encoder.encode(transferableRepresentation)
            },
            importing: { data in
                // Décoder Data en TransferableTab
                let decoder = JSONDecoder()
                let transferableRepresentation = try decoder.decode(TransferableTab.self, from: data)
                // Créer un nouveau Tab à partir de TransferableTab
                return Tab(id: transferableRepresentation.id,
                           urlString: transferableRepresentation.urlString,
                           title: transferableRepresentation.title,
                           order: transferableRepresentation.order,
                           lastAccessed: transferableRepresentation.lastAccessed)
            }
        )

        ProxyRepresentation(exporting: \.urlString)
    }
}
