import KeyboardShortcuts

/// Atalhos globais — funcionam de qualquer app, sem trazer o Focata para frente.
///
/// Nenhum vem com combinação de fábrica: atalhos globais roubam teclas do
/// sistema inteiro, então quem escolhe é você, na aba Atalhos.
extension KeyboardShortcuts.Name {
    static let toggleEditor = Self("toggleEditor")
    static let toggleTimer = Self("toggleTimer")
    static let skipPhase = Self("skipPhase")
    static let completeTask = Self("completeTask")
    static let togglePrivate = Self("togglePrivate")
}

@MainActor
enum GlobalShortcuts {
    static func register(with actions: AppActions) {
        KeyboardShortcuts.onKeyUp(for: .toggleEditor) { actions.openEditor() }
        KeyboardShortcuts.onKeyUp(for: .toggleTimer) { actions.toggleTimer() }
        KeyboardShortcuts.onKeyUp(for: .skipPhase) { actions.skipPhase() }
        KeyboardShortcuts.onKeyUp(for: .completeTask) { actions.completeTask() }
        KeyboardShortcuts.onKeyUp(for: .togglePrivate) { actions.togglePrivate() }
    }
}
