import AppKit

/// Desenha o conteúdo do item da barra num `NSImage`.
///
/// Um `NSImage` em `NSStatusItem.button.image` — em vez de uma `NSView`
/// customizada dentro do botão — porque no macOS moderno o item da barra é
/// hospedado remotamente pelo Control Center: uma subview com Auto Layout
/// briga com esse hosting e a janela do item chega a ficar sem posicionamento.
enum MenuBarItemRenderer {
    /// Espaço nas laterais para o conteúdo não colar nos itens vizinhos.
    static let horizontalPadding: CGFloat = 3
    /// Respiro entre o anel (ou o cadeado) e o texto.
    private static let elementSpacing: CGFloat = 5
    private static let lockWidth: CGFloat = 9

    struct Content {
        var text: NSAttributedString
        var maximumTextWidth: CGFloat
        /// `nil` quando o Pomodoro está desligado — aí só o texto aparece.
        var ring: Ring?
        var isPrivate: Bool

        struct Ring {
            var progress: Double
            var color: NSColor
            /// Substitui o arco pelo check de ciclo concluído.
            var showsCheckmark: Bool
            /// Acende o `||` no meio do anel.
            var isPaused: Bool
        }
    }

    static func image(for content: Content) -> NSImage {
        let textWidth = content.text.length > 0
            ? ceil(min(content.text.size().width, content.maximumTextWidth))
            : 0

        var width = horizontalPadding * 2
        if content.ring != nil { width += RingRenderer.diameter + elementSpacing }
        if content.isPrivate { width += lockWidth + elementSpacing }
        width += textWidth

        let image = NSImage(size: NSSize(width: max(width, 1), height: NSStatusBar.system.thickness), flipped: false) { bounds in
            var x = horizontalPadding

            if let ring = content.ring {
                let box = NSRect(x: x, y: 0, width: RingRenderer.diameter, height: bounds.height)
                if ring.showsCheckmark {
                    RingRenderer.drawCheckmark(in: box, color: ring.color)
                } else {
                    RingRenderer.draw(in: box, progress: ring.progress, color: ring.color)
                    if ring.isPaused {
                        RingRenderer.drawPauseGlyph(in: box, color: ring.color)
                    }
                }
                x += RingRenderer.diameter + elementSpacing
            }

            if content.isPrivate {
                let box = NSRect(x: x, y: 0, width: lockWidth, height: bounds.height)
                RingRenderer.drawPrivacyLock(in: box, color: .labelColor)
                x += lockWidth + elementSpacing
            }

            if content.text.length > 0 {
                let textHeight = ceil(content.text.size().height)
                content.text.draw(in: NSRect(
                    x: x,
                    y: ((bounds.height - textHeight) / 2).rounded(),
                    width: textWidth,
                    height: textHeight
                ))
            }
            return true
        }

        // Sem cache o handler roda de novo quando a barra troca entre claro e
        // escuro, então `labelColor` e afins são resolvidos na aparência certa.
        image.cacheMode = .never
        // Não é template: o anel verde do tempo livre precisa manter a cor.
        image.isTemplate = false
        return image
    }
}
