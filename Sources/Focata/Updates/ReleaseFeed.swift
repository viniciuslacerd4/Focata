import Foundation

/// O repositório de onde o Focata vem.
enum GitHubRepository {
    static let owner = "viniciuslacerd4"
    static let name = "Focata"

    /// A API do último release publicado. Rascunhos e pré-lançamentos já ficam
    /// de fora deste endpoint — o que chega aqui é o mesmo que a página de
    /// releases marca como "Latest".
    static let latestRelease = URL(string: "https://api.github.com/repos/\(owner)/\(name)/releases/latest")!

    /// A página equivalente, para abrir no navegador.
    static let releasesPage = URL(string: "https://github.com/\(owner)/\(name)/releases/latest")!
}

/// Um release publicado no GitHub.
struct Release: Equatable, Sendable {
    let version: AppVersion
    /// As notas do release — o que a pessoa lê antes de decidir se atualiza.
    let notes: String
    /// A página do release.
    let pageURL: URL
    /// O `.dmg` anexado, quando existe.
    let downloadURL: URL?

    /// Para onde mandar quem clicou em "Baixar": o instalador, se estiver
    /// anexado; a página, se o release ainda não tiver o `.dmg`.
    var installerURL: URL { downloadURL ?? pageURL }
}

enum UpdateError: LocalizedError {
    case server(Int)
    case unreadableVersion(String)

    var errorDescription: String? {
        switch self {
        case .server(404):
            "Ainda não há nenhum release publicado."
        case .server(403), .server(429):
            "O GitHub pediu para esperar um pouco. Tente de novo mais tarde."
        case .server(let code):
            "O GitHub respondeu \(code)."
        case .unreadableVersion(let tag):
            "Não entendi a versão do release “\(tag)”."
        }
    }
}

/// De onde vêm os releases.
///
/// Uma closure guardada num `struct`, e não um protocolo: o teste troca a fonte
/// numa linha, sem uma classe falsa só para isso.
struct ReleaseFeed: Sendable {
    var latest: @Sendable () async throws -> Release

    static let gitHub = ReleaseFeed {
        var request = URLRequest(url: GitHubRepository.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // Sem cache: uma resposta guardada faria a verificação pedida no menu
        // repetir a versão velha justo depois de o release sair.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.server(http.statusCode)
        }
        return try Release(gitHubJSON: data)
    }
}

extension Release {
    /// Lê a resposta de `/releases/latest` da API do GitHub.
    init(gitHubJSON data: Data) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: data)

        guard let version = AppVersion(payload.tagName) else {
            throw UpdateError.unreadableVersion(payload.tagName)
        }

        self.init(
            version: version,
            notes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pageURL: payload.htmlURL,
            // O `.dmg` é o que o `scripts/dmg.sh` publica; os outros anexos
            // (código-fonte, checksums) não servem para instalar.
            downloadURL: payload.assets.first { $0.name.lowercased().hasSuffix(".dmg") }?.browserDownloadURL
        )
    }

    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: URL
        let body: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body, assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}
