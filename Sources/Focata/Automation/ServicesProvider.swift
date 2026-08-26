import AppKit

/// "Serviços › Enviar para o Focata": selecione texto em qualquer app e mande
/// direto para a barra (§2 da spec).
@MainActor
final class ServicesProvider: NSObject {
    private let actions: AppActions

    init(actions: AppActions) {
        self.actions = actions
        super.init()
    }

    @objc func sendToFocata(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            error.pointee = "Nenhum texto selecionado." as NSString
            return
        }

        actions.setText(text)
    }
}
