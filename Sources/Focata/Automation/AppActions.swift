import Foundation

/// Tudo que o Focata sabe fazer, num lugar só.
///
/// O menu de contexto, o esquema de URL, o app Atalhos, o menu Serviços e as
/// teclas de atalho global entram todos por aqui — assim "pular ciclo" faz
/// exatamente a mesma coisa venha de onde vier.
@MainActor
final class AppActions {
    /// Ponto de acesso para os `AppIntent`, que são instanciados pelo sistema e
    /// não têm como receber dependências por injeção.
    static var shared: AppActions?

    private let task: TaskStore
    private let settings: AppSettings
    private let engine: PomodoroEngine
    private let taskController: TaskController
    private let notifications: NotificationService

    /// Quem sabe abrir o editor — na prática, o controlador da barra.
    weak var editorPresenter: EditorPresenting?

    init(
        task: TaskStore,
        settings: AppSettings,
        engine: PomodoroEngine,
        taskController: TaskController,
        notifications: NotificationService
    ) {
        self.task = task
        self.settings = settings
        self.engine = engine
        self.taskController = taskController
        self.notifications = notifications
    }

    // MARK: - Tarefa

    var currentText: String { task.text }
    var isPrivate: Bool { task.isPrivate }
    var pomodoroCount: Int { task.pomodoroCount }

    func setText(_ text: String) {
        taskController.setText(text)
    }

    func completeTask() {
        taskController.complete()
    }

    func uncompleteTask() {
        taskController.uncomplete()
    }

    func clearTask() {
        taskController.clear()
    }

    func togglePrivate() {
        taskController.togglePrivate()
    }

    func setPrivate(_ isPrivate: Bool) {
        task.isPrivate = isPrivate
    }

    func openEditor() {
        editorPresenter?.presentEditor()
    }

    // MARK: - Pomodoro

    func startTimer() {
        notifications.requestAuthorizationIfNeeded()
        engine.start()
    }

    func pauseTimer() {
        engine.pause()
    }

    func toggleTimer() {
        notifications.requestAuthorizationIfNeeded()
        engine.toggle()
    }

    func skipPhase() {
        engine.skip()
    }

    func resetTimer() {
        engine.reset()
    }
}

/// O que o controlador da barra precisa expor para as automações.
@MainActor
protocol EditorPresenting: AnyObject {
    func presentEditor()
}
