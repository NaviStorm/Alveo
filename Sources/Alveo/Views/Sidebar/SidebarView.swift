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
    private var tabsList: some View {
        List(selection: $pane.currentTabID) {
            // Grouper les onglets en vue fractionnée sur la même ligne
            if pane.isSplitViewActive {
                splitViewTabsRow
            }
            
            // Onglets normaux (non fractionnés)
            ForEach(pane.tabsForDisplay.filter { !pane.splitViewTabIDs.contains($0.id) }) { tab in
                createTabRow(for: tab)
                    .tag(tab.id)
            }
        }
        .listStyle(.sidebar)
        .contextMenu {
            if selectedTabIDs.count > 1 {
                Button("Vue fractionnée") {
                    enableSplitViewWithSelectedTabs()
                }
            }
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
            if selectedTabIDs.contains(tab.id) {
                selectedTabIDs.remove(tab.id)
            } else {
                selectedTabIDs.insert(tab.id)
            }
        } else {
            selectedTabIDs = [tab.id]
            if pane.currentTabID != tab.id {
                pane.currentTabID = tab.id
            }
        }
        
        tab.lastAccessed = Date()
    }
    
    private func handleTabClose(_ tab: Tab) {
        print("[SidebarView] Fermeture de l'onglet: '\(tab.displayTitle)'")
        handleCloseTabInSidebar(tabToClose: tab, currentPane: pane)
    }
    
    private func handleToggleSplitView(_ tab: Tab) {
        if pane.isSplitViewActive {
            // Ajouter l'onglet à la vue fractionnée existante
            pane.addTabToSplitView(tab.id)
        } else {
            // Créer une nouvelle vue fractionnée avec l'onglet actuel + un onglet vide
            pane.addTab(urlString: "about:blank")
            if let newTabID = pane.currentTab?.id {
                pane.enableSplitView(with: [tab.id, newTabID])
            }
        }
    }
    
    private func enableSplitViewWithSelectedTabs() {
        guard selectedTabIDs.count > 1 else { return }
        
        let tabIDsArray = Array(selectedTabIDs)
        pane.enableSplitView(with: tabIDsArray)
        selectedTabIDs.removeAll()
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


