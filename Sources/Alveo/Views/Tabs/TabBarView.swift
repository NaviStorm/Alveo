import SwiftUI
import SwiftData

// PAS D'IMPORT UIKit ici, nous sommes sur macOS

struct TabBarView: View {
    @Bindable var pane: AlveoPane
    @ObservedObject var webViewHelper: WebViewHelper // Pour les contrôles de navigation
    @Environment(\.modelContext) private var modelContext
    @State private var newTabURLString: String = "" // Pour le champ de saisie

    var body: some View {
        VStack(spacing:0) {
            navigationControlsView // Vue extraite pour la barre de navigation
            tabScrollView // Vue extraite pour les onglets
        }
        .onChange(of: webViewHelper.currentURL) { _, newURL in
            // Mettre à jour le textfield si la navigation change l'URL
            // Ou si l'onglet courant est l'onglet dont l'URL a changé
            if let currentTabId = pane.currentTabID,
               let currentTab = pane.tabs.first(where: { $0.id == currentTabId }),
               currentTab.urlString == newURL?.absoluteString {
                 newTabURLString = newURL?.absoluteString ?? ""
            } else if pane.currentTabID == nil || pane.tabs.first(where: { $0.id == pane.currentTabID}) == nil {
                 // Si l'onglet courant a été supprimé ou n'existe plus, vider le champ
                 newTabURLString = ""
            }
        }
        .onAppear { // Initialiser le champ URL au premier affichage si un onglet est actif
            if let currentTabId = pane.currentTabID,
               let currentTab = pane.tabs.first(where: { $0.id == currentTabId }) {
                 newTabURLString = currentTab.urlString
            }
        }
    }

    // Méthode pour sauvegarder dans l'historique (à appeler au bon moment)
    func saveToHistory(urlString: String, title: String?) {
        let normalizedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedUrl.isEmpty, normalizedUrl != "about:blank" else { return } // Ne pas sauvegarder les pages vides

        // Vérifier si l'entrée existe déjà
        let predicate = #Predicate<HistoryItem> { $0.urlString == normalizedUrl }
        var fetchDescriptor = FetchDescriptor<HistoryItem>(predicate: predicate)
        fetchDescriptor.fetchLimit = 1
        
        do {
            if let existingItem = try modelContext.fetch(fetchDescriptor).first {
                // Mettre à jour l'élément existant
                existingItem.title = title ?? existingItem.title // Mettre à jour le titre si un nouveau est fourni
                existingItem.lastVisitedDate = Date()
                existingItem.visitCount += 1
            } else {
                // Créer une nouvelle entrée
                let newItem = HistoryItem(urlString: normalizedUrl, title: title, lastVisitedDate: Date(), visitCount: 1)
                modelContext.insert(newItem)
            }
            // SwiftData sauvegarde automatiquement, mais un save explicite peut être forcé si besoin.
            // try modelContext.save()
        } catch {
            print("Failed to save or update history: \(error)")
        }
    }

