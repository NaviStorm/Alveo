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
    
    init(customUserAgent: String? = nil, isolationLevel: DataIsolationManager.IsolationLevel = .strict) {
        let configuration = WKWebViewConfiguration()
        
        // ✅ Configuration selon le niveau choisi
        switch isolationLevel {
        case .none:
            configuration.websiteDataStore = WKWebsiteDataStore.default()
            // Pas de script de sécurité supplémentaire
            
        case .moderate:
            configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
            Self.setupModerateIsolationSecurity(for: configuration)
            
        case .strict:
            configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
            Self.setupStrictIsolationSecurity(for: configuration)
            
        case .extreme:
            configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
            Self.setupExtremeIsolationSecurity(for: configuration)
        }
        
        // ✅ Correction de l'avertissement - Utiliser la nouvelle API
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = webpagePreferences
        
        // ✅ Maintenant on peut créer la WebView
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        
        if let agent = customUserAgent {
            self.webView.customUserAgent = agent
        }
        
        print(">>> [WebViewHelper INIT] Créé helper ID: \(self.id) avec isolation \(isolationLevel)")
        
        setupKeyValueObservations()
    }
    
    // Ajouter après setupExtremeIsolationSecurity
    private static func setupModerateIsolationSecurity(for configuration: WKWebViewConfiguration) {
        let moderateIsolationScript = """
        (function() {
            // Bloquer seulement les cookies cross-origin, pas tous
            const originalCookieDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'cookie') ||
                                           Object.getOwnPropertyDescriptor(HTMLDocument.prototype, 'cookie');
            
            Object.defineProperty(document, 'cookie', {
                get: function() {
                    return originalCookieDescriptor.get.call(this);
                },
                set: function(value) {
                    // Permettre les cookies same-origin
                    if (window.location.hostname === document.domain) {
                        return originalCookieDescriptor.set.call(this, value);
                    }
                    console.warn('Cookie cross-origin bloqué:', value);
                    return;
                }
            });
            
            // Bloquer seulement les iframes cross-origin
            const originalCreateElement = document.createElement;
            document.createElement = function(tagName) {
                const element = originalCreateElement.call(this, tagName);
                
                if (tagName.toLowerCase() === 'iframe') {
                    const originalSetAttribute = element.setAttribute;
                    element.setAttribute = function(name, value) {
                        if (name.toLowerCase() === 'src') {
                            try {
                                const iframeURL = new URL(value, window.location.href);
                                const currentOrigin = window.location.origin;
                                
                                if (iframeURL.origin !== currentOrigin) {
                                    console.warn('Iframe cross-origin bloqué:', value);
                                    return;
                                }
                            } catch (e) {
                                console.warn('URL iframe invalide:', value);
                                return;
                            }
                        }
                        return originalSetAttribute.call(this, name, value);
                    };
                }
                
                return element;
            };
            
            console.log('🔒 Isolation modérée activée');
        })();
        """
        
        let isolationScript = WKUserScript(
            source: moderateIsolationScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(isolationScript)
    }

    private static func setupStrictIsolationSecurity(for configuration: WKWebViewConfiguration) {
        let strictIsolationScript = """
        (function() {
            // Bloquer les cookies cross-origin et limiter localStorage/sessionStorage
            const originalCookieDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'cookie') ||
                                           Object.getOwnPropertyDescriptor(HTMLDocument.prototype, 'cookie');
            
            Object.defineProperty(document, 'cookie', {
                get: function() {
                    return originalCookieDescriptor.get.call(this);
                },
                set: function(value) {
                    if (window.location.hostname === document.domain) {
                        return originalCookieDescriptor.set.call(this, value);
                    }
                    console.warn('Cookie cross-origin bloqué (strict):', value);
                    return;
                }
            });
            
            // Limiter localStorage (mais ne pas le bloquer complètement)
            const originalLocalStorage = window.localStorage;
            Object.defineProperty(window, 'localStorage', {
                get: function() {
                    const currentOrigin = window.location.origin;
                    if (currentOrigin !== document.location.origin) {
                        console.warn('Accès localStorage cross-origin bloqué (strict)');
                        return {
                            getItem: () => null,
                            setItem: () => {},
                            removeItem: () => {},
                            clear: () => {},
                            key: () => null,
                            length: 0
                        };
                    }
                    return originalLocalStorage;
                }
            });
            
            // Bloquer tous les iframes
            const originalCreateElement = document.createElement;
            document.createElement = function(tagName) {
                const element = originalCreateElement.call(this, tagName);
                
                if (tagName.toLowerCase() === 'iframe') {
                    console.warn('Iframe bloqué (strict)');
                    return document.createElement('div');
                }
                
                return element;
            };
            
            console.log('🔒 Isolation stricte activée');
        })();
        """
        
        let isolationScript = WKUserScript(
            source: strictIsolationScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(isolationScript)
    }

    // ✅ Méthode statique pour éviter l'utilisation de self
    private static func setupExtremeIsolationSecurity(for configuration: WKWebViewConfiguration) {
        let extremeIsolationScript = """
        (function() {
            // Bloquer complètement l'accès aux cookies
            Object.defineProperty(document, 'cookie', {
                get: function() { return ''; },
                set: function(value) { 
                    console.warn('Cookie bloqué par isolation extrême:', value);
                    return;
                }
            });
            
            // Bloquer localStorage
            Object.defineProperty(window, 'localStorage', {
                get: function() {
                    console.warn('localStorage bloqué par isolation extrême');
                    return {
                        getItem: () => null,
                        setItem: () => {},
                        removeItem: () => {},
                        clear: () => {},
                        key: () => null,
                        length: 0
                    };
                }
            });
            
            // Bloquer sessionStorage
            Object.defineProperty(window, 'sessionStorage', {
                get: function() {
                    console.warn('sessionStorage bloqué par isolation extrême');
                    return {
                        getItem: () => null,
                        setItem: () => {},
                        removeItem: () => {},
                        clear: () => {},
                        key: () => null,
                        length: 0
                    };
                }
            });
            
            // Bloquer IndexedDB
            Object.defineProperty(window, 'indexedDB', {
                get: function() {
                    console.warn('IndexedDB bloqué par isolation extrême');
                    return null;
                }
            });
            
            // Bloquer WebSQL (si supporté)
            if (window.openDatabase) {
                window.openDatabase = function() {
                    console.warn('WebSQL bloqué par isolation extrême');
                    return null;
                };
            }
            
            // Bloquer les iframes complètement
            const originalCreateElement = document.createElement;
            document.createElement = function(tagName) {
                const element = originalCreateElement.call(this, tagName);
                
                if (tagName.toLowerCase() === 'iframe') {
                    console.warn('Iframe bloqué par isolation extrême');
                    return document.createElement('div');
                }
                
                return element;
            };
            
            // Bloquer les workers
            if (window.Worker) {
                window.Worker = function() {
                    console.warn('Web Worker bloqué par isolation extrême');
                    throw new Error('Web Workers désactivés pour l\\'isolation');
                };
            }
            
            if (window.SharedWorker) {
                window.SharedWorker = function() {
                    console.warn('Shared Worker bloqué par isolation extrême');
                    throw new Error('Shared Workers désactivés pour l\\'isolation');
                };
            }
            
            // Bloquer les Service Workers
            if ('serviceWorker' in navigator) {
                Object.defineProperty(navigator, 'serviceWorker', {
                    get: function() {
                        console.warn('Service Worker bloqué par isolation extrême');
                        return undefined;
                    }
                });
            }
            
            console.log('🔒 Isolation extrême activée - Toutes les données sont isolées');
        })();
        """
        
        let isolationScript = WKUserScript(
            source: extremeIsolationScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(isolationScript)
    }

    private func setupSecurityConfiguration(for configuration: WKWebViewConfiguration) {
        // Bloquer l'accès cross-origin aux cookies
        let cookieIsolationScript = """
        (function() {
            // Intercepter les tentatives d'accès aux cookies cross-origin
            const originalCookieDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'cookie') ||
                                           Object.getOwnPropertyDescriptor(HTMLDocument.prototype, 'cookie');
            
            Object.defineProperty(document, 'cookie', {
                get: function() {
                    return originalCookieDescriptor.get.call(this);
                },
                set: function(value) {
                    // Vérifier l'origine
                    const currentOrigin = window.location.origin;
                    const documentOrigin = document.location.origin;
                    
                    if (currentOrigin !== documentOrigin) {
                        console.warn('Tentative de définition de cookie cross-origin bloquée:', value);
                        return;
                    }
                    
                    return originalCookieDescriptor.set.call(this, value);
                }
            });
            
            // Bloquer l'accès au localStorage cross-origin
            const originalLocalStorage = window.localStorage;
            Object.defineProperty(window, 'localStorage', {
                get: function() {
                    const currentOrigin = window.location.origin;
                    if (currentOrigin !== document.location.origin) {
                        console.warn('Accès localStorage cross-origin bloqué');
                        return {};
                    }
                    return originalLocalStorage;
                }
            });
            
            // Bloquer l'accès au sessionStorage cross-origin
            const originalSessionStorage = window.sessionStorage;
            Object.defineProperty(window, 'sessionStorage', {
                get: function() {
                    const currentOrigin = window.location.origin;
                    if (currentOrigin !== document.location.origin) {
                        console.warn('Accès sessionStorage cross-origin bloqué');
                        return {};
                    }
                    return originalSessionStorage;
                }
            });
        })();
        """
        
        let securityScript = WKUserScript(
            source: cookieIsolationScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(securityScript)
        
        // ✅ Bloquer les iframes cross-origin
        let iframeBlockingScript = """
        (function() {
            const originalCreateElement = document.createElement;
            document.createElement = function(tagName) {
                const element = originalCreateElement.call(this, tagName);
                
                if (tagName.toLowerCase() === 'iframe') {
                    const originalSetAttribute = element.setAttribute;
                    element.setAttribute = function(name, value) {
                        if (name.toLowerCase() === 'src') {
                            try {
                                const iframeURL = new URL(value, window.location.href);
                                const currentOrigin = window.location.origin;
                                
                                if (iframeURL.origin !== currentOrigin) {
                                    console.warn('Iframe cross-origin bloqué:', value);
                                    return;
                                }
                            } catch (e) {
                                console.warn('URL iframe invalide:', value);
                                return;
                            }
                        }
                        return originalSetAttribute.call(this, name, value);
                    };
                }
                
                return element;
            };
        })();
        """
        
        let iframeScript = WKUserScript(
            source: iframeBlockingScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(iframeScript)
    }
    
    private func addContentSecurityPolicy(to configuration: WKWebViewConfiguration) {
        let cspScript = """
        (function() {
            // Ajouter une CSP stricte
            const meta = document.createElement('meta');
            meta.httpEquiv = 'Content-Security-Policy';
            meta.content = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self'; frame-src 'none'; object-src 'none';";
            
            if (document.head) {
                document.head.appendChild(meta);
            } else {
                document.addEventListener('DOMContentLoaded', function() {
                    document.head.appendChild(meta);
                });
            }
        })();
        """
        
        let cspUserScript = WKUserScript(
            source: cspScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(cspUserScript)
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
