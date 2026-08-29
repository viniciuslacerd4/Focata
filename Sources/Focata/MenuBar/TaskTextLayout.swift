import AppKit

/// A máquina de layout que mede o texto da tarefa fora da tela.
///
/// Existe para que três lugares concordem sobre onde cada linha começa e
/// termina: a altura da caixa, o texto desenhado dentro dela e o risco que
/// atravessa a tarefa concluída. Feita a conta duas vezes de jeitos diferentes,
/// o risco cairia num lugar e a palavra em outro.
///
/// É TextKit 1 de propósito: é o mesmo motor do `NSTextView` do editor.
@MainActor
final class TaskTextLayout {
    /// Cinco linhas: o bastante para uma tarefa escrita por extenso sem que a
    /// caixa flutuante vire uma janela de texto no meio da tela.
    static let maxLines = 5
    static let fontSize: CGFloat = 14
    static let font = NSFont.systemFont(ofSize: fontSize)

    /// Uma linha do texto já quebrado, medida na largura da caixa.
    struct Line {
        /// Onde a linha começa e quanto dela é texto — sem contar o resto vazio
        /// da largura da caixa.
        var rect: NSRect
        /// A altura em que o risco cruza a linha, contada do topo.
        var strikeY: CGFloat
    }

    /// Os três objetos ficam guardados porque a rede do TextKit se sustenta de
    /// cima para baixo — o armazenamento segura o layout, que segura o contêiner
    /// —, e guardar só o contêiner deixaria os outros dois caírem.
    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private let container = NSTextContainer(
        size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )

    init(limitedToMaxLines: Bool = false) {
        container.lineFragmentPadding = 0
        // O editor rola o que passa de cinco linhas; quem só desenha, corta.
        container.maximumNumberOfLines = limitedToMaxLines ? Self.maxLines : 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
    }

    var lineHeight: CGFloat { manager.defaultLineHeight(for: Self.font) }

    /// Refaz o layout do texto na largura dada. Vem antes de perguntar qualquer
    /// medida.
    func update(text: String, width: CGFloat) {
        container.size = NSSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude)
        storage.setAttributedString(
            NSAttributedString(string: text, attributes: [
                .font: Self.font,
                .foregroundColor: NSColor.labelColor,
            ])
        )
        manager.ensureLayout(for: container)
    }

    /// A altura do texto, entre uma linha e `maxLines`.
    func height() -> CGFloat {
        let used = manager.usedRect(for: container).height
        return min(max(used, lineHeight), lineHeight * CGFloat(Self.maxLines)).rounded(.up)
    }

    /// As linhas visíveis, de cima para baixo.
    func lines() -> [Line] {
        var lines: [Line] = []
        let glyphs = manager.glyphRange(for: container)
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, range, _ in
            // A linha do risco não é o meio do retângulo: é a altura da própria
            // caneta, um pouco acima da metade das minúsculas, contada a partir
            // da base onde as letras se apoiam.
            let baseline = used.minY + self.manager.location(forGlyphAt: range.location).y
            lines.append(Line(rect: used, strikeY: baseline - Self.font.xHeight / 2))
        }
        return lines
    }

    /// Desenha o texto já medido, do topo do retângulo para baixo.
    func draw(at origin: NSPoint) {
        let glyphs = manager.glyphRange(for: container)
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }
}
