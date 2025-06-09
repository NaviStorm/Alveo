import SwiftUI

struct SidebarTabRow: View {
    let tab: Tab
    @Bindable var pane: AlveoPane
    let allPanes: [AlveoPane]
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onToggleSplitView: () -> Void
    
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var newName: String = ""
    @State private var isOptionKeyPressed = false
    
    let emojiList = ["😀", "🚀", "🔥", "🌟", "🐱", "🐶", "🍎", "🍕", "🎉", "💡", "📱", "💻", "🌐", "📧", "🎵", "🎮", "📚", "⚡", "🌈", "🎯"]
    
    private var isInSplitView: Bool {
        pane.splitViewTabIDs.contains(tab.id)
    }
    
    private var shouldShowSplitViewCloseButton: Bool {
        isHovering && isOptionKeyPressed && isInSplitView
    }

    var body: some View {
        HStack(spacing: 6) {
            tabIcon
            tabContent
            Spacer()
            
            if shouldShowSplitViewCloseButton {
                splitViewCloseButton
            } else if shouldShowCloseButton {
                closeButton
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(tabBackground)
        .overlay(
            // Bordure pour l'onglet actif (plus épaisse)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    tab.id == pane.currentTabID ? Color.accentColor :
                    (pane.selectedTabIDs.contains(tab.id) ? Color.accentColor.opacity(0.6) : Color.clear),
                    lineWidth: tab.id == pane.currentTabID ? 2 : 1
                )
        )
        .overlay(
            // Indicateur Option pressé
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isOptionKeyPressed ? Color.orange : Color.clear,
                    lineWidth: isOptionKeyPressed ? 2 : 0
                )
                .opacity(isOptionKeyPressed && isHovering ? 1.0 : 0.0)
        )
        .contentShape(Rectangle())
        .onTapGesture { event in
            handleTapGesture(event: event)
        }
        .onHover { hovering in
            if !isRenaming {
                isHovering = hovering
            }
        }
        .onAppear {
            // Surveiller les touches Option (Alt)
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                isOptionKeyPressed = event.modifierFlags.contains(.option)
                return event
            }
        }
        
