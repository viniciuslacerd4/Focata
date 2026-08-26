import AppKit

/// O indicador visual do Pomodoro: um anel que se preenche em sentido horário,
/// como o progresso de um download (§1 da spec).
///
/// Nada de cronômetro digital — o objetivo é ser glanceável: você entende o
/// progresso num olhar, sem ler número nenhum.
enum RingRenderer {
    static let diameter: CGFloat = 13
    private static let lineWidth: CGFloat = 1.8

    /// Desenha o anel dentro de `rect`, centralizado.
    /// - Parameters:
    ///   - progress: 0 a 1.
    ///   - color: a cor do modo — clara para foco, verde para tempo livre.
    static func draw(in rect: NSRect, progress: Double, color: NSColor) {
        let box = centeredBox(in: rect)
        let center = NSPoint(x: box.midX, y: box.midY)
        let radius = (diameter - lineWidth) / 2

        // Trilha: mostra o círculo inteiro que falta fechar.
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        color.withAlphaComponent(0.25).setStroke()
        track.stroke()

        guard progress > 0 else { return }

        // Começa no topo (90°) e fecha no sentido horário.
        let start: CGFloat = 90
        let end = start - CGFloat(min(1, progress)) * 360
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    /// As duas barrinhas de pausa, dentro do anel.
    ///
    /// Só aparecem com a sessão pausada. Parada, o anel vazio já diz que não
    /// começou — o `||` é para distinguir "parei no meio" de "está correndo",
    /// que de longe se parecem quando o arco quase não anda.
    static func drawPauseGlyph(in rect: NSRect, color: NSColor) {
        let box = centeredBox(in: rect)
        let barWidth: CGFloat = 1.6
        let barHeight: CGFloat = 5
        let gap: CGFloat = 1.8
        let y = (box.midY - barHeight / 2).rounded()
        let firstX = box.midX - (barWidth * 2 + gap) / 2

        color.setFill()
        for index in 0..<2 {
            let bar = NSRect(
                x: firstX + CGFloat(index) * (barWidth + gap),
                y: y,
                width: barWidth,
                height: barHeight
            )
            NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }

    /// O check breve que marca o ciclo concluído antes da troca de modo.
    static func drawCheckmark(in rect: NSRect, color: NSColor) {
        let box = centeredBox(in: rect)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: box.minX + box.width * 0.18, y: box.minY + box.height * 0.52))
        path.line(to: NSPoint(x: box.minX + box.width * 0.42, y: box.minY + box.height * 0.28))
        path.line(to: NSPoint(x: box.minX + box.width * 0.84, y: box.minY + box.height * 0.74))
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// O cadeado do modo privado, ao lado do anel (§7).
    static func drawPrivacyLock(in rect: NSRect, color: NSColor) {
        guard let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Sessão privada") else {
            return
        }
        let size = NSSize(width: 8, height: 9)
        let box = NSRect(
            x: rect.midX - size.width / 2,
            y: (rect.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
        lock.isTemplate = true
        let tinted = NSImage(size: box.size, flipped: false) { bounds in
            color.set()
            lock.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: box)
    }

    private static func centeredBox(in rect: NSRect) -> NSRect {
        NSRect(
            x: rect.midX - diameter / 2,
            y: (rect.midY - diameter / 2).rounded(),
            width: diameter,
            height: diameter
        )
    }
}
