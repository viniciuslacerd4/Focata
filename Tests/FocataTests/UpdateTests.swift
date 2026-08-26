import Foundation
import Testing

@testable import Focata

@Suite("AppVersion")
struct AppVersionTests {
    @Test("compara número a número, não string a string")
    func ordem() {
        #expect(AppVersion("0.10.0")! > AppVersion("0.9.0")!, "a décima versão é o teste que a comparação textual reprova")
        #expect(AppVersion("1.0.0")! > AppVersion("0.99.99")!)
        #expect(AppVersion("1.2.3")! > AppVersion("1.2.2")!)
        #expect(!(AppVersion("1.2.3")! > AppVersion("1.2.3")!))
    }

    @Test("o v das tags entra e sai, e componentes faltando valem zero")
    func formatos() {
        #expect(AppVersion("v1.2.0")! == AppVersion("1.2.0")!)
        #expect(AppVersion("1.2")! == AppVersion("1.2.0")!)
        #expect(AppVersion("v0.2.0")!.description == "0.2.0", "o v não aparece na tela")
    }

    @Test("recusa o que não é versão")
    func invalidas() {
        #expect(AppVersion("banana") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1..2") == nil)
        #expect(AppVersion("1.2.") == nil)
        // Pré-lançamento não vira estável por descuido.
        #expect(AppVersion("1.2.3-beta") == nil)
    }
}

@Suite("Release")
struct ReleaseTests {
    /// A forma da resposta de `/releases/latest`, recortada nos campos usados.
    private func json(tag: String, assets: String) -> Data {
        """
        {
          "tag_name": "\(tag)",
          "name": "Focata \(tag)",
          "html_url": "https://github.com/viniciuslacerd4/Focata/releases/tag/\(tag)",
          "body": "  Corrige o anel depois do sleep.  ",
          "assets": [\(assets)]
        }
        """.data(using: .utf8)!
    }

    private func asset(_ name: String) -> String {
        """
        {"name": "\(name)", "browser_download_url": "https://github.com/viniciuslacerd4/Focata/releases/download/x/\(name)"}
        """
    }

    @Test("lê versão, notas e o .dmg entre os anexos")
    func leitura() throws {
        let release = try Release(
            gitHubJSON: json(tag: "v0.2.0", assets: [asset("Focata-0.2.0.dmg"), asset("checksums.txt")].joined(separator: ","))
        )

        #expect(release.version == AppVersion("0.2.0")!)
        #expect(release.notes == "Corrige o anel depois do sleep.", "as notas chegam sem o espaço em volta")
        #expect(release.downloadURL?.lastPathComponent == "Focata-0.2.0.dmg")
        #expect(release.installerURL == release.downloadURL)
    }

    @Test("sem .dmg anexado, baixar leva à página do release")
    func semInstalador() throws {
        let release = try Release(gitHubJSON: json(tag: "v0.2.0", assets: asset("checksums.txt")))

        #expect(release.downloadURL == nil)
        #expect(release.installerURL == release.pageURL)
    }

    @Test("uma tag que não é versão vira erro, e não versão zero")
    func tagIlegivel() {
        #expect(throws: UpdateError.self) {
            try Release(gitHubJSON: json(tag: "nightly", assets: ""))
        }
    }
}

/// Fonte de releases controlada pelo teste: nenhuma consulta sai daqui.
///
/// Fora do `@MainActor` porque a closure do `ReleaseFeed` é `@Sendable` e não
/// pode presumir isolamento nenhum; o estado fica atrás de um `NSLock`.
private final class FakeFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<Release, Error>
    private var callCount = 0

    init(_ result: Result<Release, Error>) {
        storedResult = result
    }

    convenience init(version: String) {
        self.init(.success(FakeFeed.release(version)))
    }

    /// O que a próxima consulta devolve.
    var result: Result<Release, Error> {
        get { lock.withLock { storedResult } }
        set { lock.withLock { storedResult = newValue } }
    }

    /// Quantas consultas foram feitas — é assim que os testes de intervalo
    /// sabem que o app não perguntou de novo.
    var calls: Int { lock.withLock { callCount } }

    static func release(_ version: String) -> Release {
        Release(
            version: AppVersion(version)!,
            notes: "Novidades",
            pageURL: URL(string: "https://github.com/viniciuslacerd4/Focata/releases/tag/v\(version)")!,
            downloadURL: URL(string: "https://example.com/Focata-\(version).dmg")!
        )
    }

    var feed: ReleaseFeed {
        ReleaseFeed { [self] in
            try lock.withLock {
                callCount += 1
                return try storedResult.get()
            }
        }
    }
}

/// Relógio que o teste adianta, como no `PomodoroEngine`.
@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    var clock: Clock { Clock(now: { [self] in MainActor.assumeIsolated { now } }) }

    func advance(_ interval: TimeInterval) { now += interval }
}

/// A verificação montada para um teste: sem rede, com relógio na mão e um
/// domínio de preferências que some junto com a fixture.
@MainActor
private final class UpdateFixture {
    let feed: FakeFeed
    let clock = TestClock()
    let settings: AppSettings
    let checker: UpdateChecker

    private let storage = TemporaryDefaults()

