import AppKit

/// Converte o texto da tarefa em `NSAttributedString` para a barra de menu,
/// aplicando Markdown inline (negrito, itálico, tachado, links) e a aparência
/// configurada.
///
/// A conversão é feita à mão em vez de `NSAttributedString(AttributedString:)`
/// porque a ponte não traduz `inlinePresentationIntent` em traços de `NSFont` —
/// o negrito e o itálico simplesmente sumiriam.
enum MarkdownRenderer {
    struct Style {
        var baseSize: CGFloat
        var isBold: Bool
        /// -1 (estreita) a 1 (larga); 0 é a largura padrão.
        var width: Double
        var color: NSColor
        var isStruckThrough: Bool
        var maximumWidth: CGFloat
    }

    static func render(_ raw: String, style: Style) -> NSAttributedString {
        let baseFont = font(size: style.baseSize, bold: style.isBold, italic: false, width: style.width)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let result = NSMutableAttributedString()

        guard let parsed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return NSAttributedString(
                string: raw,
                attributes: baseAttributes(baseFont, style: style, paragraph: paragraph)
            )
        }

        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            let bold = style.isBold || intent.contains(.stronglyEmphasized)
            let italic = intent.contains(.emphasized)

            var attributes = baseAttributes(
                font(size: style.baseSize, bold: bold, italic: italic, width: style.width),
                style: style,
                paragraph: paragraph
            )

            // Tachado do Markdown (`~~texto~~`) e tachado de "tarefa concluída"
            // são a mesma decoração — qualquer um dos dois liga o atributo.
            if intent.contains(.strikethrough) || style.isStruckThrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = style.color
            }

            if let link = run.link {
                attributes[.link] = link
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }

        return result
    }

    private static func baseAttributes(
        _ font: NSFont,
        style: Style,
        paragraph: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.color,
            .paragraphStyle: paragraph,
        ]
        if style.isStruckThrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = style.color
        }
        return attributes
    }

    private static func font(size: CGFloat, bold: Bool, italic: Bool, width: Double) -> NSFont {
        var base = NSFont.menuBarFont(ofSize: size)

        // A largura entra pelo descritor para manter a fonte da barra como base,
        // em vez de trocá-la pela fonte de sistema genérica.
        if width != 0 {
            let descriptor = base.fontDescriptor.addingAttributes([
                .traits: [NSFontDescriptor.TraitKey.width: width]
            ])
            base = NSFont(descriptor: descriptor, size: size) ?? base
        }

        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        guard !traits.isEmpty else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: traits)
    }
}
