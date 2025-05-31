import SwiftUI
import SwiftData

@MainActor
struct ContentView: View {
    // MARK: - Environment & Queries
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlveoPane.creationDate, order: .forward) private var alveoPanes: [AlveoPane]
    
    // MARK: - State Variables
    @State private var activeAlveoPaneID: UUID?
    
    // Dictionnaire pour stocker un WebViewHelper par AlveoPane (Espace)
    // La modification de ce dictionnaire doit se faire dans des contextes sûrs.
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
    
    // Cette propriété calculée lit UNIQUEMENT le dictionnaire. Elle ne crée PAS de helper.
    private var currentWebViewHelperFromDict: WebViewHelper? {
        guard let activeID = activeAlveoPaneID else { return nil }
        return webViewHelpers[activeID]
    }
    
    // MARK: - Helper Management (Contextes Sûrs)

    // Fonction pour créer un nouveau helper et l'ajouter au dictionnaire.
    // Doit être appelée depuis .onAppear, .onChange, ou d'autres actions utilisateur.
    private func createAndStoreWebViewHelper(for paneID: UUID) -> WebViewHelper {
        // Vérifier à nouveau au cas où il aurait été créé par un autre appel entre-temps
        if let existingHelper = webViewHelpers[paneID] {
            print("[ContentView createAndStore] Helper EXISTANT DÉJÀ pour \(paneID). Retourne existant: \(existingHelper.id)")
            return existingHelper
        }
        
        print("[ContentView createAndStore] Création NOUVEAU helper pour Espace ID: \(paneID)")
        let newHelper = WebViewHelper(customUserAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15")
        newHelper.onNavigationEvent = { newURL, newTitle in
            self.handleNavigationEvent(forPaneID: paneID, newURL: newURL, newTitle: newTitle)
        }
        webViewHelpers[paneID] = newHelper // Modification de @State dans un contexte sûr
        return newHelper
    }

    // Fonction pour s'assurer qu'un helper existe, en le créant si nécessaire.
    // Appelée depuis des contextes où la création est permise.
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
        if let urlAbsoluteString = newURL?.absoluteString {
            if activeTab.urlString != urlAbsoluteString {
                activeTab.urlString = urlAbsoluteString
                print("[Callback NavEvent] Espace '\(activePane.name ?? "")' Onglet '\(activeTab.displayTitle)' URL DANS MODELE: \(urlAbsoluteString)")
                tabModelUpdated = true
            }
        }
        if let title = newTitle, !title.isEmpty {
            if activeTab.title != title {
                activeTab.title = title
                print("[Callback NavEvent] Espace '\(activePane.name ?? "")' Onglet '\(activeTab.displayTitle)' Titre DANS MODELE: \(title)")
                tabModelUpdated = true
            }
        }
        
        if tabModelUpdated &&
           activePane.id == self.activeAlveoPaneID &&
           activeTab.id == self.currentActiveAlveoPaneObject?.currentTabID &&
           !self.isToolbarAddressBarFocused { // Condition pour ne pas écraser la saisie utilisateur
            
            if let currentTabActualURL = newURL?.absoluteString {
                if toolbarURLInput != currentTabActualURL {
                     toolbarURLInput = currentTabActualURL
                     print("[Callback NavEvent] toolbarURLInput mis à jour (car non focus) vers: \(currentTabActualURL)")
                }
            }
        } else if tabModelUpdated {
            print("[Callback NavEvent] Modèle Tab mis à jour, mais toolbarURLInput NON modifié (raison: espace/onglet non actif OU barre focus). isToolbarAddressBarFocused = \(self.isToolbarAddressBarFocused)")
        }
    }
    
    private func saveCurrentTabState(forPaneID paneID: UUID?, forTabID tabID: UUID?) {
        guard let paneIdToSave = paneID,
              let tabIdToSave = tabID,
              let paneToSave = alveoPanes.first(where: { $0.id == paneIdToSave }),
              let tabToSave = paneToSave.tabs.first(where: { $0.id == tabIdToSave }),
              let helperToSaveFrom = webViewHelpers[paneIdToSave] // Utiliser le helper de l'espace concerné
        else {
            // print("[ContentView saveCurrentTabState] Rien à sauvegarder (paneID, tabID, helper ou pane/tab non trouvés).")
            return
        }
        
        if let currentURL = helperToSaveFrom.currentURL {
            tabToSave.urlString = currentURL.absoluteString
        }
        if let currentTitle = helperToSaveFrom.pageTitle {
            tabToSave.title = currentTitle
        }
        // tabToSave.lastAccessed = Date() // Peut-être redondant si déjà fait ailleurs
        print("[ContentView saveCurrentTabState] État sauvegardé pour onglet ID \(tabIdToSave) dans Espace ID \(paneIdToSave)")
    }
    
    private func updateToolbarURLInputAndLoadIfNeeded(forPaneID paneID: UUID, forceLoad: Bool = false) {
        print(">>> [UpdateToolbar ENTER] forceLoad: \(forceLoad), Pour Espace ID: \(paneID)")
        
        guard let pane = alveoPanes.first(where: { $0.id == paneID }) else {
            toolbarURLInput = ""
            print("[UpdateToolbar] Espace ID \(paneID) non trouvé dans alveoPanes.")
            return
        }
        
        // Obtenir/Créer le helper dans un contexte sûr (updateToolbar... est appelé par .onChange)
        let paneWebViewHelper = ensureWebViewHelperExists(for: pane.id)
        
        var urlStringToSetForToolbar: String = "about:blank"
        var urlToActuallyLoad: URL? = nil
        
        if let currentTabId = pane.currentTabID, let tabToLoad = pane.tabs.first(where: { $0.id == currentTabId }) {
            print("[UpdateToolbar] Espace: '\(pane.name ?? "")', Onglet actif: '\(tabToLoad.displayTitle)', URL modèle: \(tabToLoad.urlString)")
            urlStringToSetForToolbar = tabToLoad.urlString
            if forceLoad {
                urlToActuallyLoad = tabToLoad.displayURL
            }
        } else if let firstTab = pane.sortedTabs.first {
            print("[UpdateToolbar] Espace: '\(pane.name ?? "")', Pas d'onglet actif, sélection du premier: '\(firstTab.displayTitle)'")
            // Si currentTabID est nil, le SidebarView ne le reflétera pas comme sélectionné.
            // On met à jour le currentTabID du modèle ici.
            // Le .onChange(of: currentActiveAlveoPaneObject?.currentTabID) sera déclenché.
            pane.currentTabID = firstTab.id
            urlStringToSetForToolbar = firstTab.urlString
            // Le chargement sera géré par le prochain appel à cette fonction déclenché par le .onChange.
            // Ou, si on veut charger maintenant :
            // if forceLoad { urlToActuallyLoad = firstTab.displayURL }
        } else {
            print("[UpdateToolbar] Espace: '\(pane.name ?? "")', Aucun onglet. Ajout d'un onglet vide.")
            pane.addTab(urlString: "about:blank") // addTab définit currentTabID.
            urlStringToSetForToolbar = "about:blank"
            // Le chargement sera géré par le prochain appel à cette fonction.
        }
        
        if toolbarURLInput != urlStringToSetForToolbar && !isToolbarAddressBarFocused {
            toolbarURLInput = urlStringToSetForToolbar
            print("[UpdateToolbar] toolbarURLInput mis à jour vers: \(toolbarURLInput)")
        }
        
        if let finalURLToLoad = urlToActuallyLoad {
            // On charge si forceLoad est vrai, OU si l'URL du helper est différente de celle qu'on veut charger.
            if forceLoad || paneWebViewHelper.currentURL?.absoluteString != finalURLToLoad.absoluteString {
                print(">>> [UpdateToolbar] CHARGEMENT DEMANDÉ. Helper: \(paneWebViewHelper.id), URL: \(finalURLToLoad.absoluteString)")
                paneWebViewHelper.loadURL(finalURLToLoad)
            } else {
                print(">>> [UpdateToolbar] Non chargé (pas de forceLoad et URL identique, ou helper déjà en chargement): \(finalURLToLoad.absoluteString)")
            }
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
        saveCurrentTabState(forPaneID: activeAlveoPaneID, forTabID: currentActiveAlveoPaneObject?.currentTabID)
        let paneName = name ?? "Espace \(alveoPanes.count + 1)"
        let newPane = AlveoPane(name: paneName, initialTabURLString: url.absoluteString)
        modelContext.insert(newPane)
        activeAlveoPaneID = newPane.id // Déclenche .onChange(of: activeAlveoPaneID)
    }
    
    private func resetAddAlveoPaneDialogFields() { /* ... */ }
    @ViewBuilder private var noActivePanesView: some View { /* ... */ }
    private func addAlveoPaneDialog() -> some View { /* ... */ }

    // mainToolbarContent doit maintenant recevoir le helper en paramètre
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
                webViewHelper: helper, // Passer le helper fourni
                urlInput: $toolbarURLInput,
                showSuggestions: $showToolbarSuggestions,
                filteredHistory: $filteredToolbarHistory,
                isFocused: $isToolbarAddressBarFocused,
                geometryProxy: geometry,
                fetchHistoryAction: { queryText in fetchToolbarHistorySuggestions(for: queryText) }
            )
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(alveoPanes) { paneItem in
                    Button {
                        saveCurrentTabState(forPaneID: activeAlveoPaneID, forTabID: currentActiveAlveoPaneObject?.currentTabID)
                        activeAlveoPaneID = paneItem.id
                    } label: {
                        HStack { Text(paneItem.name ?? "Espace"); if paneItem.id == activeAlveoPaneID { Image(systemName: "checkmark") } }
                    }
                }
                Divider()
                Button("Nouvel Espace...") { showAddAlveoPaneDialog = true }
                if let paneID = activeAlveoPaneID, let paneToDelete = alveoPanes.first(where: { $0.id == paneID }) {
                    Button("Supprimer l'Espace Actif", role: .destructive) {
                        webViewHelpers.removeValue(forKey: paneToDelete.id) // Nettoyer le helper
                        modelContext.delete(paneToDelete)
                        // activeAlveoPaneID sera mis à jour par .onChange(of: alveoPanes.count)
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
                    // Volet gauche (Sidebar)
                    if let activePaneToDisplay = currentActiveAlveoPaneObject {
                        // Passer le helper seulement s'il existe, sinon SidebarView pourrait le créer au mauvais moment.
                        // Il est crucial que `ensureWebViewHelperExists` soit appelé AVANT que ce body ne soit évalué si possible.
                        // Le .onChange(of: activeAlveoPaneID) devrait s'en charger.
                        if let helperForSidebar = webViewHelpers[activePaneToDisplay.id] {
                            SidebarView(
                                pane: activePaneToDisplay,
                                webViewHelper: helperForSidebar
                            )
                            .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                        } else {
                            // Cas où l'espace est actif mais son helper n'est pas encore prêt
                            ProgressView().frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                            let _ = print("[ContentView BODY sidebar] Espace actif \(activePaneToDisplay.id) mais helper non trouvé. Attente de création via .onChange.")
                        }
                    } else {
                        Text("Aucun espace sélectionné.").frame(minWidth: 180, idealWidth: 240, maxWidth: 400).background(Color(NSColor.controlBackgroundColor))
                    }
                    
                    // Volet principal (WebView)
                    Group {
                        if let activePaneToDisplay = currentActiveAlveoPaneObject {
                            if let helperForContent = webViewHelpers[activePaneToDisplay.id] {
                                ActiveAlveoPaneContainerView(
                                    pane: activePaneToDisplay,
                                    webViewHelper: helperForContent,
                                    globalURLInput: $toolbarURLInput
                                )
                            } else {
                                ProgressView() // Attente de la création du helper
                                let _ = print("[ContentView BODY content] Espace actif \(activePaneToDisplay.id) mais helper non trouvé. Attente de création via .onChange.")
                            }
                        } else {
                            noActivePanesView
                        }
                    }
                }
                .toolbar {
                    // Passer le helper actuel à la toolbar, seulement s'il existe
                    if let helperForToolbar = currentWebViewHelperFromDict {
                        mainToolbarContent(geometry: geometry, using: helperForToolbar)
                    } else {
                        // Toolbar minimale si aucun espace/helper actif
                        ToolbarItemGroup(placement: .principal) { Text("Alveo") }
                         let _ = print("[ContentView TOOLBAR] Aucun helper actif pour la toolbar (activeAlveoPaneID: \(String(describing: activeAlveoPaneID))).")
                    }
                }
                .onAppear {
                    print("[ContentView .onAppear] Début. activeAlveoPaneID: \(String(describing: activeAlveoPaneID))")
                    if activeAlveoPaneID == nil, let firstPane = alveoPanes.first {
                        print("[ContentView .onAppear] Aucun espace actif, sélection du premier: \(firstPane.id)")
                        activeAlveoPaneID = firstPane.id // Déclenchera .onChange(of: activeAlveoPaneID)
                    } else if let currentID = activeAlveoPaneID {
                        print("[ContentView .onAppear] Espace déjà actif: \(currentID). Vérification/création du helper.")
                        let _ = ensureWebViewHelperExists(for: currentID) // S'assurer que le helper existe
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: currentID, forceLoad: true) // Charger l'état actuel
                    } else if alveoPanes.isEmpty {
                        print("[ContentView .onAppear] Aucun espace existant.")
                    }
                    DispatchQueue.main.async { NSApplication.shared.windows.first { $0.isMainWindow }?.title = "" }
                }
                .onChange(of: alveoPanes.count) { oldValue, newValue in
                    print("[ContentView .onChange(alveoPanes.count)] Changement de \(oldValue) à \(newValue)")
                    let previousActiveID = activeAlveoPaneID
                    if let activeID = activeAlveoPaneID, !alveoPanes.contains(where: { $0.id == activeID }) {
                        activeAlveoPaneID = alveoPanes.first?.id
                        print("[ContentView .onChange(alveoPanes.count)] Espace actif supprimé. Nouvel activeAlveoPaneID: \(String(describing: activeAlveoPaneID))")
                    } else if activeAlveoPaneID == nil && !alveoPanes.isEmpty {
                        activeAlveoPaneID = alveoPanes.first?.id
                        print("[ContentView .onChange(alveoPanes.count)] Aucun espace actif, sélection du premier. Nouvel activeAlveoPaneID: \(String(describing: activeAlveoPaneID))")
                    }
                    
                    // Nettoyer les helpers orphelins
                    let currentPaneIDs = Set(alveoPanes.map { $0.id })
                    for (id, _) in webViewHelpers {
                        if !currentPaneIDs.contains(id) {
                            print("[ContentView .onChange(alveoPanes.count)] Nettoyage helper orphelin pour ID: \(id)")
                            webViewHelpers.removeValue(forKey: id) // Le helper sera déinitialisé si plus rien ne le retient
                        }
                    }
                    
                    if previousActiveID != activeAlveoPaneID {
                        // Si activeAlveoPaneID a changé, le .onChange(of: activeAlveoPaneID) s'en occupera.
                    } else if let currentID = activeAlveoPaneID {
                        // Si l'ID actif n'a pas changé mais que le nombre d'espaces a changé (peu probable sans suppression de l'actif)
                        // on pourrait vouloir recharger.
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: currentID, forceLoad: true)
                    }
                }
                .onChange(of: activeAlveoPaneID) { oldValue, newValue in
                    print(">>> [ContentView .onChange(activeAlveoPaneID)] DEBUT. Ancien: \(String(describing: oldValue)), Nouveau: \(String(describing: newValue))")
                    // Sauvegarder l'état de l'ancien onglet de l'ancien espace
                    if let oldPaneID = oldValue, let oldPane = alveoPanes.first(where: {$0.id == oldPaneID}) {
                         saveCurrentTabState(forPaneID: oldPaneID, forTabID: oldPane.currentTabID)
                    }
                    
                    if let newPaneID = newValue {
                        print("[ContentView .onChange(activeAlveoPaneID)] Nouvel Espace ID: \(newPaneID). Assurer existence helper.")
                        let _ = ensureWebViewHelperExists(for: newPaneID)
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: newPaneID, forceLoad: true)
                    } else {
                        toolbarURLInput = "" // Aucun espace actif
                    }
                    print("<<< [ContentView .onChange(activeAlveoPaneID)] FIN.")
                }
                .onChange(of: currentActiveAlveoPaneObject?.currentTabID) { oldValue, newValue in
                    print(">>> [ContentView .onChange(currentTabID)] DEBUT. Espace: '\(currentActiveAlveoPaneObject?.name ?? "N/A")' Ancien OngletID: \(String(describing: oldValue)), Nouveau OngletID: \(String(describing: newValue))")
                    if let paneID = currentActiveAlveoPaneObject?.id {
                        // Sauvegarder l'état de l'ancien onglet DANS LE MÊME ESPACE
                        saveCurrentTabState(forPaneID: paneID, forTabID: oldValue)
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: paneID, forceLoad: true)
                    }
                    print("<<< [ContentView .onChange(currentTabID)] FIN.")
                }
                .sheet(isPresented: $showAddAlveoPaneDialog) { addAlveoPaneDialog() }
            }
        }
    }
}

