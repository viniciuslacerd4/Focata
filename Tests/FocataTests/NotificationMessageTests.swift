import Testing

@testable import Focata

@Suite("Texto das notificações de transição")
@MainActor
struct NotificationMessageTests {
    @Test("fim do foco anuncia o pomodoro somado à tarefa")
    func fimDoFoco() {
        let message = NotificationService.message(
            for: .init(from: .focus, to: .freeShort, earnedPomodoro: true),
            task: "Escrever spec"
        )
        #expect(message.title == "Pomodoro concluído")
        #expect(message.body == "Timer livre começou · +1 pomodoro em “Escrever spec”")
    }

    @Test("fim do tempo livre volta ao foco, sem somar nada")
    func fimDoLivre() {
        let message = NotificationService.message(
            for: .init(from: .freeShort, to: .focus, earnedPomodoro: false),
            task: "Escrever spec"
        )
        #expect(message.title == "Tempo livre acabou")
        #expect(message.body == "Foco começou")
    }

    @Test("sem tarefa definida, o aviso não inventa nome")
    func semTarefa() {
        let message = NotificationService.message(
            for: .init(from: .focus, to: .freeLong, earnedPomodoro: true),
            task: ""
        )
        #expect(message.body == "Timer livre começou")
    }

    @Test("pular o foco não anuncia pomodoro")
    func pular() {
        let message = NotificationService.message(
            for: .init(from: .focus, to: .freeShort, earnedPomodoro: false),
            task: "Escrever spec"
        )
        #expect(message.body == "Timer livre começou")
    }
}
