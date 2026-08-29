import AppKit

/// Dono do `NSStatusItem` do Focata: cria a célula na barra, mantém o desenho
/// em dia com o estado do app e trata os cliques.
@MainActor
final class StatusItemController: NSObject, EditorPresenting {
    /// O anel é redesenhado a 4 Hz enquanto há sessão ativa. Não é o relógio do
    /// Pomodoro — esse vem de `Date` —, é só a taxa de repintura.
    private static let redrawInterval: TimeInterval = 0.25

    private let statusItem: NSStatusItem
    private let task: TaskStore
    private let settings: AppSettings
    private let engine: PomodoroEngine
    private let taskController: TaskController
    private let actions: AppActions
    private let notifications: NotificationService
    private let clock: Clock
    private let dragView = StatusItemDragView()

    private var redrawTimer: Timer?

    /// O menu do clique direito — o mesmo que os três pontinhos da caixa abrem.
    private lazy var menu: FocataMenu = {
        let menu = FocataMenu(task: task, settings: settings, engine: engine, actions: actions)
        menu.onTimerAction = { [weak self] in self?.tick() }
        menu.onWindowAction = { [weak self] in self?.panel.hide() }
        menu.onCenterPanel = { [weak self] in self?.panel.center() }
        return menu
    }()

    /// A caixa da tarefa. Nasce na primeira abertura; daí em diante só some e
    /// volta, preservando onde você a deixou na tela.
    private lazy var panel: TaskPanelController = {
        let panel = TaskPanelController(
            task: task, settings: settings, engine: engine, actions: actions, menu: menu
        )
        panel.onShow = { [weak self] in
            self?.taskController.editorDidOpen()
            self?.refresh()
        }
        panel.onHide = { [weak self] in
            self?.taskController.editorDidClose()
            self?.refresh()
        }
        return panel
    }()

    init(
        task: TaskStore,
        settings: AppSettings,
        engine: PomodoroEngine,
        taskController: TaskController,
        actions: AppActions,
        notifications: NotificationService,
        clock: Clock = .system
    ) {
        self.task = task
        self.settings = settings
        self.engine = engine
        self.taskController = taskController
        self.actions = actions
        self.notifications = notifications
        self.clock = clock
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // Arrastar um item do Lembretes ou do Things sobre o ícone define o texto.
            dragView.onDrop = { [weak self] text in self?.actions.setText(text) }
            button.addSubview(dragView)
        }

        engine.onTransition = { [weak self] transition in
            self?.handleTransition(transition)
        }

