import SwiftUI
import SwiftData

@Model
final class AlveoPane {
    var id: UUID
    var name: String?
    var creationDate: Date
    var lastAccessed: Date?
    var currentTabID: UUID?
    
    // Gestion des vues fractionnées
    var splitViewTabIDs: [UUID] = [] // IDs des onglets en vue fractionnée
    var isSplitViewActive: Bool = false
    var splitViewProportions: [Double] = [] // Proportions de largeur pour chaque onglet
    
    @Relationship(deleteRule: .cascade, inverse: \Tab.pane)
    var tabs: [Tab] = []

    init(id: UUID = UUID(), name: String? = nil, creationDate: Date = Date(), initialTabURLString: String? = nil) {
        self.id = id
        self.name = name
        self.creationDate = creationDate
        self.lastAccessed = creationDate
        
        if let urlString = initialTabURLString, !urlString.isEmpty {
            let initialTab = Tab(urlString: urlString)
            self.tabs.append(initialTab)
            self.currentTabID = initialTab.id
        } else {
            let defaultTab = Tab(urlString: "about:blank")
            self.tabs.append(defaultTab)
            self.currentTabID = defaultTab.id
        }
    }

    var currentTab: Tab? {
        guard let currentTabID = self.currentTabID else { return nil }
        return self.tabs.first(where: { $0.id == currentTabID })
    }

    var tabsForDisplay: [Tab] {
        tabs.sorted { $0.creationDate < $1.creationDate }
    }

    var sortedTabs: [Tab] {
        tabs.sorted { tab1, tab2 in
            guard let t1Date = tab1.lastAccessed else { return false }
            guard let t2Date = tab2.lastAccessed else { return true }
            return t1Date > t2Date
        }
    }
    
    // Onglets en vue fractionnée
    var splitViewTabs: [Tab] {
        return splitViewTabIDs.compactMap { id in
            tabs.first(where: { $0.id == id })
        }
    }
    
    func addTab(urlString: String) {
        let newTab = Tab(urlString: urlString.isEmpty ? "about:blank" : urlString)
        self.tabs.append(newTab)
        self.currentTabID = newTab.id
        self.lastAccessed = Date()
        print("[AlveoPane ADD_TAB] Espace '\(self.name ?? "")' Nouvel onglet ajouté: \(newTab.displayTitle), ID: \(newTab.id)")
    }

    func removeTab(tab: Tab) {
        // Retirer de la vue fractionnée si nécessaire
        if let index = splitViewTabIDs.firstIndex(of: tab.id) {
            splitViewTabIDs.remove(at: index)
            if splitViewProportions.count > index {
                splitViewProportions.remove(at: index)
            }
            // Si c'était le dernier onglet en vue fractionnée, désactiver
            if splitViewTabIDs.isEmpty {
                isSplitViewActive = false
            } else {
                // Redistribuer les proportions
                redistributeSplitViewProportions()
            }
        }
        
        if let indexToRemove = self.tabs.firstIndex(where: { $0.id == tab.id }) {
            let wasSelected = (self.currentTabID == tab.id)
            self.tabs.remove(at: indexToRemove)
            
            if wasSelected {
                if self.tabs.isEmpty {
                    self.currentTabID = nil
                } else {
                    let newIndex = min(indexToRemove, self.tabs.count - 1)
                    if newIndex >= 0 && newIndex < self.tabs.count {
                        self.currentTabID = self.tabs[newIndex].id
                    } else if !self.tabs.isEmpty {
                        self.currentTabID = self.tabs.first!.id
                    } else {
                        self.currentTabID = nil
                    }
                }
            }
        }
        self.lastAccessed = Date()
    }
    
    // MARK: - Méthodes pour la vue fractionnée
    
    func enableSplitView(with tabIDs: [UUID]) {
        guard tabIDs.count >= 1 else { return }
        
        splitViewTabIDs = tabIDs
        isSplitViewActive = true
        
        // Initialiser les proportions égales
        let proportion = 1.0 / Double(tabIDs.count)
        splitViewProportions = Array(repeating: proportion, count: tabIDs.count)
        
        // Définir le premier onglet comme actif
        if let firstTabID = tabIDs.first {
            currentTabID = firstTabID
        }
        
        print("[AlveoPane] Vue fractionnée activée avec \(tabIDs.count) onglets")
    }
    
    func disableSplitView() {
        isSplitViewActive = false
        splitViewTabIDs.removeAll()
        splitViewProportions.removeAll()
        print("[AlveoPane] Vue fractionnée désactivée")
    }
    
    func addTabToSplitView(_ tabID: UUID) {
        guard !splitViewTabIDs.contains(tabID) else { return }
        
        splitViewTabIDs.append(tabID)
        redistributeSplitViewProportions()
        
        if !isSplitViewActive {
            isSplitViewActive = true
        }
    }
    
    func removeTabFromSplitView(_ tabID: UUID) {
        guard let index = splitViewTabIDs.firstIndex(of: tabID) else { return }
        
        splitViewTabIDs.remove(at: index)
        if splitViewProportions.count > index {
            splitViewProportions.remove(at: index)
        }
        
        if splitViewTabIDs.isEmpty {
            disableSplitView()
        } else {
            redistributeSplitViewProportions()
        }
    }
    
    private func redistributeSplitViewProportions() {
        guard !splitViewTabIDs.isEmpty else { return }
        
        let proportion = 1.0 / Double(splitViewTabIDs.count)
        splitViewProportions = Array(repeating: proportion, count: splitViewTabIDs.count)
    }
    
    func updateSplitViewProportions(_ proportions: [Double]) {
        guard proportions.count == splitViewTabIDs.count else { return }
        splitViewProportions = proportions
    }
}

