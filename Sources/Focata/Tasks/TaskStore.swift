import Foundation
import Observation

/// A tarefa em foco. Uma de cada vez — é a filosofia do app, não uma limitação.
@MainActor
@Observable
final class TaskStore {
    static let shared = TaskStore()

    private let defaults: UserDefaults

    /// O texto da tarefa, cru (sem prefix/suffix, com Markdown ainda por renderizar).
    ///
    /// Persistido na chave `text` para que `defaults read dev.vinicius.focata text`
    /// funcione, como no One Thing.
    ///
    /// Editar este texto **não** zera a contagem de pomodoros: o editor grava a
    /// cada tecla, e uma correção de digitação não pode apagar o trabalho já
    /// feito. Começar tarefa nova é uma ação explícita — `beginNewTask`.
    var text: String {
        didSet {
            guard text != oldValue else { return }
            defaults.set(text, forKey: Key.text)
        }
    }

    /// Concluída não é o mesmo que apagada: o texto continua visível, riscado (§4).
    var isCompleted: Bool {
        didSet { defaults.set(isCompleted, forKey: Key.isCompleted) }
    }

    /// Quantos ciclos de foco esta tarefa já custou (§5).
    var pomodoroCount: Int {
        didSet { defaults.set(pomodoroCount, forKey: Key.pomodoroCount) }
    }

    /// Sessão privada: funciona com o Pomodoro normalmente, mas não entra no
    /// histórico — nem como concluída, nem como abandonada (§7).
    var isPrivate: Bool {
        didSet { defaults.set(isPrivate, forKey: Key.isPrivate) }
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        text = defaults.string(forKey: Key.text) ?? ""
        isCompleted = defaults.bool(forKey: Key.isCompleted)
        pomodoroCount = defaults.integer(forKey: Key.pomodoroCount)
        isPrivate = defaults.bool(forKey: Key.isPrivate)
    }

    /// Troca de tarefa: texto novo, contadores zerados.
    func beginNewTask(_ newText: String, isPrivate: Bool) {
        text = newText
        isCompleted = false
        pomodoroCount = 0
        self.isPrivate = isPrivate
    }

    /// Esvazia a barra.
    func clear(defaultToPrivate: Bool) {
        beginNewTask("", isPrivate: defaultToPrivate)
    }

    enum Key {
        static let text = "text"
        static let isCompleted = "isCompleted"
        static let pomodoroCount = "pomodoroCount"
        static let isPrivate = "isPrivate"
    }
}
