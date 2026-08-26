import AppKit
import Testing

@testable import Focata

@MainActor
private func render(
    _ raw: String,
    bold: Bool = false,
    width: Double = 0,
    struck: Bool = false
) -> NSAttributedString {
    MarkdownRenderer.render(raw, style: .init(
        baseSize: 14,
        isBold: bold,
        width: width,
        color: .labelColor,
        isStruckThrough: struck,
        maximumWidth: 300
    ))
}

@MainActor
private func traits(_ string: NSAttributedString, at index: Int) -> NSFontTraitMask {
    let font = string.attribute(.font, at: index, effectiveRange: nil) as! NSFont
    return NSFontManager.shared.traits(of: font)
}

@Suite("MarkdownRenderer")
@MainActor
struct MarkdownRendererTests {
    @Test("o Markdown some do texto visível")
    func marcacaoNaoAparece() {
        #expect(render("Finalizar o **projeto**").string == "Finalizar o projeto")
        #expect(render("Ler ~~depois~~ agora").string == "Ler depois agora")
        #expect(render("Um *talvez*").string == "Um talvez")
    }

    @Test("negrito e itálico viram traços de fonte de verdade")
    func tracosDeFonte() {
        let negrito = render("normal **forte**")
        #expect(!traits(negrito, at: 0).contains(.boldFontMask))
        #expect(traits(negrito, at: 8).contains(.boldFontMask))

        let italico = render("normal *inclinado*")
        #expect(traits(italico, at: 8).contains(.italicFontMask))
    }

    @Test("tachado do Markdown vira o atributo de tachado")
    func tachadoDoMarkdown() {
        let string = render("Ler ~~depois~~")
        let attribute = string.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) as? Int
        #expect(attribute == NSUnderlineStyle.single.rawValue)
        #expect(string.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil)
    }

    @Test("tarefa concluída risca o texto inteiro")
    func tachadoDeConcluida() {
        let string = render("Escrever spec", struck: true)
        for index in 0..<string.length {
            let attribute = string.attribute(.strikethroughStyle, at: index, effectiveRange: nil) as? Int
            #expect(attribute == NSUnderlineStyle.single.rawValue)
        }
    }

    @Test("negrito global convive com o negrito do Markdown")
    func negritoGlobal() {
        let string = render("normal **forte**", bold: true)
        #expect(traits(string, at: 0).contains(.boldFontMask))
        #expect(traits(string, at: 8).contains(.boldFontMask))
    }

    @Test("links viram atributo de link")
    func links() {
        let string = render("Ver [a spec](https://exemplo.com)")
        #expect(string.string == "Ver a spec")
        #expect(string.attribute(.link, at: 5, effectiveRange: nil) != nil)
    }

    @Test("a largura da fonte muda a largura renderizada")
    func larguraDaFonte() {
        let estreita = render("Finalizar o projeto", width: -1).size().width
        let padrao = render("Finalizar o projeto", width: 0).size().width
        let larga = render("Finalizar o projeto", width: 1).size().width

        #expect(estreita < padrao)
        #expect(larga > padrao)
    }

    @Test("Markdown malformado não perde o texto")
    func markdownQuebrado() {
        #expect(render("**sem fechar").string.contains("sem fechar"))
        #expect(render("").string.isEmpty)
    }

    @Test("emoji e acentos sobrevivem à conversão")
    func unicode() {
        #expect(render("Finalizar o **projeto** 🦄").string == "Finalizar o projeto 🦄")
        #expect(render("Revisar a especificação").string == "Revisar a especificação")
    }
}