    // --- Sous-vue pour la barre de navigation ---
    private var navigationControlsView: some View {
        HStack {
            Button { webViewHelper.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!webViewHelper.canGoBack)
            Button { webViewHelper.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!webViewHelper.canGoForward)
            Button { webViewHelper.reload() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(webViewHelper.isLoading) // Désactiver pendant le chargement

            TextField("Entrer une URL ou rechercher", text: $newTabURLString)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit { // Gère "Entrée"
                    handleSubmit(input: newTabURLString)
                }

            Button {
                // Pour le bouton "+", on peut ouvrir une page par défaut ou une page "nouvel onglet"
                handleSubmit(input: "https://www.google.com") // Ou une URL de type "about:newtab"
            } label: {
                Image(systemName: "plus")
            }
        }
        .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .background(Color(nsColor: .windowBackgroundColor)) // Couleur de fond standard pour les barres d'outils
    }

    // --- Sous-vue pour la barre d'onglets ---
    private var tabScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(pane.sortedTabs) { tab in
                    TabButton(tab: tab, isSelected: tab.id == pane.currentTabID,
                              onSelect: {
                                  print("TabButton onSelect")
                                  pane.currentTabID = tab.id
                                  tab.lastAccessed = Date()
                              },
                              onClose: {
                                  print("TabButton onClose")
                                  modelContext.delete(tab)
                                  // Si l'onglet courant est supprimé, pane.currentTabID sera mis à nil par la logique de AlveoPane
                                  // ou vous pouvez explicitement choisir le prochain onglet ici si nécessaire.
                              }
                    )
                    .draggable(tab) // Permet de glisser l'onglet
                }
            }
        }
        .frame(height: 30) // Hauteur fixe pour la barre d'onglets
        .background(Color(nsColor: .textBackgroundColor).opacity(0.1)) // Légèrement différent pour distinction
    }
    
    // --- Logique de soumission centralisée ---
    private func handleSubmit(input: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        let urlToLoad: String
        
        // Essayer de construire une URL, ajouter https si nécessaire
        if var potentialURL = URL(string: trimmedInput), (potentialURL.scheme != nil || trimmedInput.contains(".")) {
            if potentialURL.scheme == nil, trimmedInput.contains(".") && !trimmedInput.contains(" ") { // Ex: "google.com"
                 potentialURL = URL(string: "https://" + trimmedInput)! // Force unwrap ok ici car on a vérifié
            }
            urlToLoad = potentialURL.absoluteString
        } else if trimmedInput.lowercased() == "about:blank" {
            urlToLoad = "about:blank"
        }
        // Si ce n'est toujours pas une URL valide mais contient des caractères, considérer comme une recherche
        else if !trimmedInput.contains("://") && trimmedInput.contains(" ") || !trimmedInput.contains(".") {
            let searchQuery = trimmedInput.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            urlToLoad = "https://www.google.com/search?q=\(searchQuery)"
        }
        // Si l'input est déjà une URL complète
        else if URL(string:trimmedInput)?.scheme != nil {
             urlToLoad = trimmedInput
        }
         else {
            // Fallback si rien d'autre ne correspond, peut-être une page d'erreur locale
            print("Entrée URL non gérée: \(trimmedInput)")
            return
        }

        // Ajouter l'onglet et le sélectionner
        pane.addTab(urlString: urlToLoad)
        if let newTab = pane.tabs.first(where: { $0.urlString == urlToLoad && $0.pane == pane }) {
            pane.currentTabID = newTab.id
        } else if let lastAddedTab = pane.tabs.last(where: {$0.pane == pane }) { // Fallback
            pane.currentTabID = lastAddedTab.id
        }
        
        // Ne pas réinitialiser newTabURLString ici, car l'URL chargée peut être différente
        // de l'input (ex: après une recherche). Le onChange(of: webViewHelper.currentURL)
        // s'en chargera si l'URL de la webview correspond à celle de l'onglet.
    }
}

// TabButton reste le même, je l'omets ici pour la concision
struct TabButton: View {
    let tab: Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Optionnel : Favicon (nécessiterait de stocker/charger l'icône)
            // Image(systemName: "globe") // Placeholder
            //    .font(.callout)
            //    .padding(.leading, 6)

            Text(tab.displayTitle)
                .font(.system(size: 12)) // Taille de police pour les onglets
                .lineLimit(1)
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .foregroundColor(isSelected ? .accentColor : .primary.opacity(0.8))


            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium)) // Plus petit et plus fin pour la croix
            }
            .buttonStyle(.borderless) // Enlève le style de fond par défaut
            .padding(.trailing, 8)
            .opacity(isSelected || /*isHovering*/ false ? 1 : 0.5) // Afficher la croix plus clairement si sélectionné/survolé
        }
        .frame(minWidth: 80, idealWidth:150, maxWidth: 180) // Donne une taille aux onglets
        .padding(.vertical, 5) // Un peu plus de hauteur pour le clic
        .background(
            ZStack { // Pour les effets de fond
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.05)) // Fond subtil pour les onglets non sélectionnés
                }
            }
        )
        .contentShape(Rectangle()) // Pour que toute la zone soit cliquable pour la sélection
        .onTapGesture(perform: onSelect)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)) // Assure que le draggable respecte le cornerRadius
        .padding(.horizontal, 2) // Petit espacement entre les onglets
    }
}
