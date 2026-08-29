import AppKit
import Observation

/// Cores permitidas para o texto na barra.
///
/// Só cores do sistema, de propósito: elas se adaptam automaticamente para
/// continuar legíveis em barra clara ou escura — uma cor fixa não faria isso.
enum MenuBarTextColor: String, CaseIterable, Identifiable {
    case `default`, red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .default: .labelColor
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .cyan: .systemCyan
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .brown: .systemBrown
        case .gray: .systemGray
        }
    }

    var label: String {
        switch self {
        case .default: "Padrão"
        case .red: "Vermelho"
        case .orange: "Laranja"
        case .yellow: "Amarelo"
        case .green: "Verde"
        case .mint: "Menta"
        case .teal: "Azul-petróleo"
        case .cyan: "Ciano"
        case .blue: "Azul"
        case .indigo: "Índigo"
        case .purple: "Roxo"
        case .pink: "Rosa"
        case .brown: "Marrom"
        case .gray: "Cinza"
        }
    }
}

/// O que acontece quando a última tarefa é concluída (§4 da spec).
enum OnLastTaskCompleted: String, CaseIterable, Identifiable {
    /// O texto some e a barra fica limpa, pronta para a próxima tarefa. Padrão:
    /// a entrada já está no histórico, e uma barra vazia convida a começar de
    /// novo em vez de deixar um troféu ocupando o lugar.
    case clearBar
    /// Mantém o texto riscado à mostra — o "respiro" de tudo feito. É a única
    /// opção em que dá para reabrir a tarefa: com a barra limpa não sobra o que
    /// desmarcar.
    case keepStruckThrough

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clearBar: "Limpar a barra"
        case .keepStruckThrough: "Manter o texto riscado"
        }
    }
}

