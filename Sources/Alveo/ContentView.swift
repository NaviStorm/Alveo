import SwiftUI
import SwiftData

@MainActor
struct ContentView: View {
    // MARK: - Environment & Queries
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlveoPane.creationDate, order: .forward) private var alveoPanes: [AlveoPane]
    
    // MARK: - State Variables
    @State private var activeAlveoPaneID: UUID?
    
    // Dictionnaire de WebViewHelpers par espace (SEULE SOURCE DE VÉRITÉ)
    @State private var webViewHelpers: [UUID: WebViewHelper] = [:]
    
    @State private var toolbarURLInput: String = ""
    @State private var showToolbarSuggestions: Bool = false
    @State private var filteredToolbarHistory: [HistoryItem] = []
    @FocusState private var isToolbarAddressBarFocused: Bool
    @State private var showAddAlveoPaneDialog = false
    @State private var newAlveoPaneName: String = ""
    @State private var initialAlveoPaneURLString: String = "https://www.google.com"
    // Note: @State var showSuggestions: Bool = false; est redondant avec showToolbarSuggestions.
    // Conserver showToolbarSuggestions si elle est utilisée par PrincipalToolbarView
    
    // MARK: - Computed Properties
    var currentActiveAlveoPaneObject: AlveoPane? {
        guard let activeID = activeAlveoPaneID else { return alveoPanes.first }
        return alveoPanes.first(where: { $0.id == activeID })
    }
    
    private var currentWebViewHelper: WebViewHelper? {
        guard let activePane = currentActiveAlveoPaneObject else { return nil }
        return getWebViewHelper(for: activePane.id)
    }
    
    // MARK: - Private Methods
    private func getWebViewHelper(for paneID: UUID) -> WebViewHelper {
        if let existing = webViewHelpers[paneID] {
            return existing
        }
        let newHelper = WebViewHelper(customUserAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15")
        webViewHelpers[paneID] = newHelper
        print("[ContentView] Nouveau WebViewHelper \(Unmanaged.passUnretained(newHelper).toOpaque()) créé pour l'espace: \(paneID)")
        return newHelper
    }
    
    private func saveCurrentTabState() {
        guard let currentPane = currentActiveAlveoPaneObject,
              let currentTabID = currentPane.currentTabID,
              let currentTab = currentPane.tabs.first(where: { $0.id == currentTabID }),
              let paneWebViewHelper = currentWebViewHelper else { return }
        
        if let currentURL = paneWebViewHelper.currentURL {
            currentTab.urlString = currentURL.absoluteString
        }
        if let currentTitle = paneWebViewHelper.pageTitle {
            currentTab.title = currentTitle
        }
        currentTab.lastAccessed = Date()
        print("[ContentView] État sauvegardé pour l'onglet: \(currentTab.displayTitle) dans l'espace \(currentPane.name ?? "")")
    }
    
    private func updateToolbarURLInputAndLoadIfNeeded(forceLoad: Bool = false) {
        guard let pane = currentActiveAlveoPaneObject else {
            toolbarURLInput = ""
            print("[UpdateToolbar] Aucun espace actif.")
            return
        }
        
        let paneWebViewHelper = getWebViewHelper(for: pane.id)
        var urlStringToSetForToolbar: String = "about:blank"
        var urlToActuallyLoad: URL? = nil
        
        if let currentTabId = pane.currentTabID, let tabToLoad = pane.tabs.first(where: { $0.id == currentTabId }) {
            print("[UpdateToolbar] Espace: \(pane.name ?? "N/A"), Onglet actif: \(tabToLoad.displayTitle), URL: \(tabToLoad.urlString)")
            urlStringToSetForToolbar = tabToLoad.urlString
            if forceLoad {
                urlToActuallyLoad = tabToLoad.displayURL // S'attend à une URL complète
            }
        } else if let firstTab = pane.sortedTabs.first { // Si aucun onglet sélectionné, prendre le premier
            print("[UpdateToolbar] Espace: \(pane.name ?? "N/A"), Pas d'onglet actif, sélection du premier: \(firstTab.displayTitle)")
            pane.currentTabID = firstTab.id // Ceci déclenchera un autre appel à cette fonction via .onChange
            urlStringToSetForToolbar = firstTab.urlString
            // Le chargement sera géré par le prochain appel à cette fonction déclenché par le .onChange(of: currentTabID)
        } else { // Aucun onglet dans l'espace
            print("[UpdateToolbar] Espace: \(pane.name ?? "N/A"), Aucun onglet. Ajout d'un onglet vide.")
            pane.addTab(urlString: "about:blank") // addTab définit currentTabID, ce qui rappellera cette fonction.
            urlStringToSetForToolbar = "about:blank"
        }
        
        if toolbarURLInput != urlStringToSetForToolbar {
            toolbarURLInput = urlStringToSetForToolbar
            print("[UpdateToolbar] toolbarURLInput mis à jour vers: \(toolbarURLInput)")
        }
        
        if let finalURLToLoad = urlToActuallyLoad {
            // Charger seulement si 'forceLoad' est vrai OU si l'URL actuelle du webView est différente
            if forceLoad || paneWebViewHelper.currentURL?.absoluteString != finalURLToLoad.absoluteString {
                print("[UpdateToolbar] Demande de chargement à paneWebViewHelper (\(Unmanaged.passUnretained(paneWebViewHelper).toOpaque())) URL: \(finalURLToLoad.absoluteString)")
                paneWebViewHelper.loadURL(finalURLToLoad)
            } else {
                print("[UpdateToolbar] Déjà sur l'URL \(finalURLToLoad.absoluteString) ou chargement non forcé.")
            }
        } else if forceLoad && (urlStringToSetForToolbar == "about:blank" || urlStringToSetForToolbar.isEmpty) {
             // Si on force le chargement et que l'URL cible est vide ou about:blank
            if let blankURL = URL(string: "about:blank") {
                 print("[UpdateToolbar] Forcer chargement de about:blank car forceLoad=true et url est vide/about:blank.")
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
        do {
            filteredToolbarHistory = try modelContext.fetch(fetchDescriptor)
        } catch {
            print("ERREUR: Échec de la récupération des suggestions d'historique: \(error)"); filteredToolbarHistory = []
        }
    }
    
    private func addAlveoPane(name: String? = nil, withURL url: URL) {
        saveCurrentTabState() // Sauvegarder l'état de l'onglet actuel avant de changer d'espace
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
        VStack {
            Text("Bienvenue dans Alveo !").font(.largeTitle)
            Text("Créez votre premier Espace pour commencer.").foregroundStyle(.secondary)
            Button("Créer le premier Espace") {
                addAlveoPane(withURL: URL(string: initialAlveoPaneURLString) ?? URL(string: "about:blank")!)
            }.padding(.top)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func addAlveoPaneDialog() -> some View {
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
            if let helper = currentWebViewHelper { // Utiliser currentWebViewHelper
                Button { if helper.canGoBack { helper.goBack() } } label: { Image(systemName: "chevron.left") }
                    .disabled(!helper.canGoBack)
                Button { if helper.canGoForward { helper.goForward() } } label: { Image(systemName: "chevron.right") }
                    .disabled(!helper.canGoForward)
            }
        }
        ToolbarItem(placement: .principal) {
            if let helper = currentWebViewHelper { // Utiliser currentWebViewHelper
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
                    Button { saveCurrentTabState(); activeAlveoPaneID = paneItem.id } label: {
                        HStack { Text(paneItem.name ?? "Espace"); if paneItem.id == activeAlveoPaneID { Image(systemName: "checkmark") } }
                    }
                }
                Divider()
                Button("Nouvel Espace...") { showAddAlveoPaneDialog = true }
                if let paneID = activeAlveoPaneID, let paneToDelete = alveoPanes.first(where: { $0.id == paneID }) {
                    Button("Supprimer l'Espace Actif", role: .destructive) {
                        modelContext.delete(paneToDelete)
                        // La logique de sélection du prochain espace est gérée par .onChange(of: alveoPanes.count)
                    }
                }
            } label: { Label("Espaces", systemImage: "square.stack.3d.down.right") }
            
            Button { currentActiveAlveoPaneObject?.addTab(urlString: "about:blank") } label: { Image(systemName: "plus.circle") }
            
            if let helper = currentWebViewHelper { // Utiliser currentWebViewHelper
                Button { helper.reload() } label: { Image(systemName: "arrow.clockwise") }.disabled(helper.isLoading)
            }
        }
    }
    
    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                HSplitView { // Utilisation de HSplitView pour le volet latéral
                    // Volet gauche (Sidebar)
                    if let activePaneToDisplay = currentActiveAlveoPaneObject {
                        SidebarView(
                            pane: activePaneToDisplay,
                            webViewHelper: getWebViewHelper(for: activePaneToDisplay.id)
                        )
                        .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                    } else {
                        Text("Aucun espace sélectionné.")
                            .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                            .background(Color(NSColor.controlBackgroundColor)) // Couleur de fond pour le placeholder
                    }
                    
                    // Volet principal (WebView)
                    Group {
                        if let activePaneToDisplay = currentActiveAlveoPaneObject {
                            ActiveAlveoPaneContainerView(
                                pane: activePaneToDisplay,
                                webViewHelper: getWebViewHelper(for: activePaneToDisplay.id),
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
                .onChange(of: alveoPanes.count) {
                    if let activeID = activeAlveoPaneID, !alveoPanes.contains(where: { $0.id == activeID }) {
                        activeAlveoPaneID = alveoPanes.first?.id
                    } else if activeAlveoPaneID == nil && !alveoPanes.isEmpty {
                        activeAlveoPaneID = alveoPanes.first?.id
                    }
                    // L'appel à updateToolbarURLInputAndLoadIfNeeded sera fait par le .onChange(of: activeAlveoPaneID)
                }
                .onChange(of: activeAlveoPaneID) {
                    print("[ContentView] activeAlveoPaneID changé en: \(String(describing: activeAlveoPaneID))")
                    // Sauvegarder l'état de l'ancien onglet/espace n'est pas fait ici,
                    // car l'ancien activeAlveoPaneID n'est plus directement accessible.
                    // La sauvegarde devrait se faire AVANT de changer activeAlveoPaneID.
                    updateToolbarURLInputAndLoadIfNeeded(forceLoad: true)
                }
                .onChange(of: currentActiveAlveoPaneObject?.currentTabID) {
                     print("[ContentView] currentTabID de l'espace \(currentActiveAlveoPaneObject?.name ?? "N/A") changé en: \(String(describing: currentActiveAlveoPaneObject?.currentTabID))")
                    updateToolbarURLInputAndLoadIfNeeded(forceLoad: true)
                }
                .sheet(isPresented: $showAddAlveoPaneDialog) { addAlveoPaneDialog() }
            }
        }
    }
}
