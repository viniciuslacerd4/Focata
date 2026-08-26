import AppKit

/// Os dois modos do timer, distinguidos pela cor do anel (§2 da spec).
enum PomodoroPhase: String, Codable, Sendable {
    /// Anel claro. O bloco de trabalho — o único que soma pomodoro à tarefa.
    case focus
    /// Anel verde, pausa curta.
    case freeShort
    /// Anel verde, pausa longa (a cada N ciclos de foco).
    case freeLong

    var isFree: Bool { self != .focus }

    /// A cor do anel diz em que modo você está, sem precisar ler texto.
    ///
    /// A spec pede "anel branco" para o foco, mas branco literal desaparece em
    /// barra clara — `labelColor` é a mesma intenção com a adaptação que o
    /// próprio documento descreve.
    var ringColor: NSColor {
        isFree ? .systemGreen : .labelColor
    }

    /// Título do aviso quando *esta* fase termina.
    var completionTitle: String {
        switch self {
        case .focus: "Pomodoro concluído"
        case .freeShort, .freeLong: "Tempo livre acabou"
        }
    }
}

/// Durações configuráveis (§8 da spec).
struct PomodoroDurations: Equatable, Sendable {
    var focus: TimeInterval
    var freeShort: TimeInterval
    var freeLong: TimeInterval
    /// Quantos ciclos de foco até a pausa longa.
    var cyclesBeforeLongFree: Int

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .freeShort: freeShort
        case .freeLong: freeLong
        }
    }

    static let classic = PomodoroDurations(
        focus: 25 * 60, freeShort: 5 * 60, freeLong: 15 * 60, cyclesBeforeLongFree: 4
    )
}

/// Presets rápidos, para não obrigar ninguém a mexer em quatro campos.
enum PomodoroPreset: String, CaseIterable, Identifiable {
    case classic, long, sprint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: "Clássico 25/5"
        case .long: "Longo 50/10"
        case .sprint: "Sprint 15/3"
        }
    }

    var durations: PomodoroDurations {
        switch self {
        case .classic: .classic
        case .long: .init(focus: 50 * 60, freeShort: 10 * 60, freeLong: 30 * 60, cyclesBeforeLongFree: 2)
        case .sprint: .init(focus: 15 * 60, freeShort: 3 * 60, freeLong: 10 * 60, cyclesBeforeLongFree: 4)
        }
    }
}
