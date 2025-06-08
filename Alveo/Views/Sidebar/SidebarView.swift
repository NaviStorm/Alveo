Alveo/Views/Sidebar/SidebarView.swift
import SwiftUI
import SwiftData

@MainActor
struct SidebarView: View {
    @Bindable var pane: AlveoPane
    @ObservedObject var webViewHelper: WebViewHelper
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \AlveoPane.creationDate, order: .forward) private var allAlveoPanes: [AlveoPane]
    
    @State private var selectedTabIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider()
            tabsList
        }
        .onReceive(NotificationCenter.default.publisher(for: .enableSplitViewWithSelection)) { notification in
            if let paneID = notification.object as? UUID, paneID == pane.id {
                enableSplitViewWithSelectedTabs()
            }
        }
    }
    
    @ViewBuilder
    private var sidebarHeader: some View {
        HStack {
            Text(pane.name ?? "Espace")
                .font(.headline)
                .lineLimit(1)
                .padding(.leading, 12)
            Spacer()
            addTabButton
        }
        .frame(height: 38)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private var addTabButton: some View {
        Button {
            print("[SidebarView] Bouton '+' cliqué pour l'espace '\(pane.name ?? "")'")
            pane.addTab(urlString: "about:blank")
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .padding(.trailing, 12)
    }

    @ViewBuilder
    private func tabListItemView(for tab: Tab) -> some View {
        SidebarTabRow(
            tab: tab,
            pane: pane, // Pass the current pane
            allPanes: allAlveoPanes, // Pass the list of all panes
            isSelected: tab.id == pane.currentTabID || pane.selectedTabIDs.contains(tab.id),
            onSelect: {
                handleTabSelection(tab) // Use existing handler
            },
            onClose: {
                handleTabClose(tab) // Use existing handler
            },
            onToggleSplitView: {
                handleToggleSplitView(tab) // Use existing handler
            }
        )
        .tag(tab.id) // Tag for List selection
        .contextMenu {
            Button("Fermer l’onglet") {
                // Corrected call to removeTab with the 'tab:' label
                pane.removeTab(tab: tab)
                pane.selectedTabIDs.remove(tab.id)
            }

            if pane.selectedTabIDs.count > 1 {
                Button("Fermer les \(pane.selectedTabIDs.count) onglets sélectionnés") {
                    for id in pane.selectedTabIDs {
                        if let t = pane.tabs.first(where: { $0.id == id }) {
                            // Corrected call to removeTab with the 'tab:' label
                            pane.removeTab(tab: t)
                        }
                    }
                    pane.selectedTabIDs.removeAll()
                }
            }
        }
    }

    @ViewBuilder
    private var tabsList: some View {
        List(selection: $pane.selectedTabIDs) {
            ForEach(pane.tabs) { tab in
                tabListItemView(for: tab)
            }
        }
        .contextMenu {
            // Menu contextuel existant...
            
            // ✅ Nouvelle option pour vue fractionnée avec sélection multiple
            if pane.selectedTabIDs.count > 1 {
                Divider()
                Button("Vue fractionnée avec les \(pane.selectedTabIDs.count) onglets sélectionnés") {
                    enableSplitViewWithSelectedTabs()
                }
            }
        }
        .onChange(of: pane.selectedTabIDs) { oldSelection, newSelection in
            print("[SidebarView] Sélection changée: \(oldSelection) -> \(newSelection)")
            
            // Si un seul onglet est sélectionné, le définir comme actif
            if newSelection.count == 1, let singleSelectedID = newSelection.first {
                if pane.currentTabID != singleSelectedID {
                    pane.currentTabID = singleSelectedID
                }
            }
            // Si plusieurs onglets sont sélectionnés, garder l'onglet actif actuel
            // Si aucun onglet n'est sélectionné, ne pas changer l'onglet actif
        }
    }
    
    
    @ViewBuilder
    private var splitViewTabsRow: some View {
        HStack(spacing: 4) {
            ForEach(pane.splitViewTabs) { tab in
                createMiniTabRow(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func createMiniTabRow(for tab: Tab) -> some View {
        HStack(spacing: 4) {
            // Icône
            Group {
                if let emoji = tab.customEmojiIcon {
                    Text(emoji).font(.system(size: 12))
                } else {
                    Image(systemName: "globe").font(.system(size: 10))
                }
            }
            .frame(width: 12, height: 12)
            
            // Titre tronqué
            Text(tab.displayTitle)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundColor(tab.id == pane.currentTabID ? .accentColor : .primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(tab.id == pane.currentTabID ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor, lineWidth: tab.id == pane.currentTabID ? 1 : 0)
        )
        .onTapGesture {
            pane.currentTabID = tab.id
            tab.lastAccessed = Date()
        }
    }
    
    @ViewBuilder
    private func createTabRow(for tab: Tab) -> some View {
        SidebarTabRow(
            tab: tab,
            pane: pane,
            allPanes: allAlveoPanes,
            isSelected: tab.id == pane.currentTabID,
            onSelect: {
                handleTabSelection(tab)
            },
            onClose: {
                handleTabClose(tab)
            },
            onToggleSplitView: {
                handleToggleSplitView(tab)
            }
        )
    }
    
    // MARK: - Actions
    private func handleTabSelection(_ tab: Tab) {
        print(">>> [SidebarTabRow onSelect] Clic sur onglet: '\(tab.displayTitle)', ID: \(tab.id)")
        
        // Gestion de la sélection multiple avec Cmd
        if NSEvent.modifierFlags.contains(.command) {
            if pane.selectedTabIDs.contains(tab.id) {
                pane.selectedTabIDs.remove(tab.id)
            } else {
                pane.selectedTabIDs.insert(tab.id)
            }
        } else {
            // ✅ Sélection simple : effacer la sélection multiple et définir l'onglet actif
            pane.selectedTabIDs.removeAll() // Vider la sélection multiple
            pane.selectedTabIDs.insert(tab.id) // Ajouter seulement l'onglet sélectionné
            if pane.currentTabID != tab.id {
                pane.currentTabID = tab.id
            }
        }
        
        tab.lastAccessed = Date()
    }
    
    private func handleTabClose(_ tab: Tab) {
        print("[SidebarView] Fermeture de l'onglet: '\(tab.displayTitle)'")
        
        // ✅ Retirer de la sélection multiple
        pane.selectedTabIDs.remove(tab.id)
        
        handleCloseTabInSidebar(tabToClose: tab, currentPane: pane)
    }
    
    private func handleToggleSplitView(_ tab: Tab) {
        if pane.isSplitViewActive {
            // Ajouter l'onglet à la vue fractionnée existante
            pane.addTabToSplitView(tab.id)
            if let newTabID = pane.currentTab?.id { // Après pane.addTab(...)
                pane.enableSplitView(with: [tab.id, newTabID]) // Correction ici
            }
        } else {
            // Créer une nouvelle vue fractionnée avec l'onglet actuel + un onglet vide
            pane.addTab(urlString: "about:blank")
            if let newTabID = pane.currentTab?.id {
                pane.enableSplitView(with: [tab.id, newTabID])
            }
        }
    }
    
    private func enableSplitViewWithSelectedTabs() {
        guard pane.selectedTabIDs.count > 1 else {
            print("[SidebarView] Pas assez d'onglets sélectionnés pour une vue fractionnée")
            return
        }
        
        let tabIDsArray = Array(pane.selectedTabIDs)
        print("[SidebarView] Activation de la vue fractionnée avec \(tabIDsArray.count) onglets: \(tabIDsArray)")
        
        // Activer la vue fractionnée avec tous les onglets sélectionnés
        pane.enableSplitView(with: tabIDsArray)
        
        // Définir le premier onglet sélectionné comme actif
        if let firstSelectedTabID = tabIDsArray.first {
            pane.currentTabID = firstSelectedTabID
        }
        
        // Vider la sélection après l'action
        pane.selectedTabIDs.removeAll()
        
        print("[SidebarView] Vue fractionnée activée avec les onglets sélectionnés")
    }

    private func handleCloseTabInSidebar(tabToClose: Tab, currentPane: AlveoPane) {
        let tabIDToClose = tabToClose.id
        let wasSelected = currentPane.currentTabID == tabIDToClose
        
        guard let indexToRemove = currentPane.tabs.firstIndex(where: { $0.id == tabIDToClose }) else {
            print("[SidebarView handleCloseTab] Erreur: Onglet à fermer non trouvé dans la collection.")
            return
        }
        
        // Retirer de la sélection multiple
        selectedTabIDs.remove(tabIDToClose)
        
        modelContext.delete(tabToClose)

        if wasSelected {
            selectNextTabAfterClose(currentPane: currentPane, indexToRemove: indexToRemove)
        }
    }
    
    private func selectNextTabAfterClose(currentPane: AlveoPane, indexToRemove: Int) {
        if currentPane.tabs.isEmpty {
            currentPane.currentTabID = nil
            print("[SidebarView handleCloseTab] Dernier onglet fermé. Espace '\(currentPane.name ?? "")' est maintenant vide.")
        } else {
            var newIndexToSelect = indexToRemove
            if newIndexToSelect >= currentPane.tabs.count {
                newIndexToSelect = currentPane.tabs.count - 1
            }
            
            if newIndexToSelect >= 0 && newIndexToSelect < currentPane.tabs.count {
                currentPane.currentTabID = currentPane.tabs[newIndexToSelect].id
            } else if !currentPane.tabs.isEmpty {
                currentPane.currentTabID = currentPane.tabs.first!.id
            } else {
                 currentPane.currentTabID = nil
            }
            
            print("[SidebarView handleCloseTab] Nouvel onglet sélectionné ID: \(String(describing: currentPane.currentTabID))")
        }
    }
}


