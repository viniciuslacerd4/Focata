import Foundation

/// Um número de versão comparável.
///
/// Comparar as strings direto diria que "0.10.0" vem antes de "0.9.0" — o erro
/// que só aparece na décima versão, quando já está tarde. Aqui a comparação é
/// número a número.
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    /// Os componentes, do mais significativo para o menos.
    let numbers: [Int]

    /// A forma normalizada (sem o `v`), para mostrar na tela.
    let description: String

    /// Aceita `1.2.3`, `v1.2.3` e `1.2` — o `v` das tags do Git entra e sai.
    ///
    /// Um sufixo de pré-lançamento (`1.2.3-beta`) devolve `nil` em vez de ser
    /// ignorado: tratá-lo como `1.2.3` acabaria oferecendo uma beta a quem só
    /// pediu a versão estável.
    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed

        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }

        var numbers: [Int] = []
        for part in parts {
            guard part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }

        self.numbers = numbers
        description = digits
    }

    /// A versão deste app, lida do `Info.plist`.
    static let current: AppVersion = {
        let string = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        // O `!` é seguro: o literal sempre lê. Ele só entra em cena se o
        // `Info.plist` vier sem `CFBundleShortVersionString`, e uma versão zero
        // é justamente o que faz qualquer release publicado parecer mais novo.
        return AppVersion(string ?? "") ?? AppVersion("0.0.0")!
    }()

    /// Componentes faltando contam como zero: `1.2` e `1.2.0` são a mesma versão.
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
