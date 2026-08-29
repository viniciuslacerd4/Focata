import AppKit
import Observation
import SwiftUI

/// A caixa da tarefa: abre centralizada ao clicar no item da barra.
///
/// A barra de título é desenhada aqui, e não pelo sistema, porque é nela que
/// moram as três coisas que se quer de relance sem tirar as mãos do teclado: o
/// tempo do ciclo, quantos pomodoros a tarefa já custou e o mesmo menu do
/// clique direito na barra.
struct TaskPanelView: View {
    @Bindable var task: TaskStore
    let engine: PomodoroEngine
    let settings: AppSettings
    /// Abre o menu de três pontinhos ancorado no próprio botão que o chamou.
    var presentMenu: (NSView) -> Void
    /// Some com a caixa — a tarefa continua rodando na barra.
    var minimize: () -> Void
    /// Conclui a tarefa — ou a reabre, se já estiver concluída.
    var toggleCompletion: () -> Void
    /// Inicia, pausa ou retoma o ciclo.
    var toggleTimer: () -> Void
    let focus: EditorFocus
    /// A saída de cena da tarefa concluída, quando concluir limpa a barra.
    let completion: TaskCompletionAnimation

    static let width: CGFloat = 380

    var body: some View {
        VStack(spacing: 0) {
            // `TimelineView` em vez de um `Timer` nosso: o relógio do Pomodoro
            // vem de datas absolutas, então basta reler o motor a cada meio
            // segundo — e a SwiftUI para sozinha quando a caixa some da tela.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                titleBar(at: context.date)
            }

            Divider()

            HStack(alignment: .top, spacing: 0) {
                completeButton
                EditorView(
                    task: task,
                    onDismiss: minimize,
                    focusToken: focus.token,
                    completion: completion
                )
            }
        }
        .frame(width: Self.width)
        // A caixa flutua sobre o que você estava fazendo; o material deixa isso
        // aparecer por baixo, em vez de plantar um retângulo opaco na tela.
        .background(VisualEffectBackground(material: .hudWindow))
    }

    /// O check redondo ao lado do campo.
    ///
    /// Marcá-lo não apaga nada: a tarefa continua escrita, como continua na
    /// barra — riscada. Desmarcar desfaz por inteiro, tirando também a entrada
    /// que a conclusão criou no histórico.
    private var completeButton: some View {
        Button(action: toggleCompletion) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(task.isEmpty)
        .opacity(task.isEmpty ? 0.35 : 1)
        .help(task.isCompleted ? "Reabrir tarefa" : "Concluir tarefa")
        .padding(.top, 12)
        .padding(.leading, 12)
    }

    // MARK: - Barra de título

    private func titleBar(at now: Date) -> some View {
        HStack(spacing: 8) {
            if settings.pomodoroEnabled {
                // O botão diz o que o clique faz, e a cor diz em que modo você
                // está — claro no foco, verde no tempo livre, como o anel.
                TitleBarButton(
                    symbol: engine.isRunning ? "pause.fill" : "play.fill",
                    help: engine.isRunning
                        ? "Pausar \(engine.phase.isFree ? "tempo livre" : "foco")"
                        : (engine.isIdle ? "Iniciar foco" : "Retomar"),
                    tint: engine.phase.ringColor,
                    pointSize: 12,
                    action: { _ in toggleTimer() }
                )
                Text(remainingText(at: now))
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Focata")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text("\(task.pomodoroCount) 🍅")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("\(task.pomodoroCount) pomodoro(s) nesta tarefa")

            TitleBarButton(symbol: "minus", help: "Minimizar para a barra") { _ in minimize() }
            TitleBarButton(symbol: "ellipsis", help: "Mais ações", action: presentMenu)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { progressLine(at: now) }
    }

    /// O anel da barra é a leitura de relance; aqui, onde há espaço, o mesmo
    /// progresso vira uma linha fina sob a barra de título.
    @ViewBuilder
    private func progressLine(at now: Date) -> some View {
        if settings.pomodoroEnabled {
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color(nsColor: engine.phase.ringColor))
                    .opacity(0.85)
                    .frame(width: geometry.size.width * engine.progress(at: now))
            }
            .frame(height: 2)
        }
    }

    private func remainingText(at now: Date) -> String {
        let remaining = Int(engine.remaining(at: now).rounded(.up))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private var statusText: String {
        let modo = engine.phase.isFree ? "Tempo livre" : "Foco"
        if engine.isIdle { return "\(modo) parado" }
        return engine.isRunning ? modo : "\(modo) pausado"
    }
}

