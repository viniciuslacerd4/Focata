import AppKit
import UserNotifications

/// Avisos curtos no topo da tela a cada troca de modo (§3 da spec).
///
/// Notificação nativa, discreta, que some sozinha — e som só se você pedir,
/// para manter o padrão silencioso do app.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private var didRequestAuthorization = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// A permissão é pedida no primeiro uso do Pomodoro, não no launch: ninguém
    /// gosta de um app que pede autorização antes de você usar qualquer coisa.
    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("Focata: notificações indisponíveis: \(error.localizedDescription)")
            } else if !granted {
                NSLog("Focata: notificações não autorizadas")
            }
        }
    }

    /// O texto do aviso. Separado do envio para ser testável sem depender da
    /// permissão do sistema.
    static func message(for transition: PomodoroEngine.Transition, task: String) -> (title: String, body: String) {
        var body = transition.to.isFree ? "Timer livre começou" : "Foco começou"
        // A notificação também confirma quando um pomodoro foi somado à tarefa.
        if transition.earnedPomodoro, !task.isEmpty {
            body += " · +1 pomodoro em “\(task)”"
        }
        return (transition.from.completionTitle, body)
    }

    func notifyTransition(_ transition: PomodoroEngine.Transition, task: String, withSound: Bool) {
        let message = Self.message(for: transition, task: task)
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body

        if withSound { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Focata: falha ao notificar: \(error.localizedDescription)")
            }
        }
    }

    /// Sem isto o macOS engole a notificação sempre que o Focata está ativo —
    /// exatamente o momento em que o editor acabou de ser usado.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
