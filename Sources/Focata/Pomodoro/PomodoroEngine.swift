import Foundation
import Observation

/// A máquina de estados do Pomodoro.
///
/// Todo o progresso é derivado de datas absolutas (`endDate` vs. agora), nunca
/// de contagem de ticks: é isso que faz o timer sobreviver ao Mac dormindo, ao
/// run loop atrasar ou ao app ser relançado.
@MainActor
@Observable
final class PomodoroEngine {
    /// Quanto tempo o check de "ciclo concluído" fica no lugar do anel (§1).
    static let checkmarkDuration: TimeInterval = 1.2

    enum Activity: Equatable {
        case idle
        case running(endDate: Date, duration: TimeInterval)
        case paused(remaining: TimeInterval, duration: TimeInterval)
    }

    struct Transition: Equatable {
        var from: PomodoroPhase
        var to: PomodoroPhase
        /// Só o fim natural de um bloco de foco soma pomodoro; pular, não.
        var earnedPomodoro: Bool
    }

    private(set) var phase: PomodoroPhase = .focus
    private(set) var activity: Activity = .idle
    private(set) var completedFocusCount: Int = 0
    /// Enquanto != nil, o anel mostra o check em vez do arco.
    private(set) var checkmarkUntil: Date?
    /// A fase que o check está celebrando — ele fica na cor dela, não na cor da
    /// fase que acabou de começar: o check marca o ciclo concluído (Fig. 1).
    private(set) var checkmarkPhase: PomodoroPhase?

    var durations: PomodoroDurations
    /// Avisado a cada troca de modo — quem escuta dispara a notificação e soma
    /// o pomodoro à tarefa.
    var onTransition: ((Transition) -> Void)?

    private let clock: Clock
    private let defaults: UserDefaults

    init(
        durations: PomodoroDurations = .classic,
        clock: Clock = .system,
        defaults: UserDefaults = .standard
    ) {
        self.durations = durations
        self.clock = clock
        self.defaults = defaults
        restore()
    }

    // MARK: - Estado derivado

    var isRunning: Bool {
        if case .running = activity { return true }
        return false
    }

    var isIdle: Bool { activity == .idle }

    /// Parada no meio — diferente de `isIdle`, que é não ter começado.
    var isPaused: Bool {
        if case .paused = activity { return true }
        return false
    }

    /// 0 a 1 — o quanto do anel já está preenchido.
    func progress(at now: Date) -> Double {
        switch activity {
        case .idle:
            0
        case .running(let endDate, let duration):
            _progress(remaining: endDate.timeIntervalSince(now), duration: duration)
        case .paused(let remaining, let duration):
            _progress(remaining: remaining, duration: duration)
        }
    }

    func remaining(at now: Date) -> TimeInterval {
        switch activity {
        case .idle: durations.duration(of: phase)
        case .running(let endDate, _): max(0, endDate.timeIntervalSince(now))
        case .paused(let remaining, _): remaining
        }
    }

    func showsCheckmark(at now: Date) -> Bool {
        guard let until = checkmarkUntil else { return false }
        return now < until
    }

