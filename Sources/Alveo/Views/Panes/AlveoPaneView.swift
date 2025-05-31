import SwiftUI
import SwiftData // Nécessaire car AlveoPane est un @Model

@MainActor
struct AlveoPaneView: View {
    @Bindable var pane: AlveoPane // CORRECT : @Bindable est utilisé
    @ObservedObject var webViewHelper: WebViewHelper
    @Binding var globalURLInput: String

    var body: some View {
        VStack(spacing: 0) {
            // Utilisation de la propriété calculée pane.currentTab
            if let currentTab = pane.currentTab { // Plus besoin de vérifier pane.currentTabID != nil
                let _ = print(">>> [AlveoPaneView BODY] Espace '\(pane.name ?? "N/A")', Onglet '\(currentTab.displayTitle)', Helper ID: \(webViewHelper.id), sa WKWebView ID: \(Unmanaged.passUnretained(webViewHelper.webView).toOpaque())")
                
                WebViewRepresentable(webView: webViewHelper.webView)
                    .id(webViewHelper.id)

                if webViewHelper.isLoading && webViewHelper.estimatedProgress > 0 && webViewHelper.estimatedProgress < 1.0 {
                    ProgressView(value: webViewHelper.estimatedProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 3)
                        .transition(.opacity)
                }
                
            } else if pane.tabs.isEmpty {
                Text("Cet espace n'a aucun onglet.\nAjoutez-en un depuis le volet latéral.")
                    .font(.title2).multilineTextAlignment(.center).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Ce cas peut arriver si currentTabID est nil mais qu'il y a des onglets (par ex. après suppression du dernier sélectionné)
                Text("Aucun onglet sélectionné dans cet espace.")
                    .font(.title2).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
