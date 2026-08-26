import Foundation
import Observation

/// Descobre se saiu uma versão nova do Focata.
///
/// O app é assinado ad-hoc e distribuído em `.dmg` pelo GitHub, então não há
/// atualização automática para instalar: o que dá para fazer bem é avisar, uma
/// vez por dia, e abrir o download. Nada é baixado nem trocado sem clique.
///
/// A verificação é uma pergunta só — o último release público do repositório.
/// Não vai identificador nenhum junto, e a tarefa em foco nunca sai do Mac.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        /// A última consulta disse que esta é a versão mais recente.
        case upToDate
        case available(Release)
        /// Mensagem já pronta para mostrar.
        case failed(String)
    }

    /// Uma vez por dia. Mais que isso não descobre nada — releases não saem de
    /// hora em hora — e ainda gasta o limite de consultas anônimas do GitHub.
    static let interval: TimeInterval = 24 * 60 * 60

    private(set) var state: State = .idle

    let currentVersion: AppVersion

    private let feed: ReleaseFeed
    private let settings: AppSettings
    private let clock: Clock
    private let defaults: UserDefaults

    /// A consulta em andamento. Duas verificações ao mesmo tempo — o timer e o
    /// botão "Verificar agora" — viram uma só, e as duas esperam o mesmo
    /// resultado.
    private var inFlight: Task<State, Never>?

    init(
        feed: ReleaseFeed = .gitHub,
        settings: AppSettings = .shared,
        currentVersion: AppVersion = .current,
        clock: Clock = .system,
        defaults: UserDefaults = .standard
    ) {
        self.feed = feed
        self.settings = settings
        self.currentVersion = currentVersion
        self.clock = clock
        self.defaults = defaults
    }

    // MARK: - Verificação

    /// A verificação pedida por você — no menu ou no botão das Configurações.
    /// Responde sempre, inclusive quando não há nada de novo.
    @discardableResult
    func check() async -> State {
        if let inFlight { return await inFlight.value }

        state = .checking
        let task = Task { await fetch() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    /// A verificação automática. Devolve o release que merece interromper —
    /// `nil` quando ainda não é hora, quando a verificação está desligada,
    /// quando já é a versão mais recente, quando esta versão foi ignorada ou
    /// quando a consulta falhou (estar sem rede é comum demais para virar
    /// alerta).
    ///
    /// `after` é o quanto precisa ter passado desde a última resposta. O
    /// padrão é a régua diária; o launch usa uma mais curta, porque ligar o Mac
    /// é o momento em que o aviso cabe.
    func checkInBackground(after minimumInterval: TimeInterval = UpdateChecker.interval) async -> Release? {
        guard settings.automaticUpdateChecks, isDue(after: minimumInterval) else { return nil }

        guard case .available(let release) = await check() else { return nil }
        guard release.version != skippedVersion else { return nil }
        return release
    }

    private func isDue(after minimumInterval: TimeInterval) -> Bool {
        guard let lastCheck else { return true }
        return clock.now().timeIntervalSince(lastCheck) >= minimumInterval
    }

    private func fetch() async -> State {
        do {
            let release = try await feed.latest()
            // Só uma resposta de verdade adia a próxima verificação: depois de
            // uma falha, a varredura da hora seguinte tenta de novo.
            lastCheck = clock.now()

            state = release.version > currentVersion ? .available(release) : .upToDate
        } catch {
            state = .failed(error.localizedDescription)
        }
        return state
    }

    // MARK: - Versão ignorada

    /// A versão que você mandou pular. Ela continua aparecendo nas
    /// Configurações e em quem pede a verificação — o que ela deixa de fazer é
    /// interromper sozinha.
    private(set) var skippedVersion: AppVersion? {
        get { defaults.string(forKey: Key.skippedVersion).flatMap(AppVersion.init) }
        set { defaults.set(newValue?.description, forKey: Key.skippedVersion) }
    }

    func skip(_ version: AppVersion) {
        skippedVersion = version
    }

    /// Quando a última consulta deu resposta. `nil` significa nunca.
    private(set) var lastCheck: Date? {
        get { defaults.object(forKey: Key.lastCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastCheck) }
    }

    /// Anotações de funcionamento, não preferências: por isso ficam aqui e não
    /// no `AppSettings`, que é o que a janela de Configurações mostra.
    private enum Key {
        static let lastCheck = "lastUpdateCheck"
        static let skippedVersion = "skippedUpdateVersion"
    }
}
