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
        guard let activeID = activeAlveoPaneID else {
            // Si aucun ID n'est actif, mais qu'il y a des panneaux, prendre le premier.
            // Cela peut arriver au tout premier lancement après la création du panneau par défaut.
            return alveoPanes.first
        }
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
        guard let paneForEvent = alveoPanes.first(where: { $0.id == paneID }), // Important: utiliser paneForEvent
              let tabIDForEvent = paneForEvent.currentTabID,
              let tabForEvent = paneForEvent.tabs.first(where: { $0.id == tabIDForEvent }) else {
            print("[Callback NavEvent] Pane ou Tab non trouvé pour paneID: \(paneID) et son currentTabID \(String(describing: alveoPanes.first(where: { $0.id == paneID })?.currentTabID))")
            return
        }

        var tabModelUpdated = false
        if let urlAbsoluteString = newURL?.absoluteString, tabForEvent.urlString != urlAbsoluteString {
            tabForEvent.urlString = urlAbsoluteString
            print("[Callback NavEvent] Espace '\(paneForEvent.name ?? "")' Onglet '\(tabForEvent.displayTitle)' URL DANS MODELE: \(urlAbsoluteString)")
            tabModelUpdated = true
        }
        if let title = newTitle, !title.isEmpty, tabForEvent.title != title {
            tabForEvent.title = title
            print("[Callback NavEvent] Espace '\(paneForEvent.name ?? "")' Onglet '\(tabForEvent.displayTitle)' Titre DANS MODELE: \(title)")
            tabModelUpdated = true
        }
        
        // Mettre à jour toolbarURLInput si l'événement concerne l'espace et l'onglet actuellement actifs
        // ET que la barre d'adresse n'est pas focus.
        if tabModelUpdated &&
           paneID == self.activeAlveoPaneID &&
           tabIDForEvent == self.currentActiveAlveoPaneObject?.currentTabID && // Comparer avec currentTabID de l'espace actif
           !self.isToolbarAddressBarFocused {
            
            if let currentTabActualURL = newURL?.absoluteString, toolbarURLInput != currentTabActualURL {
                 toolbarURLInput = currentTabActualURL
                 print("[Callback NavEvent] toolbarURLInput mis à jour (car non focus) vers: \(currentTabActualURL)")
            }
        } else if tabModelUpdated {
            print("[Callback NavEvent] Modèle Tab mis à jour, mais toolbarURLInput NON modifié. Raisons possibles: paneID (\(paneID)) != activeAlveoPaneID (\(String(describing: self.activeAlveoPaneID))); tabIDForEvent (\(tabIDForEvent)) != currentActiveTabID (\(String(describing: self.currentActiveAlveoPaneObject?.currentTabID))); isToolbarAddressBarFocused (\(self.isToolbarAddressBarFocused))")
        }
    }
    
    private func saveCurrentTabState(forPaneID paneID: UUID?, forTabID tabID: UUID?) {
        guard let paneIdToSave = paneID, let tabIdToSave = tabID,
              let paneToSave = alveoPanes.first(where: { $0.id == paneIdToSave }),
              let tabToSave = paneToSave.tabs.first(where: { $0.id == tabIdToSave }),
              let helperToSaveFrom = webViewHelpers[paneIdToSave] else {
            // print("[ContentView saveCurrentTabState] Rien à sauvegarder (paneID, tabID, helper ou pane/tab non trouvés).")
            return
        }
        if let currentURL = helperToSaveFrom.currentURL { tabToSave.urlString = currentURL.absoluteString }
        if let currentTitle = helperToSaveFrom.pageTitle, !currentTitle.isEmpty { tabToSave.title = currentTitle } // Ne pas sauvegarder un titre vide
        tabToSave.lastAccessed = Date() // Mettre à jour explicitement lastAccessed ici aussi
        print("[ContentView saveCurrentTabState] État sauvegardé pour onglet ID \(tabIdToSave) ('\(tabToSave.displayTitle)') dans Espace ID \(paneIdToSave)")
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
        } else if let firstTab = pane.tabsForDisplay.first { // Utiliser tabsForDisplay pour cohérence avec Sidebar
            print("[UpdateToolbar] Espace: '\(pane.name ?? "")', Pas d'onglet actif, sélection du premier (via tabsForDisplay): '\(firstTab.displayTitle)'")
            pane.currentTabID = firstTab.id; urlStringToSetForToolbar = firstTab.urlString
            // Le chargement sera géré par le .onChange(of: currentTabID) si currentTabID a réellement changé.
            // Si on veut forcer ici aussi :
            if forceLoad { urlToActuallyLoad = firstTab.displayURL }
        } else {
            print("[UpdateToolbar] Espace: '\(pane.name ?? "")', Aucun onglet. Ajout onglet vide.")
            pane.addTab(urlString: "about:blank"); urlStringToSetForToolbar = "about:blank"
            // Le .onChange(of: currentTabID) s'occupera du reste.
            // Si on veut forcer ici aussi :
            if forceLoad, let newTab = pane.currentTab { urlToActuallyLoad = newTab.displayURL }
        }

        // Mettre à jour la barre d'URL seulement si elle n'a pas le focus et que la valeur a changé
        if toolbarURLInput != urlStringToSetForToolbar && !isToolbarAddressBarFocused {
            toolbarURLInput = urlStringToSetForToolbar
            print("[UpdateToolbar] toolbarURLInput mis à jour vers: \(toolbarURLInput)")
        } else if toolbarURLInput != urlStringToSetForToolbar && isToolbarAddressBarFocused {
             print("[UpdateToolbar] toolbarURLInput NON mis à jour car focus (actuel: '\(toolbarURLInput)', nouveau serait: '\(urlStringToSetForToolbar)')")
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
    
    private func fetchToolbarHistorySuggestions(for query: String) {
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
        // Sauvegarder l'état de l'ancien espace/onglet avant de créer le nouveau et de changer activeAlveoPaneID
        saveCurrentTabState(forPaneID: activeAlveoPaneID, forTabID: currentActiveAlveoPaneObject?.currentTabID)
        
        let paneName = name ?? "Espace \(alveoPanes.count + 1)"
        let newPane = AlveoPane(name: paneName, initialTabURLString: url.absoluteString)
        modelContext.insert(newPane)
        print("[ContentView addAlveoPane] Nouvel Espace créé: \(newPane.id) - '\(paneName)'. Mise à jour de activeAlveoPaneID.")
        activeAlveoPaneID = newPane.id // Déclenche .onChange(of: activeAlveoPaneID)
    }
    
    // MARK: - Méthodes de Vue restaurées
    private func resetAddAlveoPaneDialogFields() {
        newAlveoPaneName = ""
        initialAlveoPaneURLString = "https://www.google.com"
    }

    @ViewBuilder
    private var noActivePanesView: some View {
        VStack {
            Text("Bienvenue dans Alveo !")
                .font(.largeTitle)
            Text("Créez votre premier Espace pour commencer.\n(Un Espace par défaut aurait dû être créé.)")
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
            Text("Nouvel Espace").font(.headline).padding(.bottom)
            TextField("Nom de l'Espace (optionnel)", text: $newAlveoPaneName).textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("URL initiale de l'onglet", text: $initialAlveoPaneURLString).textFieldStyle(RoundedBorderTextFieldStyle()).textContentType(.URL)
            HStack {
                Button("Annuler") { showAddAlveoPaneDialog = false; resetAddAlveoPaneDialogFields() }
                Spacer()
                Button("Ajouter") {
                    let urlToLoad = URL(string: initialAlveoPaneURLString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "about:blank")!
                    let nameToSet = newAlveoPaneName.trimmingCharacters(in: .whitespacesAndNewlines)
                    addAlveoPane(name: nameToSet.isEmpty ? nil : nameToSet, withURL: urlToLoad)
                    showAddAlveoPaneDialog = false; resetAddAlveoPaneDialogFields()
                }.disabled(initialAlveoPaneURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.top)
        }.padding().frame(minWidth: 350, idealHeight: 180) // Ajuster la taille de la sheet
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
                    } label: { HStack { Text(paneItem.name ?? "Espace \(paneItem.id.uuidString.prefix(4))"); if paneItem.id == activeAlveoPaneID { Image(systemName: "checkmark") } } }
                }
                Divider(); Button("Nouvel Espace...") { showAddAlveoPaneDialog = true }
                if let paneID = activeAlveoPaneID, let paneToDelete = alveoPanes.first(where: { $0.id == paneID }) {
                    Button("Supprimer l'Espace Actif", role: .destructive) {
                        webViewHelpers.removeValue(forKey: paneToDelete.id)
                        modelContext.delete(paneToDelete)
                        // activeAlveoPaneID sera mis à jour par .onChange(of: alveoPanes.count)
                    }
                }
            } label: { Label("Espaces", systemImage: "square.stack.3d.down.right") }
            Button { currentActiveAlveoPaneObject?.addTab(urlString: "about:blank") } label: { Image(systemName: "plus.circle") }
            Button { helper.reload() } label: { Image(systemName: "arrow.clockwise") }.disabled(helper.isLoading)
        }
    }
    
    // MARK: - Default Pane Creation
    private func createDefaultPaneIfNeeded() {
        if alveoPanes.isEmpty {
            print("[ContentView createDefaultPaneIfNeeded] Aucun Espace existant. Création de l'Espace par défaut.")
            let defaultURL = URL(string: initialAlveoPaneURLString) ?? URL(string: "about:blank")!
            let defaultPaneName = "Mon Premier Espace"
            addAlveoPane(name: defaultPaneName, withURL: defaultURL)
        } else {
            print("[ContentView createDefaultPaneIfNeeded] Des Espaces existent déjà.")
            if activeAlveoPaneID == nil { // S'il n'y a pas d'ID actif, sélectionner le premier.
                activeAlveoPaneID = alveoPanes.first?.id
                print("[ContentView createDefaultPaneIfNeeded] Aucun espace actif, sélection du premier existant: \(String(describing: activeAlveoPaneID))")
            }
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
                            let _ = print("[CV BODY sidebar] Espace \(activePaneToDisplay.id) actif mais helper (encore?) manquant.") }
                    } else { Text("Aucun espace.").frame(minWidth: 180, idealWidth: 240, maxWidth: 400).background(Color(NSColor.controlBackgroundColor)) }
                    
                    Group {
                        if let activePaneToDisplay = currentActiveAlveoPaneObject {
                            if let helperForContent = webViewHelpers[activePaneToDisplay.id] {
                                ActiveAlveoPaneContainerView(pane: activePaneToDisplay, webViewHelper: helperForContent, globalURLInput: $toolbarURLInput)
                            } else { ProgressView()
                                let _ = print("[CV BODY content] Espace \(activePaneToDisplay.id) actif mais helper (encore?) manquant.") }
                        } else { noActivePanesView }
                    }
                }
                .toolbar {
                    if let helperForToolbar = currentWebViewHelperFromDict { // Utilise la propriété calculée qui lit du dict
                        mainToolbarContent(geometry: geometry, using: helperForToolbar)
                    } else { ToolbarItemGroup(placement: .principal) { Text("Alveo") }
                        let _ = print("[CV TOOLBAR] Aucun helper actif pour la toolbar (activeAlveoPaneID: \(String(describing: activeAlveoPaneID))).") }
                }
                .onAppear {
                    print("[CV .onAppear] Début. alveoPanes.count: \(alveoPanes.count), activeAlveoPaneID: \(String(describing: activeAlveoPaneID))")
                    createDefaultPaneIfNeeded() // Crée un espace par défaut si nécessaire
                    
                    // S'assurer que si un activeAlveoPaneID est défini (par createDefaultPaneIfNeeded ou existant), son helper est créé et la page chargée.
                    // Le .onChange(of: activeAlveoPaneID) devrait s'en charger si l'ID change.
                    // Si l'ID ne change pas mais que le helper n'existe pas (cas improbable au 1er lancement après création), on s'en assure.
                    if let currentID = activeAlveoPaneID {
                        let _ = ensureWebViewHelperExists(for: currentID)
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: currentID, forceLoad: true)
                    }
                    DispatchQueue.main.async { NSApplication.shared.windows.first { $0.isMainWindow }?.title = "" }
                }
                .onChange(of: alveoPanes.count) { oldValue, newValue in
                    print("[CV .onChange(alveoPanes.count)] De \(oldValue) à \(newValue). activeID actuel: \(String(describing: activeAlveoPaneID))")
                    let previousActiveID = activeAlveoPaneID
                    if let currentActiveID = activeAlveoPaneID, !alveoPanes.contains(where: { $0.id == currentActiveID }) {
                        // L'espace actif a été supprimé
                        activeAlveoPaneID = alveoPanes.first?.id // Sélectionner le premier, ou nil si la liste est vide
                        print("[CV .onChange(alveoPanes.count)] Espace actif supprimé. Nouvel activeAlveoPaneID: \(String(describing: activeAlveoPaneID))")
                    } else if activeAlveoPaneID == nil && !alveoPanes.isEmpty {
                        // Aucun espace actif, mais il y en a, sélectionner le premier
                        activeAlveoPaneID = alveoPanes.first?.id
                        print("[CV .onChange(alveoPanes.count)] Aucun espace actif, sélection du premier. Nouvel activeAlveoPaneID: \(String(describing: activeAlveoPaneID))")
                    }
                    
                    // Nettoyer les helpers orphelins
                    let currentPaneIDs = Set(alveoPanes.map { $0.id })
                    webViewHelpers = webViewHelpers.filter { currentPaneIDs.contains($0.key) }
                    print("[CV .onChange(alveoPanes.count)] Helpers nettoyés. Il reste \(webViewHelpers.count) helpers.")

                    if previousActiveID != activeAlveoPaneID {
                        // Si activeAlveoPaneID a changé, le .onChange(of: activeAlveoPaneID) suivant s'en occupera.
                    } else if let currentID = activeAlveoPaneID {
                        // Si l'ID actif n'a pas changé mais que le nombre d'espaces a changé (ex: ajout d'un autre espace)
                        // on pourrait vouloir s'assurer que l'UI est à jour pour l'espace actif.
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: currentID, forceLoad: false) // Peut-être pas forceLoad ici
                    }
                }
                .onChange(of: activeAlveoPaneID) { oldValue, newValue in
                    print(">>> [CV .onChange(activeAlveoPaneID)] DEBUT. Ancien: \(String(describing: oldValue)), Nouveau: \(String(describing: newValue))")
                    // Sauvegarder l'état de l'ancien onglet/espace
                    if let oldPaneID = oldValue, let oldPane = alveoPanes.first(where: {$0.id == oldPaneID}) { // Trouver l'ancien pane dans la liste actuelle
                         saveCurrentTabState(forPaneID: oldPaneID, forTabID: oldPane.currentTabID)
                    }
                    
                    if let newPaneID = newValue {
                        print("[CV .onChange(activeAlveoPaneID)] Nouvel Espace ID: \(newPaneID). Assurer existence helper et charger.")
                        let _ = ensureWebViewHelperExists(for: newPaneID) // S'assurer que le helper existe
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: newPaneID, forceLoad: true)
                    } else {
                        toolbarURLInput = "" // Aucun espace actif
                        print("[CV .onChange(activeAlveoPaneID)] Aucun nouvel espace actif.")
                    }
                    print("<<< [CV .onChange(activeAlveoPaneID)] FIN.")
                }
                .onChange(of: currentActiveAlveoPaneObject?.currentTabID) { oldValue, newValue in
                    print(">>> [CV .onChange(currentTabID)] DEBUT. Espace: '\(currentActiveAlveoPaneObject?.name ?? "N/A")' (ID: \(String(describing: currentActiveAlveoPaneObject?.id))) AncienTID: \(String(describing: oldValue)), NouveauTID: \(String(describing: newValue))")
                    if let paneID = currentActiveAlveoPaneObject?.id {
                        // Sauvegarder l'état de l'ancien onglet DANS LE MÊME ESPACE
                        saveCurrentTabState(forPaneID: paneID, forTabID: oldValue)
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: paneID, forceLoad: true)
                    } else {
                         print("[CV .onChange(currentTabID)] ERREUR: currentActiveAlveoPaneObject est nil, ne peut pas mettre à jour l'onglet.")
                    }
                    print("<<< [CV .onChange(currentTabID)] FIN.")
                }
                .sheet(isPresented: $showAddAlveoPaneDialog) { addAlveoPaneDialog() }
            }
        }
    }
}

