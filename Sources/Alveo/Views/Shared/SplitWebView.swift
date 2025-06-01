import SwiftUI

struct SplitWebView: View {
    @Bindable var pane: AlveoPane
    let webViewHelpers: [UUID: WebViewHelper]
    @Binding var globalURLInput: String
    
    @State private var splitSizes: [CGFloat] = []
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(Array(pane.splitViewTabs.enumerated()), id: \.element.id) { index, tab in
                    let helper = webViewHelpers[pane.id] // Utiliser le même helper pour l'instant
                    
                    VStack(spacing: 0) {
                        // En-tête de l'onglet
                        tabHeader(for: tab, isActive: tab.id == pane.currentTabID)
                        
                        // Contenu web
                        if let webViewHelper = helper {
                            WebViewRepresentable(webView: webViewHelper.webView)
                                .overlay(
                                    // Overlay pour détecter les clics et activer l'onglet
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if pane.currentTabID != tab.id {
                                                pane.currentTabID = tab.id
                                                tab.lastAccessed = Date()
                                                
                                                // Charger l'URL de cet onglet
                                                if let url = tab.displayURL {
                                                    webViewHelper.loadURL(url)
                                                    globalURLInput = tab.urlString
                                                }
                                            }
                                        }
                                )
                        } else {
                            Text("Chargement...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.gray.opacity(0.1))
                        }
                    }
                    .frame(width: splitSizes.indices.contains(index) ? splitSizes[index] : geometry.size.width / CGFloat(pane.splitViewTabs.count))
                    .overlay(
                        // Bordure bleue pour l'onglet actif
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Color.accentColor, lineWidth: tab.id == pane.currentTabID ? 2 : 0)
                    )
                    
                    // Séparateur redimensionnable (sauf pour le dernier)
                    if index < pane.splitViewTabs.count - 1 {
                        resizeHandle(for: index, geometry: geometry)
                    }
                }
            }
        }
        .onAppear {
            initializeSplitSizes()
        }
        .onChange(of: pane.splitViewTabs.count) { _, _ in
            initializeSplitSizes()
        }
    }
    
    @ViewBuilder
    private func tabHeader(for tab: Tab, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            // Icône
            Group {
                if let emoji = tab.customEmojiIcon {
                    Text(emoji).font(.system(size: 14))
                } else if let faviconURL = tab.faviconURL {
                    AsyncImage(url: faviconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                        default:
                            Image(systemName: "globe")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            // Titre
            Text(tab.displayTitle)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .foregroundColor(isActive ? .accentColor : .primary)
            
            Spacer()
            
            // Bouton de fermeture
            Button {
                pane.removeTabFromSplitView(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.05))
        .onTapGesture {
            if pane.currentTabID != tab.id {
                pane.currentTabID = tab.id
                tab.lastAccessed = Date()
            }
        }
    }
    
    @ViewBuilder
    private func resizeHandle(for index: Int, geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        handleResize(index: index, translation: value.translation.width, geometry: geometry)
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
    
    private func initializeSplitSizes() {
        let count = pane.splitViewTabs.count
        guard count > 0 else { return }
        
        if pane.splitViewProportions.count == count {
            // Utiliser les proportions sauvegardées
            splitSizes = pane.splitViewProportions.map { CGFloat($0) * 800 } // 800 est une largeur de référence
        } else {
            // Proportions égales
            let size = CGFloat(800) / CGFloat(count)
            splitSizes = Array(repeating: size, count: count)
        }
    }
    
    private func handleResize(index: Int, translation: CGFloat, geometry: GeometryProxy) {
        guard index < splitSizes.count - 1 else { return }
        
        let minSize: CGFloat = 200 // Taille minimale pour chaque vue
        let totalWidth = geometry.size.width
        
        // Calculer les nouvelles tailles
        var newSizes = splitSizes
        let currentLeft = newSizes[index]
        let currentRight = newSizes[index + 1]
        
        let newLeft = max(minSize, currentLeft + translation)
        let newRight = max(minSize, currentRight - translation)
        
        // Vérifier que la somme ne dépasse pas la largeur totale
        let otherSizesSum = newSizes.enumerated().reduce(0) { sum, element in
            let (i, size) = element
            return sum + (i == index || i == index + 1 ? 0 : size)
        }
        
        if newLeft + newRight + otherSizesSum <= totalWidth {
            newSizes[index] = newLeft
            newSizes[index + 1] = newRight
            splitSizes = newSizes
            
            // Sauvegarder les proportions
            let proportions = splitSizes.map { Double($0 / totalWidth) }
            pane.updateSplitViewProportions(proportions)
        }
    }
}

