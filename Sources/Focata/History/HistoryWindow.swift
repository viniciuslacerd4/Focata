import AppKit
import SwiftUI

/// Um registro enxuto, no espírito do app: tarefa, pomodoros e data.
/// Sem gráficos — só o suficiente para olhar para trás e reconhecer padrões.
struct HistoryView: View {
    @Bindable var history: HistoryStore
    @State private var confirmingClearAll = false

    var body: some View {
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                ContentUnavailableView(
                    "Nada no histórico ainda",
                    systemImage: "clock",
                    description: Text("Tarefas concluídas e abandonadas aparecem aqui. Sessões privadas, nunca.")
                )
                // Sem esticar, o bloco vazio fica do tamanho do seu conteúdo e a
                // `VStack` centraliza tudo, deixando um vão embaixo do rodapé.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(history.entries) { entry in
                        HistoryRow(entry: entry) { history.delete(entry) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Divider()

            HStack {
                Text(resumo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Limpar tudo", role: .destructive) { confirmingClearAll = true }
                    .disabled(history.entries.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 460, height: 420)
        .background(VisualEffectBackground())
        .confirmationDialog(
            "Apagar todo o histórico?",
            isPresented: $confirmingClearAll
        ) {
            Button("Apagar tudo", role: .destructive) { history.deleteAll() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Isso remove todas as entradas, concluídas e abandonadas. Não dá para desfazer.")
        }
    }

    private var resumo: String {
        let concluidas = history.entries.filter { $0.outcome == .completed }.count
        let abandonadas = history.entries.count - concluidas
        let pomodoros = history.entries.reduce(0) { $0 + $1.pomodoros }
        return "\(concluidas) concluída(s) · \(abandonadas) abandonada(s) · \(pomodoros) pomodoro(s)"
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onDelete: () -> Void

    /// O mesmo Markdown inline da barra: negrito, itálico, tachado e links.
    ///
    /// A entrada guarda o texto cru, e quem mostra é que decide como exibi-lo.
    /// Sem isto o histórico entrega os `**` na cara, e a mesma tarefa aparece de
    /// um jeito na barra e de outro aqui.
    private var rendered: AttributedString {
        (try? AttributedString(
            markdown: entry.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(entry.text)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(entry.outcome == .completed ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(rendered)
                    .lineLimit(2)
                Text("\(entry.outcome.label) · \(entry.finishedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(entry.pomodoros) 🍅")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Apagar esta entrada")
        }
        .padding(.vertical, 4)
    }
}

/// Janela do histórico, criada à mão pelo mesmo motivo da de configurações: o
/// app usa ciclo de vida AppKit e precisa se ativar para receber foco.
@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: HistoryView(history: HistoryStore.shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Histórico do Focata"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            // O mesmo escuro translúcido da caixa da tarefa.
            window.adoptTranslucentBackground()
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
