//
//  TabButton.swift
//  Alveo
//
//  Created by Thierry Andreu Asscensio on 31/05/2025.
//

import SwiftUI

// Utiliser un protocole si TabButton doit être générique pour différents types d'onglets à l'avenir.
// Pour l'instant, nous allons le lier directement à votre modèle `Tab` existant.
// Si `Tab` est un @Model SwiftData, il doit être observable.
// Le passage de `pane: AlveoPane` est nécessaire pour la logique de fermeture.

@MainActor // Assurer les mises à jour UI sur le thread principal
struct TabButton: View {
    // Utiliser @ObservedObject si Tab est une classe ObservableObject.
    // Si Tab est un @Model SwiftData, le simple passage de l'instance suffit
    // car la vue parente (TabBarView) réagira aux changements via son @Query ou @Bindable.
    let tab: Tab // Supposons que Tab est votre modèle @Model SwiftData
    @Bindable var pane: AlveoPane // Nécessaire pour currentTabID et la suppression
    
    // Booléen pour savoir si cet onglet est l'onglet actuellement sélectionné
    var isSelected: Bool
    
    // Action à exécuter lorsque le bouton est pressé (sélection de l'onglet)
    let onSelect: () -> Void
    // Action pour fermer l'onglet
    let onClose: () -> Void
    
    @State private var isHoveringCloseButton: Bool = false
    @State private var isHoveringTab: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) { // Réduire l'espacement si nécessaire
                // Favicon (placeholder pour l'instant)
                // Image(systemName: "globe") // Placeholder
                //     .font(.system(size: 12))
                //     .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(tab.displayTitle)
                    .font(.system(size: 12)) // Police légèrement plus petite pour les onglets
                    .lineLimit(1)
                    .foregroundColor(isSelected ? (isHoveringTab ? .primary.opacity(0.9) : .primary) : (isHoveringTab ? .primary.opacity(0.8) : .secondary))
                    .padding(.leading, 8) // Un peu de padding à gauche du titre

                // Bouton de fermeture (croix)
                // Visible uniquement si l'onglet est sélectionné OU survolé
                if isSelected || isHoveringTab {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium)) // Icône plus petite
                            .padding(3) // Pour une meilleure zone de clic
                    }
                    .buttonStyle(.plain) // Style sans bordure ni fond
                    .contentShape(Rectangle()) // Assure que le padding est cliquable
                    .foregroundColor(isHoveringCloseButton ? .red : (isSelected ? .primary.opacity(0.7) : .secondary.opacity(0.7)))
                    .background(isHoveringCloseButton ? Color.red.opacity(0.2) : Color.clear)
                    .cornerRadius(isHoveringCloseButton ? 4 : 0)
                    .onHover { hovering in
                        isHoveringCloseButton = hovering
                    }
                    .padding(.trailing, 4) // Un peu d'espace après la croix
                } else {
                    // Placeholder pour garder la même hauteur si la croix n'est pas visible,
                    // ou simplement permettre au HStack de se réduire.
                    // Pour une hauteur constante, on pourrait ajouter un Spacer ou une Image transparente.
                    // Pour l'instant, on laisse le HStack se réduire.
                }
            }
            .padding(.vertical, 5) // Padding vertical pour le bouton entier
        }
        .buttonStyle(.plain) // Style de base pour le bouton principal
        .background(
            ZStack {
                // Fond de l'onglet
                if isSelected {
                    // Couleur de fond plus prononcée pour l'onglet sélectionné
                    (isHoveringTab ? Color.accentColor.opacity(0.3) : Color.accentColor.opacity(0.25))
                } else if isHoveringTab {
                    Color.primary.opacity(0.08) // Léger fond au survol
                }
                
                // Ligne de soulignement pour l'onglet sélectionné
                if isSelected {
                    VStack {
                        Spacer()
                        Color.accentColor
                            .frame(height: 1.5)
                    }
                }
            }
        )
        .cornerRadius(4) // Coins légèrement arrondis pour les onglets
        .onHover { hovering in
            isHoveringTab = hovering
        }
        // .frame(maxWidth: 150) // Optionnel: Limiter la largeur maximale d'un onglet
    }
}
