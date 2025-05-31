import SwiftUI
import SwiftData
import WebKit

@MainActor
struct AlveoPaneView: View {
    @Bindable var pane: AlveoPane // 'pane' est votre "Espace"
    @StateObject var webViewHelper: WebViewHelper // Reçu de ContentView
    @Binding var globalURLInput: String      // Reçu de ContentView

    @Environment(\.modelContext) private var modelContext // Renommé pour éviter la confusion avec celui de ContentView

    init(pane: AlveoPane, webViewHelper: WebViewHelper, globalURLInput: Binding<String>) {
        self._pane = Bindable(wrappedValue: pane)
        self._webViewHelper = StateObject(wrappedValue: webViewHelper)
        self._globalURLInput = globalURLInput
    }

    var body: some View {
        // AlveoPaneView se concentre maintenant UNIQUEMENT sur l'affichage de la WebView
        // La barre d'onglets est gérée par ContentView via .safeAreaInset
        WebViewRepresentable(
            webView: webViewHelper.webView,
            onTitleChanged: { newTitle in
                if let currentTabId = pane.currentTabID,
                   let currentTab = pane.tabs.first(where: { $0.id == currentTabId }) {
                    // Vérifier si le titre a réellement changé pour éviter des écritures inutiles
                    if currentTab.title != newTitle {
                        currentTab.title = newTitle
                    }
                }
            },
            onURLChanged: { newURL in
                 if let currentTabId = pane.currentTabID,
                    let currentTab = pane.tabs.first(where: { $0.id == currentTabId }) {
                    let urlString = newURL?.absoluteString ?? ""
                    // Mettre à jour le modèle Tab seulement si l'URL a changé
                    if currentTab.urlString != urlString {
                        currentTab.urlString = urlString
                    }
                    // Mettre à jour le champ d'URL global dans ContentView
                    // seulement si l'URL a réellement changé dans la webview.
                    if self.globalURLInput != urlString {
                        self.globalURLInput = urlString
                    }
                }
            }
        )
        .onAppear {
            loadCurrentTabOrFallbackInPane()
        }
        // Les .onChange pour currentTabID sont maintenant gérés par ContentView
        // car ils affectent le activeWebViewHelper qui est dans ContentView.
        // Ce .onChange local est redondant si ContentView le fait déjà.
        // Je le commente pour éviter les doubles chargements.
        // .onChange(of: pane.currentTabID) { oldValue, newValue in
        //     handleCurrentTabChangeInPane(newTabID: newValue)
        // }
        .onChange(of: webViewHelper.isLoading) { oldValue, newValue in
            if oldValue == true && newValue == false {
                if let url = webViewHelper.currentURL, !url.absoluteString.isEmpty, url.absoluteString != "about:blank" {
                    saveToHistoryInPane(urlString: url.absoluteString, title: webViewHelper.pageTitle)
                }
            }
        }
        .onChange(of: webViewHelper.pageTitle) { oldValue, newValue in
            // Sauvegarder uniquement si le titre est non vide et que la page n'est pas en chargement
            if !webViewHelper.isLoading, let url = webViewHelper.currentURL, let title = newValue, !title.isEmpty {
                 saveToHistoryInPane(urlString: url.absoluteString, title: title)
            }
        }
    }

    // handleCloseTab a été déplacé dans ContentView car il doit potentiellement affecter activeAlveoPaneID

    private func loadCurrentTabOrFallbackInPane() {
        var urlToLoad: URL? = nil
        var urlStringToSetForGlobalInput: String = "about:blank"

        if let currentTabId = pane.currentTabID,
           let tabToLoad = pane.tabs.first(where: { $0.id == currentTabId }) {
            urlToLoad = tabToLoad.displayURL
            urlStringToSetForGlobalInput = tabToLoad.urlString
        } else if let firstTab = pane.sortedTabs.first {
            // Si aucun onglet n'est sélectionné, sélectionner le premier et le charger
            pane.currentTabID = firstTab.id // Ceci déclenchera le onChange dans ContentView
            urlToLoad = firstTab.displayURL
            urlStringToSetForGlobalInput = firstTab.urlString
        } else { // Aucun onglet du tout
            urlToLoad = URL(string: "about:blank")
            urlStringToSetForGlobalInput = "about:blank"
            if pane.tabs.isEmpty { // S'il n'y a vraiment aucun onglet
                pane.addTab(urlString: "about:blank") // Ceci déclenchera les onChange
            }
        }
        
        // Mettre à jour le champ global et charger l'URL via le helper partagé
        if globalURLInput != urlStringToSetForGlobalInput {
            globalURLInput = urlStringToSetForGlobalInput
        }
        if let finalURL = urlToLoad, (webViewHelper.currentURL != finalURL || webViewHelper.isLoading) {
            webViewHelper.loadURL(finalURL)
        }
    }

    // handleCurrentTabChangeInPane est maintenant principalement géré par les onChange de ContentView
    // qui observent currentActiveAlveoPaneObject?.currentTabID et activeAlveoPaneID.
    // Cette fonction est gardée pour référence si une logique locale était nécessaire.
    // private func handleCurrentTabChangeInPane(newTabID: UUID?) {
    //     // ... (Logique si AlveoPaneView devait réagir directement au changement de son propre currentTabID) ...
    //     // Typiquement, cela impliquerait de mettre à jour globalURLInput et de demander au webViewHelper de charger.
    //     // Mais c'est maintenant centralisé dans ContentView.
    // }
    
    private func saveToHistoryInPane(urlString: String, title: String?) {
        let normalizedUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedUrl.isEmpty,
              normalizedUrl != "about:blank",
              !normalizedUrl.starts(with: "https://www.google.com/search?q=") // Exemple
        else { return }

        let predicate = #Predicate<HistoryItem> { $0.urlString == normalizedUrl }
        var fetchDescriptor = FetchDescriptor<HistoryItem>(predicate: predicate)
        fetchDescriptor.fetchLimit = 1
        
        do {
            if let existingItem = try modelContext.fetch(fetchDescriptor).first {
                existingItem.title = title ?? existingItem.title
                existingItem.lastVisitedDate = Date()
                existingItem.visitCount += 1
            } else {
                let newItem = HistoryItem(urlString: normalizedUrl, title: title, lastVisitedDate: Date(), visitCount: 1)
                modelContext.insert(newItem)
            }
        } catch {
            print("Failed to save or update history from PaneView: \(error)")
        }
    }
}
