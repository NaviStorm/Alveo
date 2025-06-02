import SwiftUI
import SwiftData

@MainActor
struct TabBarView: View {
    // @Bindable est correct ici car currentTabID est modifié
    @Bindable var pane: AlveoPane
    
    // Le WebViewHelper est celui de l'Espace actif, passé depuis ContentView
    @ObservedObject var webViewHelper: WebViewHelper
    
    // Utilisé pour la communication avec la barre d'adresse principale
    @Binding var globalURLInput: String
    
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // La barre d'onglets elle-même
        tabBarContent
            .frame(height: 30) // Hauteur fixe pour la barre d'onglets
            .background(Color(NSColor.windowBackgroundColor)) // Couleur de fond standard pour les barres
            .overlay( // Ajoute une ligne de séparation en bas
                Divider(), alignment: .bottom
            )
    }

    // Propriété calculée pour le contenu de la barre d'onglets
    @ViewBuilder
    private var tabBarContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) { // Pas d'espacement entre les boutons d'onglets, ils gèrent leur propre padding/marge
                // Utiliser la propriété qui trie par date de création pour un ordre stable
                // Assurez-vous que `pane.tabsForDisplay` existe et trie par `creationDate`.
                ForEach(pane.tabsForDisplay) { tab in
                    TabButton(
                        tab: tab,
                        pane: pane, // Passer le pane pour la gestion du currentTabID et la suppression
                        isSelected: pane.currentTabID == tab.id,
                        onSelect: {
                            print(">>> [TabBarView onSelect TabButton] TabID: \(tab.id)")
                            if pane.currentTabID != tab.id {
                                // La sauvegarde de l'ancien onglet est maintenant gérée par le .onChange dans ContentView
                                pane.currentTabID = tab.id // Déclenche .onChange dans ContentView
                            }
                            // La mise à jour de tab.lastAccessed est maintenant faite dans ContentView
                            // après la sélection pour éviter les problèmes de modification d'état.
                            // Ou, si TabButton le fait, s'assurer que ce n'est pas problématique.
                            // Pour simplifier, laissons ContentView le gérer.
                        },
                        onClose: {
                            print(">>> [TabBarView onClose TabButton] TabID: \(tab.id)")
                            handleCloseTab(tabToClose: tab)
                        }
                    )
                    .padding(.leading, pane.tabsForDisplay.first?.id == tab.id ? 4 : 0) // Léger padding pour le premier onglet
                    .padding(.trailing, 4) // Espacement après chaque onglet (sauf le dernier, implicitement)
                }
            }
            .padding(.horizontal, 4) // Padding horizontal pour le ScrollView
        }
    }

    // Logique pour fermer un onglet
    private func handleCloseTab(tabToClose: Tab) {
        let tabIDToClose = tabToClose.id
        let wasSelected = pane.currentTabID == tabIDToClose
        
        guard let indexToRemove = pane.tabs.firstIndex(where: { $0.id == tabIDToClose }) else {
            print("[TabBarView handleCloseTab] Erreur: Onglet à fermer non trouvé.")
            return
        }
        
        // Supprimer l'objet du ModelContext d'abord
        modelContext.delete(tabToClose)
        // SwiftData devrait mettre à jour `pane.tabs` après cela.

        // Logique pour sélectionner le prochain onglet si l'onglet fermé était actif
        if wasSelected {
            // La collection `pane.tabs` est maintenant (ou sera bientôt) mise à jour par SwiftData.
            // Pour être sûr d'opérer sur la liste à jour, on peut attendre un court instant
            // ou s'appuyer sur le fait que la modification de currentTabID va redessiner.
            // Pour l'instant, on opère sur la collection telle qu'elle est après la suppression.
            
            // Si vous ne supprimez pas manuellement de `pane.tabs` ici,
            // la logique de sélection du prochain index doit être plus robuste.
            // Pour l'instant, on suppose que `pane.tabs` est déjà mise à jour (ce qui est optimiste).
            
            // Pour plus de robustesse, laissons ContentView gérer la sélection du prochain onglet
            // lorsque `currentTabID` devient invalide après la suppression.
            // Ici, on pourrait simplement mettre currentTabID à nil si l'onglet actif est fermé.
            // ContentView.onChange(of: alveoPanes.count) et .onChange(of: currentTabID) géreront la suite.
            
            // Si l'onglet actif est celui qui est fermé, on doit invalider currentTabID
            // pour que ContentView puisse choisir le prochain.
            if pane.tabs.isEmpty { // S'il n'y a plus d'onglets
                pane.currentTabID = nil
            } else {
                // Si l'onglet fermé était sélectionné, essayons de sélectionner un autre.
                // La logique de sélection précise du "prochain" onglet peut être complexe.
                // Une approche simple est de sélectionner le premier disponible.
                // Ou, si vous avez l'index, celui d'avant ou d'après.
                
                // Si l'index est toujours valide dans la "future" liste (après suppression implicite par SwiftData)
                if indexToRemove < pane.tabs.count {
                    pane.currentTabID = pane.tabs[indexToRemove].id
                } else if !pane.tabs.isEmpty { // Sinon, prendre le nouveau dernier
                    pane.currentTabID = pane.tabs.last!.id
                } else {
                    pane.currentTabID = nil // Plus d'onglets
                }
            }
             print("[TabBarView handleCloseTab] Après suppression, currentTabID (potentiellement) mis à: \(String(describing: pane.currentTabID))")
        }
        // Le .onChange(of: currentActiveAlveoPaneObject?.currentTabID) dans ContentView
        // devrait se charger du reste (charger la page, ajouter un onglet vide si nécessaire).
    }
}
