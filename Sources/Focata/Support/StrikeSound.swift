import AppKit

/// O barulho do risco: giz de cera arrastado no papel, um traço por linha.
///
/// São três gravações do mesmo gesto, tocadas em rodízio — numa tarefa de várias
/// linhas, o mesmo arquivo três vezes soaria mecânico, e o gesto é justamente o
/// contrário disso. Os arquivos são sintetizados por
/// `scripts/gerar-som-do-risco.py`.
@MainActor
enum StrikeSound {
    /// Baixo de propósito: é um detalhe do gesto, não um aviso.
    private static let volume: Float = 0.35

    private static let sounds: [NSSound] = (1...3).compactMap { numero in
        guard let url = Bundle.main.url(forResource: "strike-\(numero)", withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: false)
        else { return nil }
        sound.volume = volume
        return sound
    }

    /// Toca o traço de número `index` (a enésima linha riscada).
    static func play(_ index: Int) {
        guard !sounds.isEmpty else { return }
        let sound = sounds[abs(index) % sounds.count]
        // Um `NSSound` não toca duas vezes ao mesmo tempo; parar antes garante
        // que um traço rápido recomece do início em vez de ser ignorado.
        sound.stop()
        sound.play()
    }
}
