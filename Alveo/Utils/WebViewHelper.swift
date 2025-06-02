import SwiftUI
import WebKit

@MainActor
class WebViewHelper: ObservableObject, Identifiable { // Ajout de Identifiable
    let id = UUID() // Identifiant unique pour chaque instance de WebViewHelper
    let webView: WKWebView
    
    @Published var currentURL: URL?
    @Published var pageTitle: String?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var estimatedProgress: Double = 0.0
    
    var onNavigationEvent: ((_ newURL: URL?, _ newTitle: String?) -> Void)?
    
    private var progressObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var isLoadingObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    
    init(customUserAgent: String? = nil) {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        // configuration.preferences.javaScriptCanOpenWindowsAutomatically = true // Décommentez si nécessaire
        
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        
        if let agent = customUserAgent {
            self.webView.customUserAgent = agent
        }
        
        print(">>> [WebViewHelper INIT] Créé helper ID: \(self.id), WKWebView ID: \(Unmanaged.passUnretained(self.webView).toOpaque())")
        setupKeyValueObservations()
    }
    
    private func setupKeyValueObservations() {
        urlObservation = webView.observe(\.url, options: [.new, .initial]) { [weak self] webViewInstance, _ in
            guard let self = self else { return }
            let newURL = webViewInstance.url
            DispatchQueue.main.async {
                if self.currentURL != newURL {
                    self.currentURL = newURL
                    print(">>> [WebViewHelper KVO] Helper \(self.id) - URL changé vers: \(newURL?.absoluteString ?? "nil")")
                    self.onNavigationEvent?(newURL, self.pageTitle)
                }
            }
        }
        
        titleObservation = webView.observe(\.title, options: [.new, .initial]) { [weak self] webViewInstance, _ in
            guard let self = self else { return }
            let newTitle = webViewInstance.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if self.pageTitle != newTitle && (newTitle != nil && !newTitle!.isEmpty) {
                    self.pageTitle = newTitle
                    print(">>> [WebViewHelper KVO] Helper \(self.id) - Titre changé vers: '\(newTitle ?? "nil")'")
                    self.onNavigationEvent?(self.currentURL, newTitle)
                }
            }
        }
        
        isLoadingObservation = webView.observe(\.isLoading, options: .new) { [weak self] webViewInstance, _ in
            guard let self = self else { return }
            let loadingState = webViewInstance.isLoading
            DispatchQueue.main.async {
                if self.isLoading != loadingState {
                    self.isLoading = loadingState
                    if !loadingState { self.estimatedProgress = 0.0 }
                    print(">>> [WebViewHelper KVO] Helper \(self.id) - isLoading: \(loadingState)")
                }
            }
        }
        canGoBackObservation = webView.observe(\.canGoBack, options: .new) { [weak self] w, _ in DispatchQueue.main.async { if self?.canGoBack != w.canGoBack { self?.canGoBack = w.canGoBack } } }
        canGoForwardObservation = webView.observe(\.canGoForward, options: .new) { [weak self] w, _ in DispatchQueue.main.async { if self?.canGoForward != w.canGoForward { self?.canGoForward = w.canGoForward } } }
        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] w, _ in DispatchQueue.main.async { self?.estimatedProgress = w.estimatedProgress } }
    }

    func loadURL(_ url: URL) {
        print(">>> [WebViewHelper loadURL] Helper \(self.id) - Chargement effectif de: '\(url.absoluteString)' sur sa WKWebView: \(Unmanaged.passUnretained(webView).toOpaque())")
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func loadURLString(_ urlStringInput: String) {
        let trimmedInput = urlStringInput.trimmingCharacters(in: .whitespacesAndNewlines)
        print(">>> [WebViewHelper loadURLString] Helper \(self.id) - Tentative pour: '\(trimmedInput)'")
        
        guard !trimmedInput.isEmpty else {
            print("[WebViewHelper loadURLString] Input vide, chargement de about:blank")
            if let blankURL = URL(string: "about:blank") { loadURL(blankURL) }
            return
        }
        
        let schemeRegex = try! NSRegularExpression(pattern: "^[a-zA-Z][a-zA-Z0-9+.-]*://")
        let hasScheme = schemeRegex.firstMatch(in: trimmedInput, options: [], range: NSRange(location: 0, length: trimmedInput.utf16.count)) != nil
        var finalURL: URL?

        if hasScheme {
            finalURL = URL(string: trimmedInput)
        } else {
            if trimmedInput.lowercased() == "localhost" || trimmedInput.starts(with: "localhost:") {
                finalURL = URL(string: (trimmedInput.starts(with: "localhost:") ? "http://" : "http://") + trimmedInput)
            } else if trimmedInput.contains(".") && !trimmedInput.contains(" ") {
                finalURL = URL(string: "https://" + trimmedInput)
            } else if trimmedInput.starts(with: "/") || trimmedInput.starts(with: "file://") {
                finalURL = URL(string: trimmedInput.starts(with: "file://") ? trimmedInput : "file://" + trimmedInput)
            }
        }
        
        if let urlToLoad = finalURL {
            print(">>> [WebViewHelper loadURLString] URL parsée: '\(urlToLoad.absoluteString)'")
            loadURL(urlToLoad)
        } else {
            let searchEngineBaseURL = "https://www.google.com/search?q="
            if let searchQuery = trimmedInput.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let searchURL = URL(string: searchEngineBaseURL + searchQuery) {
                print(">>> [WebViewHelper loadURLString] URL de recherche: '\(searchURL.absoluteString)'")
                loadURL(searchURL)
            } else {
                print(">>> [WebViewHelper loadURLString] ERREUR: Impossible de former URL/recherche pour: '\(trimmedInput)'")
                if let blankURL = URL(string: "about:blank") { loadURL(blankURL) }
            }
        }
    }
    
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }
    
    deinit {
        print(">>> [WebViewHelper DEINIT] Helper \(self.id) est déinitialisé.")
        urlObservation?.invalidate(); titleObservation?.invalidate(); isLoadingObservation?.invalidate()
        canGoBackObservation?.invalidate(); canGoForwardObservation?.invalidate(); progressObservation?.invalidate()
    }
}
