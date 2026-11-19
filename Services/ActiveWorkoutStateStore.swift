import Foundation

// MARK: - Persistencia de la sesión de entrenamiento activa

struct PersistedWorkoutSet: Codable, Hashable {
    var routineExerciseID: UUID
    var setNumber: Int
    var weight: Double
    var reps: Int
    var date: Date
}

struct PersistedBPMPoint: Codable, Hashable {
    var timestamp: Date
    var bpm: Int
}

struct PersistedWorkoutState: Codable, Hashable {
    var activeWorkoutID: UUID
    var routineID: UUID
    var workoutStartDate: Date
    var completedSets: [PersistedWorkoutSet]
    var restTimerEndDate: Date?
    /// Lecturas de BPM de los últimos minutos. Opcional para mantener la
    /// compatibilidad con estados guardados por versiones anteriores.
    var bpmHistory: [PersistedBPMPoint]? = nil
    /// Acumulado y número de lecturas de toda la sesión para calcular el BPM
    /// medio real. Opcionales por compatibilidad con estados anteriores.
    var bpmTotal: Int? = nil
    var bpmCount: Int? = nil

    // Estado auxiliar para reanudar el temporizador exactamente donde se quedó.
    var timerStartDate: Date?
    var totalRestSeconds: Int
    var restTimeRemaining: Int
    var isResting: Bool
    var isRestPaused: Bool
    var isRestTimerActive: Bool
    var isTimerMinimized: Bool
    var restCondition: RestCondition?
    var restTargetBpm: Int?
    var currentExerciseName: String
    var currentRestModeTitle: String
    var restingSetNumber: Int
    var restingTotalSets: Int

    /// Cronómetro por serie que estaba en marcha. Opcionales para poder leer
    /// estados guardados antes de existir este campo.
    var stopwatchRoutineExerciseID: UUID? = nil
    var stopwatchSetIndex: Int? = nil
    var stopwatchStartDate: Date? = nil

    var updatedAt: Date

    /// Versión del formato del snapshot. Opcional para leer estados antiguos
    /// (que se tratan como versión 1).
    var schemaVersion: Int? = nil

    /// Comprobaciones mínimas antes de reanudar un entrenamiento guardado.
    /// Un estado incoherente es más peligroso que no reanudar nada.
    var isPlausible: Bool {
        guard completedSets.count <= 2_000 else { return false }
        guard totalRestSeconds >= 0, restTimeRemaining >= 0 else { return false }
        guard restingSetNumber >= 0, restingTotalSets >= 0 else { return false }
        guard workoutStartDate <= updatedAt.addingTimeInterval(3_600) else { return false }
        guard (bpmCount ?? 0) >= 0 else { return false }
        return true
    }
}

enum ActiveWorkoutStateStore {
    private static let storageKey = "activeWorkoutState.v1"
    /// Último estado ilegible, conservado para diagnóstico en lugar de borrarlo
    /// sin más.
    private static let quarantineKey = "activeWorkoutState.v1.corrupt"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static var defaults: UserDefaults { UserDefaults.standard }

    static func save(_ state: PersistedWorkoutState) {
        guard let data = try? encoder.encode(state) else {
            // No se pisa el estado anterior con un contenido inválido.
            print("[Persistence] No se pudo codificar el estado del entrenamiento; se conserva el anterior.")
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    static func load() -> PersistedWorkoutState? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }

        do {
            let state = try decoder.decode(PersistedWorkoutState.self, from: data)
            guard state.isPlausible else {
                print("[Persistence] Estado de entrenamiento incoherente; se descarta para reanudar de forma segura.")
                quarantine(data)
                defaults.removeObject(forKey: storageKey)
                return nil
            }
            return state
        } catch {
            // Estado ilegible (datos corruptos o de una versión incompatible):
            // se conserva una copia antes de volver a la pantalla principal.
            print("[Persistence] No se pudo leer el estado del entrenamiento: \(error)")
            quarantine(data)
            defaults.removeObject(forKey: storageKey)
            return nil
        }
    }

    private static func quarantine(_ data: Data) {
        defaults.set(data, forKey: quarantineKey)
    }

    static func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    static var hasActiveWorkout: Bool {
        load() != nil
    }
}
