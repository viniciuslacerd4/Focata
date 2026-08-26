import AppKit

/// Monta o grafo de objetos do app e liga as portas de entrada da automação.
///
/// Tudo é criado aqui, num lugar só, em vez de cada objeto construir os seus:
/// assim o `PomodoroEngine` que o menu usa é o mesmo que o app Atalhos pilota.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var actions: AppActions?
    private var servicesProvider: ServicesProvider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings.shared
        let task = TaskStore.shared
        let history = HistoryStore.shared
        let engine = PomodoroEngine(durations: settings.durations)
        let notifications = NotificationService()
        let taskController = TaskController(
            task: task, history: history, settings: settings, engine: engine
        )
        let actions = AppActions(
            task: task,
            settings: settings,
            engine: engine,
            taskController: taskController,
            notifications: notifications
        )

        let statusItem = StatusItemController(
            task: task,
            settings: settings,
            engine: engine,
            taskController: taskController,
            actions: actions,
            notifications: notifications
        )
        actions.editorPresenter = statusItem

        self.actions = actions
        self.statusItem = statusItem

        // Os `AppIntent` são instanciados pelo sistema, sem chance de injeção.
        AppActions.shared = actions

        let servicesProvider = ServicesProvider(actions: actions)
        self.servicesProvider = servicesProvider
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()

        GlobalShortcuts.register(with: actions)

        // Fora da App Store, ninguém avisa que saiu versão nova — o app
        // pergunta sozinho, uma vez por dia, e só se você deixar.
        UpdateController.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let actions else { return }
        for url in urls {
            URLSchemeHandler.handle(url, actions: actions)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
