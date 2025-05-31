import SwiftUI
import SwiftData

@Model
final class AlveoPane {
    var id: UUID
    var name: String?
    var creationDate: Date
    var lastAccessed: Date?
    var currentTabID: UUID?
    
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
    
    func addTab(urlString: String) {
        let newTab = Tab(urlString: urlString.isEmpty ? "about:blank" : urlString)
        self.tabs.append(newTab)
        self.currentTabID = newTab.id
        self.lastAccessed = Date()
        print("[AlveoPane ADD_TAB] Espace '\(self.name ?? "")' Nouvel onglet ajouté: \(newTab.displayTitle), ID: \(newTab.id)")
    }

    func removeTab(tab: Tab) {
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
}
