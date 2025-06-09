// Alveo/ContentView.swift
import SwiftUI
import SwiftData
import WebKit

@MainActor
struct ContentView: View {
    // MARK: - Environment & Queries
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlveoPane.creationDate, order: .forward) private var alveoPanes: [AlveoPane]

    // MARK: - State Variables
    @State private var activeAlveoPaneID: UUID?
    // ANCIEN: @State private var webViewHelpers: [UUID: WebViewHelper] = [:] // Clé: Pane.ID
    @State private var tabWebViewHelpers: [UUID: WebViewHelper] = [:] // NOUVEAU: Clé: Tab.ID

    @State private var toolbarURLInput: String = ""
    @State private var showToolbarSuggestions: Bool = false
    @State private var filteredToolbarHistory: [HistoryItem] = []
    @FocusState private var isToolbarAddressBarFocused: Bool

    @State private var showAddAlveoPaneDialog = false
    @State private var newAlveoPaneName: String = ""
    @State private var initialAlveoPaneURLString: String = "https://www.google.com"
    @State private var tabHistory: [UUID] = []
    
    @StateObject private var globalIsolationManager = DataIsolationManager()

    // MARK: - Computed Properties
    var currentActiveAlveoPaneObject: AlveoPane? {
        guard let activeID = activeAlveoPaneID else { return alveoPanes.first }
        return alveoPanes.first(where: { $0.id == activeID })
    }

    // NOUVEAU: Helper pour l'onglet actif globalement
    private var currentActiveWebViewHelper: WebViewHelper? {
        guard let activePane = currentActiveAlveoPaneObject,
              let activeTabID = activePane.currentTabID else { return nil }
        return tabWebViewHelpers[activeTabID]
    }
    
    // MARK: - Action Handlers for Keyboard Shortcuts
    private func createNewTabAction() {
        print("[ContentView ACTION] Nouvel Onglet (Cmd-T)")
        guard let activePane = currentActiveAlveoPaneObject else {
            print("[ContentView ACTION] Aucun espace actif pour créer un onglet.")
            if alveoPanes.isEmpty {
                createDefaultPaneIfNeeded() // Ceci devrait sélectionner un pane et permettre la création d'onglet après
            }
            return
        }
        activePane.addTab(urlString: "about:blank") // Ceci changera activePane.currentTabID
                                                    // et .onChange(of: currentActiveAlveoPaneObject?.currentTabID) s'en occupera.
    }

    private func closeCurrentTabOrWindowAction() {
        print("[ContentView ACTION] Fermer Onglet ou Fenêtre (Cmd-W)")
        guard let activePane = currentActiveAlveoPaneObject,
              let currentTabID = activePane.currentTabID,
              let tabToClose = activePane.tabs.first(where: { $0.id == currentTabID }) else {
            // S'il n'y a pas d'onglet actif ou de pane actif, on peut envisager de fermer la fenêtre
             print("[ContentView ACTION] Aucun onglet actif à fermer. Tentative de fermeture de la fenêtre.")
             NSApplication.shared.keyWindow?.close()
            return
        }
        
        print("[ContentView ACTION] Fermeture de l'onglet: '\(tabToClose.displayTitle)' ID: \(currentTabID)")
        let tabIDToClose = tabToClose.id
        guard let indexToRemove = activePane.tabs.firstIndex(where: { $0.id == tabIDToClose }) else { return }

        tabHistory.removeAll { $0 == tabIDToClose }
        tabWebViewHelpers.removeValue(forKey: tabIDToClose) // Nettoyer le helper
        modelContext.delete(tabToClose) // SwiftData mettra à jour activePane.tabs

        // La logique de sélection du prochain onglet est délicate car activePane.tabs
        // n'est peut-être pas encore mis à jour par SwiftData ici.
        // On se fie à .onChange(of: currentActiveAlveoPaneObject?.tabs.count) ou .onChange(of: currentTabID)
        // pour gérer la sélection du prochain onglet. Pour l'instant, on invalide currentTabID.
        
        if activePane.tabs.isEmpty { // Après suppression, si le pane devient vide
            activePane.currentTabID = nil
        } else {
            // Essayer de sélectionner un autre onglet basé sur l'historique ou la position
            var nextTabID: UUID? = nil
            if let historyBasedNextTab = tabHistory.first(where: { tid in activePane.tabs.contains(where: { $0.id == tid }) && tid != tabIDToClose }) {
                nextTabID = historyBasedNextTab
            } else { // Logique positionnelle
                let newIndex = min(indexToRemove, activePane.tabs.count - 1) // tabs.count est déjà après la suppression implicite par SwiftData
                if newIndex >= 0 && newIndex < activePane.tabs.count {
                    nextTabID = activePane.tabs[newIndex].id
                } else if !activePane.tabs.isEmpty {
                    nextTabID = activePane.tabs.first?.id
                }
            }
            activePane.currentTabID = nextTabID
        }
    }

    // MARK: - Helper Management
    private func createAndStoreWebViewHelper(forTabID tabID: UUID, paneID: UUID) -> WebViewHelper {
        if let existingHelper = tabWebViewHelpers[tabID] {
            return existingHelper
        }

        // ✅ Utiliser le niveau d'isolation configuré
        let newHelper = WebViewHelper(
            customUserAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15",
            isolationLevel: globalIsolationManager.isolationLevel // ← Utiliser le niveau configuré
        )
        
        newHelper.onNavigationEvent = { newURL, newTitle in
            self.handleNavigationEvent(forPaneID: paneID, forTabID: tabID, newURL: newURL, newTitle: newTitle)
        }
        
        tabWebViewHelpers[tabID] = newHelper
        return newHelper
    }
    

    private func ensureWebViewHelperExists(forTabID tabID: UUID, paneID: UUID) -> WebViewHelper {
        if let existingHelper = tabWebViewHelpers[tabID] {
            return existingHelper
        }
        return createAndStoreWebViewHelper(forTabID: tabID, paneID: paneID)
    }

    private func handleNavigationEvent(forPaneID paneID: UUID, forTabID tabID: UUID, newURL: URL?, newTitle: String?) {
        guard let paneForEvent = alveoPanes.first(where: { $0.id == paneID }),
              let tabForEvent = paneForEvent.tabs.first(where: { $0.id == tabID }) else {
            print("[Callback NavEvent] Pane ou Tab non trouvé pour paneID: \(paneID), tabID: \(tabID)")
            return
        }

        var tabModelUpdated = false
        if let urlAbsoluteString = newURL?.absoluteString, tabForEvent.urlString != urlAbsoluteString {
            tabForEvent.urlString = urlAbsoluteString
            print("[Callback NavEvent] TabID \(tabID) - URL mise à jour: \(urlAbsoluteString)")
            tabModelUpdated = true
        }

        if let title = newTitle, !title.isEmpty, tabForEvent.title != title {
            tabForEvent.title = title
            print("[Callback NavEvent] TabID \(tabID) - Titre mis à jour: \(title)")
            tabModelUpdated = true
        }

        if tabModelUpdated {
             tabForEvent.lastAccessed = Date() // Mettre à jour la date d'accès si l'URL ou le titre change
        }
        
        // Mettre à jour la barre d'URL si cet onglet est l'actif global et que la barre n'est pas en focus
        if paneID == self.activeAlveoPaneID && tabID == self.currentActiveAlveoPaneObject?.currentTabID && !self.isToolbarAddressBarFocused {
            if let currentTabActualURL = newURL?.absoluteString, toolbarURLInput != currentTabActualURL {
                toolbarURLInput = currentTabActualURL
                print("[Callback NavEvent] toolbarURLInput mis à jour pour TabID \(tabID): \(currentTabActualURL)")
            }
        }
    }
    
    private func saveCurrentTabState(forPaneID paneID: UUID?, forTabID tabID: UUID?) {
        guard let paneIdToSave = paneID, let tabIdToSave = tabID,
              let paneToSave = alveoPanes.first(where: { $0.id == paneIdToSave }),
              let tabToSave = paneToSave.tabs.first(where: { $0.id == tabIdToSave }),
              let helperToSaveFrom = tabWebViewHelpers[tabIdToSave] else {
            // print("[ContentView saveCurrentTabState] Conditions non remplies pour TabID \(String(describing: tabID))")
            return
        }

        if let currentURL = helperToSaveFrom.currentURL, currentURL.absoluteString != "about:blank" {
            if tabToSave.urlString != currentURL.absoluteString {
                tabToSave.urlString = currentURL.absoluteString
            }
        }
        if let currentTitle = helperToSaveFrom.pageTitle, !currentTitle.isEmpty {
             if tabToSave.title != currentTitle {
                tabToSave.title = currentTitle
            }
        }
        // tabToSave.lastAccessed = Date() // lastAccessed est mis à jour lors de la sélection ou de l'événement de navigation
        print("[ContentView saveCurrentTabState] État (potentiellement) sauvegardé pour onglet \(tabIdToSave)")
    }

    private func updateToolbarURLInputAndLoadIfNeeded(forPaneID paneID: UUID, forTabID tabID: UUID?, forceLoad: Bool) {
        guard let pane = alveoPanes.first(where: { $0.id == paneID }) else {
            toolbarURLInput = ""
            print("[UpdateToolbarAndLoad] Espace non trouvé pour ID: \(paneID)")
            return
        }

        guard let targetTabID = tabID, // Utiliser le tabID fourni
              let tabToLoad = pane.tabs.first(where: { $0.id == targetTabID }) else {
            // Si le tabID fourni est nil ou non trouvé, essayer de prendre le currentTabID du pane, ou le premier, ou créer un onglet vide.
            // Cette situation devrait être gérée par l'appelant ou les .onChange qui définissent un currentTabID valide.
            print("[UpdateToolbarAndLoad] Onglet non trouvé pour TabID: \(String(describing: tabID)) dans PaneID: \(paneID). Tentative de fallback.")
            if let currentTabOfPane = pane.currentTab { // Si le pane a un onglet courant défini
                updateToolbarURLInputAndLoadIfNeeded(forPaneID: paneID, forTabID: currentTabOfPane.id, forceLoad: forceLoad)
            } else if let firstTab = pane.tabsForDisplay.first { // Sinon, prendre le premier
                pane.currentTabID = firstTab.id // Ceci déclenchera .onChange(of: currentActiveAlveoPaneObject?.currentTabID)
            } else { // Sinon, ajouter un onglet vide
                pane.addTab(urlString: "about:blank") // Ceci déclenchera aussi .onChange
            }
            return
        }
        
        print(">>> [UpdateToolbarAndLoad] Pane: '\(pane.name ?? "N/A")', Tab: '\(tabToLoad.displayTitle)', forceLoad: \(forceLoad)")

        let tabWebViewHelper = ensureWebViewHelperExists(forTabID: tabToLoad.id, paneID: pane.id)
        let urlStringToSetForToolbar = tabToLoad.urlString

        if toolbarURLInput != urlStringToSetForToolbar && !isToolbarAddressBarFocused {
            toolbarURLInput = urlStringToSetForToolbar
            print("[UpdateToolbarAndLoad] toolbarURLInput mis à jour: \(toolbarURLInput)")
        }

        if forceLoad {
            let urlToLoadInWebView = tabToLoad.displayURL ?? URL(string: "about:blank")!
            // Charger seulement si l'URL actuelle du helper est différente, ou si c'est about:blank (pour forcer le rafraîchissement de la page vide)
            // ou si l'URL du helper est nil.
            if tabWebViewHelper.currentURL != urlToLoadInWebView || urlToLoadInWebView.absoluteString == "about:blank" || tabWebViewHelper.currentURL == nil {
                print(">>> [UpdateToolbarAndLoad] CHARGEMENT effectif via helper pour TabID \(tabToLoad.id): \(urlToLoadInWebView.absoluteString)")
                tabWebViewHelper.loadURL(urlToLoadInWebView)
            } else {
                 print(">>> [UpdateToolbarAndLoad] Pas de rechargement nécessaire pour TabID \(tabToLoad.id), URL identique: \(urlToLoadInWebView.absoluteString)")
            }
        }
    }
    
    private func fetchToolbarHistorySuggestions(for query: String) {
        // ... (logique existante)
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
        // Sauver l'état de l'onglet actif du pane précédent
        if let oldPaneID = activeAlveoPaneID, let oldPane = alveoPanes.first(where: {$0.id == oldPaneID}) {
             saveCurrentTabState(forPaneID: oldPaneID, forTabID: oldPane.currentTabID)
        }
       
        let paneName = name ?? "Espace \(alveoPanes.count + 1)"
        // Crée un pane avec un onglet initial. Le currentTabID sera défini par l'init de AlveoPane.
        let newPane = AlveoPane(name: paneName, initialTabURLString: url.absoluteString)
        modelContext.insert(newPane)
        print("[ContentView addAlveoPane] Nouvel Espace créé: '\(paneName)' avec TabID \(String(describing: newPane.currentTabID))")
        
        activeAlveoPaneID = newPane.id // Déclenche .onChange(of: activeAlveoPaneID)
    }

    private func createDefaultPaneIfNeeded() {
        if alveoPanes.isEmpty {
            print("[ContentView createDefaultPaneIfNeeded] Création de l'Espace par défaut")
            let defaultURL = URL(string: initialAlveoPaneURLString) ?? URL(string: "about:blank")!
            addAlveoPane(name: "Mon Premier Espace", withURL: defaultURL)
        } else {
            print("[ContentView createDefaultPaneIfNeeded] Des Espaces existent déjà.")
            if activeAlveoPaneID == nil { // Si aucun pane n'est actif, activer le premier
                activeAlveoPaneID = alveoPanes.first?.id
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
        // ... (contenu existant, qui utilise le 'helper' passé, qui est currentActiveWebViewHelper)
        ToolbarItemGroup(placement: .navigation) {
            Button {
                if helper.canGoBack { helper.goBack() }
            } label: { Image(systemName: "chevron.left") }
            .disabled(!helper.canGoBack)

            Button {
                if helper.canGoForward { helper.goForward() }
            } label: { Image(systemName: "chevron.right") }
            .disabled(!helper.canGoForward)
        }

        ToolbarItem(placement: .principal) {
            PrincipalToolbarView(
                webViewHelper: helper, // C'est le helper de l'onglet actif global
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
            Menu { // Menu de sélection des Espaces
                ForEach(alveoPanes) { paneItem in
                    Button {
                        if activeAlveoPaneID != paneItem.id {
                            // Sauver état onglet actif du pane précédent
                            saveCurrentTabState(forPaneID: activeAlveoPaneID, forTabID: currentActiveAlveoPaneObject?.currentTabID)
                            activeAlveoPaneID = paneItem.id // Déclenche .onChange(of: activeAlveoPaneID)
                        }
                    } label: {
                        HStack { Text(paneItem.name ?? "Espace"); if paneItem.id == activeAlveoPaneID { Image(systemName: "checkmark") } }
                    }
                }
                Divider()
                Button("Nouvel Espace...") { showAddAlveoPaneDialog = true }

                if let paneID = activeAlveoPaneID, let paneToDelete = alveoPanes.first(where: { $0.id == paneID }), alveoPanes.count > 1 {
                    Divider()
                    Button("Supprimer l'Espace Actif", role: .destructive) {
                        // Nettoyer les helpers des onglets de ce pane
                        paneToDelete.tabs.forEach { tab in tabWebViewHelpers.removeValue(forKey: tab.id) }
                        modelContext.delete(paneToDelete)
                        // activeAlveoPaneID deviendra nil ou le premier de la liste restante via .onChange(of: alveoPanes.count)
                    }
                }
            } label: { Label("Espaces", systemImage: "square.stack.3d.down.right") }
            
            Button { // Bouton "+" pour nouvel onglet
                createNewTabAction()
            } label: { Image(systemName: "plus.circle") }

            Button { // Bouton Recharger
                helper.reload()
            } label: { Image(systemName: "arrow.clockwise") }
            .disabled(helper.isLoading)
        }
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Barre d'outils principale
            GeometryReader { geometry in
                HStack {
                    Spacer()
                    
                    if let activeHelper = currentActiveWebViewHelper {
                        PrincipalToolbarView(
                            webViewHelper: activeHelper,
                            urlInput: $toolbarURLInput,
                            showSuggestions: $showToolbarSuggestions,
                            filteredHistory: $filteredToolbarHistory,
                            isFocused: $isToolbarAddressBarFocused,
                            geometryProxy: geometry,
                            fetchHistoryAction: fetchToolbarHistorySuggestions
                        )
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(height: 48)
            
            Divider()
            
            // Contenu principal avec sidebar et vue principale
            HStack(spacing: 0) {
                // SIDEBAR à gauche
                if let activePane = currentActiveAlveoPaneObject,
                   let activeHelper = currentActiveWebViewHelper {
                    SidebarView(
                        pane: activePane,
                        webViewHelper: activeHelper,
                        globalIsolationManager: globalIsolationManager
                    )
                    .frame(minWidth: 200, maxWidth: 300)
                }
                
                Divider()
                
                // CONTENU PRINCIPAL à droite
                VStack(spacing: 0) {
                    // WebView
                    if let activePane = currentActiveAlveoPaneObject {
                        ActiveAlveoPaneContainerView(
                            pane: activePane,
                            tabWebViewHelpers: tabWebViewHelpers,
                            globalURLInput: $toolbarURLInput
                        )
                    } else {
                        noActivePanesView
                    }
                }
            }
        }
        .onAppear {
            createDefaultPaneIfNeeded()
            if activeAlveoPaneID == nil && !alveoPanes.isEmpty {
                activeAlveoPaneID = alveoPanes.first?.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNewTabFromMenu)) { _ in
            createNewTabAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTabOrWindowFromMenu)) { _ in
            closeCurrentTabOrWindowAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: .enableSplitViewFromMenu)) { _ in
            enableSplitViewFromMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: .disableSplitViewFromMenu)) { _ in
            disableSplitViewFromMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: .enableSplitViewWithSelection)) { notification in
            guard let paneID = notification.object as? UUID,
                  let activePane = alveoPanes.first(where: { $0.id == paneID }),
                  let tabIDsArray = notification.userInfo?["tabIDs"] as? [UUID] else { return }
            
            // ✅ Créer les helpers pour tous les onglets avant d'activer la vue fractionnée
            for tabID in tabIDsArray {
                let _ = ensureWebViewHelperExists(forTabID: tabID, paneID: activePane.id)
            }
            
            activePane.enableSplitView(with: tabIDsArray)
            
            // Définir le premier comme actif
            if let firstSelectedTabID = tabIDsArray.first {
                activePane.currentTabID = firstSelectedTabID
            }
            
            print("[ContentView] Vue fractionnée activée via notification avec \(tabIDsArray.count) onglets")
        }
        .onChange(of: activeAlveoPaneID) { oldPaneID, newPaneID in
            print("[ContentView .onChange(of: activeAlveoPaneID)] Changement de \(String(describing: oldPaneID)) vers \(String(describing: newPaneID))")
            
            // Sauvegarder l'état de l'ancien pane
            if let oldID = oldPaneID, let oldPane = alveoPanes.first(where: { $0.id == oldID }) {
                saveCurrentTabState(forPaneID: oldID, forTabID: oldPane.currentTabID)
            }
            
            // Charger le nouvel espace actif
            if let newID = newPaneID {
                updateToolbarURLInputAndLoadIfNeeded(forPaneID: newID, forTabID: currentActiveAlveoPaneObject?.currentTabID, forceLoad: true)
            }
        }
        .onChange(of: currentActiveAlveoPaneObject?.currentTabID) { oldTabID, newTabID in
            print("[ContentView .onChange(of: currentTabID)] Changement de \(String(describing: oldTabID)) vers \(String(describing: newTabID))")
            
            guard let activePane = currentActiveAlveoPaneObject else { return }
            
            // Sauvegarder l'état de l'ancien onglet
            if let oldID = oldTabID {
                saveCurrentTabState(forPaneID: activePane.id, forTabID: oldID)
            }
            
            // Mettre à jour l'historique des onglets
            if let newID = newTabID {
                tabHistory.removeAll { $0 == newID }
                tabHistory.insert(newID, at: 0)
                if tabHistory.count > 10 { tabHistory.removeLast() }
                
                // Mettre à jour lastAccessed
                if let newTab = activePane.tabs.first(where: { $0.id == newID }) {
                    newTab.lastAccessed = Date()
                }
                
                updateToolbarURLInputAndLoadIfNeeded(forPaneID: activePane.id, forTabID: newID, forceLoad: true)
            } else {
                // Aucun onglet sélectionné, ajouter un onglet vide
                activePane.addTab(urlString: "about:blank")
            }
        }
        .onChange(of: alveoPanes.count) { oldCount, newCount in
            print("[ContentView .onChange(of: alveoPanes.count)] Changement de \(oldCount) vers \(newCount)")
            
            if newCount == 0 {
                activeAlveoPaneID = nil
                tabWebViewHelpers.removeAll()
                toolbarURLInput = ""
            } else if activeAlveoPaneID == nil || !alveoPanes.contains(where: { $0.id == activeAlveoPaneID }) {
                activeAlveoPaneID = alveoPanes.first?.id
            }
        }
        .onChange(of: currentActiveAlveoPaneObject?.tabs.count) { oldCount, newCount in
            print("[ContentView .onChange(of: tabs.count)] Changement de \(String(describing: oldCount)) vers \(String(describing: newCount))")
            
            guard let activePane = currentActiveAlveoPaneObject else { return }
            
            if newCount == 0 {
                activePane.currentTabID = nil
            } else if activePane.currentTabID == nil || !activePane.tabs.contains(where: { $0.id == activePane.currentTabID }) {
                activePane.currentTabID = activePane.tabs.first?.id
            }
            
            // Nettoyer les helpers orphelins
            let validTabIDs = Set(activePane.tabs.map { $0.id })
            for (tabID, _) in tabWebViewHelpers {
                if !validTabIDs.contains(tabID) {
                    tabWebViewHelpers.removeValue(forKey: tabID)
                    print("[ContentView] Helper orphelin supprimé pour TabID: \(tabID)")
                }
            }
        }
        .sheet(isPresented: $showAddAlveoPaneDialog, onDismiss: resetAddAlveoPaneDialogFields) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Créer un nouvel Espace")
                    .font(.headline)
                
                TextField("Nom de l'Espace", text: $newAlveoPaneName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("URL de départ", text: $initialAlveoPaneURLString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    Button("Annuler") {
                        showAddAlveoPaneDialog = false
                    }
                    .keyboardShortcut(.escape)
                    
                    Spacer()
                    
                    Button("Créer") {
                        let url = URL(string: initialAlveoPaneURLString) ?? URL(string: "about:blank")!
                        addAlveoPane(name: newAlveoPaneName.isEmpty ? nil : newAlveoPaneName, withURL: url)
                        showAddAlveoPaneDialog = false
                    }
                    .keyboardShortcut(.return)
                }
            }
            .padding()
            .frame(width: 400)
        }
    }
    
    private func enableSplitViewFromMenu() {
        guard let activePane = currentActiveAlveoPaneObject else { return }
        
        // ✅ Si plusieurs onglets sont sélectionnés, les utiliser pour la vue fractionnée
        if activePane.selectedTabIDs.count > 1 {
            let tabIDsArray = Array(activePane.selectedTabIDs)
            activePane.enableSplitView(with: tabIDsArray)
            
            // Définir le premier comme actif
            if let firstSelectedTabID = tabIDsArray.first {
                activePane.currentTabID = firstSelectedTabID
            }
            
            // Vider la sélection
            activePane.selectedTabIDs.removeAll()
            
            print("[ContentView] Vue fractionnée activée via menu avec \(tabIDsArray.count) onglets sélectionnés")
            return
        }
        
        // ✅ Comportement existant si un seul onglet ou aucune sélection
        if !activePane.isSplitViewActive {
            if let currentTabID = activePane.currentTabID {
                // Ajouter un nouvel onglet vide à côté
                activePane.addTab(urlString: "about:blank")
                if let newBlankTabID = activePane.currentTabID, newBlankTabID != currentTabID {
                    activePane.enableSplitView(with: [currentTabID, newBlankTabID])
                    activePane.currentTabID = currentTabID
                }
            }
        }
    }
    

    private func disableSplitViewFromMenu() {
        guard let activePane = currentActiveAlveoPaneObject else { return }
        activePane.disableSplitView()
    }
}
