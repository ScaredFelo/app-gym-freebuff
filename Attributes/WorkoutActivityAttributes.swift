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
