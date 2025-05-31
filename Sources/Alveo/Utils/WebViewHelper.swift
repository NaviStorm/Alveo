import SwiftUI // Pour @MainActor et ObservableObject
import WebKit   // Pour WKWebView et KVO

@MainActor
class WebViewHelper: ObservableObject {
    let webView: WKWebView
    
    @Published var currentURL: URL?
    @Published var pageTitle: String?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var estimatedProgress: Double = 0.0
    
    // Callback pour informer ContentView des changements de navigation
    var onNavigationEvent: ((_ newURL: URL?, _ newTitle: String?) -> Void)?
    
    private var progressObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var isLoadingObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    
    init(customUserAgent: String? = nil) {
        let configuration = WKWebViewConfiguration()
        // Activer JavaScript (généralement souhaité)
        configuration.preferences.javaScriptEnabled = true
        // Permettre aux fenêtres JavaScript de s'ouvrir (si nécessaire, sinon le supprimer)
        // configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        
        if let agent = customUserAgent {
            self.webView.customUserAgent = agent
        }
        
        setupKeyValueObservations()
    }
    
    // Assurez-vous que cette méthode est appelée dans l'init
    private func setupKeyValueObservations() {
        // Observation de l'URL
        urlObservation = webView.observe(\.url, options: [.new, .initial]) { [weak self] webViewInstance, _ in
            guard let self = self else { return }
            let newURL = webViewInstance.url // L'URL réelle après toute redirection
            
            // Mettre à jour sur le thread principal
            DispatchQueue.main.async {
                // Mettre à jour la variable @Published uniquement si elle a changé
                // pour éviter des cycles de mise à jour inutiles dans SwiftUI
                if self.currentURL != newURL {
                    self.currentURL = newURL
                    print(">>> [WebViewHelper KVO] URL changé vers: \(newURL?.absoluteString ?? "nil") sur helper \(Unmanaged.passUnretained(self).toOpaque())")
                    // Appeler le callback pour que ContentView puisse mettre à jour le modèle Tab
                    self.onNavigationEvent?(newURL, self.pageTitle)
                }
            }
        }
        
        // Observation du titre de la page
        titleObservation = webView.observe(\.title, options: [.new, .initial]) { [weak self] webViewInstance, _ in
            guard let self = self else { return }
            let newTitle = webViewInstance.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            DispatchQueue.main.async {
                // Mettre à jour seulement si le titre a changé et n'est pas vide
                // Un titre vide peut apparaître brièvement pendant le chargement.
                if self.pageTitle != newTitle && (newTitle != nil && !newTitle!.isEmpty) {
                    self.pageTitle = newTitle
                    print(">>> [WebViewHelper KVO] Titre changé vers: '\(newTitle ?? "nil")' sur helper \(Unmanaged.passUnretained(self).toOpaque())")
                    // Appeler le callback pour que ContentView puisse mettre à jour le modèle Tab
                    self.onNavigationEvent?(self.currentURL, newTitle)
                }
            }
        }
        
        // Observation de l'état de chargement
        isLoadingObservation = webView.observe(\.isLoading, options: .new) { [weak self] webViewInstance, _ in
            guard let self = self else { return }
            let loadingState = webViewInstance.isLoading
            
            DispatchQueue.main.async {
                if self.isLoading != loadingState {
                    self.isLoading = loadingState
                    // Réinitialiser la progression si le chargement est terminé
                    if !loadingState {
                        self.estimatedProgress = 0.0
                    }
                     print(">>> [WebViewHelper KVO] isLoading: \(loadingState) sur helper \(Unmanaged.passUnretained(self).toOpaque())")
                }
            }
        }
        
        // Observation de la possibilité de revenir en arrière
        canGoBackObservation = webView.observe(\.canGoBack, options: .new) { [weak self] webViewInstance, _ in
            guard let self = self else { return }
            let canGoBackState = webViewInstance.canGoBack
            
            DispatchQueue.main.async {
                if self.canGoBack != canGoBackState {
                    self.canGoBack = canGoBackState
                }
            }
        }
        
        // Observation de la possibilité d'aller en avant
        canGoForwardObservation = webView.observe(\.canGoForward, options: .new) { [weak self] webViewInstance, _ in
            guard let self = self else { return }
            let canGoForwardState = webViewInstance.canGoForward
            
            DispatchQueue.main.async {
                if self.canGoForward != canGoForwardState {
                    self.canGoForward = canGoForwardState
                }
            }
        }
        
        // Observation de la progression estimée du chargement
        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] webViewInstance, _ in
            guard let self = self else { return }
            let progress = webViewInstance.estimatedProgress
            
