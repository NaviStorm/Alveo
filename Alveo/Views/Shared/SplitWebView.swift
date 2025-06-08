// Alveo/Views/Shared/SplitWebView.swift
import SwiftUI

@MainActor
struct SplitWebView: View {
    @Bindable var pane: AlveoPane
    let tabWebViewHelpers: [UUID: WebViewHelper] // Dictionnaire de tous les helpers par Tab.ID
    @Binding var globalURLInput: String

    // @State private var splitSizes: [CGFloat] = [] // Géré par les proportions du pane maintenant

    // Fonction pour comparer les doubles avec une tolérance
    private func doublesApproximatelyEqual(_ a: Double, _ b: Double, tolerance: Double = 0.00001) -> Bool {
        return abs(a - b) < tolerance
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) { // Un séparateur fin entre les vues
                ForEach(Array(pane.splitViewTabs.enumerated()), id: \.element.id) { index, tab in
                    if let webViewHelperForTab = tabWebViewHelpers[tab.id] {
                        VStack(spacing: 0) {
                            // En-tête optionnel pour chaque panneau de la vue fractionnée
                            tabHeader(for: tab, isActive: tab.id == pane.currentTabID, webViewHelper: webViewHelperForTab)

                            WebViewRepresentable(webView: webViewHelperForTab.webView)
                                .id(tab.id) // S'assurer que la vue est unique par onglet
                                .overlay( // Bordure pour l'onglet actif dans la SplitView
                                    Rectangle()
                                        .stroke(Color.accentColor.opacity(tab.id == pane.currentTabID ? 1.0 : 0.0), lineWidth: 2)
                                )
                        }
                        // La largeur est gérée par les proportions du NSSplitViewItem si on utilisait AppKit,
                        // ou par un calcul manuel ici.
                        // `pane.splitViewProportions` devrait être la source de vérité.
                        .frame(width: calculateWidth(for: index, totalWidth: geometry.size.width))

                    } else {
                        // Helper non (encore) disponible pour cet onglet
                        VStack {
                            Text("Chargement du contenu pour")
                            Text(tab.displayTitle).bold()
                            ProgressView()
                        }
                        .frame(width: calculateWidth(for: index, totalWidth: geometry.size.width))
                        .onAppear {
                             print("[SplitWebView] Helper manquant pour tab \(tab.id) lors de l'affichage. ContentView devrait le créer.")
                             // ContentView.ensureWebViewHelperExists le gère quand un onglet devient actif ou est préparé.
                        }
                    }

                    // Séparateur redimensionnable (sauf pour le dernier)
                    if index < pane.splitViewTabs.count - 1 {
                        SplitterResizeHandle(
                            pane: pane,
                            index: index,
                            totalWidth: geometry.size.width
                        )
                    }
                }
            }
            .onAppear {
                initializeSplitSizes_onAppear()
                // S'assurer que les proportions sont initialisées si nécessaire
                if pane.splitViewTabs.count > 0 && (pane.splitViewProportions.isEmpty || pane.splitViewProportions.count != pane.splitViewTabs.count || !doublesApproximatelyEqual(pane.splitViewProportions.reduce(0, +), 1.0)) {
                    pane.redistributeSplitViewProportions()
                }
            }
             // Réagir si le nombre d'onglets change pour redistribuer
            .onChange(of: pane.splitViewTabs.count) { _, newCount in
                initializeSplitSizes_onChange(for: newCount)
            }
        }
    }
    
    private func initializeSplitSizes_onAppear() {
        let count = pane.splitViewTabs.count
        guard count > 0 else { return }
        
        // S'assurer que les proportions sont initialisées si nécessaire
        if pane.splitViewTabs.count > 0 && (pane.splitViewProportions.isEmpty || pane.splitViewProportions.count != pane.splitViewTabs.count || !doublesApproximatelyEqual(pane.splitViewProportions.reduce(0, +), 1.0)) {
            pane.redistributeSplitViewProportions()
        }
    }


    private func initializeSplitSizes_onChange(for newCount: Int) {
        let count = pane.splitViewTabs.count
        guard count > 0 else { return }
        
        // S'assurer que les proportions sont initialisées si nécessaire
        if newCount > 0 && (pane.splitViewProportions.isEmpty || pane.splitViewProportions.count != newCount || !doublesApproximatelyEqual(pane.splitViewProportions.reduce(0, +), 1.0)) {
            pane.redistributeSplitViewProportions()
        }
    }
    
    private func calculateWidth(for index: Int, totalWidth: CGFloat) -> CGFloat {
        guard pane.splitViewTabs.count > 0,
              pane.splitViewProportions.count == pane.splitViewTabs.count,
              index < pane.splitViewProportions.count else {
            // Fallback si les proportions ne sont pas prêtes (devrait être rare)
            return totalWidth / CGFloat(max(1, pane.splitViewTabs.count))
        }
        return totalWidth * CGFloat(pane.splitViewProportions[index])
    }

    // En-tête (optionnel, si vous voulez un titre/boutons par panneau de SplitView)
    @ViewBuilder
    private func tabHeader(for tab: Tab, isActive: Bool, webViewHelper: WebViewHelper) -> some View {
        HStack(spacing: 8) {
            Group { // Icône
                if let emoji = tab.customEmojiIcon { Text(emoji).font(.system(size: 14)) }
                else if let faviconURL = tab.faviconURL { FaviconAsyncImage(url: faviconURL, size: 14) }
                else { Image(systemName: "globe").font(.system(size: 12)).foregroundColor(.secondary) }
            }.frame(width: 14, height: 14)

            Text(webViewHelper.pageTitle ?? tab.displayTitle) // Titre du helper (plus à jour)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .foregroundColor(isActive ? .accentColor : .primary)
            Spacer()
            Button { // Bouton pour retirer cet onglet spécifique de la vue fractionnée
                pane.removeTabFromSplitView(tab.id)
            } label: { Image(systemName: "xmark").font(.system(size: 8)) }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.05))
        .onTapGesture { // Double-clic pour activer cet onglet s'il n'est pas actif
            if !isActive { pane.currentTabID = tab.id }
        }
    }
}

