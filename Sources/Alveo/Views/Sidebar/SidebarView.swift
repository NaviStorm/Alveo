import SwiftUI
import SwiftData

@MainActor // Assurer que les mises à jour UI se font sur le thread principal
struct SidebarView: View {
    // @Bindable est crucial ici pour que les modifications de pane.currentTabID
    // (faites par la sélection dans la List) soient propagées et déclenchent les .onChange dans ContentView.
    @Bindable var pane: AlveoPane
    
    // webViewHelper est principalement passé pour information ou actions directes
    // qui ne sont pas des chargements d'URL (le chargement est géré par ContentView).
    @ObservedObject var webViewHelper: WebViewHelper
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tête du volet (Nom de l'espace + bouton nouvel onglet)
            HStack {
                Text(pane.name ?? "Espace")
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.leading, 12)
                Spacer()
                Button {
                    print("[SidebarView] Bouton '+' cliqué pour l'espace '\(pane.name ?? "")'")
                    // La méthode addTab dans AlveoPane devrait sélectionner le nouvel onglet
                    pane.addTab(urlString: "about:blank")
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless) // Style macOS standard pour les boutons de barre d'outils/sidebar
                .padding(.trailing, 12)
            }
            .frame(height: 38) // Hauteur cohérente pour un en-tête de section
            .background(Color(NSColor.controlBackgroundColor)) // Fond standard pour les sidebars
            
            Divider() // Séparateur visuel
            
            // Liste des onglets
            // Utiliser List(selection: ...) est la manière la plus idiomatique et robuste
            // pour gérer la sélection dans une sidebar sur macOS.
            List(selection: $pane.currentTabID) {
                // Utiliser la propriété qui trie par date de création pour un ordre stable
                // Adaptez `pane.tabsForDisplay` au nom que vous avez choisi dans AlveoPane.swift
                ForEach(pane.tabsForDisplay) { tab in
                    SidebarTabRow(
                        tab: tab,
                        // isSelected est toujours utile pour le style visuel personnalisé de SidebarTabRow
                        // même si List gère la sélection principale.
                        isSelected: tab.id == pane.currentTabID,
                        onSelect: {
                            print(">>> [SidebarTabRow onSelect] Clic sur onglet: '\(tab.displayTitle)', ID: \(tab.id)")
                            // Mettre à jour currentTabID si ce n'est pas déjà l'onglet sélectionné.
                            // Le $pane.currentTabID de List(selection:...) devrait aussi gérer cela,
                            // mais une action explicite ici est plus claire pour le débogage
                            // et pour mettre à jour `lastAccessed`.
                            if pane.currentTabID != tab.id {
                                pane.currentTabID = tab.id
                                // Ce changement déclenchera le .onChange dans ContentView,
                                // qui appellera updateToolbarURLInputAndLoadIfNeeded(forceLoad: true).
                            } else {
                                print(">>> [SidebarTabRow onSelect] Onglet déjà sélectionné. On pourrait forcer un rechargement ici si besoin.")
                                // Optionnel: Si vous voulez qu'un clic sur un onglet déjà actif recharge la page :
                                // webViewHelper.reload() // Attention, ceci interagit directement avec le helper.
                                // Il serait plus propre que ContentView gère cela aussi.
                            }
                            tab.lastAccessed = Date() // Mettre à jour la date du dernier accès
                        },
                        onClose: {
                            print("[SidebarView] Fermeture de l'onglet: '\(tab.displayTitle)'")
                            handleCloseTabInSidebar(tabToClose: tab, currentPane: pane)
                        }
                    )
                    .tag(tab.id) // Crucial pour que List(selection: ...) fonctionne correctement
                }
            }
            .listStyle(.sidebar) // Applique le style natif macOS pour les sidebars
                                 // (fond, espacement, indicateurs de sélection, etc.)
        }
        // Le fond général du sidebar est maintenant géré par .listStyle(.sidebar)
        // et l'en-tête a son propre fond.
        // .background(Color(NSColor.controlBackgroundColor)) // Peut être redondant avec .listStyle(.sidebar)
    }

    private func handleCloseTabInSidebar(tabToClose: Tab, currentPane: AlveoPane) {
        let tabIDToClose = tabToClose.id
        let paneID = currentPane.id
        let wasSelected = currentPane.currentTabID == tabIDToClose
        
        // Option 1: Laisser AlveoPane gérer la logique de sélection du prochain onglet
        // currentPane.removeTab(tab: tabToClose) // Si AlveoPane.removeTab gère la sélection du prochain onglet.
        // Puis, s'assurer que modelContext.delete est appelé.
        
        // Option 2: Gérer explicitement ici (plus de contrôle)
        guard let indexToRemove = currentPane.tabs.firstIndex(where: { $0.id == tabIDToClose }) else {
            print("[SidebarView handleCloseTab] Erreur: Onglet à fermer non trouvé dans la collection.")
            return
        }
        
        // D'abord, supprimer l'objet du ModelContext
        modelContext.delete(tabToClose)
        // SwiftData devrait automatiquement mettre à jour la collection `currentPane.tabs`
        // après la suppression de l'objet du contexte (surtout si la vue est redessinée).
        // Si ce n'est pas le cas, vous pourriez avoir à retirer manuellement de `currentPane.tabs.remove(at: indexToRemove)`
        // MAIS cela peut causer des conflits avec la gestion de SwiftData.
        // Il est généralement préférable de laisser SwiftData mettre à jour la collection après `modelContext.delete`.
        // Pour l'instant, nous allons supposer que la collection `currentPane.tabs` se met à jour.

        // Logique pour sélectionner le prochain onglet si l'onglet fermé était actif
        if wasSelected {
            // Après la suppression, currentPane.tabs est (devrait être) la nouvelle liste.
            if !currentPane.tabs.isEmpty {
                // Essayer de sélectionner l'onglet à la même position (qui est maintenant le suivant)
                // ou le précédent si c'était le dernier.
                let newIndexToSelect = min(indexToRemove, currentPane.tabs.count - 1)
                
                if newIndexToSelect >= 0 && newIndexToSelect < currentPane.tabs.count {
                    currentPane.currentTabID = currentPane.tabs[newIndexToSelect].id
                } else if !currentPane.tabs.isEmpty { // Fallback si l'index n'est pas valide mais qu'il reste des onglets
                    currentPane.currentTabID = currentPane.tabs.first!.id
                } else {
                     currentPane.currentTabID = nil // Plus aucun onglet
                }
            } else { // Plus aucun onglet dans l'espace
                currentPane.currentTabID = nil
                // ContentView.updateToolbarURLInputAndLoadIfNeeded (appelé par .onChange)
                // devrait gérer le cas où il n'y a plus d'onglets et en ajouter un "about:blank".
            }
            print("[SidebarView handleCloseTab] Nouvel onglet sélectionné ID: \(String(describing: currentPane.currentTabID))")
        }
        // Le .onChange(of: currentActiveAlveoPaneObject?.currentTabID) dans ContentView
        // gèrera le chargement de la page pour le nouvel onglet sélectionné (ou "about:blank").
    }
}

