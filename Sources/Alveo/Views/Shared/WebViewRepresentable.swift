import SwiftUI
import WebKit

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView // 'let' est important pour la stabilité

    func makeNSView(context: Context) -> WKWebView {
        print(">>> [WebViewRepresentable makeNSView] Configuration avec WKWebView ID: \(Unmanaged.passUnretained(webView).toOpaque())")
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        print(">>> [WebViewRepresentable updateNSView] NSView (actuelle): \(Unmanaged.passUnretained(nsView).toOpaque()), self.webView (attendue): \(Unmanaged.passUnretained(webView).toOpaque())")
        
        if nsView !== webView {
            print(">>> [WebViewRepresentable updateNSView] ALERTE: nsView et self.webView ne sont PAS la même instance! C'est un problème potentiel.")
            // Si cela se produit, la vue pourrait afficher une webView différente de celle sur laquelle les chargements sont initiés.
            // Il faudrait alors s'assurer que `nsView` est correctement configurée ou que `webView` est bien la source de vérité.
            // Pour l'instant, on logue. On s'attend à ce qu'elles soient identiques si `WebViewHelper` est stable.
        }
        
        // Ré-assigner les délégués au cas où, bien que cela ne devrait pas être nécessaire si nsView === webView
        // et que makeNSView est appelé correctement lorsque l'instance de WebViewRepresentable change vraiment.
        if nsView.navigationDelegate !== context.coordinator {
             print(">>> [WebViewRepresentable updateNSView] Réassignation du navigationDelegate.")
            nsView.navigationDelegate = context.coordinator
        }
        if nsView.uiDelegate !== context.coordinator {
            print(">>> [WebViewRepresentable updateNSView] Réassignation du uiDelegate.")
            nsView.uiDelegate = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
            print(">>> [Coordinator INIT] Créé pour WebViewRepresentable avec WKWebView ID: \(Unmanaged.passUnretained(parent.webView).toOpaque())")
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print(">>> [Coordinator didStartProvisionalNavigation] WKWebView ID: \(Unmanaged.passUnretained(webView).toOpaque()), URL: \(webView.url?.absoluteString ?? "N/A")")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            print(">>> [Coordinator didCommit] WKWebView ID: \(Unmanaged.passUnretained(webView).toOpaque()), URL: \(webView.url?.absoluteString ?? "N/A")")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print(">>> [Coordinator didFinish] WKWebView ID: \(Unmanaged.passUnretained(webView).toOpaque()), URL: \(webView.url?.absoluteString ?? "N/A")")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            print(">>> [Coordinator didFailProvisionalNavigation] ERREUR: '\(nsError.localizedDescription)', Code: \(nsError.code), Domaine: \(nsError.domain) pour WKWebView ID: \(Unmanaged.passUnretained(webView).toOpaque()) URL: \(webView.url?.absoluteString ?? "N/A")")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            print(">>> [Coordinator didFail] ERREUR: '\(nsError.localizedDescription)', Code: \(nsError.code), Domaine: \(nsError.domain) pour WKWebView ID: \(Unmanaged.passUnretained(webView).toOpaque()) URL: \(webView.url?.absoluteString ?? "N/A")")
        }
        
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            print(">>> [Coordinator webViewWebContentProcessDidTerminate] Processus WebContent terminé. WKWebView ID: \(Unmanaged.passUnretained(webView).toOpaque())")
        }
        
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            print(">>> [Coordinator runJavaScriptAlertPanelWithMessage]: \(message)")
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .warning
            alert.runModal()
            completionHandler()
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { // Typiquement target="_blank"
                print(">>> [Coordinator createWebViewWith] Action pour nouvelle fenêtre (target='_blank'?): \(navigationAction.request.url?.absoluteString ?? "N/A"). Chargement dans la vue actuelle.")
                webView.load(navigationAction.request) // Charger dans la webView existante
            }
            return nil // Ne pas créer une nouvelle instance de WKWebView pour la popup
        }
    }
}