/// Preferências do app, espelhadas em `UserDefaults`.
///
/// Ficam em `UserDefaults` (e não num arquivo próprio) para que a automação por
/// terminal continue funcionando como no One Thing:
/// `defaults read dev.vinicius.focata text`.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    // MARK: General

    var trackHistory: Bool { didSet { defaults.set(trackHistory, forKey: Key.trackHistory) } }
    var hideEditorWhenDeactivated: Bool { didSet { defaults.set(hideEditorWhenDeactivated, forKey: Key.hideEditorWhenDeactivated) } }

    /// Se o app pergunta ao GitHub, uma vez por dia, se saiu versão nova.
    ///
    /// Ligado de fábrica: o Focata é distribuído em `.dmg` fora da App Store, e
    /// sem isto uma correção só chega a quem lembrar de visitar o repositório.
    /// A consulta é anônima e não leva nada do que você escreve.
    var automaticUpdateChecks: Bool { didSet { defaults.set(automaticUpdateChecks, forKey: Key.automaticUpdateChecks) } }

    // MARK: Appearance

    var prefixText: String { didSet { defaults.set(prefixText, forKey: Key.prefixText) } }
    var suffixText: String { didSet { defaults.set(suffixText, forKey: Key.suffixText) } }
    var maximumWidth: Double { didSet { defaults.set(maximumWidth, forKey: Key.maximumWidth) } }
    var textSize: Double { didSet { defaults.set(textSize, forKey: Key.textSize) } }
    var textIsBold: Bool { didSet { defaults.set(textIsBold, forKey: Key.textIsBold) } }
    /// Largura da fonte, de -1 (estreita) a 1 (larga). 0 é a padrão do sistema.
    var textWidth: Double { didSet { defaults.set(textWidth, forKey: Key.textWidth) } }
    var textColor: MenuBarTextColor { didSet { defaults.set(textColor.rawValue, forKey: Key.textColor) } }

    // MARK: Pomodoro

    var pomodoroEnabled: Bool { didSet { defaults.set(pomodoroEnabled, forKey: Key.pomodoroEnabled) } }
    var focusMinutes: Double { didSet { defaults.set(focusMinutes, forKey: Key.focusMinutes) } }
    var freeShortMinutes: Double { didSet { defaults.set(freeShortMinutes, forKey: Key.freeShortMinutes) } }
    var freeLongMinutes: Double { didSet { defaults.set(freeLongMinutes, forKey: Key.freeLongMinutes) } }
    var cyclesBeforeLongFree: Int { didSet { defaults.set(cyclesBeforeLongFree, forKey: Key.cyclesBeforeLongFree) } }
    var transitionNotifications: Bool { didSet { defaults.set(transitionNotifications, forKey: Key.transitionNotifications) } }
    var transitionSound: Bool { didSet { defaults.set(transitionSound, forKey: Key.transitionSound) } }
    var logToHistory: Bool { didSet { defaults.set(logToHistory, forKey: Key.logToHistory) } }
    var defaultToPrivate: Bool { didSet { defaults.set(defaultToPrivate, forKey: Key.defaultToPrivate) } }

    /// Se concluir uma tarefa limpa a barra.
    var clearsBarOnCompletion: Bool { onLastTaskCompleted == .clearBar }

    /// O histórico do Pomodoro depende do "Guardar histórico" geral: desligar lá
    /// desliga aqui, sem estados contraditórios.
    ///
    /// E depende de "Limpar a barra": mantendo o texto riscado, a conclusão é
    /// reversível pelo check da caixa — um registro que some quando você
    /// desmarca não é registro, é rascunho. Nesse modo o histórico fica parado
    /// inteiro, concluídas e abandonadas.
    var recordsHistory: Bool { trackHistory && logToHistory && clearsBarOnCompletion }

    /// Se faz sentido mexer no "Registrar no histórico": com o histórico geral
    /// desligado, ou sem limpar a barra, o interruptor não tem o que ligar.
    var recordsHistoryIsPossible: Bool { trackHistory && clearsBarOnCompletion }
    var onLastTaskCompleted: OnLastTaskCompleted { didSet { defaults.set(onLastTaskCompleted.rawValue, forKey: Key.onLastTaskCompleted) } }

    /// As durações no formato que o motor consome.
    var durations: PomodoroDurations {
        PomodoroDurations(
            focus: focusMinutes * 60,
            freeShort: freeShortMinutes * 60,
            freeLong: freeLongMinutes * 60,
            cyclesBeforeLongFree: cyclesBeforeLongFree
        )
    }

    func apply(_ preset: PomodoroPreset) {
        let durations = preset.durations
        focusMinutes = durations.focus / 60
        freeShortMinutes = durations.freeShort / 60
        freeLongMinutes = durations.freeLong / 60
        cyclesBeforeLongFree = durations.cyclesBeforeLongFree
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Key.trackHistory: true,
            Key.hideEditorWhenDeactivated: true,
            Key.automaticUpdateChecks: true,
            Key.prefixText: "",
            Key.suffixText: "",
            Key.maximumWidth: 300.0,
            Key.textSize: 14.0,
            Key.textIsBold: false,
            Key.textWidth: 0.0,
            Key.textColor: MenuBarTextColor.default.rawValue,
            Key.pomodoroEnabled: true,
            Key.focusMinutes: 25.0,
            Key.freeShortMinutes: 5.0,
            Key.freeLongMinutes: 15.0,
            Key.cyclesBeforeLongFree: 4,
            Key.transitionNotifications: true,
            // Desligado por padrão: o app é silencioso por natureza.
            Key.transitionSound: false,
            Key.logToHistory: true,
            Key.defaultToPrivate: false,
            Key.onLastTaskCompleted: OnLastTaskCompleted.clearBar.rawValue,
        ])

        trackHistory = defaults.bool(forKey: Key.trackHistory)
        hideEditorWhenDeactivated = defaults.bool(forKey: Key.hideEditorWhenDeactivated)
        automaticUpdateChecks = defaults.bool(forKey: Key.automaticUpdateChecks)
        prefixText = defaults.string(forKey: Key.prefixText) ?? ""
        suffixText = defaults.string(forKey: Key.suffixText) ?? ""
        maximumWidth = defaults.double(forKey: Key.maximumWidth)
        textSize = defaults.double(forKey: Key.textSize)
        textIsBold = defaults.bool(forKey: Key.textIsBold)
        textWidth = defaults.double(forKey: Key.textWidth)
        textColor = MenuBarTextColor(rawValue: defaults.string(forKey: Key.textColor) ?? "") ?? .default
        pomodoroEnabled = defaults.bool(forKey: Key.pomodoroEnabled)
        focusMinutes = defaults.double(forKey: Key.focusMinutes)
        freeShortMinutes = defaults.double(forKey: Key.freeShortMinutes)
        freeLongMinutes = defaults.double(forKey: Key.freeLongMinutes)
        cyclesBeforeLongFree = defaults.integer(forKey: Key.cyclesBeforeLongFree)
        transitionNotifications = defaults.bool(forKey: Key.transitionNotifications)
        transitionSound = defaults.bool(forKey: Key.transitionSound)
        logToHistory = defaults.bool(forKey: Key.logToHistory)
        defaultToPrivate = defaults.bool(forKey: Key.defaultToPrivate)
        onLastTaskCompleted = OnLastTaskCompleted(rawValue: defaults.string(forKey: Key.onLastTaskCompleted) ?? "") ?? .clearBar
    }

    enum Key {
        static let trackHistory = "trackHistory"
        static let hideEditorWhenDeactivated = "hideEditorWhenDeactivated"
        static let automaticUpdateChecks = "automaticUpdateChecks"
        static let prefixText = "prefixText"
        static let suffixText = "suffixText"
        static let maximumWidth = "maximumWidth"
        static let textSize = "textSize"
        static let textIsBold = "textIsBold"
        static let textWidth = "textWidth"
        static let textColor = "textColor"
        static let pomodoroEnabled = "pomodoroEnabled"
        static let focusMinutes = "focusMinutes"
        static let freeShortMinutes = "freeShortMinutes"
        static let freeLongMinutes = "freeLongMinutes"
        static let cyclesBeforeLongFree = "cyclesBeforeLongFree"
        static let transitionNotifications = "transitionNotifications"
        static let transitionSound = "transitionSound"
        static let logToHistory = "logToHistory"
        static let defaultToPrivate = "defaultToPrivate"
        static let onLastTaskCompleted = "onLastTaskCompleted"
    }
}
