import SwiftUI
import WebKit

@MainActor
class WebViewHelper: ObservableObject {
    let webView: WKWebView
    
    @Published var currentURL: URL?
    @Published var pageTitle: String?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var estimatedProgress: Double = 0.0
    
    private var progressObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var isLoadingObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    
    init(customUserAgent: String? = nil) {
        let configuration = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        
        if let agent = customUserAgent {
            self.webView.customUserAgent = agent
        }
        
        setupKeyValueObservations()
    }
    
    private func setupKeyValueObservations() {
        urlObservation = webView.observe(\.url, options: .new) { [weak self] _, change in
            DispatchQueue.main.async { self?.currentURL = change.newValue ?? nil }
        }
        
        titleObservation = webView.observe(\.title, options: .new) { [weak self] _, change in
            DispatchQueue.main.async { self?.pageTitle = change.newValue ?? nil }
        }
        
        isLoadingObservation = webView.observe(\.isLoading, options: .new) { [weak self] _, change in
            DispatchQueue.main.async {
                self?.isLoading = change.newValue ?? false
                if !(change.newValue ?? true) { self?.estimatedProgress = 0.0 }
            }
        }
        
        canGoBackObservation = webView.observe(\.canGoBack, options: .new) { [weak self] _, change in
            DispatchQueue.main.async { self?.canGoBack = change.newValue ?? false }
        }
        
        canGoForwardObservation = webView.observe(\.canGoForward, options: .new) { [weak self] _, change in
            DispatchQueue.main.async { self?.canGoForward = change.newValue ?? false }
        }
        
        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] _, change in
            DispatchQueue.main.async { self?.estimatedProgress = change.newValue ?? 0.0 }
        }
    }
    
    func loadURL(_ url: URL) {
        print("[WebViewHelper \(Unmanaged.passUnretained(self).toOpaque())] Chargement effectif de: \(url.absoluteString)")
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func loadURLString(_ urlStringInput: String) {
        let trimmedInput = urlStringInput.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[WebViewHelper \(Unmanaged.passUnretained(self).toOpaque())] Tentative de chargement: '\(trimmedInput)'")
        
        guard !trimmedInput.isEmpty else {
            print("[WebViewHelper] Input vide, chargement de about:blank")
            if let blankURL = URL(string: "about:blank") {
                loadURL(blankURL)
            }
            return
        }
        
        let schemeRegex = try! NSRegularExpression(pattern: "^[a-zA-Z][a-zA-Z0-9+.-]*://")
        let hasScheme = schemeRegex.firstMatch(in: trimmedInput, options: [], range: NSRange(location: 0, length: trimmedInput.utf16.count)) != nil
        
        if hasScheme {
            if let url = URL(string: trimmedInput) {
                loadURL(url)
                return
            } else {
                print("Invalid URL string despite having a scheme: \(trimmedInput)")
            }
        } else {
            if trimmedInput.lowercased() == "localhost" || trimmedInput.starts(with: "localhost:") {
                let fullLocalhost = trimmedInput.starts(with: "localhost:") ? "http://\(trimmedInput)" : "http://localhost"
                if let url = URL(string: fullLocalhost) {
                    loadURL(url)
                    return
                }
            } else if trimmedInput.contains(".") && !trimmedInput.contains(" ") {
                if let url = URL(string: "https://" + trimmedInput) {
                    loadURL(url)
                    return
                }
            } else if trimmedInput.starts(with: "/") || trimmedInput.starts(with: "file://") {
                if let url = URL(string: trimmedInput.starts(with: "file://") ? trimmedInput : "file://" + trimmedInput) {
                    loadURL(url)
                    return
                }
            }
        }
        
        let searchEngineBaseURL = "https://www.google.com/search?q="
        if let searchQuery = trimmedInput.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let searchURL = URL(string: searchEngineBaseURL + searchQuery) {
            loadURL(searchURL)
        } else {
            print("Could not form a valid search query or URL for: \(trimmedInput)")
        }
    }
    
    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }
    
    func reload() {
        webView.reload()
    }
    
    func stopLoading() {
        webView.stopLoading()
    }
    
    deinit {
        urlObservation?.invalidate()
        titleObservation?.invalidate()
        isLoadingObservation?.invalidate()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()
        progressObservation?.invalidate()
    }
}
