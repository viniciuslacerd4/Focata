import Foundation

/// Fonte do tempo, injetável.
///
/// O Pomodoro deriva tudo de datas absolutas, então os testes conseguem simular
/// 25 minutos — ou um Mac dormindo 40 — sem esperar nada.
struct Clock: Sendable {
    var now: @Sendable () -> Date

    static let system = Clock(now: { Date() })
}
