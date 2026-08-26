import AppKit

/// Alvo de arrastar-e-soltar sobre o item da barra: solte um item do Lembretes,
/// do Things ou um texto qualquer e ele vira a tarefa em foco (§2 da spec).
///
/// Precisa ser uma subview real porque as callbacks de arraste vêm de
/// `NSDraggingDestination`, que não dá para implementar sem subclasse — e o
/// `NSStatusBarButton` não é nosso para subclassar. Os cliques são repassados ao
/// botão em vez de a view se esconder do hit test: sumir do hit test mataria
/// também o alvo de arraste.
final class StatusItemDragView: NSView {
    var onDrop: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string, .URL, .fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

    // MARK: - Cliques continuam sendo do botão

    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        superview?.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        superview?.otherMouseDown(with: event)
    }

    // MARK: - Arraste

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        text(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let text = text(from: sender.draggingPasteboard) else { return false }
        onDrop?(text)
        return true
    }

    /// Um item do Lembretes chega como string; um link, como URL. Preferimos a
    /// string porque é o título legível.
    private func text(from pasteboard: NSPasteboard) -> String? {
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let url = NSURL(from: pasteboard) as URL? {
            return url.isFileURL ? url.lastPathComponent : url.absoluteString
        }
        return nil
    }
}
