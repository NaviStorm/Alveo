import SwiftUI
import SwiftData

@MainActor
struct ActiveAlveoPaneContainerView: View {
    @Bindable var activePaneToDisplay: AlveoPane
    @StateObject var webViewHelperForActivePane: WebViewHelper
    @Binding var globalURLInputFromToolbar: String
    
    init(
        pane: AlveoPane,
        webViewHelper: WebViewHelper,
        globalURLInput: Binding<String>
    ) {
        self._activePaneToDisplay = Bindable(wrappedValue: pane)
        self._webViewHelperForActivePane = StateObject(wrappedValue: webViewHelper)
        self._globalURLInputFromToolbar = globalURLInput
    }
    
    var body: some View {
        AlveoPaneView(
            pane: activePaneToDisplay,
            webViewHelper: webViewHelperForActivePane,
            globalURLInput: $globalURLInputFromToolbar
        )
    }
}
