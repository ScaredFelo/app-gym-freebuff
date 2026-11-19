import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private let restFinishedIdentifier = "REST_TIMER_END"

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                print("[Notifications] Error solicitando permiso: \(error.localizedDescription)")
            } else {
                print("[Notifications] Permiso concedido: \(granted)")
            }
        }
    }

    /// Programa el aviso de fin de descanso solo si el usuario ha autorizado
    /// las notificaciones: programarlo sin permiso no muestra nada y deja la
    /// sensación de que el temporizador no avisa.
    func scheduleRestFinishedNotification(endingAt endDate: Date) {
        cancelRestFinishedNotification()

        let timeInterval = endDate.timeIntervalSince(Date())
        guard timeInterval > 0 else { return }

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.addRestFinishedNotification(timeInterval: timeInterval)
            default:
                print("[Notifications] Aviso de descanso omitido: sin permiso de notificaciones.")
            }
        }
    }

    private func addRestFinishedNotification(timeInterval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "¡Tiempo de descanso finalizado!"
        content.body = "Prepara la siguiente serie"
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, timeInterval),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: restFinishedIdentifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Notifications] Error programando aviso de descanso: \(error.localizedDescription)")
            } else {
                print("[Notifications] Aviso de descanso programado en \(Int(timeInterval))s")
            }
        }
    }

    func cancelRestFinishedNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [restFinishedIdentifier]
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [restFinishedIdentifier]
        )
    }
}
