import Foundation
import Testing

@testable import Focata

@Suite("HistoryStore")
@MainActor
struct HistoryStoreTests {
    @Test("grava, relê do disco e apaga entradas")
    func persistencia() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("focata-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = HistoryStore(fileURL: fileURL)
        let a = HistoryEntry(text: "Escrever spec", pomodoros: 3, finishedAt: .now, outcome: .completed)
        let b = HistoryEntry(text: "Refatorar", pomodoros: 1, finishedAt: .now, outcome: .abandoned)
        store.record(a)
        store.record(b)

        // Mais recente primeiro.
        #expect(store.entries.map(\.text) == ["Refatorar", "Escrever spec"])

        let recarregado = HistoryStore(fileURL: fileURL)
        #expect(recarregado.entries.count == 2)
        #expect(recarregado.entries[0].outcome == .abandoned)
        #expect(recarregado.entries[1].pomodoros == 3)

        store.delete(a)
        #expect(store.entries.map(\.text) == ["Refatorar"])
        #expect(HistoryStore(fileURL: fileURL).entries.count == 1)

        store.deleteAll()
        #expect(HistoryStore(fileURL: fileURL).entries.isEmpty)
    }

    @Test("desfazer uma conclusão apaga a entrada mais recente daquele texto")
    func desfazerConclusao() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("focata-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = HistoryStore(fileURL: fileURL)
        store.record(HistoryEntry(text: "Escrever spec", pomodoros: 1, finishedAt: .now, outcome: .completed))
        store.record(HistoryEntry(text: "Escrever spec", pomodoros: 4, finishedAt: .now, outcome: .completed))
        store.record(HistoryEntry(text: "Refatorar", pomodoros: 2, finishedAt: .now, outcome: .abandoned))

        store.undoCompletion(of: "  Escrever spec  ")

        #expect(store.entries.map(\.pomodoros) == [2, 1], "some a conclusão mais recente, e só ela")

        store.undoCompletion(of: "Refatorar")
        #expect(store.entries.count == 2, "abandonada não é conclusão para desfazer")
    }
}

@Suite("TaskController")
@MainActor
struct TaskControllerTests {
    @Test("concluir registra com os pomodoros e limpa a barra")
    func concluir() {
        let f = TestFixture()

        f.task.beginNewTask("Escrever spec", isPrivate: false)
        f.task.pomodoroCount = 3
        f.taskController.complete()

        #expect(f.task.isEmpty, "a barra fica pronta para a próxima tarefa")
        #expect(f.history.entries.count == 1)
        #expect(f.history.entries[0].text == "Escrever spec")
        #expect(f.history.entries[0].outcome == .completed)
        #expect(f.history.entries[0].pomodoros == 3)
    }

    @Test("concluir com a caixa aberta e digitar por cima não vira abandono")
    func concluirComACaixaAberta() {
        let f = TestFixture()

        f.task.beginNewTask("Escrever spec", isPrivate: false)
        f.taskController.editorDidOpen()
        f.taskController.complete()
        // O check fica ao lado do campo: concluir e já escrever a próxima é o
        // caminho normal, não um caso de canto.
        f.task.text = "Outra coisa"
        f.taskController.editorDidClose()

        #expect(f.history.entries.map(\.outcome) == [.completed], "entrou no histórico uma vez só")
        #expect(f.task.text == "Outra coisa")
        #expect(f.task.pomodoroCount == 0, "tarefa nova começa do zero")
    }

    @Test("desmarcar reabre a tarefa e devolve os pomodoros")
    func reabrir() {
        let f = TestFixture()

        f.settings.onLastTaskCompleted = .keepStruckThrough
        f.task.beginNewTask("Escrever spec", isPrivate: false)
        f.task.pomodoroCount = 3
        f.taskController.complete()
        f.taskController.uncomplete()

        #expect(!f.task.isCompleted)
        #expect(f.task.text == "Escrever spec")
        #expect(f.task.pomodoroCount == 3, "os pomodoros ganhos continuam contados")
        // Reabrir só existe no modo riscado, onde o histórico está parado —
        // não há registro para desfazer, nem para deixar para trás.
        #expect(f.history.entries.isEmpty)
    }

