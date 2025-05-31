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
    
    // Récupère le WebViewHelper pour l'Espace actif
    private var currentWebViewHelper: WebViewHelper? {
        guard let activePane = currentActiveAlveoPaneObject else { return nil }
        return getWebViewHelper(for: activePane.id)
    }
    
    // MARK: - Private Methods
    
    // Crée ou récupère le WebViewHelper pour un Espace donné
    private func getWebViewHelper(for paneID: UUID) -> WebViewHelper {
        if let existingHelper = webViewHelpers[paneID] {
            print("[ContentView GET_HELPER] Retour helper EXISTANT: \(Unmanaged.passUnretained(existingHelper).toOpaque()) pour Espace ID: \(paneID)")
            return existingHelper
        }
        let newHelper = WebViewHelper(customUserAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15")
        // Assignation du callback pour synchroniser Tab.urlString (NOUVEAU)
        newHelper.onNavigationEvent = { [weak self] newURL, newTitle in
            self?.handleNavigationEvent(forPaneID: paneID, newURL: newURL, newTitle: newTitle)
        }
        webViewHelpers[paneID] = newHelper
        print("[ContentView GET_HELPER] Création NOUVEAU helper: \(Unmanaged.passUnretained(newHelper).toOpaque()) pour Espace ID: \(paneID)")
        return newHelper
    }
    
    private func handleNavigationEvent(forPaneID paneID: UUID, newURL: URL?, newTitle: String?) {
        guard let activePane = alveoPanes.first(where: { $0.id == paneID }), // Trouver le bon pane
              let activeTabID = activePane.currentTabID,
              let activeTab = activePane.tabs.first(where: { $0.id == activeTabID }) else {
            print("[Callback NavEvent] Pane ou Tab non trouvé pour paneID: \(paneID)")
            return
        }

        var updated = false
        if let urlAbsoluteString = newURL?.absoluteString {
            if activeTab.urlString != urlAbsoluteString {
                activeTab.urlString = urlAbsoluteString
                print("[Callback NavEvent] Espace \(activePane.name ?? "") Onglet \(activeTab.displayTitle) URL mis à jour: \(urlAbsoluteString)")
                updated = true
            }
        }
        if let title = newTitle, !title.isEmpty { // Ne pas mettre à jour avec un titre vide
            if activeTab.title != title {
                activeTab.title = title
                print("[Callback NavEvent] Espace \(activePane.name ?? "") Onglet \(activeTab.displayTitle) Titre mis à jour: \(title)")
                updated = true
            }
        }
        
        // Si l'URL de la barre d'outils doit refléter l'URL de l'onglet après navigation
        if updated && activePane.id == self.activeAlveoPaneID && activeTab.id == self.currentActiveAlveoPaneObject?.currentTabID {
            if let currentTabURL = newURL?.absoluteString, toolbarURLInput != currentTabURL {
                 toolbarURLInput = currentTabURL
                 print("[Callback NavEvent] toolbarURLInput mis à jour vers: \(toolbarURLInput)")
            }
        }
    }
    
    private func saveCurrentTabState() {
        guard let currentPane = currentActiveAlveoPaneObject,
              let currentTabID = currentPane.currentTabID,
              let currentTab = currentPane.tabs.first(where: { $0.id == currentTabID }),
              let paneWebViewHelper = currentWebViewHelper else { return } // Utilise currentWebViewHelper
        
        if let currentURL = paneWebViewHelper.currentURL {
            currentTab.urlString = currentURL.absoluteString
        }
        if let currentTitle = paneWebViewHelper.pageTitle {
            currentTab.title = currentTitle
        }
        currentTab.lastAccessed = Date()
        print("[ContentView] État sauvegardé pour onglet: \(currentTab.displayTitle) dans Espace: \(currentPane.name ?? "N/A")")
    }
    
    private func updateToolbarURLInputAndLoadIfNeeded(forceLoad: Bool = false) {
        guard let pane = currentActiveAlveoPaneObject else {
            toolbarURLInput = "" // Pas d'Espace actif, vider la barre d'URL
            print("[UpdateToolbar] Aucun Espace actif.")
            return
        }
        
        // Obtenir le WebViewHelper spécifique à cet Espace
        let paneWebViewHelper = getWebViewHelper(for: pane.id)
        var urlStringToSetForToolbar: String = "about:blank"
        var urlToActuallyLoad: URL? = nil
        
        if let currentTabId = pane.currentTabID, let tabToLoad = pane.tabs.first(where: { $0.id == currentTabId }) {
            print("[UpdateToolbar] Espace: \(pane.name ?? "N/A"), Onglet actif: \(tabToLoad.displayTitle), URL: \(tabToLoad.urlString)")
            urlStringToSetForToolbar = tabToLoad.urlString
            if forceLoad {
                urlToActuallyLoad = tabToLoad.displayURL // displayURL devrait retourner une URL valide ou nil
            }
        } else if let firstTab = pane.sortedTabs.first {
            print("[UpdateToolbar] Espace: \(pane.name ?? "N/A"), Pas d'onglet actif, sélection du premier: \(firstTab.displayTitle)")
            pane.currentTabID = firstTab.id // Ceci déclenchera .onChange(of: currentTabID), qui rappellera cette fonction
            urlStringToSetForToolbar = firstTab.urlString
            // Le chargement sera géré par l'appel suivant à cette fonction, déclenché par .onChange.
        } else { // Aucun onglet dans l'Espace
            print("[UpdateToolbar] Espace: \(pane.name ?? "N/A"), Aucun onglet. Ajout d'un onglet vide.")
            pane.addTab(urlString: "about:blank") // addTab définit currentTabID, ce qui rappellera cette fonction.
            urlStringToSetForToolbar = "about:blank"
        }
        
        if toolbarURLInput != urlStringToSetForToolbar {
            toolbarURLInput = urlStringToSetForToolbar
            print("[UpdateToolbar] toolbarURLInput mis à jour vers: \(toolbarURLInput)")
        }
        
        if let finalURLToLoad = urlToActuallyLoad {
            if forceLoad {
                print("[UpdateToolbar] Forçage chargement. Helper: \(Unmanaged.passUnretained(paneWebViewHelper).toOpaque()), URL: \(finalURLToLoad.absoluteString)")
                paneWebViewHelper.loadURL(finalURLToLoad)
            } else if paneWebViewHelper.currentURL?.absoluteString != finalURLToLoad.absoluteString {
                print("[UpdateToolbar] URL différente, chargement. Helper: \(Unmanaged.passUnretained(paneWebViewHelper).toOpaque()), URL: \(finalURLToLoad.absoluteString)")
                paneWebViewHelper.loadURL(finalURLToLoad)
            } else {
                print("[UpdateToolbar] Non chargé (pas de forceLoad et URL identique ou helper déjà en chargement): \(finalURLToLoad.absoluteString)")
            }
        } else if forceLoad && (urlStringToSetForToolbar == "about:blank" || urlStringToSetForToolbar.isEmpty) {
            if let blankURL = URL(string: "about:blank") {
                print("[UpdateToolbar] Forçage chargement about:blank (urlToActuallyLoad était nil). Helper: \(Unmanaged.passUnretained(paneWebViewHelper).toOpaque())")
                paneWebViewHelper.loadURL(blankURL)
            }
        }
    }
    
    private func fetchToolbarHistorySuggestions(for query: String) {
        // ... (votre code existant, semble correct)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { filteredToolbarHistory = []; return }
        let predicate = #Predicate<HistoryItem> {
            $0.urlString.localizedStandardContains(trimmedQuery) || ($0.title?.localizedStandardContains(trimmedQuery) ?? false)
        }
        let sortDescriptor = SortDescriptor(\HistoryItem.lastVisitedDate, order: .reverse)
        var fetchDescriptor = FetchDescriptor(predicate: predicate, sortBy: [sortDescriptor])
        fetchDescriptor.fetchLimit = 7
        do {
            filteredToolbarHistory = try modelContext.fetch(fetchDescriptor)
        } catch {
            print("ERREUR: Échec de la récupération des suggestions d'historique: \(error)"); filteredToolbarHistory = []
        }
    }
    
    private func addAlveoPane(name: String? = nil, withURL url: URL) {
        saveCurrentTabState() // Sauvegarder l'état de l'onglet/espace actuel AVANT de changer
        let paneName = name ?? "Espace \(alveoPanes.count + 1)"
        let newPane = AlveoPane(name: paneName, initialTabURLString: url.absoluteString)
        modelContext.insert(newPane)
        activeAlveoPaneID = newPane.id // Le .onChange(of: activeAlveoPaneID) se chargera de l'update/load
    }
    
    private func resetAddAlveoPaneDialogFields() {
        newAlveoPaneName = ""
        initialAlveoPaneURLString = "https://www.google.com"
    }
    
    // MARK: - View Builders
    @ViewBuilder private var noActivePanesView: some View {
        // ... (votre code existant, semble correct)
        VStack {
            Text("Bienvenue dans Alveo !").font(.largeTitle)
            Text("Créez votre premier Espace pour commencer.").foregroundStyle(.secondary)
            Button("Créer le premier Espace") {
                addAlveoPane(withURL: URL(string: initialAlveoPaneURLString) ?? URL(string: "about:blank")!)
            }.padding(.top)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func addAlveoPaneDialog() -> some View {
        // ... (votre code existant, semble correct)
        VStack {
            Text("Nouvel Espace").font(.headline).padding(.bottom)
            TextField("Nom de l'Espace (optionnel)", text: $newAlveoPaneName).textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("URL initiale", text: $initialAlveoPaneURLString).textFieldStyle(RoundedBorderTextFieldStyle()).textContentType(.URL)
            HStack {
                Button("Annuler") { showAddAlveoPaneDialog = false; resetAddAlveoPaneDialogFields() }
                Spacer()
                Button("Ajouter") {
                    let url = URL(string: initialAlveoPaneURLString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(string: "about:blank")!
                    addAlveoPane(name: newAlveoPaneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newAlveoPaneName.trimmingCharacters(in: .whitespacesAndNewlines), withURL: url)
                    showAddAlveoPaneDialog = false; resetAddAlveoPaneDialogFields()
                }.disabled(initialAlveoPaneURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.top)
        }.padding().frame(minWidth: 300)
    }
    
    @ToolbarContentBuilder private func mainToolbarContent(geometry: GeometryProxy) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if let helper = currentWebViewHelper { // Utilise currentWebViewHelper
                Button { if helper.canGoBack { helper.goBack() } } label: { Image(systemName: "chevron.left") }
                    .disabled(!helper.canGoBack)
                Button { if helper.canGoForward { helper.goForward() } } label: { Image(systemName: "chevron.right") }
                    .disabled(!helper.canGoForward)
            }
        }
        ToolbarItem(placement: .principal) {
            if let helper = currentWebViewHelper { // Utilise currentWebViewHelper
                PrincipalToolbarView(
                    webViewHelper: helper,
                    urlInput: $toolbarURLInput,
                    showSuggestions: $showToolbarSuggestions, // Doit être showToolbarSuggestions
                    filteredHistory: $filteredToolbarHistory,
                    isFocused: $isToolbarAddressBarFocused,
                    geometryProxy: geometry,
                    fetchHistoryAction: { queryText in fetchToolbarHistorySuggestions(for: queryText) }
                )
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(alveoPanes) { paneItem in
                    Button {
                        saveCurrentTabState() // Sauvegarder AVANT de changer activeAlveoPaneID
                        activeAlveoPaneID = paneItem.id
                    } label: {
                        HStack { Text(paneItem.name ?? "Espace"); if paneItem.id == activeAlveoPaneID { Image(systemName: "checkmark") } }
                    }
                }
                Divider()
                Button("Nouvel Espace...") { showAddAlveoPaneDialog = true }
                if let paneID = activeAlveoPaneID, let paneToDelete = alveoPanes.first(where: { $0.id == paneID }) {
                    Button("Supprimer l'Espace Actif", role: .destructive) {
                        // La sauvegarde de l'état de l'espace à supprimer n'est pas nécessaire
                        // car il va être supprimé.
                        webViewHelpers.removeValue(forKey: paneToDelete.id) // Nettoyer le helper
                        modelContext.delete(paneToDelete)
                        // La sélection du prochain espace est gérée par .onChange(of: alveoPanes.count)
                    }
                }
            } label: { Label("Espaces", systemImage: "square.stack.3d.down.right") }
            
            Button { currentActiveAlveoPaneObject?.addTab(urlString: "about:blank") } label: { Image(systemName: "plus.circle") }
            
            if let helper = currentWebViewHelper { // Utilise currentWebViewHelper
                Button { helper.reload() } label: { Image(systemName: "arrow.clockwise") }.disabled(helper.isLoading)
            }
        }
    }
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                HSplitView { // Structure avec volet latéral
                    // Volet gauche (Sidebar)
                    if let activePaneToDisplay = currentActiveAlveoPaneObject {
                        SidebarView(
                            pane: activePaneToDisplay,
                            webViewHelper: getWebViewHelper(for: activePaneToDisplay.id) // Passe le helper de l'Espace actif
                        )
                        .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                    } else {
                        Text("Aucun espace sélectionné.")
                            .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                            .background(Color(NSColor.controlBackgroundColor))
                    }
                    
                    // Volet principal (WebView)
                    Group {
                        if let activePaneToDisplay = currentActiveAlveoPaneObject {
                            ActiveAlveoPaneContainerView(
                                pane: activePaneToDisplay,
                                webViewHelper: getWebViewHelper(for: activePaneToDisplay.id), // Passe le helper de l'Espace actif
                                globalURLInput: $toolbarURLInput
                            )
                        } else {
                            noActivePanesView
                        }
                    }
                }
                .toolbar { mainToolbarContent(geometry: geometry) }
                .onAppear {
                    if activeAlveoPaneID == nil, let firstPane = alveoPanes.first {
                        activeAlveoPaneID = firstPane.id
                    } else if activeAlveoPaneID != nil {
                        // Si un espace est déjà actif, s'assurer qu'il est bien chargé
                         updateToolbarURLInputAndLoadIfNeeded(forceLoad: true)
                    }
                    
                    DispatchQueue.main.async { NSApplication.shared.windows.first { $0.isMainWindow }?.title = "" }
                }
                .onChange(of: alveoPanes.count) { // Gère la suppression/ajout d'Espaces
                    if let activeID = activeAlveoPaneID, !alveoPanes.contains(where: { $0.id == activeID }) {
                        // L'espace actif a été supprimé
                        activeAlveoPaneID = alveoPanes.first?.id // Sélectionner le premier Espace restant, ou nil
                    } else if activeAlveoPaneID == nil && !alveoPanes.isEmpty {
                        // Aucun Espace actif, mais il y en a, sélectionner le premier
                        activeAlveoPaneID = alveoPanes.first?.id
                    }
                    // Le .onChange(of: activeAlveoPaneID) se chargera de l'update/load si activeAlveoPaneID change
                }
                .onChange(of: activeAlveoPaneID) { // Gère le changement d'Espace actif
                    print("[ContentView] activeAlveoPaneID changé en: \(String(describing: activeAlveoPaneID))")
                    // La sauvegarde de l'état de l'ancien onglet/espace a dû être faite *avant* ce changement.
                    updateToolbarURLInputAndLoadIfNeeded(forceLoad: true)
                }
                .onChange(of: currentActiveAlveoPaneObject?.currentTabID) { // Gère le changement d'onglet DANS l'Espace actif
                     print("[ContentView] currentTabID de l'Espace \(currentActiveAlveoPaneObject?.name ?? "N/A") changé en: \(String(describing: currentActiveAlveoPaneObject?.currentTabID))")
                    updateToolbarURLInputAndLoadIfNeeded(forceLoad: true)
                }
                .sheet(isPresented: $showAddAlveoPaneDialog) { addAlveoPaneDialog() }
            }
        }
    }
}
