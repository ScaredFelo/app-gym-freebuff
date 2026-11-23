import Foundation
import UserNotifications

/// Programación del aviso local de fin de descanso.
///
/// La consulta del permiso de notificaciones es asíncrona: entre la petición y
/// su respuesta el usuario puede pausar, cancelar o empezar otro descanso. Por
/// eso cada descanso abre una **generación** nueva y la respuesta solo se aplica
/// si su token sigue siendo el vigente. Una solicitud antigua no puede programar
/// nada después de cancelar, pausar o sustituir el descanso, ni siquiera si su
/// callback llega mucho más tarde.
///
/// La segunda barrera es el propio registro: el token se vuelve a comprobar
/// justo antes de añadir el aviso y, si el registro termina cuando el descanso
/// ya cambió, el aviso recién creado se retira. Así no queda ningún aviso
/// fantasma en el centro de notificaciones.
final class NotificationManager {
    static let shared = NotificationManager()

    /// Identificador del aviso de fin de descanso.
    static let restFinishedIdentifier: String = "REST_TIMER_END"

    /// Contenido ya resuelto del aviso, sin tipos de `UserNotifications`, para
    /// poder comprobar la concurrencia sin depender del centro real.
    struct RestNotification: Equatable {
        let identifier: String
        let title: String
        let body: String
        let timeInterval: TimeInterval
    }

    /// Token opaco de la generación del descanso a la que pertenece una
    /// solicitud. Solo sirve para comprobar que sigue vigente.
    struct RestToken: Equatable {
        let generation: UInt64
    }

    /// Efectos externos, inyectables en las pruebas. En producción apuntan al
    /// centro de notificaciones real.
    struct Dependencies {
        var authorizationStatus: (@escaping (UNAuthorizationStatus) -> Void) -> Void
        var add: (RestNotification, @escaping (Error?) -> Void) -> Void
        var removePending: (String) -> Void
        var removeDelivered: (String) -> Void
        var now: () -> Date

        static var live: Dependencies {
            return Dependencies(
                authorizationStatus: { completion in
                    UNUserNotificationCenter.current().getNotificationSettings { settings in
                        completion(settings.authorizationStatus)
                    }
                },
                add: { notification, completion in
                    let content: UNMutableNotificationContent = UNMutableNotificationContent()
                    content.title = notification.title
                    content.body = notification.body
                    content.sound = UNNotificationSound.default
                    // `.timeSensitive` necesita la capability "Time Sensitive
                    // Notifications" (com.apple.developer.usernotifications.time-sensitive),
                    // que hoy NO está en AppGym.entitlements. Sin ella iOS entrega
                    // el aviso como `.active`: no lanza error ni rompe el build,
                    // solo deja de saltar los controles de Enfoque. Añadir la
                    // capability obliga a regenerar el perfil de aprovisionamiento,
                    // así que se deja documentado en lugar de cambiarlo a ciegas.
                    content.interruptionLevel = .timeSensitive

                    let trigger: UNTimeIntervalNotificationTrigger = UNTimeIntervalNotificationTrigger(
                        timeInterval: notification.timeInterval,
                        repeats: false
                    )
                    let request: UNNotificationRequest = UNNotificationRequest(
                        identifier: notification.identifier,
                        content: content,
                        trigger: trigger
                    )
                    UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
                },
                removePending: { identifier in
                    UNUserNotificationCenter.current().removePendingNotificationRequests(
                        withIdentifiers: [identifier]
                    )
                },
                removeDelivered: { identifier in
                    UNUserNotificationCenter.current().removeDeliveredNotifications(
                        withIdentifiers: [identifier]
                    )
                },
                now: Date.init
            )
        }
    }

    private let dependencies: Dependencies
    private let lock: NSLock = NSLock()
    /// Generación vigente. Cada descanso nuevo y cada cancelación la aumentan.
    private var generation: UInt64 = 0
    /// Token del descanso vigente; `nil` cuando no hay ninguno abierto.
    private var activeToken: RestToken?

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    // MARK: - Permiso

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

    // MARK: - Aviso de fin de descanso

    /// Abre un descanso nuevo y programa su aviso. Devuelve el token de la
    /// generación creada, que invalida cualquier solicitud anterior.
    ///
    /// Programar sin permiso no muestra nada y deja la sensación de que el
    /// temporizador no avisa; por eso se comprueba el permiso antes de añadir.
    @discardableResult
    func scheduleRestFinishedNotification(endingAt endDate: Date) -> RestToken? {
        let token: RestToken = openGeneration()

        // Un descanso nuevo sustituye al anterior: su aviso ya no vale.
        dependencies.removePending(Self.restFinishedIdentifier)
        dependencies.removeDelivered(Self.restFinishedIdentifier)

        let timeInterval: TimeInterval = endDate.timeIntervalSince(dependencies.now())
        guard timeInterval > 0 else { return nil }

        dependencies.authorizationStatus { [weak self] status in
            guard let self else { return }

            guard Self.deliversNotifications(status) else {
                print("[Notifications] Aviso de descanso omitido: sin permiso de notificaciones.")
                return
            }

            self.addIfCurrent(token: token, endDate: endDate)
        }

        return token
    }

    /// Cancela el aviso y cierra la generación vigente: cualquier respuesta
    /// asíncrona pendiente quedará invalidada.
    func cancelRestFinishedNotification() {
        invalidateGeneration()
        dependencies.removePending(Self.restFinishedIdentifier)
        dependencies.removeDelivered(Self.restFinishedIdentifier)
    }

    // MARK: - Generaciones

    private func openGeneration() -> RestToken {
        lock.lock()
        defer { lock.unlock() }

        generation &+= 1
        let token: RestToken = RestToken(generation: generation)
        activeToken = token
        return token
    }

    private func invalidateGeneration() {
        lock.lock()
        defer { lock.unlock() }

        generation &+= 1
        activeToken = nil
    }

    private func isCurrent(_ token: RestToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return activeToken == token
    }

    /// Registra el aviso solo si el token sigue vigente.
    ///
    /// La comprobación y el alta se hacen con la generación bloqueada: un
    /// `cancel()` no puede colarse entre ambas. Si aun así el registro termina
    /// con el descanso ya sustituido (por ejemplo, porque la cancelación se
    /// procesó antes que el alta en el centro de notificaciones), el propio
    /// callback retira el aviso recién creado.
    private func addIfCurrent(token: RestToken, endDate: Date) {
        let remaining: TimeInterval = endDate.timeIntervalSince(dependencies.now())
        guard remaining > 0 else { return }

        let notification: RestNotification = RestNotification(
            identifier: Self.restFinishedIdentifier,
            title: "¡Tiempo de descanso finalizado!",
            body: "Prepara la siguiente serie",
            timeInterval: max(1, remaining)
        )

        lock.lock()
        guard activeToken == token else {
            lock.unlock()
            return
        }

        dependencies.add(notification) { [weak self] error in
            guard let self else { return }

            if let error {
                print("[Notifications] Error programando aviso de descanso: \(error.localizedDescription)")
                return
            }

            guard !self.isCurrent(token) else { return }
            self.dependencies.removePending(Self.restFinishedIdentifier)
            self.dependencies.removeDelivered(Self.restFinishedIdentifier)
        }

        lock.unlock()
    }

    private static func deliversNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }
}
