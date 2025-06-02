import SwiftUI

struct SuggestionsList: View {
    let suggestions: [HistoryItem]
    let width: CGFloat
    let onSelect: (HistoryItem) -> Void

    var body: some View {
        // let _ = print("[SuggestionsList BODY] Appel. Reçu \(suggestions.count) suggestions. Largeur: \(width)")

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions) { item in
                    Button(action: {
                        print("[SuggestionsList ✅ BOUTON ITEM TAP] \(item.urlString)")
                        onSelect(item)
                    }) {                    VStack(alignment: .leading) { // VStack pour chaque item
                        Text(item.title ?? item.urlString).bold().lineLimit(1).font(.system(size: 12))
                        Text(item.urlString).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.2)) // Fond de debug
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("[SuggestionsList ✅ TAP SUR ITEM] \(item.urlString)")
                        onSelect(item)
                    }
                    .background(Color.red.opacity(0.5)) // Nouveau fond pour le bouton
                    }
                    .buttonStyle(.plain) // Pour qu'il ressemble à une ligne
                    // Pas de .listRowBackground ou .listRowSeparator ici si on n'est pas dans une List
                    if item.id != suggestions.last?.id { Divider().padding(.leading, 8) }
                }
            }
        }
        // Modificateurs pour la ScrollView ENTIÈRE
        .background(Material.bar)
        .frame(width: width) // Largeur
        .frame(maxHeight: 250) // UNIQUEMENT maxHeight pour la hauteur adaptative
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 5)
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }
}
