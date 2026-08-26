import Foundation

/// Pilota o Focata pelo terminal ou por qualquer app que abra URLs.
///
/// A forma `focata:?text=...` é deliberadamente igual à do One Thing, para que
/// automações existentes continuem valendo:
/// ```
/// open --background 'focata:?text=Exercitar'
/// open --background 'focata://start'
/// open --background 'focata://private?on=1'
/// ```
@MainActor
enum URLSchemeHandler {
    static func handle(_ url: URL, actions: AppActions) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let query = components.queryItems ?? []

        // `focata:?text=...` — define a tarefa. Vem antes das ações porque é a
        // forma compatível com o One Thing e não tem host.
        if let text = query.first(where: { $0.name == "text" })?.value {
            actions.setText(text)
            return
        }

        // `focata://acao` — o host carrega a ação; se vier vazio, tentamos o path.
        let action = components.host ?? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        switch action {
        case "start": actions.startTimer()
        case "pause": actions.pauseTimer()
        case "toggle": actions.toggleTimer()
        case "skip": actions.skipPhase()
        case "reset": actions.resetTimer()
        case "complete": actions.completeTask()
        case "clear": actions.clearTask()
        case "edit": actions.openEditor()
        case "private":
            // Sem `on`, alterna; com `on=1`/`on=0`, define.
            if let value = query.first(where: { $0.name == "on" })?.value {
                actions.setPrivate(["1", "true", "yes", "sim"].contains(value.lowercased()))
            } else {
                actions.togglePrivate()
            }
        default:
            NSLog("Focata: ação de URL desconhecida: \(action)")
        }
    }
}
