import SwiftUI
import SwiftData

struct SidebarView: View {
    @Bindable var pane: AlveoPane
    @ObservedObject var webViewHelper: WebViewHelper
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tête du volet
            HStack {
                Text(pane.name ?? "Espace")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    pane.addTab(urlString: "about:blank")
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Liste des onglets
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(pane.sortedTabs) { tab in
                        SidebarTabRow(
                            tab: tab,
                            isSelected: tab.id == pane.currentTabID,
                            onSelect: {
                                pane.currentTabID = tab.id
                                tab.lastAccessed = Date()
                            },
                            onClose: {
                                modelContext.delete(tab)
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
        .background(Color(nsColor: .safeSidebarBackground))
    }
}

struct SidebarTabRow: View {
    let tab: Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Indicateur de sélection
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                if let url = tab.displayURL?.host {
                    Text(url)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if isHovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .opacity(0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : 
                      (isHovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
        .padding(.horizontal, 8)
    }
}

