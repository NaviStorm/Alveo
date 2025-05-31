import SwiftUI
import SwiftData

@MainActor
struct ContentView: View {
    // MARK: - Environment & Queries
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlveoPane.creationDate, order: .forward) private var alveoPanes: [AlveoPane]
    
    // MARK: - State Variables
    @State private var activeAlveoPaneID: UUID?
    @State private var webViewHelpers: [UUID: WebViewHelper] = [:] // Géré dans .onAppear/.onChange
    
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
    
    // MARK: - Helper Management (Contextes Sûrs)
    private func createAndStoreWebViewHelper(for paneID: UUID) -> WebViewHelper {
        if let existingHelper = webViewHelpers[paneID] {
            print("[ContentView createAndStore] Helper EXISTANT DÉJÀ pour \(paneID). Retourne existant: \(existingHelper.id)")
            return existingHelper
        }
        print("[ContentView createAndStore] Création NOUVEAU helper pour Espace ID: \(paneID)")
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
        guard let activePane = alveoPanes.first(where: { $0.id == paneID }),
              let activeTabID = activePane.currentTabID,
              let activeTab = activePane.tabs.first(where: { $0.id == activeTabID }) else {
            print("[Callback NavEvent] Pane ou Tab non trouvé pour paneID: \(paneID)")
            return
        }
        var tabModelUpdated = false
        if let urlAbsoluteString = newURL?.absoluteString, activeTab.urlString != urlAbsoluteString {
            activeTab.urlString = urlAbsoluteString
            print("[Callback NavEvent] Espace '\(activePane.name ?? "")' Onglet '\(activeTab.displayTitle)' URL DANS MODELE: \(urlAbsoluteString)")
            tabModelUpdated = true
        }
        if let title = newTitle, !title.isEmpty, activeTab.title != title {
            activeTab.title = title
            print("[Callback NavEvent] Espace '\(activePane.name ?? "")' Onglet '\(activeTab.displayTitle)' Titre DANS MODELE: \(title)")
            tabModelUpdated = true
        }
        if tabModelUpdated && activePane.id == self.activeAlveoPaneID && activeTab.id == self.currentActiveAlveoPaneObject?.currentTabID && !self.isToolbarAddressBarFocused {
            if let currentTabActualURL = newURL?.absoluteString, toolbarURLInput != currentTabActualURL {
                 toolbarURLInput = currentTabActualURL
                 print("[Callback NavEvent] toolbarURLInput mis à jour (car non focus) vers: \(currentTabActualURL)")
            }
        } else if tabModelUpdated {
            print("[Callback NavEvent] Modèle Tab mis à jour, mais toolbarURLInput NON modifié (raison: espace/onglet non actif OU barre focus). isToolbarAddressBarFocused = \(self.isToolbarAddressBarFocused)")
        }
    }
    
    private func saveCurrentTabState(forPaneID paneID: UUID?, forTabID tabID: UUID?) {
        guard let paneIdToSave = paneID, let tabIdToSave = tabID,
              let paneToSave = alveoPanes.first(where: { $0.id == paneIdToSave }),
              let tabToSave = paneToSave.tabs.first(where: { $0.id == tabIdToSave }),
              let helperToSaveFrom = webViewHelpers[paneIdToSave] else { return }
        if let currentURL = helperToSaveFrom.currentURL { tabToSave.urlString = currentURL.absoluteString }
        if let currentTitle = helperToSaveFrom.pageTitle { tabToSave.title = currentTitle }
        print("[ContentView saveCurrentTabState] État sauvegardé pour onglet ID \(tabIdToSave) dans Espace ID \(paneIdToSave)")
    }
    
    private func updateToolbarURLInputAndLoadIfNeeded(forPaneID paneID: UUID, forceLoad: Bool = false) {
        print(">>> [UpdateToolbar ENTER] forceLoad: \(forceLoad), Pour Espace ID: \(paneID)")
        guard let pane = alveoPanes.first(where: { $0.id == paneID }) else {
            toolbarURLInput = ""; print("[UpdateToolbar] Espace ID \(paneID) non trouvé."); return
        }
        let paneWebViewHelper = ensureWebViewHelperExists(for: pane.id)
        var urlStringToSetForToolbar = "about:blank"; var urlToActuallyLoad: URL? = nil
        
        if let currentTabId = pane.currentTabID, let tabToLoad = pane.tabs.first(where: { $0.id == currentTabId }) {
            print("[UpdateToolbar] Espace: '\(pane.name ?? "")', Onglet actif: '\(tabToLoad.displayTitle)', URL modèle: \(tabToLoad.urlString)")
            urlStringToSetForToolbar = tabToLoad.urlString
            if forceLoad { urlToActuallyLoad = tabToLoad.displayURL }
        } else if let firstTab = pane.sortedTabs.first {
            print("[UpdateToolbar] Espace: '\(pane.name ?? "")', Pas d'onglet actif, sélection du premier: '\(firstTab.displayTitle)'")
            pane.currentTabID = firstTab.id; urlStringToSetForToolbar = firstTab.urlString
        } else {
            print("[UpdateToolbar] Espace: '\(pane.name ?? "")', Aucun onglet. Ajout onglet vide.")
            pane.addTab(urlString: "about:blank"); urlStringToSetForToolbar = "about:blank"
        }
        if toolbarURLInput != urlStringToSetForToolbar && !isToolbarAddressBarFocused {
            toolbarURLInput = urlStringToSetForToolbar
            print("[UpdateToolbar] toolbarURLInput mis à jour vers: \(toolbarURLInput)")
        }
        if let finalURLToLoad = urlToActuallyLoad {
            if forceLoad || paneWebViewHelper.currentURL?.absoluteString != finalURLToLoad.absoluteString {
                print(">>> [UpdateToolbar] CHARGEMENT DEMANDÉ. Helper: \(paneWebViewHelper.id), URL: \(finalURLToLoad.absoluteString)")
                paneWebViewHelper.loadURL(finalURLToLoad)
            } else { print(">>> [UpdateToolbar] Non chargé (pas forceLoad et URL identique): \(finalURLToLoad.absoluteString)") }
        } else if forceLoad && (urlStringToSetForToolbar == "about:blank" || urlStringToSetForToolbar.isEmpty) {
            if let blankURL = URL(string: "about:blank") {
                print(">>> [UpdateToolbar] Forçage chargement about:blank. Helper: \(paneWebViewHelper.id)")
                paneWebViewHelper.loadURL(blankURL)
            }
        }
    }
    
    private func fetchToolbarHistorySuggestions(for query: String) { /* ... (Votre code existant) ... */
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { filteredToolbarHistory = []; return }
        let predicate = #Predicate<HistoryItem> {
            $0.urlString.localizedStandardContains(trimmedQuery) || ($0.title?.localizedStandardContains(trimmedQuery) ?? false)
        }
        let sortDescriptor = SortDescriptor(\HistoryItem.lastVisitedDate, order: .reverse)
        var fetchDescriptor = FetchDescriptor(predicate: predicate, sortBy: [sortDescriptor])
        fetchDescriptor.fetchLimit = 7
        do { filteredToolbarHistory = try modelContext.fetch(fetchDescriptor) }
        catch { print("ERREUR fetchToolbarHistorySuggestions: \(error)"); filteredToolbarHistory = [] }
    }
    
    private func addAlveoPane(name: String? = nil, withURL url: URL) {
        saveCurrentTabState(forPaneID: activeAlveoPaneID, forTabID: currentActiveAlveoPaneObject?.currentTabID)
        let paneName = name ?? "Espace \(alveoPanes.count + 1)"
        let newPane = AlveoPane(name: paneName, initialTabURLString: url.absoluteString)
        modelContext.insert(newPane); activeAlveoPaneID = newPane.id
    }
    
    // MARK: - Méthodes restaurées
    private func resetAddAlveoPaneDialogFields() {
        newAlveoPaneName = ""
        initialAlveoPaneURLString = "https://www.google.com" // Ou votre URL par défaut
    }

    @ViewBuilder
    private var noActivePanesView: some View {
        VStack {
            Text("Bienvenue dans Alveo !")
                .font(.largeTitle)
            Text("Créez votre premier Espace pour commencer.")
                .foregroundStyle(.secondary)
            Button("Créer le premier Espace") {
                addAlveoPane(withURL: URL(string: initialAlveoPaneURLString) ?? URL(string: "about:blank")!)
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
            TextField("URL initiale", text: $initialAlveoPaneURLString)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(.URL) // Aide pour la saisie automatique
            HStack {
                Button("Annuler") {
                    showAddAlveoPaneDialog = false
                    resetAddAlveoPaneDialogFields() // Réinitialiser les champs
                }
                Spacer()
                Button("Ajouter") {
                    let urlToLoad = URL(string: initialAlveoPaneURLString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "about:blank")!
                    let nameToSet = newAlveoPaneName.trimmingCharacters(in: .whitespacesAndNewlines)
                    addAlveoPane(name: nameToSet.isEmpty ? nil : nameToSet, withURL: urlToLoad)
                    showAddAlveoPaneDialog = false
                    resetAddAlveoPaneDialogFields() // Réinitialiser les champs
                }
                .disabled(initialAlveoPaneURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top)
        }
        .padding()
        .frame(minWidth: 300) // Taille minimale pour la sheet
    }
    
    // MARK: - Toolbar Content Builder
    @ToolbarContentBuilder
    private func mainToolbarContent(geometry: GeometryProxy, using helper: WebViewHelper) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { if helper.canGoBack { helper.goBack() } } label: { Image(systemName: "chevron.left") }
                .disabled(!helper.canGoBack)
            Button { if helper.canGoForward { helper.goForward() } } label: { Image(systemName: "chevron.right") }
                .disabled(!helper.canGoForward)
        }
        ToolbarItem(placement: .principal) {
            PrincipalToolbarView(
                webViewHelper: helper, urlInput: $toolbarURLInput, showSuggestions: $showToolbarSuggestions,
                filteredHistory: $filteredToolbarHistory, isFocused: $isToolbarAddressBarFocused,
                geometryProxy: geometry, fetchHistoryAction: { queryText in fetchToolbarHistorySuggestions(for: queryText) }
            )
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(alveoPanes) { paneItem in
                    Button {
                        saveCurrentTabState(forPaneID: activeAlveoPaneID, forTabID: currentActiveAlveoPaneObject?.currentTabID)
                        activeAlveoPaneID = paneItem.id
                    } label: { HStack { Text(paneItem.name ?? "Espace"); if paneItem.id == activeAlveoPaneID { Image(systemName: "checkmark") } } }
                }
                Divider()
                Button("Nouvel Espace...") { showAddAlveoPaneDialog = true }
                if let paneID = activeAlveoPaneID, let paneToDelete = alveoPanes.first(where: { $0.id == paneID }) {
                    Button("Supprimer l'Espace Actif", role: .destructive) {
                        webViewHelpers.removeValue(forKey: paneToDelete.id)
                        modelContext.delete(paneToDelete)
                    }
                }
            } label: { Label("Espaces", systemImage: "square.stack.3d.down.right") }
            Button { currentActiveAlveoPaneObject?.addTab(urlString: "about:blank") } label: { Image(systemName: "plus.circle") }
            Button { helper.reload() } label: { Image(systemName: "arrow.clockwise") }.disabled(helper.isLoading)
        }
    }
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                HSplitView {
                    if let activePaneToDisplay = currentActiveAlveoPaneObject {
                        if let helperForSidebar = webViewHelpers[activePaneToDisplay.id] {
                            SidebarView(pane: activePaneToDisplay, webViewHelper: helperForSidebar)
                                .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                        } else { ProgressView().frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                            let _ = print("[CV BODY sidebar] Espace \(activePaneToDisplay.id) actif mais helper manquant.") }
                    } else { Text("Aucun espace.").frame(minWidth: 180, idealWidth: 240, maxWidth: 400).background(Color(NSColor.controlBackgroundColor)) }
                    
                    Group {
                        if let activePaneToDisplay = currentActiveAlveoPaneObject {
                            if let helperForContent = webViewHelpers[activePaneToDisplay.id] {
                                ActiveAlveoPaneContainerView(pane: activePaneToDisplay, webViewHelper: helperForContent, globalURLInput: $toolbarURLInput)
                            } else { ProgressView()
                                let _ = print("[CV BODY content] Espace \(activePaneToDisplay.id) actif mais helper manquant.") }
                        } else { noActivePanesView }
                    }
                }
                .toolbar {
                    if let helperForToolbar = currentWebViewHelperFromDict {
                        mainToolbarContent(geometry: geometry, using: helperForToolbar)
                    } else { ToolbarItemGroup(placement: .principal) { Text("Alveo") }
                        let _ = print("[CV TOOLBAR] Aucun helper actif (activeAlveoPaneID: \(String(describing: activeAlveoPaneID))).") }
                }
                .onAppear {
                    print("[CV .onAppear] Début. activeAlveoPaneID: \(String(describing: activeAlveoPaneID))")
                    if activeAlveoPaneID == nil, let firstPane = alveoPanes.first {
                        activeAlveoPaneID = firstPane.id
                    } else if let currentID = activeAlveoPaneID {
                        let _ = ensureWebViewHelperExists(for: currentID)
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: currentID, forceLoad: true)
                    } else if alveoPanes.isEmpty { print("[CV .onAppear] Aucun espace existant.") }
                    DispatchQueue.main.async { NSApplication.shared.windows.first { $0.isMainWindow }?.title = "" }
                }
                .onChange(of: alveoPanes.count) { oldValue, newValue in
                    print("[CV .onChange(alveoPanes.count)] De \(oldValue) à \(newValue). activeID: \(String(describing: activeAlveoPaneID))")
                    let previousActiveID = activeAlveoPaneID
                    if let activeID = activeAlveoPaneID, !alveoPanes.contains(where: { $0.id == activeID }) {
                        activeAlveoPaneID = alveoPanes.first?.id
                    } else if activeAlveoPaneID == nil && !alveoPanes.isEmpty {
                        activeAlveoPaneID = alveoPanes.first?.id
                    }
                    let currentPaneIDs = Set(alveoPanes.map { $0.id })
                    webViewHelpers = webViewHelpers.filter { currentPaneIDs.contains($0.key) }
                    print("[CV .onChange(alveoPanes.count)] Helpers nettoyés. Nouvel activeID: \(String(describing: activeAlveoPaneID))")
                    if previousActiveID != activeAlveoPaneID, let newActiveID = activeAlveoPaneID {
                        // activeAlveoPaneID a changé, le .onChange(of: activeAlveoPaneID) va gérer.
                    } else if let currentID = activeAlveoPaneID { // ID actif n'a pas changé mais le count si
                         updateToolbarURLInputAndLoadIfNeeded(forPaneID: currentID, forceLoad: true)
                    }
                }
                .onChange(of: activeAlveoPaneID) { oldValue, newValue in
                    print(">>> [CV .onChange(activeAlveoPaneID)] DEBUT. Ancien: \(String(describing: oldValue)), Nouveau: \(String(describing: newValue))")
                    if let oldPaneID = oldValue, let oldPane = alveoPanes.first(where: {$0.id == oldPaneID}) {
                         saveCurrentTabState(forPaneID: oldPaneID, forTabID: oldPane.currentTabID)
                    }
                    if let newPaneID = newValue {
                        let _ = ensureWebViewHelperExists(for: newPaneID)
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: newPaneID, forceLoad: true)
                    } else { toolbarURLInput = "" }
                    print("<<< [CV .onChange(activeAlveoPaneID)] FIN.")
                }
                .onChange(of: currentActiveAlveoPaneObject?.currentTabID) { oldValue, newValue in
                    print(">>> [CV .onChange(currentTabID)] DEBUT. Espace: '\(currentActiveAlveoPaneObject?.name ?? "N/A")' AncienTID: \(String(describing: oldValue)), NouveauTID: \(String(describing: newValue))")
                    if let paneID = currentActiveAlveoPaneObject?.id {
                        saveCurrentTabState(forPaneID: paneID, forTabID: oldValue) // Sauvegarder l'état de l'ancien onglet
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: paneID, forceLoad: true)
                    }
                    print("<<< [CV .onChange(currentTabID)] FIN.")
                }
                .sheet(isPresented: $showAddAlveoPaneDialog) { addAlveoPaneDialog() }
            }
        }
    }
}
