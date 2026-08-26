import AppKit
import SwiftUI

/// O fundo escuro translúcido do Focata — o mesmo da caixa da tarefa, das
/// Configurações e do Histórico.
///
/// `NSVisualEffectView` e não um `Material` da SwiftUI porque só ele mistura com
/// o que está **atrás da janela** (`.behindWindow`); dentro da janela não há o
/// que borrar, e o efeito sairia chapado.
///
/// Quem usa precisa deixar a janela sem fundo próprio — `isOpaque = false` e
/// `backgroundColor = .clear` —, senão o material pinta por cima de um retângulo
/// opaco e não há transparência nenhuma.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

extension NSWindow {
    /// Prepara a janela para o fundo translúcido: sem cor própria, para o
    /// material aparecer, e sem barra de título opaca por cima dele.
    func adoptTranslucentBackground() {
        isOpaque = false
        backgroundColor = .clear
    }
}
