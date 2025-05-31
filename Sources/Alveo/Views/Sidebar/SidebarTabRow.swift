//
//  SidebarTabRow.swift
//  Alveo
//
//  Created by Thierry Andreu Asscensio on 31/05/2025.
//

import SwiftUI

struct SidebarTabRow: View {
    let tab: Tab
    @Bindable var pane: AlveoPane
    let allPanes: [AlveoPane]
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var newName: String = ""
    
    // Liste d'emojis pour le changement d'icône
    let emojiList = ["😀", "🚀", "🔥", "🌟", "🐱", "🐶", "🍎", "🍕", "🎉", "💡", "📱", "💻", "🌐", "📧", "🎵", "🎮", "📚", "⚡", "🌈", "🎯"]

    var body: some View {
        HStack(spacing: 6) {
            tabIcon
            tabContent
            Spacer()
            if shouldShowCloseButton {
                closeButton
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(tabBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming {
                onSelect()
            }
        }
        .onHover { hovering in
            if !isRenaming {
                isHovering = hovering
            }
        }
        .contextMenu {
            contextMenuContent
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
            tabInfo
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
            Text(tab.displayTitle)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundColor(isSelected ? .accentColor : .primary)

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
        (isHovering || isSelected) && !isRenaming
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
    private var tabBackground: some View {
        ZStack {
            if isSelected {
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
            // Fonctionnalité future
            print("Vue fractionnée - fonctionnalité future")
        } label: {
            Label("Vue fractionnée", systemImage: "rectangle.split.2x1")
        }
        .disabled(true)
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