    init(publica versao: String = "0.2.0", instalada: String = "0.1.0") {
        feed = FakeFeed(version: versao)
        settings = AppSettings(defaults: storage.defaults)
        checker = UpdateChecker(
            feed: feed.feed,
            settings: settings,
            currentVersion: AppVersion(instalada)!,
            clock: clock.clock,
            defaults: storage.defaults
        )
    }

    init(erro: Error, instalada: String = "0.1.0") {
        feed = FakeFeed(.failure(erro))
        settings = AppSettings(defaults: storage.defaults)
        checker = UpdateChecker(
            feed: feed.feed,
            settings: settings,
            currentVersion: AppVersion(instalada)!,
            clock: clock.clock,
            defaults: storage.defaults
        )
    }
}

@Suite("UpdateChecker")
@MainActor
struct UpdateCheckerTests {
    @Test("uma versão mais nova aparece e vale interromper")
    func versaoNova() async {
        let f = UpdateFixture()

        let release = await f.checker.checkInBackground()

        #expect(release?.version == AppVersion("0.2.0")!)
        #expect(f.checker.state == .available(FakeFeed.release("0.2.0")))
    }

    @Test("a mesma versão, ou uma mais velha, não avisa nada")
    func jaAtualizado() async {
        for publicada in ["0.1.0", "0.0.9"] {
            let f = UpdateFixture(publica: publicada)

            #expect(await f.checker.checkInBackground() == nil)
            #expect(f.checker.state == .upToDate)
        }
    }

    @Test("verifica uma vez por dia, não a cada varredura")
    func intervalo() async {
        let f = UpdateFixture()

        _ = await f.checker.checkInBackground()
        #expect(f.feed.calls == 1)

        f.clock.advance(60 * 60)
        _ = await f.checker.checkInBackground()
        #expect(f.feed.calls == 1, "uma hora depois ainda é a mesma verificação do dia")

        f.clock.advance(24 * 60 * 60)
        _ = await f.checker.checkInBackground()
        #expect(f.feed.calls == 2)
    }

    @Test("a abertura do app usa uma régua mais curta que a diária")
    func reguaDoLaunch() async {
        let f = UpdateFixture()

        // A varredura de ontem já perguntou; três horas depois, ligar o Mac
        // ainda é um momento em que o aviso cabe.
        _ = await f.checker.checkInBackground()
        f.clock.advance(3 * 60 * 60)

        #expect(await f.checker.checkInBackground(after: 60 * 60) != nil)
        #expect(f.feed.calls == 2)

        // Meia hora depois, não: sair e voltar do app não consulta de novo.
        f.clock.advance(30 * 60)
        #expect(await f.checker.checkInBackground(after: 60 * 60) == nil)
        #expect(f.feed.calls == 2)
    }

    @Test("pedir a verificação ignora o intervalo")
    func verificacaoPedida() async {
        let f = UpdateFixture()

        _ = await f.checker.checkInBackground()
        await f.checker.check()

        #expect(f.feed.calls == 2, "o botão responde na hora, não amanhã")
    }

    @Test("com a verificação automática desligada, nada é consultado")
    func desligada() async {
        let f = UpdateFixture()
        f.settings.automaticUpdateChecks = false

        #expect(await f.checker.checkInBackground() == nil)
        #expect(f.feed.calls == 0, "nenhuma consulta sai do Mac")

        // O interruptor governa só a verificação automática: pedir continua valendo.
        await f.checker.check()
        #expect(f.feed.calls == 1)
    }

    @Test("a versão ignorada não interrompe mais, mas continua à vista")
    func ignorar() async {
        let f = UpdateFixture()

        _ = await f.checker.checkInBackground()
        f.checker.skip(AppVersion("0.2.0")!)

        f.clock.advance(25 * 60 * 60)
        #expect(await f.checker.checkInBackground() == nil, "não avisa de novo sozinho")
        #expect(f.checker.state == .available(FakeFeed.release("0.2.0")), "o menu e as Configurações continuam oferecendo")

        // Ignorar uma versão não é desistir das seguintes.
        f.feed.result = .success(FakeFeed.release("0.3.0"))
        f.clock.advance(25 * 60 * 60)
        #expect(await f.checker.checkInBackground()?.version == AppVersion("0.3.0")!)
    }

    @Test("uma falha é silenciosa e não adia a próxima tentativa")
    func falha() async {
        let f = UpdateFixture(erro: UpdateError.server(403))

        #expect(await f.checker.checkInBackground() == nil, "estar sem rede não vira alerta")
        #expect(f.checker.state == .failed(UpdateError.server(403).localizedDescription))

        // Sem resposta não há dia verificado: a varredura da hora seguinte tenta de novo.
        f.clock.advance(60 * 60)
        f.feed.result = .success(FakeFeed.release("0.2.0"))
        #expect(await f.checker.checkInBackground()?.version == AppVersion("0.2.0")!)
    }

    @Test("duas verificações ao mesmo tempo viram uma consulta só")
    func consultaUnica() async {
        let f = UpdateFixture()

        async let primeira = f.checker.check()
        async let segunda = f.checker.check()
        _ = await (primeira, segunda)

        #expect(f.feed.calls == 1)
    }
}
