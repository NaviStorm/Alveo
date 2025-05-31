import SwiftUI
import WebKit

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    var onTitleChanged: ((String?) -> Void)? = nil
    var onURLChanged: ((URL?) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        print(">>> [WebViewRepresentable makeNSView] Retourne WKWebView: \(Unmanaged.passUnretained(webView).toOpaque())")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Pas besoin de recharger ici si la WKWebView est gérée par un @StateObject externe
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, onTitleChanged: onTitleChanged, onURLChanged: onURLChanged)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable
        var onTitleChanged: ((String?) -> Void)?
        var onURLChanged: ((URL?) -> Void)?


        init(_ parent: WebViewRepresentable, onTitleChanged: ((String?) -> Void)?, onURLChanged: ((URL?) -> Void)?) {
            self.parent = parent
            self.onTitleChanged = onTitleChanged
            self.onURLChanged = onURLChanged
        }

        // WKNavigationDelegate methods (exemples)
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Le titre est souvent mieux récupéré via KVO sur WKWebView directement
            // Mais on peut aussi le faire ici.
            parent.onTitleChanged?(webView.title)
            parent.onURLChanged?(webView.url)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView navigation failed: \(error.localizedDescription)")
            // parent.onTitleChanged?(webView.title ?? "Erreur")
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            // L'URL peut changer avant que le titre ne soit final
             parent.onURLChanged?(webView.url)
        }
    }
}

