import SwiftUI
import SwiftData

@MainActor
struct PrincipalToolbarView: View {
    @ObservedObject var webViewHelper: WebViewHelper
    @Binding var urlInput: String
    @Binding var showSuggestions: Bool
    @Binding var filteredHistory: [HistoryItem]
    @FocusState.Binding var isFocused: Bool
    var geometryProxy: GeometryProxy
    let fetchHistoryAction: (String) -> Void
    
    var body: some View {
        let dynamicToolbarWidth = geometryProxy.size.width * 40/100
        let textFieldHeight: CGFloat = 32
        let suggestionsListMaxHeight: CGFloat = 250
        let spacingAfterTextField: CGFloat = 4
        
        let _ = print("[PToolbarV body] dynW: \(dynamicToolbarWidth), tfH: \(textFieldHeight), showSugg: \(showSuggestions), filtHist: \(filteredHistory.count)")
        
        ZStack(alignment: .topLeading) {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .foregroundColor(urlInput.starts(with: "https://") ? .green.opacity(0.8) : .gray.opacity(0.7))
                    .font(.subheadline)
                    .opacity(urlInput.starts(with: "http") ? 1 : 0)
                
                TextField("URL ou recherche", text: $urlInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onTapGesture {
                        if !isFocused {
                            print("[TextField onTapGesture] Tentative de mettre isFocused à true")
                            isFocused = true
                        }
                    }
                    .onSubmit {
                        print("[PToolbarV onSubmit] URL saisie: \(urlInput)")
                        webViewHelper.loadURLString(urlInput)
                        showSuggestions = false
                        isFocused = false
                        print("[PToolbarV onSubmit] Chargement demandé pour: \(urlInput)")
                    }
                    .onChange(of: urlInput) { oldValue, newValue in
                        print("[PToolbarV urlInput changed] old: '\(oldValue)', new: '\(newValue)', currentFocus: \(isFocused)")
                        if newValue.isEmpty {
                            filteredHistory = []
                            showSuggestions = false
                        } else {
                            let isTyping = oldValue != newValue
                            if isTyping {
                                fetchHistoryAction(newValue)
                                self.showSuggestions = !self.filteredHistory.isEmpty
                            } else {
                                fetchHistoryAction(newValue)
                                self.showSuggestions = !self.filteredHistory.isEmpty
                            }
                        }
                        print("[PToolbarV urlInput changed] AFTER LOGIC -> showSugg: \(self.showSuggestions), histCount: \(self.filteredHistory.count)")
                    }
                    .onChange(of: isFocused) { oldValue, newValue in
                        print("[PToolbarV .onChange(of: isFocused)] Changement de focus de \(oldValue) à \(newValue)")
                        if newValue {
                            if !urlInput.isEmpty {
                                fetchHistoryAction(urlInput)
                                showSuggestions = !filteredHistory.isEmpty
                            } else {
                                showSuggestions = false
                                filteredHistory = []
                            }
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if !self.isFocused {
                                    self.showSuggestions = false
                                }
                            }
                        }
                        print("[PToolbarV isFocused changed] AFTER LOGIC -> showSugg: \(self.showSuggestions), histCount: \(self.filteredHistory.count)")
                    }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.08))
            .cornerRadius(7)
            .frame(width: dynamicToolbarWidth, height: textFieldHeight)
            
            if showSuggestions && !filteredHistory.isEmpty {
                let _ = print("[PToolbarV ZStack] Conditions OK pour SuggestionsList. Items: \(filteredHistory.count)")
                SuggestionsList(
                    suggestions: filteredHistory,
                    width: dynamicToolbarWidth,
                    onSelect: { selectedItem in
                        print("[PrincipalToolbarView onSelect from SuggestionsList] URL: \(selectedItem.urlString)")
                        urlInput = selectedItem.urlString
                        webViewHelper.loadURLString(urlInput)
                        showSuggestions = false
                        isFocused = false
                    }
                )
                .offset(y: textFieldHeight + spacingAfterTextField)
            } else {
                let _ = print("[PrincipalToolbarView ZStack] Conditions NON remplies pour le Rectangle/SuggestionsList.")
            }
        }
        .frame(width: dynamicToolbarWidth, alignment: .topLeading)
    }
}