            DispatchQueue.main.async {
                self.estimatedProgress = progress
            }
        }
    }

    func loadURL(_ url: URL) {
        print(">>> [WebViewHelper loadURL] Chargement effectif de: '\(url.absoluteString)' sur self: \(Unmanaged.passUnretained(self).toOpaque()), sa WKWebView: \(Unmanaged.passUnretained(webView).toOpaque())")
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func loadURLString(_ urlStringInput: String) {
        let trimmedInput = urlStringInput.trimmingCharacters(in: .whitespacesAndNewlines)
        print(">>> [WebViewHelper loadURLString] Tentative pour: '\(trimmedInput)' sur self: \(Unmanaged.passUnretained(self).toOpaque())")
        
        guard !trimmedInput.isEmpty else {
            print("[WebViewHelper loadURLString] Input vide, chargement de about:blank")
            if let blankURL = URL(string: "about:blank") {
                loadURL(blankURL)
            }
            return
        }
        
        // Logique de parsing d'URL (adaptée de votre code GitHub)
        let schemeRegex = try! NSRegularExpression(pattern: "^[a-zA-Z][a-zA-Z0-9+.-]*://")
        let hasScheme = schemeRegex.firstMatch(in: trimmedInput, options: [], range: NSRange(location: 0, length: trimmedInput.utf16.count)) != nil
        
        var finalURL: URL?

        if hasScheme {
            finalURL = URL(string: trimmedInput)
        } else {
            if trimmedInput.lowercased() == "localhost" || trimmedInput.starts(with: "localhost:") {
                let fullLocalhost = trimmedInput.starts(with: "localhost:") ? "http://\(trimmedInput)" : "http://localhost"
                finalURL = URL(string: fullLocalhost)
            } else if trimmedInput.contains(".") && !trimmedInput.contains(" ") { // Contient un point et pas d'espaces (ressemble à un nom de domaine)
                finalURL = URL(string: "https://" + trimmedInput)
            } else if trimmedInput.starts(with: "/") || trimmedInput.starts(with: "file://") { // Chemin de fichier local
                finalURL = URL(string: trimmedInput.starts(with: "file://") ? trimmedInput : "file://" + trimmedInput)
            }
        }
        
        if let urlToLoad = finalURL {
             print(">>> [WebViewHelper loadURLString] URL parsée: '\(urlToLoad.absoluteString)'")
            loadURL(urlToLoad)
        } else { // Si ce n'est pas une URL valide, considérer comme une recherche
            let searchEngineBaseURL = "https://www.google.com/search?q=" // Ou votre moteur de recherche préféré
            if let searchQuery = trimmedInput.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let searchURL = URL(string: searchEngineBaseURL + searchQuery) {
                print(">>> [WebViewHelper loadURLString] URL de recherche: '\(searchURL.absoluteString)'")
                loadURL(searchURL)
            } else {
                print(">>> [WebViewHelper loadURLString] ERREUR: Impossible de former une URL ou une requête de recherche pour: '\(trimmedInput)'")
                // Peut-être charger une page d'erreur ou "about:blank"
                if let blankURL = URL(string: "about:blank") { loadURL(blankURL) }
            }
        }
    }
    
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }
    
    deinit {
        print(">>> [WebViewHelper DEINIT] Helper \(Unmanaged.passUnretained(self).toOpaque()) est déinitialisé.")
        urlObservation?.invalidate()
        titleObservation?.invalidate()
        isLoadingObservation?.invalidate()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()
        progressObservation?.invalidate()
    }
}

