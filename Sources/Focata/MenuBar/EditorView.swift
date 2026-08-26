import SwiftUI

/// O campo de texto da caixa da tarefa. Um campo, e só.
///
/// Não há janela principal no Focata: toda a edição acontece no `TaskPanelView`,
/// que é este campo com uma barra de título por cima.
struct EditorView: View {
    @Bindable var task: TaskStore
    /// Chamado por `return` ou `esc` — os dois fecham o editor (§2 da spec).
    var onDismiss: () -> Void
    /// Muda a cada vez que a caixa reaparece. A janela não é recriada ao
    /// minimizar, então `onAppear` só devolveria o cursor ao campo na primeira
    /// abertura.
    var focusToken: Int = 0

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("No que você vai focar?", text: $task.text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .lineLimit(1...4)
            .focused($isFocused)
            .onSubmit(onDismiss)
            .onExitCommand(perform: onDismiss)
            .padding(12)
            .onAppear { isFocused = true }
            .onChange(of: focusToken) { isFocused = true }
    }
}
