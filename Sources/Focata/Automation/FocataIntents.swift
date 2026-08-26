import AppIntents

/// Ações do Focata no app Atalhos.
///
/// Cada uma delega para `AppActions`, o mesmo caminho do menu e do URL scheme —
/// nenhuma lógica mora aqui.

struct SetTaskTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Definir tarefa"
    static let description = IntentDescription("Substitui a tarefa em foco na barra de menu.")

    @Parameter(title: "Texto")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        AppActions.shared?.setText(text)
        return .result()
    }
}

struct GetTaskTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Obter tarefa atual"
    static let description = IntentDescription("Devolve o texto da tarefa em foco.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: AppActions.shared?.currentText ?? "")
    }
}

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Iniciar foco"
    static let description = IntentDescription("Começa (ou retoma) o bloco de foco.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppActions.shared?.startTimer()
        return .result()
    }
}

struct PauseTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Pausar timer"
    static let description = IntentDescription("Pausa o ciclo em andamento.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppActions.shared?.pauseTimer()
        return .result()
    }
}

struct SkipPhaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Pular ciclo"
    static let description = IntentDescription("Vai para o próximo modo sem contar pomodoro.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppActions.shared?.skipPhase()
        return .result()
    }
}

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Concluir tarefa"
    static let description = IntentDescription("Marca a tarefa em foco como concluída.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppActions.shared?.completeTask()
        return .result()
    }
}

struct TogglePrivateModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Alternar modo privado"
    static let description = IntentDescription("Sessões privadas não entram no histórico.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        AppActions.shared?.togglePrivate()
        return .result(value: AppActions.shared?.isPrivate ?? false)
    }
}

struct FocataShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: ["Iniciar foco no \(.applicationName)"],
            shortTitle: "Iniciar foco",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: PauseTimerIntent(),
            phrases: ["Pausar o \(.applicationName)"],
            shortTitle: "Pausar timer",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: ["Concluir tarefa no \(.applicationName)"],
            shortTitle: "Concluir tarefa",
            systemImageName: "checkmark.circle"
        )
    }
}
