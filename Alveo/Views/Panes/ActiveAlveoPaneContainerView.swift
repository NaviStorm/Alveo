// Alveo/Views/Panes/ActiveAlveoPaneContainerView.swift
import SwiftUI
import SwiftData

@MainActor
struct ActiveAlveoPaneContainerView: View {
    @Bindable var pane: AlveoPane
    // ANCIEN: @ObservedObject var webViewHelper: WebViewHelper
    let tabWebViewHelpers: [UUID: WebViewHelper] // Dictionnaire de tous les helpers par Tab.ID
    
    
    @Binding var globalURLInput: String
    @Environment(\.modelContext) private var modelContext

    // Helper pour l'onglet actuellement actif dans ce pane (pour la vue unique)
    private var webViewHelperForCurrentActiveTabInPane: WebViewHelper? {
        guard let currentTabID = pane.currentTabID else { return nil }
        return tabWebViewHelpers[currentTabID]
    }

    var body: some View {
        let isInSplitView = pane.isSplitViewActive
        let currentTabIsInSplit = pane.splitViewTabIDs.contains(pane.currentTabID ?? UUID())

        VStack(spacing: 0) {
            if isInSplitView && currentTabIsInSplit {
//            if pane.isSplitViewActive && !pane.splitViewTabs.isEmpty {
                SplitWebView(
                    pane: pane,
                    tabWebViewHelpers: tabWebViewHelpers, // Passer tout le dictionnaire
                    globalURLInput: $globalURLInput
                )
            } else {
                // Vue normale (un seul onglet)
                if let helper = webViewHelperForCurrentActiveTabInPane {
                    AlveoPaneView(
                        pane: pane,
                        webViewHelper: helper, // Passer le helper spécifique de l'onglet actif
                        globalURLInput: $globalURLInput
                    )
                } else if pane.currentTabID != nil && webViewHelperForCurrentActiveTabInPane == nil {
                    // Cas où currentTabID est défini mais son helper n'est pas (encore) là.
                    // Cela peut arriver brièvement pendant les transitions.
                    // ContentView.ensureWebViewHelperExists devrait le créer.
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            print("[ActiveAlveoPaneContainerView] Helper manquant pour tab \(pane.currentTabID!), pane \(pane.id). Devrait être créé par ContentView.")
                        }
                } else if pane.tabs.isEmpty {
                     Text("Cet espace n'a aucun onglet.\nAjoutez-en un.")
                        .font(.title2).multilineTextAlignment(.center).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                 else {
                    Text("Aucun onglet sélectionné.") // currentTabID est nil mais il y a des onglets.
                        .font(.title2).multilineTextAlignment(.center).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
