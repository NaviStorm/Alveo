import SwiftUI
import SwiftData

@MainActor
struct ContentView: View {
    // MARK: - Environment & Queries
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlveoPane.creationDate, order: .forward) private var alveoPanes: [AlveoPane]
    
    // MARK: - State Variables
    @State private var activeAlveoPaneID: UUID?
    @State private var webViewHelpers: [UUID: WebViewHelper] = [:]
    
    @State private var toolbarURLInput: String = ""
    @State private var showToolbarSuggestions: Bool = false
    @State private var filteredToolbarHistory: [HistoryItem] = []
    @FocusState private var isToolbarAddressBarFocused: Bool
    
    @State private var showAddAlveoPaneDialog = false
    @State private var newAlveoPaneName: String = ""
    @State private var initialAlveoPaneURLString: String = "https://www.google.com"

    // MARK: - Computed Properties
    var currentActiveAlveoPaneObject: AlveoPane? {
        guard let activeID = activeAlveoPaneID else { return alveoPanes.first }
        return alveoPanes.first(where: { $0.id == activeID })
    }
    
    private var currentWebViewHelperFromDict: WebViewHelper? {
        guard let activeID = activeAlveoPaneID else { return nil }
        return webViewHelpers[activeID]
    }
    
    // MARK: - Action Handlers for Keyboard Shortcuts
    private func createNewTabAction() {
        print("[ContentView ACTION] Nouvel Onglet (Cmd-T)")
        guard let activePane = currentActiveAlveoPaneObject else {
            print("[ContentView ACTION] Aucun espace actif pour créer un onglet.")
            if alveoPanes.isEmpty {
                createDefaultPaneIfNeeded()
            }
            return
        }
        activePane.addTab(urlString: "about:blank")
    }

    private func closeCurrentTabOrWindowAction() {
        print("[ContentView ACTION] Fermer Onglet ou Fenêtre (Cmd-W)")
        if let activePane = currentActiveAlveoPaneObject,
           let currentTabID = activePane.currentTabID,
           let tabToClose = activePane.tabs.first(where: { $0.id == currentTabID }) {
            
            print("[ContentView ACTION] Fermeture de l'onglet: '\(tabToClose.displayTitle)'")
            
            let tabIDToClose = tabToClose.id
            guard let indexToRemove = activePane.tabs.firstIndex(where: { $0.id == tabIDToClose }) else { return }
            
            modelContext.delete(tabToClose)

            if activePane.tabs.isEmpty {
                activePane.currentTabID = nil
                print("[ContentView ACTION] Dernier onglet fermé. Espace vide.")
            } else {
                var newIndexToSelect = indexToRemove
                if newIndexToSelect >= activePane.tabs.count {
                    newIndexToSelect = activePane.tabs.count - 1
                }
                
                if newIndexToSelect >= 0 && newIndexToSelect < activePane.tabs.count {
                    activePane.currentTabID = activePane.tabs[newIndexToSelect].id
                } else if !activePane.tabs.isEmpty {
                    activePane.currentTabID = activePane.tabs.first!.id
                } else {
                    activePane.currentTabID = nil
                }
            }
        } else {
            print("[ContentView ACTION] Aucun onglet actif. Fermeture de la fenêtre.")
            NSApplication.shared.keyWindow?.close()
        }
    }
    
    // MARK: - Helper Management (Contextes Sûrs)
    private func createAndStoreWebViewHelper(for paneID: UUID) -> WebViewHelper {
        if let existingHelper = webViewHelpers[paneID] {
            print("[ContentView createAndStore] Helper existant pour \(paneID): \(existingHelper.id)")
            return existingHelper
        }
        print("[ContentView createAndStore] Création nouveau helper pour \(paneID)")
        let newHelper = WebViewHelper(customUserAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15")
        newHelper.onNavigationEvent = { newURL, newTitle in
            self.handleNavigationEvent(forPaneID: paneID, newURL: newURL, newTitle: newTitle)
        }
        webViewHelpers[paneID] = newHelper
        return newHelper
    }

    private func ensureWebViewHelperExists(for paneID: UUID) -> WebViewHelper {
        if let existingHelper = webViewHelpers[paneID] {
            return existingHelper
        }
        return createAndStoreWebViewHelper(for: paneID)
    }
    
    // MARK: - State & Navigation Logic
    private func handleNavigationEvent(forPaneID paneID: UUID, newURL: URL?, newTitle: String?) {
        guard let paneForEvent = alveoPanes.first(where: { $0.id == paneID }),
              let tabIDForEvent = paneForEvent.currentTabID,
              let tabForEvent = paneForEvent.tabs.first(where: { $0.id == tabIDForEvent }) else {
            print("[Callback NavEvent] Pane ou Tab non trouvé pour paneID: \(paneID)")
            return
        }

        var tabModelUpdated = false
        if let urlAbsoluteString = newURL?.absoluteString, tabForEvent.urlString != urlAbsoluteString {
            tabForEvent.urlString = urlAbsoluteString
            print("[Callback NavEvent] URL mise à jour: \(urlAbsoluteString)")
            tabModelUpdated = true
        }
        if let title = newTitle, !title.isEmpty, tabForEvent.title != title {
            tabForEvent.title = title
            print("[Callback NavEvent] Titre mis à jour: \(title)")
            tabModelUpdated = true
        }
        
        if tabModelUpdated &&
           paneID == self.activeAlveoPaneID &&
           tabIDForEvent == self.currentActiveAlveoPaneObject?.currentTabID &&
           !self.isToolbarAddressBarFocused {
            
            if let currentTabActualURL = newURL?.absoluteString, toolbarURLInput != currentTabActualURL {
                 toolbarURLInput = currentTabActualURL
                 print("[Callback NavEvent] toolbarURLInput mis à jour: \(currentTabActualURL)")
            }
        }
    }
    
    private func saveCurrentTabState(forPaneID paneID: UUID?, forTabID tabID: UUID?) {
        guard let paneIdToSave = paneID, let tabIdToSave = tabID,
              let paneToSave = alveoPanes.first(where: { $0.id == paneIdToSave }),
              let tabToSave = paneToSave.tabs.first(where: { $0.id == tabIdToSave }),
              let helperToSaveFrom = webViewHelpers[paneIdToSave] else {
            return
        }
        if let currentURL = helperToSaveFrom.currentURL {
            tabToSave.urlString = currentURL.absoluteString
        }
        if let currentTitle = helperToSaveFrom.pageTitle, !currentTitle.isEmpty {
            tabToSave.title = currentTitle
        }
        tabToSave.lastAccessed = Date()
        print("[ContentView saveCurrentTabState] État sauvegardé pour onglet \(tabIdToSave)")
    }
    
    private func updateToolbarURLInputAndLoadIfNeeded(forPaneID paneID: UUID, forceLoad: Bool = false) {
        print(">>> [UpdateToolbar] forceLoad: \(forceLoad), paneID: \(paneID)")
        guard let pane = alveoPanes.first(where: { $0.id == paneID }) else {
            toolbarURLInput = ""
            print("[UpdateToolbar] Espace non trouvé")
            return
        }
        let paneWebViewHelper = ensureWebViewHelperExists(for: pane.id)
        var urlStringToSetForToolbar = "about:blank"
        var urlToActuallyLoad: URL? = nil
        
        if let currentTabId = pane.currentTabID, let tabToLoad = pane.tabs.first(where: { $0.id == currentTabId }) {
            print("[UpdateToolbar] Onglet actif: '\(tabToLoad.displayTitle)', URL: \(tabToLoad.urlString)")
            urlStringToSetForToolbar = tabToLoad.urlString
            if forceLoad { urlToActuallyLoad = tabToLoad.displayURL }
        } else if let firstTab = pane.tabsForDisplay.first {
            print("[UpdateToolbar] Sélection du premier onglet: '\(firstTab.displayTitle)'")
            pane.currentTabID = firstTab.id
            urlStringToSetForToolbar = firstTab.urlString
            if forceLoad { urlToActuallyLoad = firstTab.displayURL }
        } else {
            print("[UpdateToolbar] Aucun onglet. Ajout d'un onglet vide.")
            pane.addTab(urlString: "about:blank")
            urlStringToSetForToolbar = "about:blank"
            if forceLoad, let newTab = pane.currentTab {
                urlToActuallyLoad = newTab.displayURL
            }
        }

        if toolbarURLInput != urlStringToSetForToolbar && !isToolbarAddressBarFocused {
            toolbarURLInput = urlStringToSetForToolbar
            print("[UpdateToolbar] toolbarURLInput mis à jour: \(toolbarURLInput)")
        }
        
        if let finalURLToLoad = urlToActuallyLoad {
            if forceLoad || paneWebViewHelper.currentURL?.absoluteString != finalURLToLoad.absoluteString {
                print(">>> [UpdateToolbar] CHARGEMENT: \(finalURLToLoad.absoluteString)")
                paneWebViewHelper.loadURL(finalURLToLoad)
            }
        } else if forceLoad && (urlStringToSetForToolbar == "about:blank" || urlStringToSetForToolbar.isEmpty) {
            if let blankURL = URL(string: "about:blank") {
                print(">>> [UpdateToolbar] Chargement about:blank")
                paneWebViewHelper.loadURL(blankURL)
            }
        }
    }
    
    private func fetchToolbarHistorySuggestions(for query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            filteredToolbarHistory = []
            return
        }
        let predicate = #Predicate<HistoryItem> {
            $0.urlString.localizedStandardContains(trimmedQuery) ||
            ($0.title?.localizedStandardContains(trimmedQuery) ?? false)
        }
        let sortDescriptor = SortDescriptor(\HistoryItem.lastVisitedDate, order: .reverse)
        var fetchDescriptor = FetchDescriptor(predicate: predicate, sortBy: [sortDescriptor])
        fetchDescriptor.fetchLimit = 7
        do {
            filteredToolbarHistory = try modelContext.fetch(fetchDescriptor)
        } catch {
            print("ERREUR fetchToolbarHistorySuggestions: \(error)")
            filteredToolbarHistory = []
        }
    }
    
    private func addAlveoPane(name: String? = nil, withURL url: URL) {
        saveCurrentTabState(forPaneID: activeAlveoPaneID, forTabID: currentActiveAlveoPaneObject?.currentTabID)
        
        let paneName = name ?? "Espace \(alveoPanes.count + 1)"
        let newPane = AlveoPane(name: paneName, initialTabURLString: url.absoluteString)
        modelContext.insert(newPane)
        print("[ContentView addAlveoPane] Nouvel Espace créé: '\(paneName)'")
        activeAlveoPaneID = newPane.id
    }
    
    private func createDefaultPaneIfNeeded() {
        if alveoPanes.isEmpty {
            print("[ContentView createDefaultPaneIfNeeded] Création de l'Espace par défaut")
            let defaultURL = URL(string: initialAlveoPaneURLString) ?? URL(string: "about:blank")!
            addAlveoPane(name: "Mon Premier Espace", withURL: defaultURL)
        } else {
            print("[ContentView createDefaultPaneIfNeeded] Des Espaces existent déjà")
            if activeAlveoPaneID == nil {
                activeAlveoPaneID = alveoPanes.first?.id
                print("[ContentView createDefaultPaneIfNeeded] Sélection du premier espace")
            }
        }
    }
    
    // MARK: - View Builders
    private func resetAddAlveoPaneDialogFields() {
        newAlveoPaneName = ""
        initialAlveoPaneURLString = "https://www.google.com"
    }

    @ViewBuilder
    private var noActivePanesView: some View {
        VStack {
            Text("Bienvenue dans Alveo !")
                .font(.largeTitle)
            Text("Créez votre premier Espace pour commencer.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Créer un Espace Manuellement") {
                showAddAlveoPaneDialog = true
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addAlveoPaneDialog() -> some View {
        VStack {
            Text("Nouvel Espace")
                .font(.headline)
                .padding(.bottom)
            TextField("Nom de l'Espace (optionnel)", text: $newAlveoPaneName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("URL initiale de l'onglet", text: $initialAlveoPaneURLString)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(.URL)
            HStack {
                Button("Annuler") {
                    showAddAlveoPaneDialog = false
                    resetAddAlveoPaneDialogFields()
                }
                Spacer()
                Button("Ajouter") {
                    let urlToLoad = URL(string: initialAlveoPaneURLString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "about:blank")!
                    let nameToSet = newAlveoPaneName.trimmingCharacters(in: .whitespacesAndNewlines)
                    addAlveoPane(name: nameToSet.isEmpty ? nil : nameToSet, withURL: urlToLoad)
                    showAddAlveoPaneDialog = false
                    resetAddAlveoPaneDialogFields()
                }
                .disabled(initialAlveoPaneURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top)
        }
        .padding()
        .frame(minWidth: 350, idealHeight: 180)
    }
    
    @ToolbarContentBuilder
    private func mainToolbarContent(geometry: GeometryProxy, using helper: WebViewHelper) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                if helper.canGoBack { helper.goBack() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!helper.canGoBack)
            
            Button {
                if helper.canGoForward { helper.goForward() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!helper.canGoForward)
        }
        
        ToolbarItem(placement: .principal) {
            PrincipalToolbarView(
                webViewHelper: helper,
                urlInput: $toolbarURLInput,
                showSuggestions: $showToolbarSuggestions,
                filteredHistory: $filteredToolbarHistory,
                isFocused: $isToolbarAddressBarFocused,
                geometryProxy: geometry,
                fetchHistoryAction: { queryText in
                    fetchToolbarHistorySuggestions(for: queryText)
                }
            )
        }
        
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(alveoPanes) { paneItem in
                    Button {
                        saveCurrentTabState(forPaneID: activeAlveoPaneID, forTabID: currentActiveAlveoPaneObject?.currentTabID)
                        activeAlveoPaneID = paneItem.id
                    } label: {
                        HStack {
                            Text(paneItem.name ?? "Espace")
                            if paneItem.id == activeAlveoPaneID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("Nouvel Espace...") {
                    showAddAlveoPaneDialog = true
                }
                if let paneID = activeAlveoPaneID,
                   let paneToDelete = alveoPanes.first(where: { $0.id == paneID }) {
                    Button("Supprimer l'Espace Actif", role: .destructive) {
                        webViewHelpers.removeValue(forKey: paneToDelete.id)
                        modelContext.delete(paneToDelete)
                    }
                }
            } label: {
                Label("Espaces", systemImage: "square.stack.3d.down.right")
            }
            
            Button {
                currentActiveAlveoPaneObject?.addTab(urlString: "about:blank")
            } label: {
                Image(systemName: "plus.circle")
            }
            
            Button {
                helper.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(helper.isLoading)
        }
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                HSplitView {
                    // Volet Sidebar
                    if let activePaneToDisplay = currentActiveAlveoPaneObject {
                        if let helperForSidebar = webViewHelpers[activePaneToDisplay.id] {
                            SidebarView(pane: activePaneToDisplay, webViewHelper: helperForSidebar)
                                .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                        } else {
                            ProgressView()
                                .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                                .onAppear {
                                    let _ = ensureWebViewHelperExists(for: activePaneToDisplay.id)
                                }
                        }
                    } else {
                        Text("Aucun espace.")
                            .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                            .background(Color(NSColor.controlBackgroundColor))
                    }
                    
                    // Volet Contenu Principal
                    Group {
                        if let activePaneToDisplay = currentActiveAlveoPaneObject {
                            if let helperForContent = webViewHelpers[activePaneToDisplay.id] {
                                ActiveAlveoPaneContainerView(
                                    pane: activePaneToDisplay,
                                    webViewHelper: helperForContent,
                                    globalURLInput: $toolbarURLInput
                                )
                            } else {
                                ProgressView()
                                    .onAppear {
                                        let _ = ensureWebViewHelperExists(for: activePaneToDisplay.id)
                                    }
                            }
                        } else {
                            noActivePanesView
                        }
                    }
                }
                .toolbar {
                    if let helperForToolbar = currentWebViewHelperFromDict {
                        mainToolbarContent(geometry: geometry, using: helperForToolbar)
                    } else {
                        ToolbarItemGroup(placement: .principal) {
                            Text("Alveo")
                        }
                    }
                }
                .onAppear {
                    print("[CV .onAppear] alveoPanes.count: \(alveoPanes.count)")
                    createDefaultPaneIfNeeded()
                    
                    if let currentID = activeAlveoPaneID {
                        let _ = ensureWebViewHelperExists(for: currentID)
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: currentID, forceLoad: true)
                    }
                    DispatchQueue.main.async {
                        NSApplication.shared.windows.first { $0.isMainWindow }?.title = ""
                    }
                }
                .onChange(of: alveoPanes.count) { oldValue, newValue in
                    print("[CV .onChange(alveoPanes.count)] \(oldValue) -> \(newValue)")
                    let previousActiveID = activeAlveoPaneID
                    if let activeID = activeAlveoPaneID, !alveoPanes.contains(where: { $0.id == activeID }) {
                        activeAlveoPaneID = alveoPanes.first?.id
                    } else if activeAlveoPaneID == nil && !alveoPanes.isEmpty {
                        activeAlveoPaneID = alveoPanes.first?.id
                    }
                    
                    let currentPaneIDs = Set(alveoPanes.map { $0.id })
                    webViewHelpers = webViewHelpers.filter { currentPaneIDs.contains($0.key) }
                    
                    if previousActiveID != activeAlveoPaneID {
                        // Géré par .onChange(of: activeAlveoPaneID)
                    } else if let currentID = activeAlveoPaneID {
                         updateToolbarURLInputAndLoadIfNeeded(forPaneID: currentID, forceLoad: true)
                    }
                }
                .onChange(of: activeAlveoPaneID) { oldValue, newValue in
                    print(">>> [CV .onChange(activeAlveoPaneID)] \(String(describing: oldValue)) -> \(String(describing: newValue))")
                    if let oldPaneID = oldValue,
                       let oldPane = alveoPanes.first(where: {$0.id == oldPaneID}) {
                         saveCurrentTabState(forPaneID: oldPaneID, forTabID: oldPane.currentTabID)
                    }
                    if let newPaneID = newValue {
                        let _ = ensureWebViewHelperExists(for: newPaneID)
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: newPaneID, forceLoad: true)
                    } else {
                        toolbarURLInput = ""
                    }
                }
                .onChange(of: currentActiveAlveoPaneObject?.currentTabID) { oldValue, newValue in
                    print(">>> [CV .onChange(currentTabID)] \(String(describing: oldValue)) -> \(String(describing: newValue))")
                    if let paneID = currentActiveAlveoPaneObject?.id {
                        saveCurrentTabState(forPaneID: paneID, forTabID: oldValue)
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: paneID, forceLoad: true)
                    }
                }
                .sheet(isPresented: $showAddAlveoPaneDialog) {
                    addAlveoPaneDialog()
                }
                
                // Écouteurs pour les notifications des items de menu
                .onReceive(NotificationCenter.default.publisher(for: .createNewTabFromMenu)) { _ in
                    createNewTabAction()
                }
                .onReceive(NotificationCenter.default.publisher(for: .closeTabOrWindowFromMenu)) { _ in
                    closeCurrentTabOrWindowAction()
                }
            }
        }
        // Boutons invisibles pour les raccourcis clavier
        .background(
            ZStack {
                Button(action: createNewTabAction) { EmptyView() }
                    .keyboardShortcut("t", modifiers: .command)
                
                Button(action: closeCurrentTabOrWindowAction) { EmptyView() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        )
    }
}