    private func _progress(remaining: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / duration))
    }

    // MARK: - Ações

    func start() {
        switch activity {
        case .idle: beginPhase(phase, at: clock.now())
        case .paused: resume()
        case .running: break
        }
    }

    func pause() {
        guard case .running(let endDate, let duration) = activity else { return }
        activity = .paused(
            remaining: max(0, endDate.timeIntervalSince(clock.now())),
            duration: duration
        )
        persist()
    }

    func resume() {
        guard case .paused(let remaining, let duration) = activity else { return }
        activity = .running(endDate: clock.now().addingTimeInterval(remaining), duration: duration)
        persist()
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Pula para o próximo modo. Pular um foco não conta pomodoro.
    func skip() {
        advanceToNextPhase(at: clock.now(), earnedPomodoro: false)
    }

    func reset() {
        phase = .focus
        activity = .idle
        completedFocusCount = 0
        checkmarkUntil = nil
        checkmarkPhase = nil
        persist()
    }

    /// Chamado a cada tick e ao acordar o Mac. Completa no máximo uma fase por
    /// chamada — dormir duas horas não pode render quatro pomodoros falsos.
    func advance(to now: Date) {
        if let until = checkmarkUntil, now >= until {
            checkmarkUntil = nil
            checkmarkPhase = nil
        }
        guard case .running(let endDate, _) = activity, now >= endDate else { return }

        if phase == .focus {
            completedFocusCount += 1
            checkmarkUntil = now.addingTimeInterval(Self.checkmarkDuration)
            checkmarkPhase = .focus
            advanceToNextPhase(at: now, earnedPomodoro: true)
        } else {
            advanceToNextPhase(at: now, earnedPomodoro: false)
        }
    }

    // MARK: - Transições

    private func advanceToNextPhase(at now: Date, earnedPomodoro: Bool) {
        let from = phase
        let to = nextPhase(after: from, earnedPomodoro: earnedPomodoro)
        beginPhase(to, at: now)
        onTransition?(Transition(from: from, to: to, earnedPomodoro: earnedPomodoro))
    }

    private func nextPhase(after phase: PomodoroPhase, earnedPomodoro: Bool) -> PomodoroPhase {
        guard phase == .focus else { return .focus }
        // Sem pomodoro contabilizado (foi um "pular"), a pausa longa não é devida.
        guard earnedPomodoro else { return .freeShort }
        return completedFocusCount % max(1, durations.cyclesBeforeLongFree) == 0 ? .freeLong : .freeShort
    }

    /// Começa a fase contando a partir de `now`, e não do fim teórico da fase
    /// anterior: se o Mac dormiu 40 minutos durante um foco de 25, o tempo livre
    /// começa inteiro ao acordar em vez de já nascer vencido.
    private func beginPhase(_ newPhase: PomodoroPhase, at now: Date) {
        let duration = durations.duration(of: newPhase)
        phase = newPhase
        activity = .running(endDate: now.addingTimeInterval(duration), duration: duration)
        persist()
    }

    // MARK: - Persistência da sessão

    private func persist() {
        defaults.set(phase.rawValue, forKey: Key.phase)
        defaults.set(completedFocusCount, forKey: Key.completedFocusCount)

        switch activity {
        case .idle:
            defaults.removeObject(forKey: Key.endDate)
            defaults.removeObject(forKey: Key.pausedRemaining)
            defaults.removeObject(forKey: Key.phaseDuration)
        case .running(let endDate, let duration):
            defaults.set(endDate, forKey: Key.endDate)
            defaults.removeObject(forKey: Key.pausedRemaining)
            defaults.set(duration, forKey: Key.phaseDuration)
        case .paused(let remaining, let duration):
            defaults.removeObject(forKey: Key.endDate)
            defaults.set(remaining, forKey: Key.pausedRemaining)
            defaults.set(duration, forKey: Key.phaseDuration)
        }
    }

    private func restore() {
        phase = PomodoroPhase(rawValue: defaults.string(forKey: Key.phase) ?? "") ?? .focus
        completedFocusCount = defaults.integer(forKey: Key.completedFocusCount)

        let duration = defaults.double(forKey: Key.phaseDuration)
        guard duration > 0 else { return }

        if let remaining = defaults.object(forKey: Key.pausedRemaining) as? TimeInterval {
            activity = .paused(remaining: remaining, duration: duration)
        } else if let endDate = defaults.object(forKey: Key.endDate) as? Date, endDate > clock.now() {
            activity = .running(endDate: endDate, duration: duration)
        }
        // Um `endDate` já vencido significa que o app estava fechado quando o
        // bloco terminaria. Não dá para creditar um foco que ninguém viveu, então
        // a sessão volta parada.
    }

    private enum Key {
        static let phase = "pomodoroPhase"
        static let endDate = "pomodoroEndDate"
        static let pausedRemaining = "pomodoroPausedRemaining"
        static let phaseDuration = "pomodoroPhaseDuration"
        static let completedFocusCount = "pomodoroCompletedFocusCount"
    }
}
