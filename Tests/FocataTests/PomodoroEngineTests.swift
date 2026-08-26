import Foundation
import Testing

@testable import Focata

/// Relógio controlado pelo teste: 25 minutos passam quando o teste mandar.
@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    var clock: Clock { Clock(now: { [self] in MainActor.assumeIsolated { now } }) }

    /// Segurado aqui só para viver enquanto o teste vive: ao sair de escopo, o
    /// domínio de preferências do teste é removido.
    let temporaryDefaults = TemporaryDefaults()

    func advance(_ interval: TimeInterval) { now += interval }
}

@MainActor
private func makeEngine(
    durations: PomodoroDurations = .classic
) -> (PomodoroEngine, TestClock) {
    let clock = TestClock()
    // Armazenamento isolado por teste, apagado quando o relógio sai de escopo.
    let engine = PomodoroEngine(
        durations: durations,
        clock: clock.clock,
        defaults: clock.temporaryDefaults.defaults
    )
    return (engine, clock)
}

@Suite("PomodoroEngine")
@MainActor
struct PomodoroEngineTests {
    @Test("começa parado, no foco, sem pomodoros")
    func estadoInicial() {
        let (engine, clock) = makeEngine()
        #expect(engine.phase == .focus)
        #expect(engine.isIdle)
        #expect(engine.completedFocusCount == 0)
        #expect(engine.progress(at: clock.now) == 0)
    }

    @Test("o anel preenche de 0 a 1 ao longo do bloco de foco")
    func progressoDoAnel() {
        let (engine, clock) = makeEngine()
        engine.start()

        #expect(engine.progress(at: clock.now) == 0)

        clock.advance(25 * 60 * 0.25)
        #expect(abs(engine.progress(at: clock.now) - 0.25) < 0.001)

        clock.advance(25 * 60 * 0.35)
        #expect(abs(engine.progress(at: clock.now) - 0.60) < 0.001)

        clock.advance(25 * 60 * 0.40)
        #expect(engine.progress(at: clock.now) == 1)
    }

    @Test("o foco vira tempo livre no deadline e soma um pomodoro")
    func transicaoFocoParaLivre() {
        let (engine, clock) = makeEngine()
        var transitions: [PomodoroEngine.Transition] = []
        engine.onTransition = { transitions.append($0) }

        engine.start()
        clock.advance(25 * 60 - 1)
        engine.advance(to: clock.now)
        #expect(engine.phase == .focus, "um segundo antes ainda é foco")

        clock.advance(1)
        engine.advance(to: clock.now)

        #expect(engine.phase == .freeShort)
        #expect(engine.completedFocusCount == 1)
        #expect(transitions.count == 1)
        #expect(transitions[0].earnedPomodoro)
        #expect(engine.showsCheckmark(at: clock.now), "o check aparece antes da troca")
    }

    @Test("o tempo livre não soma pomodoro")
    func livreNaoContaPomodoro() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(25 * 60)
        engine.advance(to: clock.now)  // foco -> livre curto

        clock.advance(5 * 60)
        engine.advance(to: clock.now)  // livre curto -> foco

        #expect(engine.phase == .focus)
        #expect(engine.completedFocusCount == 1, "só o foco conta")
    }

    @Test("a pausa longa cai exatamente a cada N ciclos")
    func pausaLongaACadaNCiclos() {
        let (engine, clock) = makeEngine()
        var fases: [PomodoroPhase] = []
        engine.onTransition = { fases.append($0.to) }

        engine.start()
        // Oito transições = quatro pares foco/livre.
        for _ in 0..<8 {
            clock.advance(engine.remaining(at: clock.now))
            engine.advance(to: clock.now)
        }

        #expect(fases == [.freeShort, .focus, .freeShort, .focus, .freeShort, .focus, .freeLong, .focus])
        #expect(engine.completedFocusCount == 4)
    }

    @Test("pausar e retomar preserva o tempo restante")
    func pausarPreservaRestante() {
        let (engine, clock) = makeEngine()
        engine.start()

        clock.advance(10 * 60)
        engine.pause()
        #expect(abs(engine.remaining(at: clock.now) - 15 * 60) < 0.001)

        // Tempo passa pausado: o restante não pode andar.
        clock.advance(60 * 60)
        #expect(abs(engine.remaining(at: clock.now) - 15 * 60) < 0.001)
        engine.advance(to: clock.now)
        #expect(engine.phase == .focus, "pausado não vence")

        engine.resume()
        clock.advance(15 * 60)
        engine.advance(to: clock.now)
        #expect(engine.phase == .freeShort)
    }

    @Test("pular avança sem contar pomodoro e sem render pausa longa")
    func pularNaoConta() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(60)
        engine.skip()

        #expect(engine.phase == .freeShort)
        #expect(engine.completedFocusCount == 0)
        #expect(!engine.showsCheckmark(at: clock.now))
    }

    @Test("dormir 40 minutos durante um foco de 25 conclui a fase, não trava")
    func saltoDeRelogio() {
        let (engine, clock) = makeEngine()
        engine.start()

        clock.advance(40 * 60)
        engine.advance(to: clock.now)

        #expect(engine.phase == .freeShort)
        #expect(engine.completedFocusCount == 1)
        // O tempo livre começa inteiro ao acordar, não já vencido.
        #expect(abs(engine.remaining(at: clock.now) - 5 * 60) < 0.001)
    }

    @Test("um sono muito longo não cascateia ciclos falsos")
    func sonoLongoNaoCascateia() {
        let (engine, clock) = makeEngine()
        engine.start()

        clock.advance(4 * 60 * 60)
        engine.advance(to: clock.now)
        engine.advance(to: clock.now)
        engine.advance(to: clock.now)

        #expect(engine.completedFocusCount == 1, "quatro horas dormindo não são quatro pomodoros")
    }

    @Test("mudar as durações não afeta a fase já em andamento")
    func mudarDuracoesNaoQuebraFaseAtual() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(10 * 60)

        engine.durations = PomodoroPreset.sprint.durations

        // Ainda faltam 15 min do bloco de 25 que começou.
        #expect(abs(engine.remaining(at: clock.now) - 15 * 60) < 0.001)
        #expect(abs(engine.progress(at: clock.now) - 0.4) < 0.001)

        clock.advance(15 * 60)
        engine.advance(to: clock.now)
        // A fase nova já usa a duração nova.
        #expect(abs(engine.remaining(at: clock.now) - 3 * 60) < 0.001)
    }

    @Test("zerar volta ao início")
    func zerar() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(25 * 60)
        engine.advance(to: clock.now)

        engine.reset()

        #expect(engine.phase == .focus)
        #expect(engine.isIdle)
        #expect(engine.completedFocusCount == 0)
    }

    @Test("o check some depois da duração dele")
    func checkTemporario() {
        let (engine, clock) = makeEngine()
        engine.start()
        clock.advance(25 * 60)
        engine.advance(to: clock.now)

        #expect(engine.showsCheckmark(at: clock.now))
        clock.advance(PomodoroEngine.checkmarkDuration)
        engine.advance(to: clock.now)
        #expect(!engine.showsCheckmark(at: clock.now))
    }
}
