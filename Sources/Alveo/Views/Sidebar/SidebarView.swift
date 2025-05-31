import SwiftUI
import SwiftData

@MainActor
struct SidebarView: View {
    @Bindable var pane: AlveoPane
    @ObservedObject var webViewHelper: WebViewHelper
    @Environment(\.modelContext) private var modelContext
    
    // Query pour récupérer tous les espaces (pour le menu "Déplacer vers")
    @Query(sort: \AlveoPane.creationDate, order: .forward) private var allAlveoPanes: [AlveoPane]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider()
            tabsList
        }
    }
    
    // MARK: - Sous-vues décomposées
    
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
            ForEach(pane.tabsForDisplay) { tab in
                createTabRow(for: tab)
                    .tag(tab.id)
            }
        }
        .listStyle(.sidebar)
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
            }
        )
    }
    
    // MARK: - Actions décomposées
    
    private func handleTabSelection(_ tab: Tab) {
        print(">>> [SidebarTabRow onSelect] Clic sur onglet: '\(tab.displayTitle)', ID: \(tab.id)")
        if pane.currentTabID != tab.id {
            pane.currentTabID = tab.id
        }
        tab.lastAccessed = Date()
    }
    
    private func handleTabClose(_ tab: Tab) {
        print("[SidebarView] Fermeture de l'onglet: '\(tab.displayTitle)'")
        handleCloseTabInSidebar(tabToClose: tab, currentPane: pane)
    }

    private func handleCloseTabInSidebar(tabToClose: Tab, currentPane: AlveoPane) {
        let tabIDToClose = tabToClose.id
        let wasSelected = currentPane.currentTabID == tabIDToClose
        
        guard let indexToRemove = currentPane.tabs.firstIndex(where: { $0.id == tabIDToClose }) else {
            print("[SidebarView handleCloseTab] Erreur: Onglet à fermer non trouvé dans la collection.")
            return
        }
        
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

