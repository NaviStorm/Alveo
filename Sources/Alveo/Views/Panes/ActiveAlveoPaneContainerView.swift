import SwiftUI
import SwiftData

@MainActor
struct ActiveAlveoPaneContainerView: View {
    @Bindable var pane: AlveoPane
    @ObservedObject var webViewHelper: WebViewHelper
    @Binding var globalURLInput: String
    
    // Accès aux autres helpers pour la vue fractionnée
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            if pane.isSplitViewActive && !pane.splitViewTabs.isEmpty {
                // Vue fractionnée
                SplitWebView(
                    pane: pane,
                    webViewHelpers: [pane.id: webViewHelper], // Pour l'instant, utiliser le même helper
                    globalURLInput: $globalURLInput
                )
            } else {
                // Vue normale (un seul onglet)
                AlveoPaneView(
                    pane: pane,
                    webViewHelper: webViewHelper,
                    globalURLInput: $globalURLInput
                )
            }
        }
    }
}
