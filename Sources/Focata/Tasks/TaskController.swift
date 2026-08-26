import Foundation

/// Decide o que acontece quando uma tarefa termina — concluída ou abandonada —
/// e o que disso vai parar no histórico (§4 a §7 da spec).
///
/// Uma tarefa termina em três situações, e só nelas:
/// 1. você **conclui** (menu ou atalho);
/// 2. você **limpa** a barra (shift+clique ou menu);
/// 3. você **substitui** o texto — detectado ao fechar o editor, comparando com
///    o que havia quando ele abriu.
///
/// Editar o texto letra a letra não termina nada: seria impossível corrigir uma
/// digitação sem perder os pomodoros já ganhos.
@MainActor
final class TaskController {
    private let task: TaskStore
    private let history: HistoryStore
    private let settings: AppSettings
    private let engine: PomodoroEngine
    private let clock: Clock

    /// O que a tarefa era quando o editor abriu.
    ///
    /// Ele envelhece: com a caixa aberta dá para concluir, reabrir, limpar ou
    /// receber um texto de fora. Quem termina a tarefa por outro caminho é
    /// responsável por acertar o retrato aqui — senão o fechamento da caixa
    /// registra de novo uma tarefa que já foi para o histórico.
    private var editorSnapshot: Snapshot?

    private struct Snapshot {
        var text: String
        var pomodoros: Int
        var isCompleted: Bool
        var isPrivate: Bool
    }

    init(
        task: TaskStore,
        history: HistoryStore,
        settings: AppSettings,
        engine: PomodoroEngine,
        clock: Clock = .system
    ) {
        self.task = task
        self.history = history
        self.settings = settings
        self.engine = engine
        self.clock = clock
    }

    // MARK: - Conclusão

    /// Marcar como concluída não apaga a tarefa: ela continua ali, riscada, para
    /// você ter a sensação de fechamento antes de partir para a próxima.
    func complete() {
        guard !task.isEmpty, !task.isCompleted else { return }

        task.isCompleted = true
        record(text: task.text, pomodoros: task.pomodoroCount, outcome: .completed, isPrivate: task.isPrivate)

        // Sendo a última tarefa, você escolhe: manter o riscado à mostra ou
        // deixar a barra limpa.
        if settings.onLastTaskCompleted == .clearBar {
            task.clear(defaultToPrivate: settings.defaultToPrivate)
            // A tarefa já acabou e a barra já está limpa: não há mais nada a
            // registrar quando a caixa fechar.
            editorSnapshot = nil
        } else {
            editorSnapshot?.isCompleted = true
        }
        engine.reset()
    }

    /// Desmarcar é um desfazer, não um evento novo: a tarefa volta a valer e a
    /// entrada que a conclusão criou sai do histórico — ela não terminou, afinal.
    ///
    /// O Pomodoro não volta junto. `complete()` zerou o ciclo, e ressuscitar um
    /// cronômetro que já parou seria inventar tempo que ninguém trabalhou; os
    /// pomodoros já ganhos, esses continuam contados.
    func uncomplete() {
        guard !task.isEmpty, task.isCompleted else { return }
        task.isCompleted = false
        editorSnapshot?.isCompleted = false
        history.undoCompletion(of: task.text)
    }

    // MARK: - Limpeza e substituição

    func clear() {
        endCurrentTaskAsAbandonedIfNeeded()
        task.clear(defaultToPrivate: settings.defaultToPrivate)
        editorSnapshot = nil
        engine.reset()
    }

    func editorDidOpen() {
        editorSnapshot = Snapshot(
            text: task.text,
            pomodoros: task.pomodoroCount,
            isCompleted: task.isCompleted,
            isPrivate: task.isPrivate
        )
    }

    func editorDidClose() {
        defer { editorSnapshot = nil }
        guard let snapshot = editorSnapshot, snapshot.text != task.text else { return }

        // Texto trocado = tarefa nova. A anterior, se tinha trabalho investido e
        // não foi concluída, foi abandonada.
        if !snapshot.isCompleted {
            record(
                text: snapshot.text,
                pomodoros: snapshot.pomodoros,
                outcome: .abandoned,
                isPrivate: snapshot.isPrivate
            )
        }

        let novoTexto = task.text
        task.beginNewTask(novoTexto, isPrivate: settings.defaultToPrivate)
        engine.reset()
    }

    /// Define o texto de fora do editor (automação, Serviços, arrastar e soltar).
    func setText(_ newText: String) {
        guard newText != task.text else { return }
        endCurrentTaskAsAbandonedIfNeeded()
        task.beginNewTask(newText, isPrivate: settings.defaultToPrivate)
        editorSnapshot = nil
        engine.reset()
    }

    // MARK: - Modo privado

    func togglePrivate() {
        task.isPrivate.toggle()
    }

    // MARK: - Histórico

    private func endCurrentTaskAsAbandonedIfNeeded() {
        guard !task.isEmpty, !task.isCompleted else { return }
        record(text: task.text, pomodoros: task.pomodoroCount, outcome: .abandoned, isPrivate: task.isPrivate)
    }

    private func record(
        text: String,
        pomodoros: Int,
        outcome: HistoryEntry.Outcome,
        isPrivate: Bool
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Sessão privada não deixa rastro — nem concluída, nem abandonada.
        guard !isPrivate, settings.recordsHistory else { return }

        history.record(HistoryEntry(
            text: trimmed,
            pomodoros: pomodoros,
            finishedAt: clock.now(),
            outcome: outcome
        ))
    }
}
