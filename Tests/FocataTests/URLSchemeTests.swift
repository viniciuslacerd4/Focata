import Foundation
import Testing

@testable import Focata

@MainActor
private func handle(_ string: String, _ actions: AppActions) {
    URLSchemeHandler.handle(URL(string: string)!, actions: actions)
}

@Suite("URL scheme")
@MainActor
struct URLSchemeTests {
    @Test("focata:?text= define a tarefa, no formato do One Thing")
    func definirTexto() {
        let f = TestFixture()

        handle("focata:?text=Exercitar", f.actions)
        #expect(f.task.text == "Exercitar")
    }

    @Test("texto com espaços e acentos chega inteiro")
    func textoComEscape() {
        let f = TestFixture()

        handle("focata:?text=Revisar%20a%20especifica%C3%A7%C3%A3o", f.actions)
        #expect(f.task.text == "Revisar a especificação")
    }

    @Test("start, pause e skip pilotam o timer")
    func controlarTimer() {
        let f = TestFixture()

        handle("focata://start", f.actions)
        #expect(f.engine.isRunning)
        #expect(f.engine.phase == .focus)

        handle("focata://pause", f.actions)
        #expect(!f.engine.isRunning)

        handle("focata://skip", f.actions)
        #expect(f.engine.phase == .freeShort)
        #expect(f.engine.completedFocusCount == 0, "pular não conta pomodoro")
    }

    @Test("private aceita on=1, on=0 e alternância")
    func modoPrivado() {
        let f = TestFixture()

        handle("focata://private?on=1", f.actions)
        #expect(f.task.isPrivate)

        handle("focata://private?on=0", f.actions)
        #expect(!f.task.isPrivate)

        handle("focata://private", f.actions)
        #expect(f.task.isPrivate, "sem parâmetro, alterna")
    }

    @Test("complete risca a tarefa; clear esvazia a barra")
    func concluirELimpar() {
        let f = TestFixture()

        f.settings.onLastTaskCompleted = .keepStruckThrough
        handle("focata:?text=Escrever%20spec", f.actions)
        handle("focata://complete", f.actions)
        #expect(f.task.isCompleted)
        #expect(f.task.text == "Escrever spec")

        handle("focata://clear", f.actions)
        #expect(f.task.isEmpty)
    }

    @Test("ação desconhecida não muda nada nem quebra")
    func acaoDesconhecida() {
        let f = TestFixture()

        handle("focata:?text=Escrever%20spec", f.actions)
        handle("focata://voar", f.actions)

        #expect(f.task.text == "Escrever spec")
        #expect(f.engine.isIdle)
    }
}