// Vue pour la poignée de redimensionnement
struct SplitterResizeHandle: View {
    @Bindable var pane: AlveoPane
    let index: Int // Index du panneau à gauche de cette poignée
    let totalWidth: CGFloat
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 3) // Poignée plus épaisse pour une meilleure saisie
            .customCursor(.resizeLeftRight) // Utiliser votre extension pour le curseur
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Calculer le delta de proportion
                        let deltaWidth = value.translation.width - dragOffset
                        dragOffset = value.translation.width // Stocker pour le prochain changement

                        guard pane.splitViewProportions.count > index + 1 else { return }
                        
                        let originalLeftProportion = pane.splitViewProportions[index]
                        let originalRightProportion = pane.splitViewProportions[index+1]
                        
                        var deltaProportion = deltaWidth / totalWidth
                        
                        // Limiter le delta pour ne pas rendre les panneaux trop petits
                        let minProportion = 50.0 / totalWidth // Taille minimale de 50px en proportion
                        
                        if originalLeftProportion + deltaProportion < minProportion {
                            deltaProportion = minProportion - originalLeftProportion
                        }
                        if originalRightProportion - deltaProportion < minProportion {
                            deltaProportion = originalRightProportion - minProportion
                        }
                        
                        // Appliquer le delta
                        var newProportions = pane.splitViewProportions
                        newProportions[index] += deltaProportion
                        newProportions[index+1] -= deltaProportion
                        
                        // S'assurer que les proportions sont valides (>=0 et somme = 1)
                        // Normalement, la logique de minProportion devrait empêcher des proportions négatives.
                        // On ne normalise pas ici pour permettre un redimensionnement fluide,
                        // la normalisation se fait si la somme dévie trop.
                        pane.updateSplitViewProportions(newProportions)
                    }
                    .onEnded { _ in
                        dragOffset = 0 // Réinitialiser l'offset
                        // Normaliser les proportions pour s'assurer que la somme est 1.0
                        let sum = pane.splitViewProportions.reduce(0, +)
                        if sum > 0 && abs(sum - 1.0) > 0.0001 { // Si la somme a dérivé
                            let normalizedProportions = pane.splitViewProportions.map { $0 / sum }
                            pane.updateSplitViewProportions(normalizedProportions)
                        }
                    }
            )
    }
}

// Petite vue pour l'async image de la favicon (pour éviter la répétition)
struct FaviconAsyncImage: View {
    let url: URL
    let size: CGFloat
    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else if phase.error != nil {
                Image(systemName: "globe").font(.system(size: size * 0.8))
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(size * 0.2)
    }
}

