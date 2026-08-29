import AppKit
import SwiftUI

/// A tarefa concluída saindo de cena: o risco atravessa uma linha de cada vez,
/// da esquerda para a direita, e o que ficou riscado se desfaz.
///
/// É AppKit, e não um `Text` da SwiftUI, porque o risco precisa cair exatamente
/// sobre as palavras: quem sabe onde cada linha começa e termina é a mesma
/// máquina de layout que quebra o texto dentro do editor (`TaskTextLayout`).
/// Duas quebras de linha diferentes deixariam o traço sobrando de um lado e
/// faltando do outro.
///
/// A animação é do próprio `NSView`, contada a partir de um instante: a SwiftUI
/// não interpola valores que atravessam para uma view do AppKit, e o relógio
/// aqui é o mesmo que decide quando tocar o som de cada traço.
struct FarewellText: NSViewRepresentable {
    let text: String
    /// Chamado quando o texto acabou de se desfazer.
    let onFinish: () -> Void

    func makeNSView(context: Context) -> FarewellTextView {
        let view = FarewellTextView()
        view.onFinish = onFinish
        view.text = text
        return view
    }

    func updateNSView(_ nsView: FarewellTextView, context: Context) {
        nsView.onFinish = onFinish
        nsView.text = text
    }

    /// A caixa não muda de altura enquanto a tarefa sai: é a mesma medida do
    /// editor, com o mesmo texto.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FarewellTextView, context: Context) -> CGSize? {
        // Sem largura proposta — é a SwiftUI perguntando o tamanho ideal — vale
        // a que a view já ocupa: o retrato é do texto como ele estava, e não de
        // como ele caberia em outra caixa.
        var width = proposal.width ?? nsView.bounds.width
        if !width.isFinite || width <= 0 { width = nsView.bounds.width }
        if width <= 0 { width = TaskPanelView.width }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }
}

/// O desenho e o relógio do risco.
@MainActor
final class FarewellTextView: NSView {
    /// Cada linha leva o mesmo tempo, uma depois da outra: é o que faz o risco
    /// parecer uma mão passando pelo texto, e não uma cortina caindo sobre ele.
    ///
    /// O passo é o de quem risca sem pressa — a conclusão é o único momento em
    /// que o Focata pede para você olhar. Os sons do risco duram o mesmo tempo
    /// (`scripts/gerar-som-do-risco.py`).
    static let strokeDuration: TimeInterval = 0.30
    static let dissolveDuration: TimeInterval = 0.42
    /// A largura da borda esfumaçada que apaga o texto.
    private static let feather: CGFloat = 70
    private static let frameInterval: TimeInterval = 1.0 / 60

    var onFinish: () -> Void = {}

    var text = "" {
        didSet {
            guard text != oldValue else { return }
            relayout()
        }
    }

    /// Duas máquinas de layout: uma quebra o texto na largura da view, para
    /// desenhar; a outra responde às medidas que a SwiftUI pede em larguras
    /// hipotéticas. Fossem a mesma, uma pergunta de medida requebraria o texto
    /// no meio do risco — e as linhas mudariam de lugar debaixo do traço.
    private let layout = TaskTextLayout(limitedToMaxLines: true)
    private let ruler = TaskTextLayout(limitedToMaxLines: true)
    /// Só as linhas com texto: uma linha em branco não se risca, e pular a vez
    /// dela evita um traço mudo no meio da animação.
    private var lines: [TaskTextLayout.Line] = []
    private var startedAt: Date?
    private var strokesPlayed = 0
    private var timer: Timer?

    /// TextKit desenha de cima para baixo, como o `NSTextView` do editor.
    override var isFlipped: Bool { true }

    private var totalDuration: TimeInterval {
        TimeInterval(lines.count) * Self.strokeDuration + Self.dissolveDuration
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        ruler.update(text: text, width: width)
        return ruler.height()
    }

    // MARK: - Ciclo de vida

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? stop() : start()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    private func relayout() {
        // Antes da primeira largura de verdade não há o que quebrar; o relógio
        // espera por ela, senão a animação começaria sem linha nenhuma.
        guard bounds.width >= 1 else { return }
        layout.update(text: text, width: bounds.width)
        lines = layout.lines().filter { $0.rect.width > 1 }
        needsDisplay = true
        start()
    }

    private func start() {
        guard timer == nil, window != nil, bounds.width >= 1 else { return }
        startedAt = Date()
        strokesPlayed = 0
        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // `.common` para que o risco não congele com um menu aberto por cima.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let startedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)

        // Um traço de giz por linha, no instante em que ela começa a ser riscada.
        while strokesPlayed < lines.count,
              elapsed >= TimeInterval(strokesPlayed) * Self.strokeDuration {
            StrikeSound.play(strokesPlayed)
            strokesPlayed += 1
        }

        needsDisplay = true
        guard elapsed >= totalDuration else { return }
        stop()
        onFinish()
    }

    // MARK: - Desenho

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0

        context.saveGState()
        // O texto, os riscos e o apagamento têm que ser uma coisa só: fora de uma
        // camada de transparência, apagar o texto não apagaria o traço junto.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        layout.draw(at: .zero)
        drawStrikes(at: elapsed)
        dissolve(context, at: elapsed)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawStrikes(at elapsed: TimeInterval) {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round

        for (index, line) in lines.enumerated() {
            let fraction = strokeFraction(of: index, at: elapsed)
            guard fraction > 0 else { continue }
            path.move(to: NSPoint(x: line.rect.minX, y: line.strikeY))
            path.line(to: NSPoint(x: line.rect.minX + line.rect.width * fraction, y: line.strikeY))
        }

        guard !path.isEmpty else { return }
        NSColor.labelColor.setStroke()
        path.stroke()
    }

    /// Quanto da linha `index` já foi riscado.
    ///
    /// A curva suave nas pontas é a mão: o traço começa devagar, corre e
    /// desacelera ao chegar no fim da linha.
    private func strokeFraction(of index: Int, at elapsed: TimeInterval) -> CGFloat {
        let start = TimeInterval(index) * Self.strokeDuration
        let progress = min(max((elapsed - start) / Self.strokeDuration, 0), 1)
        return CGFloat(progress * progress * (3 - 2 * progress))
    }

    /// Apaga o que já foi riscado, da esquerda para a direita, atrás de uma
    /// borda esfumaçada — o texto não some de uma vez, ele se desfaz.
    private func dissolve(_ context: CGContext, at elapsed: TimeInterval) {
        let start = TimeInterval(lines.count) * Self.strokeDuration
        let progress = min(max((elapsed - start) / Self.dissolveDuration, 0), 1)
        guard progress > 0 else { return }

        let colors = [
            NSColor.black.withAlphaComponent(0).cgColor,
            NSColor.black.cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        ) else { return }

        // `destinationIn` mantém o desenho onde o gradiente é opaco e o apaga
        // onde ele é transparente; a borda transparente é que atravessa o texto.
        let edge = CGFloat(progress) * (bounds.width + Self.feather)
        context.setBlendMode(.destinationIn)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: edge - Self.feather, y: 0),
            end: CGPoint(x: edge, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.setBlendMode(.normal)
    }
}
