import ActivityKit
import Combine
import Foundation

final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    struct Snapshot {
        var exerciseName: String
        var completedSets: [LiveActivityCompletedSet]
        var restStartDate: Date?
        var restEndDate: Date?
        var isResting: Bool

        static var empty: Snapshot {
            Snapshot(
                exerciseName: "",
                completedSets: [],
                restStartDate: nil,
                restEndDate: nil,
                isResting: false
            )
        }
    }

    @Published private(set) var debugMessage = "Live Activity pendiente"

    private var currentActivity: Activity<WorkoutActivityAttributes>?
    private var lastState: WorkoutActivityAttributes.ContentState?
    private var snapshot: Snapshot = .empty
    private var bpm = 0
    private var isAppInBackground = false

    /// Instante de la última actualización enviada a ActivityKit. Limita las
    /// actualizaciones provocadas por el pulso (que llega a 4 Hz desde el
    /// reloj) a una cada `bpmUpdateInterval` segundos.
    private var lastActivityUpdateDate: Date = .distantPast
    private let bpmUpdateInterval: TimeInterval = 2.0
    private var pendingBPMUpdateTask: Task<Void, Never>?

    private let staleMargin: TimeInterval = 14_400

    // Arranque diferido de la Live Activity: `Activity.request` se ejecuta en
    // un Task sobre el MainActor para que el paso a `.background` no lo corte
    // a mitad de la solicitud.
    private var pendingStartTask: Task<Void, Never>?
    private var pendingWorkoutName: String?
    private var startAttempts = 0
    private let maxStartAttempts = 3

    private init() {}

    // MARK: - Ciclo de vida de la app

    /// La app pasa a segundo plano: conservamos intacto el estado actual de la
    /// Live Activity (incluido `restEndDate`) para que Dynamic Island y la
    /// pantalla bloqueada no pierdan el temporizador.
    func handleScenePhaseBackground() {
        isAppInBackground = true
    }

    func handleScenePhaseActive() {
        isAppInBackground = false
        beginPendingStartIfNeeded()
    }

    // MARK: - Inicio

    func startActivity(workoutName: String, snapshot: Snapshot, bpm: Int) {
        self.snapshot = snapshot
        self.bpm = max(0, bpm)
        self.pendingWorkoutName = workoutName
        self.startAttempts = 0
        self.lastActivityUpdateDate = .distantPast

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            currentActivity = nil
            lastState = nil
            pendingWorkoutName = nil
            debugMessage = "Live Activities desactivadas en Ajustes de iOS"
            print("[LiveActivity] Desactivadas en Ajustes de iOS")
            return
        }

        if let activity = currentActivity, isUsable(activity) {
            debugMessage = "Live Activity ya activa; datos actualizados"
            updateActivity(state: makeState())
            return
        }

        let existingActivities: [Activity<WorkoutActivityAttributes>] = Activity<WorkoutActivityAttributes>.activities
        if let existingActivity = existingActivities.first(where: { isUsable($0) }) {
            currentActivity = existingActivity
            lastState = nil
            pendingWorkoutName = nil
            debugMessage = "Live Activity existente reutilizada"

            // Al reutilizar una actividad cerramos las demás del mismo tipo:
            // si quedó alguna huérfana de una sesión anterior, no debe seguir
            // ocupando la Dynamic Island en paralelo.
            let duplicates: [Activity<WorkoutActivityAttributes>] = existingActivities.filter { (activity: Activity<WorkoutActivityAttributes>) -> Bool in
                return activity.id != existingActivity.id
            }
            if !duplicates.isEmpty {
                Task {
                    for activity in duplicates {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                }
            }

            updateActivity(state: makeState())
            return
        }

        beginPendingStartIfNeeded()
    }

    private func beginPendingStartIfNeeded() {
        guard currentActivity == nil,
              pendingStartTask == nil,
              let workoutName = pendingWorkoutName else { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            pendingWorkoutName = nil
            debugMessage = "Live Activities desactivadas en Ajustes de iOS"
            return
        }

        guard startAttempts < maxStartAttempts else {
            debugMessage = "No se pudo iniciar la Live Activity tras varios intentos"
            return
        }

        startAttempts += 1
        pendingStartTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Dejamos que termine el ciclo de vida actual antes de solicitar
            // la actividad; así el cambio a segundo plano no interrumpe nada.
            await Task.yield()

            defer { self.pendingStartTask = nil }

            guard !Task.isCancelled, self.currentActivity == nil else { return }

            do {
                // Evitar duplicados: cualquier actividad previa del mismo tipo
                // se cierra antes de solicitar la nueva.
                await self.endAllActivities()

                let attributes = WorkoutActivityAttributes(workoutName: workoutName)
                let state = self.makeState()
                let activity = try Activity<WorkoutActivityAttributes>.request(
                    attributes: attributes,
                    content: self.makeContent(for: state),
                    pushType: nil
                )

                guard !Task.isCancelled else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    return
                }

                self.currentActivity = activity
                self.lastState = state
                self.lastActivityUpdateDate = Date()
                self.pendingWorkoutName = nil
                self.startAttempts = 0
                self.debugMessage = "Live Activity iniciada correctamente"
                print("[LiveActivity] Iniciada con éxito con ID: \(activity.id)")
            } catch {
                self.currentActivity = nil
                self.lastState = nil
                self.debugMessage = "Error al iniciar Live Activity: \(error.localizedDescription)"
                print("[LiveActivity] ERROR al iniciar: \(error.localizedDescription)")
                self.scheduleStartRetryIfNeeded()
            }
        }
    }

    private func scheduleStartRetryIfNeeded() {
        guard pendingWorkoutName != nil, startAttempts < maxStartAttempts else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.beginPendingStartIfNeeded()
        }
    }

    // MARK: - Actualizaciones

    /// Sincronización inmediata de eventos (series, ejercicio, descanso).
    /// Se envía siempre: `updateActivity` descarta estados idénticos y así no
    /// se consume presupuesto de ActivityKit sin motivo.
    func updateSnapshot(_ snapshot: Snapshot, bpm: Int? = nil) {
        var resolvedSnapshot = snapshot

        // Nunca borramos un descanso que sigue vigente por una actualización
        // que llega mientras la app está en segundo plano.
        if isAppInBackground,
           !resolvedSnapshot.isResting,
           self.snapshot.isResting,
           let endDate = self.snapshot.restEndDate,
           endDate > Date() {
            resolvedSnapshot.isResting = true
            resolvedSnapshot.restStartDate = self.snapshot.restStartDate
            resolvedSnapshot.restEndDate = endDate
        }

        self.snapshot = resolvedSnapshot
        if let bpm {
            self.bpm = max(0, bpm)
        }
        updateActivity(state: makeState())
    }

    /// Actualización de pulso con throttling: como máximo una mutación del
    /// `ContentState` cada 2 segundos. El temporizador nativo del widget sigue
    /// avanzando por su cuenta entre actualizaciones.
    func setBPM(_ bpm: Int) {
        let value = max(0, bpm)
        guard value != self.bpm else { return }
        self.bpm = value

        guard let activity = currentActivity, isUsable(activity) else { return }

        let elapsed: TimeInterval = Date().timeIntervalSince(lastActivityUpdateDate)
        if elapsed >= bpmUpdateInterval {
            updateActivity(state: makeState())
        } else {
            schedulePendingBPMUpdate(after: bpmUpdateInterval - elapsed)
        }
    }

    private func schedulePendingBPMUpdate(after delay: TimeInterval) {
        guard pendingBPMUpdateTask == nil else { return }

        pendingBPMUpdateTask = Task { @MainActor [weak self] in
            let nanoseconds: UInt64 = UInt64(max(0.1, delay) * 1_000_000_000.0)
            try? await Task.sleep(nanoseconds: nanoseconds)

            guard let self, !Task.isCancelled else { return }
            self.pendingBPMUpdateTask = nil
            self.updateActivity(state: self.makeState())
        }
    }

    func updateActivity(state: WorkoutActivityAttributes.ContentState) {
        guard let activity = currentActivity else { return }

        guard isUsable(activity) else {
            currentActivity = nil
            lastState = nil
            debugMessage = "Live Activity finalizada por el sistema"
            return
        }

        guard lastState != state else { return }
        lastState = state
        lastActivityUpdateDate = Date()

        let content = makeContent(for: state)
        Task {
            await activity.update(content)
        }
    }

    // MARK: - Cierre

    /// Limpieza total: finaliza TODAS las actividades activas del tipo, no solo
    /// la registrada en memoria, para que la Dynamic Island nunca se quede
    /// bloqueada tras terminar o cancelar la rutina.
    func endActivity() {
        pendingStartTask?.cancel()
        pendingStartTask = nil
        pendingBPMUpdateTask?.cancel()
        pendingBPMUpdateTask = nil
        pendingWorkoutName = nil
        startAttempts = 0

        currentActivity = nil
        lastState = nil
        lastActivityUpdateDate = .distantPast
        debugMessage = "Live Activity finalizada"

        // Capturamos la lista ahora mismo: si el usuario inicia otra rutina
        // justo después, este cierre no debe alcanzar la actividad nueva.
        let activities: [Activity<WorkoutActivityAttributes>] = Activity<WorkoutActivityAttributes>.activities
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func endAllActivities() async {
        let activities: [Activity<WorkoutActivityAttributes>] = Activity<WorkoutActivityAttributes>.activities
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func isUsable(_ activity: Activity<WorkoutActivityAttributes>) -> Bool {
        switch activity.activityState {
        case .active, .stale:
            return true
        case .ended, .dismissed:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Estado

    private func makeState() -> WorkoutActivityAttributes.ContentState {
        let restEndDate: Date = snapshot.restEndDate ?? .distantPast
        let restStartDate: Date = snapshot.restStartDate ?? restEndDate
        let isResting: Bool = snapshot.isResting && snapshot.restEndDate != nil

        return WorkoutActivityAttributes.ContentState(
            exerciseName: snapshot.exerciseName,
            completedSets: snapshot.completedSets,
            currentBPM: max(0, bpm),
            isResting: isResting,
            restStartDate: restStartDate,
            restEndDate: restEndDate
        )
    }

    private func makeContent(
        for state: WorkoutActivityAttributes.ContentState
    ) -> ActivityContent<WorkoutActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(staleMargin)
        )
    }
}
