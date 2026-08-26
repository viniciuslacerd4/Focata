import AppKit
import SwiftUI

/// Janela de configurações.
///
/// Criada à mão em vez de usar a cena `Settings` do SwiftUI porque o Focata usa
/// ciclo de vida AppKit — e porque um app `.accessory` precisa se ativar
/// explicitamente para que a janela receba foco.
///
/// As abas são uma `NSToolbar` de verdade, no estilo `.preference`: é o que dá o
/// ícone acima do rótulo e o realce da aba escolhida sem que a gente desenhe
/// nada. Um `TabView` da SwiftUI viraria um controle segmentado, que é o visual
/// de outra coisa.
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hosting: NSHostingController<SettingsView>?
    private let selection = SettingsSelection()

    private var tab: SettingsTab { selection.tab }

    func show() {
        if window == nil { makeWindow() }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() {
        let hosting = NSHostingController(rootView: SettingsView(settings: .shared, tab: tab))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // O mesmo escuro translúcido da caixa da tarefa.
        window.adoptTranslucentBackground()

        let toolbar = NSToolbar(identifier: "FocataSettings")
        toolbar.delegate = self
        // O rótulo vem dentro da view do item; sem isso a barra desenharia o
        // dela por baixo e cada aba apareceria com o nome escrito duas vezes.
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference

        self.hosting = hosting
        self.window = window

        // O título é o nome da aba, como nas preferências do sistema: a janela
        // já se apresenta pelo ícone do app na barra de ferramentas.
        window.title = tab.label
        window.center()
    }

    private func select(_ tab: SettingsTab) {
        guard tab != selection.tab else { return }
        selection.tab = tab
        hosting?.rootView = SettingsView(settings: .shared, tab: tab)
        window?.title = tab.label
        resize(to: tab.height)
    }

    /// A janela cresce e encolhe pela borda de baixo: a barra de ferramentas
    /// fica parada no lugar enquanto o conteúdo se ajusta.
    private func resize(to height: CGFloat) {
        guard let window else { return }

        let content = NSRect(origin: .zero, size: NSSize(width: SettingsTab.width, height: height))
        let target = window.frameRect(forContentRect: content)
        var frame = window.frame
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    // MARK: - NSToolbarDelegate

    private var itemIdentifiers: [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.itemIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        itemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        itemIdentifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }

        // Item com view própria, e não `image` + seleção nativa: é o que deixa
        // o realce branco em vez do azul de destaque do sistema.
        let button = SettingsTabButton(tab: tab, selection: selection) { [weak self] tab in
            self?.select(tab)
        }
        let view = NSHostingView(rootView: button)
        view.frame.size = view.fittingSize

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = ""
        item.paletteLabel = tab.label
        item.view = view
        return item
    }
}

private extension SettingsTab {
    var itemIdentifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue) }
}
