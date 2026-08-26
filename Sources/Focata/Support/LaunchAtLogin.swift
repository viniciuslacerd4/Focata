import ServiceManagement

/// Abrir junto com o Mac, via `SMAppService` — a API moderna, que não exige
/// um helper de login separado nem entradas em `~/Library/LaunchAgents`.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Focata: falha ao alterar 'abrir com o Mac': \(error.localizedDescription)")
            }
        }
    }
}