    @Test("com “manter o texto riscado” nada entra no histórico")
    func riscadoNaoRegistra() {
        let f = TestFixture()

        f.settings.onLastTaskCompleted = .keepStruckThrough
        f.task.beginNewTask("Escrever spec", isPrivate: false)
        f.task.pomodoroCount = 2
        f.taskController.complete()

        #expect(f.task.isCompleted, "o risco na barra continua")
        #expect(f.history.entries.isEmpty, "concluída não é registrada")

        f.taskController.setText("Refatorar o parser")
        f.taskController.clear()

        #expect(f.history.entries.isEmpty, "abandonada tampouco")
    }

    @Test("limpar uma tarefa inacabada registra como abandonada")
    func abandonar() {
        let f = TestFixture()

        f.task.beginNewTask("Refatorar o parser", isPrivate: false)
        f.task.pomodoroCount = 2
        f.taskController.clear()

        #expect(f.task.isEmpty)
        #expect(f.history.entries.count == 1)
        #expect(f.history.entries[0].outcome == .abandoned)
        #expect(f.history.entries[0].pomodoros == 2)
    }

    @Test("limpar uma tarefa já concluída não gera entrada duplicada")
    func naoDuplicaConcluida() {
        let f = TestFixture()

        f.task.beginNewTask("Escrever spec", isPrivate: false)
        f.taskController.complete()
        f.taskController.clear()

        #expect(f.history.entries.count == 1)
        #expect(f.history.entries[0].outcome == .completed)
    }

    @Test("sessão privada não deixa rastro, nem concluída nem abandonada")
    func modoPrivado() {
        let f = TestFixture()

        f.task.beginNewTask("Assunto pessoal", isPrivate: true)
        f.task.pomodoroCount = 4
        f.taskController.complete()
        #expect(f.history.entries.isEmpty)

        f.task.beginNewTask("Outro assunto pessoal", isPrivate: true)
        f.taskController.clear()
        #expect(f.history.entries.isEmpty)
    }

    @Test("desligar “guardar histórico” impede qualquer registro")
    func trackHistoryDesligado() {
        let f = TestFixture()

        f.settings.trackHistory = false
        f.settings.onLastTaskCompleted = .keepStruckThrough
        f.task.beginNewTask("Escrever spec", isPrivate: false)
        f.taskController.complete()

        #expect(f.history.entries.isEmpty)
        #expect(f.task.isCompleted, "o risco na barra continua funcionando")
    }

    @Test("editar o texto no editor não zera os pomodoros")
    func edicaoPreservaContagem() {
        let f = TestFixture()

        f.task.beginNewTask("Escrever spec", isPrivate: false)
        f.task.pomodoroCount = 2

        f.taskController.editorDidOpen()
        f.task.text = "Escrever spec"  // reabriu e fechou sem mudar nada
        f.taskController.editorDidClose()

        #expect(f.task.pomodoroCount == 2)
    }

    @Test("trocar o texto pelo editor abandona a anterior e começa do zero")
    func substituirPeloEditor() {
        let f = TestFixture()

        f.task.beginNewTask("Escrever spec", isPrivate: false)
        f.task.pomodoroCount = 2

        f.taskController.editorDidOpen()
        f.task.text = "Revisar PR"
        f.taskController.editorDidClose()

        #expect(f.history.entries.count == 1)
        #expect(f.history.entries[0].text == "Escrever spec")
        #expect(f.history.entries[0].outcome == .abandoned)
        #expect(f.history.entries[0].pomodoros == 2)
        #expect(f.task.text == "Revisar PR")
        #expect(f.task.pomodoroCount == 0, "tarefa nova começa do zero")
    }

    @Test("trocar o texto de fora do editor também abandona a anterior")
    func substituirPorAutomacao() {
        let f = TestFixture()

        f.task.beginNewTask("Escrever spec", isPrivate: false)
        f.task.pomodoroCount = 1
        f.taskController.setText("Responder e-mail da Sara")

        #expect(f.history.entries.count == 1)
        #expect(f.history.entries[0].outcome == .abandoned)
        #expect(f.task.text == "Responder e-mail da Sara")
    }

    @Test("com “iniciar em privado”, a tarefa nova já nasce privada")
    func privadoPorPadrao() {
        let f = TestFixture()

        f.settings.defaultToPrivate = true
        f.taskController.setText("Assunto pessoal")

        #expect(f.task.isPrivate)
    }

    @Test("concluir zera o Pomodoro em andamento")
    func concluirZeraPomodoro() {
        let f = TestFixture()

        f.task.beginNewTask("Escrever spec", isPrivate: false)
        f.engine.start()
        #expect(f.engine.isRunning)

        f.taskController.complete()
        #expect(f.engine.isIdle)
    }
}
