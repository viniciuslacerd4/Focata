import Foundation
import Observation

/// O registro datado de concluídas e abandonadas.
///
/// JSON em Application Support, e não SwiftData: o histórico é uma lista curta
/// que precisa ser fácil de apagar item a item, exportar e versionar — sem
/// migrações de schema no caminho.
@MainActor
@Observable
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Focata", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }

    /// Grava uma entrada. Mais recente primeiro.
    func record(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    /// Desfaz a última conclusão desta tarefa.
    ///
    /// Casa pelo texto, e não por um id guardado em memória, para que desmarcar
    /// continue funcionando depois de fechar e reabrir o app. As entradas vêm da
    /// mais recente para a mais antiga, então a primeira que casa é a certa.
    func undoCompletion(of text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = entries.firstIndex(
            where: { $0.outcome == .completed && $0.text == trimmed }
        ) else { return }
        entries.remove(at: index)
        save()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func deleteAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Disco

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        // Escrita atômica: um crash no meio não pode deixar o histórico truncado.
        try? data.write(to: fileURL, options: .atomic)
    }
}
