#!/usr/bin/env swift
// Desenha o fundo da janela do .dmg em 1x e 2x, num único TIFF.
// Uso: swift scripts/dmg-background.swift saida.tiff
import AppKit

// A arte vive nesta área, do canto superior esquerdo para baixo — é o tamanho
// em que a janela abre.
let designW = 660.0, designH = 400.0

// A tela é bem maior que a arte. O Finder desenha o fundo no tamanho natural,
// ancorado no canto superior esquerdo, e não estica: se alguma coisa abrir a
// janela maior que o pedido (um gerenciador de janelas em tiling, por exemplo),
// o excedente apareceria branco. Com a tela grande ele aparece escuro.
let canvasW = 1440.0, canvasH = 1120.0

// Posições dos ícones na janela do Finder (mesmas do dmg.sh), em coordenadas
// do Finder: origem no canto superior esquerdo.
let appCenter = 165.0, applicationsCenter = 495.0, iconRow = 200.0

// O fundo é claro e o texto escuro, e isso não é escolha de gosto: o Finder
// decide a cor do rótulo dos ícones olhando o `backgroundColor` gravado no
// .DS_Store, e quando o fundo é uma *imagem* ele grava branco e desenha o
// rótulo escuro, sempre. Não adianta regravar o campo — com
// `backgroundType = 2` ele é ignorado (testado). Fundo escuro deixaria
// "Focata" e "Applications" pretos sobre preto.
let silverTop = NSColor(srgbRed: 0.957, green: 0.961, blue: 0.969, alpha: 1)
let silverBottom = NSColor(srgbRed: 0.886, green: 0.894, blue: 0.910, alpha: 1)
let slate = NSColor(srgbRed: 0.122, green: 0.145, blue: 0.169, alpha: 1)

func draw(scale: CGFloat) -> NSBitmapImageRep {
    let px = NSSize(width: canvasW * scale, height: canvasH * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(px.width), pixelsHigh: Int(px.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvasW, height: canvasH)   // pontos, não pixels

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.setShouldAntialias(true)

    // Coordenadas do Finder (y crescendo para baixo) sobre um contexto AppKit.
    func flip(_ y: Double) -> Double { canvasH - y }

    // O degradê ocupa só a faixa da arte; abaixo dela, a cor final continua
    // lisa, então a emenda não aparece.
    silverBottom.setFill()
    NSRect(x: 0, y: 0, width: canvasW, height: flip(designH)).fill()
    NSGradient(starting: silverTop, ending: silverBottom)!
        .draw(in: NSRect(x: 0, y: flip(designH), width: canvasW, height: designH), angle: -90)

    func text(_ s: String, size: CGFloat, weight: NSFont.Weight,
              color: NSColor, centerX: Double, top: Double, tracking: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: tracking,
        ]
        let a = NSAttributedString(string: s, attributes: attrs)
        let sz = a.size()
        a.draw(at: NSPoint(x: centerX - sz.width / 2, y: flip(top) - sz.height))
    }

    text("Focata", size: 30, weight: .semibold, color: slate,
         centerX: designW / 2, top: 58, tracking: 0.5)
    text("Arraste para a pasta Aplicativos", size: 13, weight: .regular,
         color: slate.withAlphaComponent(0.55), centerX: designW / 2, top: 100)

    // Seta entre os dois ícones.
    let y = flip(iconRow)
    let x0 = appCenter + 120, x1 = applicationsCenter - 120
    let arrow = NSBezierPath()
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: x0, y: y))
    arrow.line(to: NSPoint(x: x1, y: y))
    arrow.move(to: NSPoint(x: x1 - 11, y: y + 9))
    arrow.line(to: NSPoint(x: x1, y: y))
    arrow.line(to: NSPoint(x: x1 - 11, y: y - 9))
    slate.withAlphaComponent(0.38).setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.tiff"
let image = NSImage(size: NSSize(width: canvasW, height: canvasH))
image.addRepresentation(draw(scale: 1))
image.addRepresentation(draw(scale: 2))
guard let data = image.tiffRepresentation else { exit(1) }
try data.write(to: URL(fileURLWithPath: out))
