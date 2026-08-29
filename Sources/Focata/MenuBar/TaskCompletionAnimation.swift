import Observation
import SwiftUI

/// A saída de cena da tarefa concluída, quando concluir é para limpar a barra.
///
/// Sem isto o texto sumia no mesmo quadro em que o check era marcado: a tarefa
/// desaparecia antes de você ver que ela tinha acabado. Aqui ela sai em dois
/// atos — o risco atravessando linha por linha até o texto se desfazer, e o
/// convite da próxima subindo no lugar.
///
/// O primeiro ato é desenhado e cronometrado pela `FarewellText`, que sabe onde
/// cada linha começa e termina; aqui fica a emenda entre os dois.
///
/// O estado da tarefa já mudou antes disto começar: o que a animação mostra é um
/// retrato do texto, e o campo de verdade fica escondido por baixo durante a
/// passagem. Assim, interrompida, ela não tem como levar nada junto — basta
/// mostrar o campo de volta.
@MainActor
@Observable
final class TaskCompletionAnimation {
    /// Os dois atos: primeiro a tarefa velha sai, depois o convite entra.
    enum Phase {
        case farewell
        case greeting
    }

    /// O retrato do texto concluído. `nil` quer dizer que não há animação.
    private(set) var text: String?
    private(set) var phase: Phase = .farewell
    /// O convite já subiu?
    private(set) var hasGreeted = false

    private var run: Task<Void, Never>?

    /// A tarefa velha ainda está na tela: é ela que aparece, não o campo.
    var isSayingFarewell: Bool { text != nil && phase == .farewell }

    /// De quanto o convite ainda tem que subir, e o quanto ainda está apagado.
    ///
    /// Fora da animação os dois valem o repouso, então terminar não mexe em nada
    /// do que a animação já deixou no lugar.
    var greetingOffset: CGFloat { isRising ? 12 : 0 }
    var greetingOpacity: Double { isRising ? 0 : 1 }
    private var isRising: Bool { text != nil && phase == .greeting && !hasGreeted }

    /// Um quadro de folga antes de o convite subir: uma view recém-inserida na
    /// tela não anima o estado com que nasce, e sem esta pausa ele já apareceria
    /// no lugar.
    private static let settle: TimeInterval = 0.03
    private static let greetingDuration: TimeInterval = 0.40

    /// Despede-se do texto dado. Uma despedida em andamento é substituída.
    func play(farewellTo farewell: String) {
        guard !farewell.isEmpty else { return }
        reset()
        text = farewell
    }

    /// A `FarewellText` avisa que o texto acabou de se desfazer.
    func farewellDidEnd() {
        guard text != nil, phase == .farewell else { return }
        phase = .greeting

        run = Task { [weak self] in
            guard let self, await self.pause(Self.settle) else { return }
            withAnimation(.easeOut(duration: Self.greetingDuration)) { self.hasGreeted = true }
            guard await self.pause(Self.greetingDuration) else { return }
            self.reset()
        }
    }

    /// Corta a animação e devolve o campo — é o que fazem digitar durante a
    /// despedida e fechar a caixa no meio dela.
    func cancel() {
        guard text != nil else { return }
        reset()
    }

    private func reset() {
        run?.cancel()
        run = nil
        text = nil
        phase = .farewell
        hasGreeted = false
    }

    /// `false` quando a animação foi cortada no meio da espera.
    private func pause(_ seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(for: .seconds(seconds))
            return true
        } catch {
            return false
        }
    }
}