/// O cursor volta para o campo toda vez que a caixa reaparece.
///
/// A janela sobrevive ao minimizar — é a mesma `NSPanel`, apenas fora de tela —,
/// então quem avisa a SwiftUI de que houve uma nova abertura é este contador.
@MainActor
@Observable
final class EditorFocus {
    private(set) var token = 0

    func request() { token += 1 }
}

/// Botão da barra de título.
///
/// É `NSButton` e não `Button` da SwiftUI porque o menu dos três pontinhos é o
/// mesmo `NSMenu` do clique direito — e um `NSMenu` precisa de uma `NSView` de
/// carne e osso para se ancorar.
private struct TitleBarButton: NSViewRepresentable {
    let symbol: String
    let help: String
    var tint: NSColor = .secondaryLabelColor
    var pointSize: CGFloat = 11
    let action: (NSView) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .accessoryBar
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        configure(button)
        return button
    }

    /// O play vira pause no mesmo botão, então símbolo e cor precisam ser
    /// reaplicados a cada atualização — não só na criação.
    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
        configure(nsView)
    }

    private func configure(_ button: NSButton) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
        button.contentTintColor = tint
        button.toolTip = help
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: (NSView) -> Void

        init(action: @escaping (NSView) -> Void) {
            self.action = action
        }

        @objc func fire(_ sender: NSButton) {
            action(sender)
        }
    }
}

/// `NSHostingController` que conta a altura que o conteúdo gostaria de ter.
///
/// `fittingSize` só é confiável a cada passada de layout, e é aí que a caixa
/// descobre que ganhou ou perdeu uma linha de texto.
private final class ContentSizingHostingController<Content: View>: NSHostingController<Content> {
    var onContentHeight: ((CGFloat) -> Void)?

    override func viewDidLayout() {
        super.viewDidLayout()
        onContentHeight?(view.fittingSize.height)
    }
}

/// Dono da janela da caixa da tarefa.
///
/// É um `NSPanel` flutuante e não uma janela comum: o Focata é um app
/// `.accessory`, sem Dock e sem menu de app, e a caixa precisa poder ficar por
/// cima do que você está fazendo sem virar mais uma janela na sua pilha.
@MainActor
final class TaskPanelController: NSObject, NSWindowDelegate {
    private let task: TaskStore
    private let settings: AppSettings
    private let engine: PomodoroEngine
    private let actions: AppActions
    private let menu: FocataMenu
    private let defaults: UserDefaults

    /// Avisados quando a caixa aparece e some. É por aqui que o `TaskController`
    /// tira e compara o retrato da tarefa — trocar o texto com a caixa aberta é
    /// o que caracteriza começar uma tarefa nova.
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?

    private var panel: NSPanel?
    private let focus = EditorFocus()
    private let completion = TaskCompletionAnimation()
    /// Enquanto o menu está aberto a caixa perde o foco, e perder o foco
    /// normalmente a esconde. Sem esta trava, clicar nos três pontinhos fecharia
    /// a caixa por baixo do próprio menu.
    private var isPresentingMenu = false

    init(
        task: TaskStore,
        settings: AppSettings,
        engine: PomodoroEngine,
        actions: AppActions,
        menu: FocataMenu,
        defaults: UserDefaults = .standard
    ) {
        self.task = task
        self.settings = settings
        self.engine = engine
        self.actions = actions
        self.menu = menu
        self.defaults = defaults
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        let wasVisible = panel.isVisible

        // Ao reaparecer ela volta para onde você a deixou; só a primeira
        // abertura da vida do app cai no meio da tela. Já aberta, fica parada:
        // mexer na janela por baixo da mão de quem digita seria pior.
        if !wasVisible { restorePosition(of: panel) }

        // Um app `.accessory` nunca é frontmost: sem ativar, a caixa abre sem
        // teclado e o campo não recebe o cursor.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        focus.request()

        if !wasVisible { onShow?() }
    }

    /// Devolve a caixa ao meio da tela, e passa a ser essa a posição guardada.
    ///
    /// Sem isto não haveria como recentralizá-la a não ser no olho, depois de
    /// arrastada para um canto.
    func center() {
        show()
        panel?.center()
    }