        .contextMenu {
            contextMenuContent
        }
    }
    
    // MARK: - Gestion des événements
    
    private func handleTapGesture(event: Any) {
        if !isRenaming {
            // Vérifier si Option est pressé pour basculer en vue fractionnée
            if NSEvent.modifierFlags.contains(.option) {
                handleOptionClickSplitView()
            } else {
                onSelect()
            }
        }
    }
    
    // Nouvelle méthode pour gérer le clic Option
    private func handleOptionClickSplitView() {
        if !pane.isSplitViewActive {
            // Créer une nouvelle vue fractionnée avec l'onglet actuel + cet onglet
            if let currentTabID = pane.currentTabID, currentTabID != tab.id {
                // Activer la vue fractionnée avec l'onglet actuel et celui cliqué
                pane.enableSplitView(with: [currentTabID, tab.id])
            } else {
                // Si c'est le même onglet ou pas d'onglet actuel, créer un nouvel onglet vide
                pane.addTab(urlString: "about:blank")
                if let newTabID = pane.currentTab?.id {
                    pane.enableSplitView(with: [tab.id, newTabID])
                }
            }
        } else {
            // Vue fractionnée déjà active, ajouter cet onglet
            if !pane.splitViewTabIDs.contains(tab.id) {
                pane.addTabToSplitView(tab.id)
            } else {
                // Si déjà dans la vue fractionnée, le retirer
                pane.removeTabFromSplitView(tab.id)
            }
        }
    }

    // MARK: - Sous-vues décomposées
    
    @ViewBuilder
    private var tabIcon: some View {
        Group {
            if let emoji = tab.customEmojiIcon {
                Text(emoji)
                    .font(.system(size: 16))
                    .frame(width: 16, height: 16)
            } else if let faviconURL = tab.faviconURL {
                faviconImage(url: faviconURL)
            } else {
                defaultIcon
            }
        }
    }
    
    @ViewBuilder
    private func faviconImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .cornerRadius(3)
            case .failure(_):
                defaultIcon
            @unknown default:
                defaultIcon
            }
        }
    }
    
    @ViewBuilder
    private var defaultIcon: some View {
        Image(systemName: "globe")
            .font(.system(size: 12))
            .frame(width: 16, height: 16)
            .foregroundColor(.secondary)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        if isRenaming {
            renamingField
        } else {
            HStack {
                tabInfo
                
                Spacer()
                
                // ✅ Indicateurs visuels
                if tab.id == pane.currentTabID {
                    // Indicateur pour l'onglet actif
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                } else if pane.selectedTabIDs.contains(tab.id) {
                    // Indicateur pour la sélection multiple
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: 8, height: 8)
                }
            }
        }
    }
    
    @ViewBuilder
    private var renamingField: some View {
        TextField("Renommer l'onglet", text: $newName)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .font(.system(size: 12))
            .onSubmit {
                finishRenaming()
            }
            .onExitCommand {
                cancelRenaming()
            }
    }
    
    @ViewBuilder
    private var tabInfo: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(tab.displayTitle)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                
                // Indicateur de vue fractionnée
                if isInSplitView {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
            }

            tabSubtitle
        }
    }
    
    @ViewBuilder
    private var tabSubtitle: some View {
        if let host = tab.displayURL?.host?.replacingOccurrences(of: "www.", with: ""), !host.isEmpty {
            Text(host)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else if tab.urlString == "about:blank" || tab.urlString.isEmpty {
            Text("Page vide")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
    
    private var shouldShowCloseButton: Bool {
        (isHovering || isSelected) && !isRenaming && !shouldShowSplitViewCloseButton
    }
    
    @ViewBuilder
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(3)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var splitViewCloseButton: some View {
        Button(action: {
            pane.removeTabFromSplitView(tab.id)
        }) {
            Image(systemName: "rectangle.split.2x1.slash")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.orange)
                .padding(3)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var tabBackground: some View {
        ZStack {
            if isInSplitView {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.1))
            } else if tab.id == pane.currentTabID {
                // ✅ Onglet actif - surbrillance forte
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.25))
            } else if pane.selectedTabIDs.contains(tab.id) {
                // ✅ Onglet sélectionné (mais pas actif) - surbrillance plus légère
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
            } else if isHovering {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
        }
    }
    
    
    @ViewBuilder
    private var contextMenuContent: some View {
        copyURLButton
        Divider()
        changeIconMenu
        renameButton
        Divider()
        splitViewButton
        
        // ✅ Option spécifique si plusieurs onglets sont sélectionnés
        if pane.selectedTabIDs.count > 1 && pane.selectedTabIDs.contains(tab.id) {
            Button("Vue fractionnée avec sélection (\(pane.selectedTabIDs.count) onglets)") {
                // Déléguer à SidebarView
                NotificationCenter.default.post(
                    name: .enableSplitViewWithSelection,
                    object: pane.id
                )
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
        
        duplicateButton
        if allPanes.count > 1 {
            moveToMenu
        }
    }
    
    @ViewBuilder
    private var copyURLButton: some View {
        Button {
            copyURL()
        } label: {
            Label("Copier le lien URL", systemImage: "doc.on.clipboard")
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
    }
    
    @ViewBuilder
    private var changeIconMenu: some View {
        Menu {
            defaultFaviconButton
            Divider()
            emojiGrid
        } label: {
            Label("Changer l'icône...", systemImage: "face.smiling")
        }
    }
    
    @ViewBuilder
    private var defaultFaviconButton: some View {
        Button {
            tab.customEmojiIcon = nil
        } label: {
            Label("Favicon par défaut", systemImage: "globe")
        }
    }
    
    @ViewBuilder
    private var emojiGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(emojiList, id: \.self) { emoji in
                Button {
                    tab.customEmojiIcon = emoji
                } label: {
                    Text(emoji)
                        .font(.system(size: 16))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    @ViewBuilder
    private var renameButton: some View {
        Button {
            startRenaming()
        } label: {
            Label("Renommer...", systemImage: "pencil")
        }
    }
    
    @ViewBuilder
    private var splitViewButton: some View {
        Button {
            handleSplitViewAction()
        } label: {
            if isInSplitView {
                Label("Retirer de la vue fractionnée", systemImage: "rectangle.split.2x1.slash")
            } else {
                Label("Vue fractionnée", systemImage: "rectangle.split.2x1")
            }
        }
    }
    
    @ViewBuilder
    private var duplicateButton: some View {
        Button {
            duplicateTab()
        } label: {
            Label("Dupliquer", systemImage: "plus.square.on.square")
        }
    }
    
    @ViewBuilder
    private var moveToMenu: some View {
        Menu {
            ForEach(allPanes.filter { $0.id != pane.id }) { targetPane in
                Button {
                    moveTabToPane(targetPane)
                } label: {
                    Text(targetPane.name ?? "Espace sans nom")
                }
            }
        } label: {
            Label("Déplacer vers", systemImage: "arrow.right.square")
        }
    }
    
    // MARK: - Actions
    private func handleSplitViewAction() {
        if isInSplitView {
            pane.removeTabFromSplitView(tab.id)
        } else {
            // Si aucune vue fractionnée n'est active, créer avec l'onglet actuel + cet onglet
            if !pane.isSplitViewActive {
                if let currentTabID = pane.currentTabID, currentTabID != tab.id {
                    // Utiliser l'onglet actuel + celui-ci
                    pane.enableSplitView(with: [currentTabID, tab.id])
                } else {
                    // Créer un onglet vide + celui-ci
                    pane.addTab(urlString: "about:blank")
                    if let newTabID = pane.currentTab?.id {
                        pane.enableSplitView(with: [tab.id, newTabID])
                    }
                }
            } else {
                // Ajouter à la vue fractionnée existante
                pane.addTabToSplitView(tab.id)
            }
        }
    }
    
    private func copyURL() {
        if let url = tab.displayURL {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }
    
    private func startRenaming() {
        newName = tab.title ?? tab.displayTitle
        isRenaming = true
    }
    
    private func finishRenaming() {
        if !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tab.title = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        isRenaming = false
    }
    
    private func cancelRenaming() {
        isRenaming = false
    }
    
    private func duplicateTab() {
        pane.addTab(urlString: tab.urlString)
        if let newTab = pane.currentTab {
            newTab.title = tab.title
            newTab.customEmojiIcon = tab.customEmojiIcon
        }
    }
    
    private func moveTabToPane(_ targetPane: AlveoPane) {
        let tabUrlString = tab.urlString
        let tabTitle = tab.title
        let tabCustomEmoji = tab.customEmojiIcon
        
        // Retirer de la vue fractionnée si nécessaire
        if isInSplitView {
            pane.removeTabFromSplitView(tab.id)
        }
        
        if let index = pane.tabs.firstIndex(where: { $0.id == tab.id }) {
            pane.tabs.remove(at: index)
            
            if pane.currentTabID == tab.id {
                if !pane.tabs.isEmpty {
                    let newIndex = min(index, pane.tabs.count - 1)
                    pane.currentTabID = pane.tabs[newIndex].id
                } else {
                    pane.currentTabID = nil
                }
            }
        }
        
        targetPane.addTab(urlString: tabUrlString)
        if let newTab = targetPane.currentTab {
            newTab.title = tabTitle
            newTab.customEmojiIcon = tabCustomEmoji
        }
    }
}

