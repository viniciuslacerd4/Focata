import AppKit

/// A verificação de atualizações na tela: o alerta, o botão de baixar e o
/// relógio que faz a varredura diária acontecer.
///
/// Singleton como as outras janelas do app (`SettingsWindowController`,
/// `HistoryWindowController`): o menu da barra, a caixa da tarefa e as
/// Configurações precisam falar com a mesma verificação, e nenhum deles nasce
/// no mesmo lugar.
@MainActor
final class UpdateController {
    static let shared = UpdateController()

    /// De quanto em quanto tempo o app *olha* se já é hora de verificar. A
    /// verificação em si continua sendo diária — esta varredura curta é o que
    /// faz um Mac que fica dias ligado, sem nunca relançar o app, chegar lá.
    private static let sweepInterval: TimeInterval = 60 * 60

    /// A régua do launch. Ligar o Mac é o momento em que o aviso cabe — a
    /// pessoa ainda não começou nada —, então a verificação de abertura não
    /// espera o dia inteiro. A folga de uma hora existe só para quem sai e
    /// volta do app não consultar o GitHub a cada relançamento.
    private static let launchInterval: TimeInterval = 60 * 60

    /// Quanto esperar entre as tentativas da verificação de abertura.
    ///
    /// Logo depois do login a rede quase nunca está de pé: uma falha aqui não é
    /// resposta, é cedo demais. Sem estas tentativas, o aviso só apareceria na
    /// varredura da hora seguinte — bem depois do momento em que ele cabia.
    private static let launchRetries: [TimeInterval] = [15, 60, 300]

    let checker: UpdateChecker

    private var sweepTimer: Timer?
    /// Um alerta por vez: a varredura não pode empilhar janelas em cima de
    /// quem já está decidindo o que fazer com a versão nova.
    private var isPresenting = false

    init(checker: UpdateChecker = .shared) {
        self.checker = checker
    }

    /// Liga o ciclo automático. Chamado uma vez, no launch.
    func start() {
        sweepTimer?.invalidate()

        let timer = Timer(timeInterval: Self.sweepInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkInBackground() }
        }
        // O aviso não tem hora marcada; a tolerância deixa o sistema agrupar
        // este despertar com outros e não acordar o Mac só por causa dele.
        timer.tolerance = Self.sweepInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer

        checkAtLaunch()
    }

    /// A varredura silenciosa: só aparece se houver versão nova e não ignorada.
    func checkInBackground() {
        Task {
            guard let release = await checker.checkInBackground() else { return }
            present(release, userInitiated: false)
        }
    }

    /// A verificação de abertura, que insiste enquanto a rede não responde.
    private func checkAtLaunch() {
        Task {
            for retry in [0] + Self.launchRetries {
                if retry > 0 {
                    try? await Task.sleep(for: .seconds(retry))
                }

                if let release = await checker.checkInBackground(after: Self.launchInterval) {
                    present(release, userInitiated: false)
                    return
                }

                // Só falha merece nova tentativa: já estar na última versão, ou
                // não ser hora de perguntar, é uma resposta como outra qualquer.
                guard case .failed = checker.state else { return }
            }
        }
    }

    /// "Buscar atualizações…", do menu e das Configurações.
    ///
    /// Responde sempre, mesmo que a resposta seja "você já está na última": uma
    /// verificação pedida que não diz nada parece um botão quebrado.
    func checkNow() {
        Task {
            switch await checker.check() {
            case .available(let release):
                present(release, userInitiated: true)
            case .upToDate:
                presentUpToDate()
            case .failed(let message):
                presentFailure(message)
            case .idle, .checking:
                break
            }
        }
    }

    func download(_ release: Release) {
        NSWorkspace.shared.open(release.installerURL)
    }

    // MARK: - Alertas

    private func present(_ release: Release, userInitiated: Bool) {
        guard !isPresenting else { return }

        let alert = makeAlert(
            title: "Focata \(release.version) disponível",
            message: "Você está usando a \(checker.currentVersion)."
        )
        if !release.notes.isEmpty {
            alert.accessoryView = Self.notesView(release.notes)
        }
        alert.addButton(withTitle: "Baixar")
        alert.addButton(withTitle: "Depois")
        alert.addButton(withTitle: "Ignorar esta versão")

        switch run(alert) {
        case .alertFirstButtonReturn:
            download(release)
        case .alertThirdButtonReturn:
            checker.skip(release.version)
        default:
            // "Depois" é literal: a próxima varredura diária avisa de novo.
            break
        }
    }

    private func presentUpToDate() {
        guard !isPresenting else { return }
        run(makeAlert(
            title: "O Focata está atualizado",
            message: "A \(checker.currentVersion) é a versão mais recente."
        ))
    }

    private func presentFailure(_ message: String) {
        guard !isPresenting else { return }
        let alert = makeAlert(title: "Não deu para verificar", message: message)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Abrir a página de releases")

        if run(alert) == .alertSecondButtonReturn {
            NSWorkspace.shared.open(GitHubRepository.releasesPage)
        }
    }

    private func makeAlert(title: String, message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        return alert
    }

    /// Um app `.accessory` não fica na frente sozinho: sem ativar, o alerta
    /// nasce atrás da janela em que a pessoa estava trabalhando.
    @discardableResult
    private func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        isPresenting = true
        defer { isPresenting = false }

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    /// As notas do release, roláveis.
    ///
    /// Elas vão como texto cru, com o Markdown à mostra: são escritas por quem
    /// publica o release, e o renderizador do app existe para uma linha na
    /// barra, não para um changelog inteiro.
    private static func notesView(_ notes: String) -> NSView {
        let size = NSSize(width: 300, height: 110)

        let text = NSTextView(frame: NSRect(origin: .zero, size: size))
        text.string = notes
        text.isEditable = false
        text.drawsBackground = false
        text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        text.textContainerInset = NSSize(width: 4, height: 4)
        // Sem isto o texto cresce para a direita em vez de quebrar linha, e as
        // notas viram uma única linha larguíssima dentro da área de rolagem.
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(
            width: size.width, height: .greatestFiniteMagnitude
        )

        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .bezelBorder
        return scroll
    }
}