        // Ao acordar, o progresso precisa refletir o tempo real que passou —
        // não o que o timer de repintura deixou de contar enquanto dormia.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        observeAndRefresh()
        syncRedrawTimer()
    }

    // MARK: - Renderização

    /// Redesenha a partir do estado atual e se re-inscreve para a próxima mudança.
    ///
    /// `withObservationTracking` registra exatamente as propriedades que
    /// `refresh()` leu, então qualquer alteração em `TaskStore`, `AppSettings`
    /// ou `PomodoroEngine` que afete a barra dispara um novo desenho — sem lista
    /// manual de observers.
    private func observeAndRefresh() {
        withObservationTracking {
            refresh()
        } onChange: {
            Task { @MainActor [weak self] in
                self?.observeAndRefresh()
                self?.syncRedrawTimer()
            }
        }
    }

    private func refresh() {
        let now = clock.now()
        // Durações vivem nas configurações; o motor precisa segui-las. A guarda
        // de igualdade evita notificar observadores a cada repintura.
        if engine.durations != settings.durations {
            engine.durations = settings.durations
        }

        statusItem.button?.image = MenuBarItemRenderer.image(for: .init(
            text: task.isEmpty ? placeholderText() : renderedTaskText(),
            maximumTextWidth: settings.maximumWidth,
            ring: ringContent(at: now),
            isPrivate: task.isPrivate && !task.isEmpty
        ))
        statusItem.button?.toolTip = tooltip(at: now)
        // O item muda de largura conforme o texto; o alvo de arraste acompanha
        // por frame — Auto Layout dentro do botão da barra é problemático.
        if let button = statusItem.button {
            dragView.frame = button.bounds
        }
        // Enquanto a caixa está aberta o item precisa continuar visível: é a
        // ela que se volta ao minimizar.
        statusItem.isVisible = !(settings.hideMenuBarItemWhenEmpty && task.isEmpty && !panel.isVisible)
    }

    private func ringContent(at now: Date) -> MenuBarItemRenderer.Content.Ring? {
        guard settings.pomodoroEnabled else { return nil }
        let showsCheckmark = engine.showsCheckmark(at: now)
        return .init(
            progress: engine.progress(at: now),
            color: showsCheckmark
                ? (engine.checkmarkPhase ?? engine.phase).ringColor
                : engine.phase.ringColor,
            showsCheckmark: showsCheckmark,
            isPaused: engine.isPaused
        )
    }

    /// Para quem quiser o número, sob demanda (§1 da spec).
    private func tooltip(at now: Date) -> String? {
        guard settings.pomodoroEnabled else { return nil }

        let modo = engine.phase.isFree ? "Tempo livre" : "Foco"
        guard !engine.isIdle else {
            return "\(modo) parado. Clique no anel para iniciar."
        }

        let remaining = Int(engine.remaining(at: now).rounded(.up))
        let tempo = String(format: "%d:%02d", remaining / 60, remaining % 60)
        let estado = engine.isRunning ? "restam" : "pausado em"
        return "\(modo), \(estado) \(tempo) · \(task.pomodoroCount) pomodoro(s) nesta tarefa"
    }

    private func renderedTaskText() -> NSAttributedString {
        MarkdownRenderer.render(
            settings.prefixText + task.text + settings.suffixText,
            style: .init(
                baseSize: settings.textSize,
                isBold: settings.textIsBold,
                width: settings.textWidth,
                color: settings.textColor.nsColor,
                isStruckThrough: task.isCompleted,
                maximumWidth: settings.maximumWidth
            )
        )
    }

    /// Com o Pomodoro ligado o anel já dá o que clicar. Sem ele, uma tarefa
    /// vazia deixaria uma célula invisível — daí o texto esmaecido.
    private func placeholderText() -> NSAttributedString {
        guard !settings.pomodoroEnabled else { return NSAttributedString() }
        return NSAttributedString(
            string: "Focata",
            attributes: [
                .font: NSFont.menuBarFont(ofSize: settings.textSize),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.4),
            ]
        )
    }

    // MARK: - Relógio

    /// O timer só existe enquanto há o que animar: sessão rodando ou check na tela.
    private func syncRedrawTimer() {
        let needsTimer = settings.pomodoroEnabled
            && (engine.isRunning || engine.checkmarkUntil != nil)

        if needsTimer, redrawTimer == nil {
            let timer = Timer(timeInterval: Self.redrawInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = Self.redrawInterval / 2
            RunLoop.main.add(timer, forMode: .common)
            redrawTimer = timer
        } else if !needsTimer {
            redrawTimer?.invalidate()
            redrawTimer = nil
        }
    }

    private func tick() {
        engine.advance(to: clock.now())
        refresh()
        syncRedrawTimer()
    }

    private func handleTransition(_ transition: PomodoroEngine.Transition) {
        if transition.earnedPomodoro {
            task.pomodoroCount += 1
        }
        if settings.transitionNotifications {
            notifications.notifyTransition(
                transition,
                task: task.text,
                withSound: settings.transitionSound
            )
        }
    }

    // MARK: - Interação

    @objc private func handleClick() {
        // Sem evento associado (acionamento por acessibilidade ou automação),
        // o comportamento certo é o padrão: abrir o editor.
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            showContextMenu()
        } else if event?.modifierFlags.contains(.shift) == true {
            actions.clearTask()
        } else if let event, isRingClick(event) {
            // "Clica no anel para iniciar o foco" (§10).
            actions.toggleTimer()
            tick()
        } else {
            toggleEditor()
        }
    }

    /// O clique caiu sobre o anel?
    ///
    /// Com a tarefa vazia o anel ocupa o item inteiro — aí o clique tem de abrir
    /// o editor, senão não haveria como digitar a primeira tarefa.
    private func isRingClick(_ event: NSEvent) -> Bool {
        guard settings.pomodoroEnabled,
              !task.isEmpty,
              let button = statusItem.button,
              let image = button.image
        else { return false }

        let point = button.convert(event.locationInWindow, from: nil)
        // A imagem é desenhada centralizada no botão (`imagePosition == .imageOnly`).
        let imageOriginX = ((button.bounds.width - image.size.width) / 2).rounded()
        let ring = NSRect(
            x: imageOriginX + MenuBarItemRenderer.horizontalPadding,
            y: 0,
            width: RingRenderer.diameter,
            height: button.bounds.height
        )
        return ring.contains(point)
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        menu.popUp(from: button, at: NSPoint(x: 0, y: button.bounds.height + 4))
    }

    private func toggleEditor() {
        panel.toggle()
    }

    /// Abrir a caixa também é uma ação de automação (atalho global, URL).
    func presentEditor() {
        panel.show()
    }

    func animateCompletion(of text: String) {
        panel.animateCompletion(of: text)
    }
}
