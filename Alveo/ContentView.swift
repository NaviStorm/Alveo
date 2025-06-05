// Alveo/ContentView.swift
import SwiftUI
import SwiftData

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
            print("[ContentView createAndStore] Helper existant pour TabID \(tabID): \(existingHelper.id)")
            return existingHelper
        }

        print("[ContentView createAndStore] Création nouveau helper pour TabID \(tabID) dans PaneID \(paneID)")
        let newHelper = WebViewHelper(customUserAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15")
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
        GeometryReader { geometry in
            NavigationStack { // Ou NavigationSplitView si vous préférez cette structure
                HSplitView {
                    // Volet Sidebar
                    if let activePaneForSidebar = currentActiveAlveoPaneObject {
                        // Le helper passé à SidebarView est celui de l'onglet actif du pane,
                        // mais SidebarView n'utilise peut-être pas directement ce helper,
                        // sauf pour des infos générales. Pour l'instant, on passe le helper de l'onglet actif.
                        // Si SidebarView a besoin d'un helper spécifique (ex: pour prévisualisation), il faudra ajuster.
                        // Actuellement, SidebarView prend un webViewHelper, qui n'est pas beaucoup utilisé.
                        // On peut passer le currentActiveWebViewHelper s'il existe.
                        let sidebarHelper = currentActiveWebViewHelper ?? WebViewHelper() // Fallback sur un helper vide si pas d'onglet actif

                        SidebarView(pane: activePaneForSidebar, webViewHelper: sidebarHelper)
                            .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                    } else {
                        Text("Aucun espace sélectionné.")
                            .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                            .background(Color(NSColor.controlBackgroundColor))
                    }

                    // Volet Contenu Principal
                    Group {
                        if let activePaneForContent = currentActiveAlveoPaneObject {
                            // ActiveAlveoPaneContainerView a besoin de tous les helpers pour les onglets de ce pane
                            // (pour la SplitView) et du helper de l'onglet actif (pour la vue unique).
                            // On lui passe tout le dictionnaire tabWebViewHelpers.
                             ActiveAlveoPaneContainerView(
                                pane: activePaneForContent,
                                tabWebViewHelpers: tabWebViewHelpers, // Passe tous les helpers
                                globalURLInput: $toolbarURLInput
                            )
                        } else {
                            noActivePanesView // S'il n'y a aucun pane du tout
                        }
                    }
                    .frame(minWidth: 300, idealWidth: 700, maxWidth: .infinity) // Ajustez selon vos besoins
                }
            }
            .toolbar {
                if let helperForToolbar = currentActiveWebViewHelper {
                    mainToolbarContent(geometry: geometry, using: helperForToolbar)
                } else {
                    // Toolbar minimale si aucun helper actif (ex: aucun onglet)
                    ToolbarItemGroup(placement: .principal) { Text("Alveo") }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { createNewTabAction() } label: { Image(systemName: "plus.circle") }
                           .disabled(currentActiveAlveoPaneObject == nil) // Désactivé si aucun pane actif
                    }
                }
            }
            .onAppear {
                print("[CV .onAppear] alveoPanes.count: \(alveoPanes.count)")
                createDefaultPaneIfNeeded() // Assure qu'au moins un pane existe et est actif
                // La sélection du pane et de son onglet initial déclenchera les .onChange appropriés
                // pour charger l'URL et initialiser le helper.
                // Si on vient de créer le premier pane, activeAlveoPaneID est setté,
                // .onChange(of: activeAlveoPaneID) va s'exécuter.
                if let paneID = activeAlveoPaneID, let pane = currentActiveAlveoPaneObject, let tabID = pane.currentTabID {
                    let _ = ensureWebViewHelperExists(forTabID: tabID, paneID: paneID)
                    updateToolbarURLInputAndLoadIfNeeded(forPaneID: paneID, forTabID: tabID, forceLoad: true)
                }
                
                DispatchQueue.main.async {
                    NSApplication.shared.windows.first { $0.isMainWindow }?.title = currentActiveAlveoPaneObject?.currentTab?.displayTitle ?? "Alveo"
                }
            }
            .onChange(of: alveoPanes.count) { oldValue, newValue in
                print("[CV .onChange(alveoPanes.count)] \(oldValue) -> \(newValue)")
                let previousActiveID = activeAlveoPaneID // Sauvegarder l'ID actif avant modification
                
                if let activeID = activeAlveoPaneID, !alveoPanes.contains(where: { $0.id == activeID }) {
                    // L'ancien pane actif a été supprimé
                    activeAlveoPaneID = alveoPanes.first?.id // Sélectionner le premier pane restant (s'il y en a)
                } else if activeAlveoPaneID == nil && !alveoPanes.isEmpty {
                    // Aucun pane n'était actif, mais il y en a maintenant
                    activeAlveoPaneID = alveoPanes.first?.id
                }
                
                // Nettoyage des helpers pour les panes qui n'existent plus (plus robuste que dans le menu de suppression)
                let existingPaneIDs = Set(alveoPanes.map { $0.id })
                var helpersToRemove: [UUID] = []
                for (tabID, helper) in tabWebViewHelpers {
                    // Trouver à quel pane appartient ce tabID. C'est complexe sans référence inverse Tab -> Pane.ID dans le helper.
                    // Pour l'instant, on se fie au nettoyage lors de la suppression explicite du pane.
                    // On peut au moins nettoyer les helpers des onglets qui n'appartiennent plus à *aucun* pane existant.
                    var tabExistsInAnyPane = false
                    for pane_ in alveoPanes {
                        if pane_.tabs.contains(where: { $0.id == tabID }) {
                            tabExistsInAnyPane = true
                            break
                        }
                    }
                    if !tabExistsInAnyPane {
                        helpersToRemove.append(tabID)
                    }
                }
                helpersToRemove.forEach { tabWebViewHelpers.removeValue(forKey: $0) }
                if !helpersToRemove.isEmpty { print("[CV .onChange(alveoPanes.count)] Nettoyé \(helpersToRemove.count) tabWebViewHelpers orphelins.") }


                if previousActiveID != activeAlveoPaneID {
                    // Le changement de activeAlveoPaneID sera géré par son propre .onChange
                    // print("[CV .onChange(alveoPanes.count)] activeAlveoPaneID a changé. Laisser son .onChange gérer.")
                } else if let currentID = activeAlveoPaneID, let currentPane = currentActiveAlveoPaneObject { // Si l'ID actif n'a pas changé mais le contenu des panes (ex: suppression d'un *autre* pane)
                    // S'assurer que le helper pour l'onglet actif du pane actif existe
                    if let currentTabID = currentPane.currentTabID {
                         let _ = ensureWebViewHelperExists(forTabID: currentTabID, paneID: currentID)
                         updateToolbarURLInputAndLoadIfNeeded(forPaneID: currentID, forTabID: currentTabID, forceLoad: false) // Ne pas forcer le rechargement si pas nécessaire
                    } else if let firstTab = currentPane.tabsForDisplay.first { // Si le pane actif n'a plus d'onglet sélectionné
                        currentPane.currentTabID = firstTab.id // Déclenchera .onChange(of: currentTabID)
                    } else { // Si le pane actif est vide
                        currentPane.addTab(urlString: "about:blank") // Déclenchera .onChange(of: currentTabID)
                    }
                }
            }
            .onChange(of: activeAlveoPaneID) { oldValue, newValue in
                print(">>> [CV .onChange(activeAlveoPaneID)] \(String(describing: oldValue)) -> \(String(describing: newValue))")
                
                // Sauvegarder l'état de l'onglet actif du pane précédent
                if let oldPaneID = oldValue, let oldPane = alveoPanes.first(where: {$0.id == oldPaneID}) {
                     saveCurrentTabState(forPaneID: oldPaneID, forTabID: oldPane.currentTabID)
                }

                if let newPaneID = newValue, let newPane = alveoPanes.first(where: { $0.id == newPaneID }) {
                    if let newCurrentTabID = newPane.currentTabID {
                        let _ = ensureWebViewHelperExists(forTabID: newCurrentTabID, paneID: newPane.id)
                        updateToolbarURLInputAndLoadIfNeeded(forPaneID: newPaneID, forTabID: newCurrentTabID, forceLoad: true) // Forcer le chargement pour le nouveau pane/tab
                    } else if let firstTab = newPane.tabsForDisplay.first { // Si le nouveau pane n'a pas d'onglet sélectionné
                        newPane.currentTabID = firstTab.id // Ceci va redéclencher .onChange(of: currentActiveAlveoPaneObject?.currentTabID)
                                                           // qui s'occupera de ensureHelper et updateToolbar
                    } else { // Si le nouveau pane est vide
                        newPane.addTab(urlString: "about:blank") // Idem, .onChange(of: currentTabID)
                    }
                } else {
                    toolbarURLInput = "" // Aucun pane actif
                }
            }
            .onChange(of: currentActiveAlveoPaneObject?.currentTabID) { oldValue, newValue in
                print(">>> [CV .onChange(currentTabID)] Pane '\(currentActiveAlveoPaneObject?.name ?? "N/A")': \(String(describing: oldValue)) -> \(String(describing: newValue))")
                
                guard let activePane = currentActiveAlveoPaneObject else { return }

                // Sauvegarder l'état de l'ancien onglet actif (s'il y en avait un dans ce pane)
                if let oldTabID = oldValue {
                    saveCurrentTabState(forPaneID: activePane.id, forTabID: oldTabID)
                }

                if let newTabID = newValue {
                    // Mettre à jour l'historique des onglets
                    tabHistory.removeAll { $0 == newTabID }
                    tabHistory.insert(newTabID, at: 0)
                    if tabHistory.count > 10 { tabHistory = Array(tabHistory.prefix(10)) }
                    print("[ContentView] Historique onglets mis à jour. Taille: \(tabHistory.count)")

                    // S'assurer que le helper existe pour le nouvel onglet actif et charger son contenu
                    let _ = ensureWebViewHelperExists(forTabID: newTabID, paneID: activePane.id)
                    updateToolbarURLInputAndLoadIfNeeded(forPaneID: activePane.id, forTabID: newTabID, forceLoad: true)
                    
                    activePane.tabs.first(where: { $0.id == newTabID })?.lastAccessed = Date()

                } else { // currentTabID est devenu nil
                    // Cela peut arriver si tous les onglets sont fermés.
                    // Si le pane a encore des onglets, en sélectionner un. Sinon, en créer un.
                    if let firstTab = activePane.tabsForDisplay.first {
                        activePane.currentTabID = firstTab.id // Déclenchera une nouvelle passe de ce .onChange
                    } else {
                        activePane.addTab(urlString: "about:blank") // Idem
                    }
                }
            }
            // Observer les changements dans la liste des onglets du pane actif (pour le nettoyage des helpers)
            .onChange(of: currentActiveAlveoPaneObject?.tabs) { oldTabs, newTabs in
                guard let pane = currentActiveAlveoPaneObject else { return }
                let newTabIDsSet = Set((newTabs ?? []).map { $0.id })
                
                var helpersCleaned = 0
                for (tabID, _) in tabWebViewHelpers {
                    // Vérifier si cet helper appartient à un onglet qui n'est plus dans le pane actif
                    // ET qui n'est dans aucun autre pane non plus (cas plus complexe à gérer ici proprement)
                    // Pour l'instant, on nettoie seulement si un onglet du *pane actif* a été supprimé.
                    if pane.tabs.contains(where: {$0.id == tabID}) { // L'onglet appartient à ce pane
                        // Si l'onglet n'est plus dans la nouvelle liste de tabs pour ce pane, il a été supprimé de ce pane.
                        // Mais .onChange(of: tabs) est pour la collection, pas pour la suppression individuelle.
                        // Ce n'est peut-être pas le bon endroit. Le nettoyage lors de la suppression explicite est mieux.
                    }
                }
                // Mieux: nettoyer les helpers dont les tabID ne sont plus dans AUCUN pane.
                let allTabsInAllPanes = Set(alveoPanes.flatMap { $0.tabs.map { $0.id } })
                let orphanedHelperKeys = tabWebViewHelpers.keys.filter { !allTabsInAllPanes.contains($0) }
                orphanedHelperKeys.forEach { key in
                    tabWebViewHelpers.removeValue(forKey: key)
                    helpersCleaned += 1
                }
                if helpersCleaned > 0 {
                    print("[CV .onChange(tabs)] Nettoyé \(helpersCleaned) tabWebViewHelpers pour des onglets globalement supprimés.")
                }
            }
            .sheet(isPresented: $showAddAlveoPaneDialog) {
                addAlveoPaneDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .createNewTabFromMenu)) { _ in createNewTabAction() }
            .onReceive(NotificationCenter.default.publisher(for: .closeTabOrWindowFromMenu)) { _ in closeCurrentTabOrWindowAction() }
            .onReceive(NotificationCenter.default.publisher(for: .enableSplitViewFromMenu)) { _ in enableSplitViewFromMenu() }
            .onReceive(NotificationCenter.default.publisher(for: .disableSplitViewFromMenu)) { _ in disableSplitViewFromMenu() }
            
            // Retrait des boutons invisibles ici, les .keyboardShortcut sur les Button dans le menu suffisent.
        }
    }

    private func enableSplitViewFromMenu() {
        guard let activePane = currentActiveAlveoPaneObject else { return }
        if !activePane.isSplitViewActive {
            if let currentTabID = activePane.currentTabID {
                let originalTab = activePane.tabs.first(where: {$0.id == currentTabID})
                
                // Ajouter un nouvel onglet vide à côté
                activePane.addTab(urlString: "about:blank") // Cela va définir currentTabID sur le nouvel onglet
                if let newBlankTabID = activePane.currentTabID, newBlankTabID != currentTabID {
                     activePane.enableSplitView(with: [currentTabID, newBlankTabID])
                     // Rétablir l'onglet original comme onglet actif pour la vue fractionnée (ou le nouveau, selon préférence)
                     activePane.currentTabID = currentTabID // Ou newBlankTabID
                } else {
                    // Si addTab n'a pas changé currentTabID (par ex. si c'était le seul onglet),
                    // il faut trouver l'ID du nouvel onglet.
                    // C'est une situation anormale si addTab ne met pas à jour currentTabID.
                    print("Erreur: Impossible de récupérer l'ID du nouvel onglet pour la vue fractionnée.")
                }
            }
        }
    }

    private func disableSplitViewFromMenu() {
        guard let activePane = currentActiveAlveoPaneObject else { return }
        activePane.disableSplitView()
    }
}