    /// A caixa lembra onde você a deixou, inclusive entre lançamentos.
    ///
    /// Guardar só o canto superior esquerdo, e não o quadro inteiro: a janela
    /// cresce e encolhe com o texto da tarefa, e restaurar a altura antiga faria
    /// a caixa pular ao abrir.
    private func restorePosition(of panel: NSPanel) {
        guard let salvo = defaults.string(forKey: Key.topLeft) else {
            panel.center()
            return
        }

        panel.setFrameTopLeftPoint(NSPointFromString(salvo))
        // Monitor desconectado, resolução trocada: uma posição guardada que caiu
        // fora de todas as telas esconderia a caixa sem deixar rastro.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            panel.center()
        }
    }

    /// Minimizar aqui é sumir da tela e voltar para o item da barra — que é onde
    /// o Focata mora. Não há Dock para onde encolher.
    func hide() {
        guard let panel, panel.isVisible else { return }
        completion.cancel()
        panel.orderOut(nil)
        onHide?()
    }

    /// Com a caixa aberta, a tarefa concluída sai de cena antes de a caixa
    /// ficar em branco. Fechada, não há o que animar — quem conclui pelo atalho
    /// global sem olhar para a caixa não fica esperando por uma animação.
    func animateCompletion(of text: String) {
        guard isVisible else { return }
        completion.play(farewellTo: text)
    }

    /// Põe a janela na altura do conteúdo, ancorada pelo topo.
    ///
    /// A caixa cresce e encolhe pela borda de baixo — é pelo topo que você a
    /// posiciona, e mexer nele faria o texto pular sob o cursor a cada linha.
    private func fit(to height: CGFloat) {
        guard let panel, height > 0 else { return }
        let current = panel.contentRect(forFrameRect: panel.frame).height
        // Redimensionar dispara outra passada de layout: sem esta comparação as
        // duas ficariam se chamando.
        guard abs(current - height) > 0.5 else { return }

        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        // O AppKit acompanha a altura preferida do conteúdo pelo tamanho mínimo
        // da janela — que sobe com o texto e não desce. Era ele que segurava a
        // caixa grande depois que a tarefa saía.
        panel.contentMinSize = NSSize(width: TaskPanelView.width, height: height)
        panel.setContentSize(NSSize(width: TaskPanelView.width, height: height))
        panel.setFrameTopLeftPoint(topLeft)
    }

    private func toggleCompletion() {
        task.isCompleted ? actions.uncompleteTask() : actions.completeTask()
    }

    private func presentMenu(from view: NSView) {
        isPresentingMenu = true
        // Síncrono: só retorna quando o menu fecha.
        menu.popUp(from: view, at: NSPoint(x: 0, y: -4))
        isPresentingMenu = false

        // O menu pode ter aberto o Histórico ou as Configurações; nesse caso o
        // foco é delas. Só se ninguém mais o quis o teclado volta para a caixa.
        if panel?.isVisible == true, NSApp.keyWindow == nil {
            panel?.makeKey()
        }
    }

    private func makePanel() -> NSPanel {
        let view = TaskPanelView(
            task: task,
            engine: engine,
            settings: settings,
            presentMenu: { [weak self] view in self?.presentMenu(from: view) },
            minimize: { [weak self] in self?.hide() },
            toggleCompletion: { [weak self] in self?.toggleCompletion() },
            toggleTimer: { [weak self] in self?.actions.toggleTimer() },
            focus: focus,
            completion: completion
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: TaskPanelView.width, height: 120),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let hosting = ContentSizingHostingController(rootView: view)
        // Com `.fullSizeContentView` a faixa da barra de título do sistema entra
        // na safe area, e a SwiftUI empurraria a nossa barra 28pt para baixo —
        // uma sobra de espaço vazio no topo da caixa.
        hosting.safeAreaRegions = []
        hosting.onContentHeight = { [weak self] height in self?.fit(to: height) }
        panel.contentViewController = hosting
        // Medir agora, antes de posicionar: recém-criada a janela ainda tem o
        // tamanho do `contentRect` de mentira, e centralizar uma janela sem
        // largura a joga com a borda esquerda no meio da tela.
        panel.setContentSize(hosting.view.fittingSize)
        // A barra de título é a nossa; a do sistema fica só como área de arrasto.
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        // Sem fundo próprio: quem pinta a caixa é o material translúcido.
        panel.adoptTranslucentBackground()
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        self.panel = panel
        return panel
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard settings.hideEditorWhenDeactivated, !isPresentingMenu else { return }
        hide()
    }

    func windowWillClose(_ notification: Notification) {
        onHide?()
    }

    /// Arrastou, guardou. Vale também para o "Centralizar a caixa", que move a
    /// janela com ela já visível.
    func windowDidMove(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        defaults.set(
            NSStringFromPoint(NSPoint(x: panel.frame.minX, y: panel.frame.maxY)),
            forKey: Key.topLeft
        )
    }

    private enum Key {
        static let topLeft = "taskPanelTopLeft"
    }
}
