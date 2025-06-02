import SwiftUI

extension View {
    /// Définit le curseur de la souris affiché lorsqu'on survole cette vue.
    /// Attention : Peut avoir des comportements inattendus avec des gestes ou des animations complexes
    /// qui pourraient réinitialiser le curseur.
    public func customCursor(_ cursor: NSCursor) -> some View {
        if #available(macOS 13.0, *) {
            // Pour macOS 13+, onContinuousHover est plus fiable pour certains cas,
            // mais il faut gérer correctement le push/pop pour éviter les fuites de curseur.
            return self.onContinuousHover { phase in
                switch phase {
                case .active(_):
                    // Empêche de pousser le même curseur plusieurs fois
                    if NSCursor.current != cursor {
                        cursor.push()
                    }
                case .ended:
                    // Pop seulement si le curseur actuel est celui qu'on a poussé
                    if NSCursor.current == cursor {
                         NSCursor.pop()
                    } else {
                        // Si un autre curseur a été poussé par-dessus, on ne pop pas celui-ci
                        // pour ne pas perturber la pile. Cela peut arriver si une vue enfant
                        // pousse aussi un curseur.
                        // Alternativement, on pourrait avoir besoin de vider la pile jusqu'à retrouver
                        // le curseur précédent, mais c'est plus complexe.
                        // Pour l'instant, on fait un pop simple si c'est notre curseur.
                        // Si ce n'est pas notre curseur, il est possible qu'il faille un pop
                        // quand même si c'est le dernier curseur que notre vue a géré.
                        // La gestion de la pile de curseurs peut être délicate.
                        // Le plus simple est de s'assurer qu'on pop ce qu'on a poussé.
                        // Si le curseur a changé, c'est qu'une autre vue l'a modifié.
                        // Si on quitte la zone, on devrait pop NOTRE curseur.
                        // NSCursor.pop() // Tentative de pop plus agressive
                    }
                }
            }
        } else {
            // Pour les versions antérieures à macOS 13
            return self.onHover { inside in
                if inside {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}

