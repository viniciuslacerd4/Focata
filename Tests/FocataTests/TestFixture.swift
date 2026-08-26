import Foundation

@testable import Focata

/// `UserDefaults` isolado por teste, que se apaga sozinho.
///
/// `UserDefaults(suiteName:)` cria um **domínio persistente** — um plist de
/// verdade em `~/Library/Preferences`. Sem remover no fim, cada rodada de testes
/// deixa um arquivo para trás e eles se acumulam às centenas.
final class TemporaryDefaults {
    let name: String
    let defaults: UserDefaults

    init() {
        name = "focata.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
    }

    deinit {
        // `removePersistentDomain` esvazia o domínio mas **não** apaga o plist:
        // sem o `removeItem`, cada teste deixa um arquivo vazio em
        // ~/Library/Preferences e eles se acumulam às centenas.
        defaults.removePersistentDomain(forName: name)
        defaults.synchronize()
        try? FileManager.default.removeItem(atPath: Self.plistPath(for: name))
    }

    private static func plistPath(for name: String) -> String {
        ("~/Library/Preferences/\(name).plist" as NSString).expandingTildeInPath
    }
}

/// O grafo de objetos do app montado para um teste, com armazenamento
/// descartável. Tudo — plist de preferências e JSON de histórico — some quando
/// a fixture sai de escopo.
@MainActor
final class TestFixture {
    let task: TaskStore
    let history: HistoryStore
    let settings: AppSettings
    let engine: PomodoroEngine
    let taskController: TaskController

    private let temporaryDefaults = TemporaryDefaults()
    private let historyURL: URL

    init() {
        historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("focata-history-\(UUID().uuidString).json")

        let defaults = temporaryDefaults.defaults
        task = TaskStore(defaults: defaults)
        history = HistoryStore(fileURL: historyURL)
        settings = AppSettings(defaults: defaults)
        engine = PomodoroEngine(defaults: defaults)
        taskController = TaskController(
            task: task, history: history, settings: settings, engine: engine
        )
    }

    /// A fachada que URL scheme, Atalhos e Serviços usam.
    lazy var actions = AppActions(
        task: task,
        settings: settings,
        engine: engine,
        taskController: taskController,
        notifications: NotificationService()
    )

    deinit {
        try? FileManager.default.removeItem(at: historyURL)
    }
}
