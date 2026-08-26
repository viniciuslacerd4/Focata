import AppKit

// Ciclo de vida em AppKit puro (em vez de `SwiftUI.App`): um app que vive só na
// barra de status precisa de controle direto sobre o NSStatusItem e sobre as
// janelas. As telas continuam sendo SwiftUI, hospedadas em NSHostingView.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
