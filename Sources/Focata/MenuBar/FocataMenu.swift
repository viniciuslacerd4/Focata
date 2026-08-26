import AppKit

/// O menu de ações do Focata, num lugar só.
///
/// Ele nasce do clique direito no item da barra e reaparece nos três pontinhos
/// da caixa da tarefa. Construir o `NSMenu` aqui — em vez de montar uma lista em
/// cada lugar — é o que garante que os dois sejam literalmente o mesmo menu, e
/// não duas listas que um dia divergem.
@MainActor
final class FocataMenu: NSObject {
    private let task: TaskStore
    private let settings: AppSettings
    private let engine: PomodoroEngine
    private let actions: AppActions
    private let updates: UpdateController

    /// Avisado depois das ações que mexem no timer: quem desenha precisa
    /// repintar na hora, sem esperar o próximo tick.
    var onTimerAction: (() -> Void)?

    /// Traz a caixa da tarefa de volta ao meio da tela.
    var onCenterPanel: (() -> Void)?

    /// Avisado antes de abrir Histórico ou Configurações. A caixa da tarefa
    /// flutua acima de tudo, inclusive das janelas do próprio Focata — então ela
    /// sai da frente em vez de cobrir o que você acabou de mandar abrir.
    var onWindowAction: (() -> Void)?

    init(
        task: TaskStore,
        settings: AppSettings,
        engine: PomodoroEngine,
        actions: AppActions,
        updates: UpdateController = .shared
    ) {
        self.task = task
        self.settings = settings
        self.engine = engine
        self.actions = actions
        self.updates = updates
        super.init()
    }

    /// Abre o menu ancorado numa view. `point` fica no espaço de coordenadas
    /// dela — o item da barra quer o menu logo abaixo da barra de menus, a caixa
    /// da tarefa quer logo abaixo do botão.
    func popUp(from view: NSView, at point: NSPoint) {
        build().popUp(positioning: nil, at: point, in: view)
    }

    func build() -> NSMenu {
        let menu = NSMenu()

        if settings.pomodoroEnabled {
            let toggleTitle = engine.isRunning
                ? "Pausar \(engine.phase.isFree ? "tempo livre" : "foco")"
                : (engine.isIdle ? "Iniciar foco" : "Retomar")
            add(toggleTitle, symbol: engine.isRunning ? "pause.fill" : "play.fill",
                action: #selector(togglePomodoro), to: menu)
            add("Pular ciclo", symbol: "forward.end.fill", action: #selector(skipPhase), to: menu)
            add("Zerar Pomodoro", symbol: "arrow.counterclockwise",
                action: #selector(resetPomodoro), to: menu)
            menu.addItem(.separator())
        }

        if !task.isEmpty {
            // Concluída por engano? O mesmo lugar que fecha a tarefa a reabre.
            if task.isCompleted {
                add("Reabrir tarefa", symbol: "arrow.uturn.backward",
                    action: #selector(uncompleteTask), to: menu)
            } else {
                add("Concluir tarefa", symbol: "checkmark.circle",
                    action: #selector(completeTask), to: menu)
            }
        }
        add("Limpar tarefa", symbol: "xmark.circle", action: #selector(clearTask), to: menu)

        // O cadeado é o mesmo símbolo que a barra mostra em sessão privada.
        let privateItem = add("Modo privado", symbol: "lock", action: #selector(togglePrivate), to: menu)
        privateItem.state = task.isPrivate ? .on : .off
        privateItem.toolTip = "Sessões privadas não entram no histórico."

        menu.addItem(.separator())
        add("Centralizar a caixa", symbol: "rectangle.center.inset.filled",
            action: #selector(centerPanel), to: menu)
        add("Histórico…", symbol: "clock", action: #selector(openHistory), to: menu)
        // Quando já se sabe que há versão nova, o item deixa de ser um convite
        // a verificar e passa a dizer o que vai acontecer.
        if case .available(let release) = updates.checker.state {
            add("Baixar o Focata \(release.version)…", symbol: "arrow.down.circle.fill",
                action: #selector(downloadUpdate), to: menu)
        } else {
            add("Buscar atualizações…", symbol: "arrow.down.circle",
                action: #selector(checkForUpdates), to: menu)
        }
        add("Configurações…", symbol: "gearshape", action: #selector(openSettings),
            keyEquivalent: ",", to: menu)
        menu.addItem(.separator())
        add("Sair do Focata", symbol: "power", action: #selector(quit), keyEquivalent: "q", to: menu)

        return menu
    }

    /// Cada item leva um símbolo à esquerda — a coluna de ícones é o que deixa o
    /// menu legível de relance, sem obrigar a ler as nove linhas.
    @discardableResult
    private func add(
        _ title: String,
        symbol: String,
        action: Selector,
        keyEquivalent: String = "",
        to menu: NSMenu
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func togglePomodoro() {
        actions.toggleTimer()
        onTimerAction?()
    }

    @objc private func skipPhase() {
        actions.skipPhase()
        onTimerAction?()
    }

    @objc private func resetPomodoro() {
        actions.resetTimer()
        onTimerAction?()
    }

    @objc private func completeTask() { actions.completeTask() }
    @objc private func uncompleteTask() { actions.uncompleteTask() }
    @objc private func clearTask() { actions.clearTask() }
    @objc private func togglePrivate() { actions.togglePrivate() }
    @objc private func centerPanel() { onCenterPanel?() }

    @objc private func openHistory() {
        onWindowAction?()
        HistoryWindowController.shared.show()
    }

    @objc private func checkForUpdates() {
        updates.checkNow()
    }

    @objc private func downloadUpdate() {
        guard case .available(let release) = updates.checker.state else { return }
        updates.download(release)
    }

    @objc private func openSettings() {
        onWindowAction?()
        SettingsWindowController.shared.show()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
