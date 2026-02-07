import SwiftUI

struct GhosttyColorSchemeSyncView<Content: View>: View {
  @Environment(\.colorScheme) private var colorScheme
  let ghostty: GhosttyRuntime
  let content: Content

  init(ghostty: GhosttyRuntime, @ViewBuilder content: () -> Content) {
    self.ghostty = ghostty
    self.content = content()
  }

  var body: some View {
    content
      .task {
        // Apply the initial color scheme when the view appears.
        // This must happen in the view lifecycle, not in App.init(),
        // because NSApp.effectiveAppearance is not available during init.
        apply(colorScheme)
      }
      .onChange(of: colorScheme) { _, newValue in
        apply(newValue)
      }
  }

  private func apply(_ scheme: ColorScheme) {
    ghostty.setColorScheme(scheme)
  }
}