struct SidebarTabRow: View {
    // `tab` est un objet @Model, donc il est observé par SwiftData.
    // On n'a pas besoin de @Bindable ici car SidebarTabRow ne modifie pas directement les propriétés de `tab`
    // d'une manière qui nécessite un binding bidirectionnel (sauf `lastAccessed` qui est un effet de bord de `onSelect`).
    let tab: Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHoveringCloseButton = false // Pour le style du bouton de fermeture
    @State private var isHoveringRow = false // Pour le style général de la ligne

    var body: some View {
        HStack(spacing: 6) { // Espacement entre le texte et le bouton de fermeture
            // Contenu principal de l'onglet (titre, URL)
            VStack(alignment: .leading, spacing: 1) { // Espacement réduit entre titre et URL
                Text(tab.displayTitle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    // La couleur de sélection est gérée par List, mais on peut la forcer si besoin.
                    // .foregroundColor(isSelected ? .white : .primary) // Si List ne fait pas le style correctement
                
                // Afficher l'hôte de l'URL ou "Page vide"
                if let host = tab.displayURL?.host?.replacingOccurrences(of: "www.", with: ""), !host.isEmpty {
                    Text(host)
                        .font(.caption2) // Plus petit pour l'URL
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if tab.urlString == "about:blank" || tab.urlString.isEmpty {
                     Text("Page vide")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer() // Pousse le bouton de fermeture vers la droite
            
            // Bouton de fermeture, visible si la ligne est survolée ou sélectionnée
            if isHoveringRow || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption) // Taille appropriée pour une icône de fermeture d'onglet
                        .padding(2) // Petite zone de clic supplémentaire
                }
                .buttonStyle(.plain) // Style sans bordure/fond, typique pour les sidebars
                .foregroundColor(isHoveringCloseButton ? .primary : .secondary) // Change de couleur au survol du bouton
                .opacity(isHoveringCloseButton || isSelected ? 1.0 : 0.7) // Plus opaque si survolé ou sélectionné
                .onHover { hovering in
                    isHoveringCloseButton = hovering
                }
            }
        }
        // Le padding est géré par le style de la List. Si vous voulez un padding personnalisé :
        // .padding(.vertical, 4)
        // .padding(.horizontal, 8)
        
        // Le fond de sélection est géré par List(selection: ...).
        // Si vous voulez un fond personnalisé au survol (non sélectionné) :
        // .background(isHoveringRow && !isSelected ? Color.primary.opacity(0.05) : Color.clear)
        // .cornerRadius(4) // Si vous ajoutez un fond personnalisé

        .contentShape(Rectangle()) // Assure que toute la zone de la HStack est cliquable pour onSelect
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHoveringRow = hovering
        }
    }
}
