import ActivityKit
import Foundation

// MARK: - Modelo compartido (targets AppGym y AppGymWidgets)

/// Serie ya completada dentro del ejercicio activo. Se envía a la Live
/// Activity para poder listarla como "Serie 1: 80 kg × 10".
public struct LiveActivityCompletedSet: Codable, Hashable, Identifiable {
    /// Número de serie dentro del ejercicio: 1, 2, 3...
    public var id: Int
    public var weight: Double
    public var reps: Int

    public init(id: Int, weight: Double, reps: Int) {
        self.id = id
        self.weight = weight
        self.reps = reps
    }
}

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var exerciseName: String
        /// Series completadas del ejercicio actual durante esta sesión.
        public var completedSets: [LiveActivityCompletedSet]
        public var currentBPM: Int
        public var isResting: Bool
        public var restStartDate: Date
        public var restEndDate: Date

        public init(
            exerciseName: String,
            completedSets: [LiveActivityCompletedSet],
            currentBPM: Int,
            isResting: Bool,
            restStartDate: Date,
            restEndDate: Date
        ) {
            self.exerciseName = exerciseName
            self.completedSets = completedSets
            self.currentBPM = currentBPM
            self.isResting = isResting
            self.restStartDate = restStartDate
            self.restEndDate = restEndDate
        }

        /// Rango seguro para `ProgressView(timerInterval:)` y `Text(timerInterval:)`.
        /// Nunca es decreciente, así que un descanso sin fechas válidas no rompe
        /// el renderizado del widget.
        public var restRange: ClosedRange<Date> {
            if restEndDate > restStartDate {
                return restStartDate...restEndDate
            }
            return restStartDate...restStartDate
        }

    }

    public var workoutName: String

    public init(workoutName: String) {
        self.workoutName = workoutName
    }
}

// MARK: - Live Activity de cardio

/// Atributos de la Live Activity de una sesión de cardio: modalidad y estado
/// del cronómetro. La cuenta atrás se dibuja con el temporizador nativo del
/// sistema, así sigue avanzando con la pantalla bloqueada.
public struct CardioActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var typeName: String
        public var startedAt: Date
        public var endDate: Date
        public var currentBPM: Int
        public var isPaused: Bool
        /// Tiempo restante congelado mientras la sesión está en pausa.
        public var pausedRemaining: TimeInterval
        /// Fracción completada; se usa para la barra estática en pausa.
        public var progress: Double

        public init(
            typeName: String,
            startedAt: Date,
            endDate: Date,
            currentBPM: Int,
            isPaused: Bool,
            pausedRemaining: TimeInterval,
            progress: Double
        ) {
            self.typeName = typeName
            self.startedAt = startedAt
            self.endDate = endDate
            self.currentBPM = currentBPM
            self.isPaused = isPaused
            self.pausedRemaining = pausedRemaining
            self.progress = progress
        }

        /// Rango seguro para `Text(timerInterval:)` y `ProgressView(timerInterval:)`.
        public var timerRange: ClosedRange<Date> {
            return endDate > startedAt ? startedAt...endDate : startedAt...startedAt
        }
    }

    public var sessionName: String

    public init(sessionName: String) {
        self.sessionName = sessionName
    }
}
