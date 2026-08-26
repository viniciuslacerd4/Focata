import Foundation

/// Uma entrada do histórico: tarefa, nº de pomodoros e data (§6 da spec).
struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable {
        /// Fechada por você.
        case completed
        /// Largada pelo caminho — útil para perceber o que costuma travar.
        case abandoned

        var label: String {
            switch self {
            case .completed: "Concluída"
            case .abandoned: "Abandonada"
            }
        }
    }

    var id: UUID = UUID()
    var text: String
    var pomodoros: Int
    var finishedAt: Date
    var outcome: Outcome
}
