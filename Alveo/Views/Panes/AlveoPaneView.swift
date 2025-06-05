// Alveo/Views/Panes/AlveoPaneView.swift
import SwiftUI
import SwiftData

@MainActor
struct AlveoPaneView: View {
    @Bindable var pane: AlveoPane
    @ObservedObject var webViewHelper: WebViewHelper // C'est le helper de pane.currentTab
    @Binding var globalURLInput: String

    var body: some View {
        VStack(spacing: 0) {
            // La vue parente (ActiveAlveoPaneContainerView) s'assure que webViewHelper est fourni
            // et correspond à pane.currentTab.
            let _ = print(">>> [AlveoPaneView BODY] Espace '\(pane.name ?? "N/A")', Tab '\(pane.currentTab?.displayTitle ?? "N/A")', Helper ID: \(webViewHelper.id), sa WKWebView ID: \(Unmanaged.passUnretained(webViewHelper.webView).toOpaque())")
            
            WebViewRepresentable(webView: webViewHelper.webView)
                .id(webViewHelper.id) // Pour s'assurer que la vue est recréée si l'instance du helper change

            if webViewHelper.isLoading && webViewHelper.estimatedProgress > 0 && webViewHelper.estimatedProgress < 1.0 {
                ProgressView(value: webViewHelper.estimatedProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 3)
                    .transition(.opacity)
            }
            // Les textes pour "aucun onglet" etc. sont gérés par ActiveAlveoPaneContainerView
        }
    }
}
