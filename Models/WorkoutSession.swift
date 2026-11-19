import Foundation
import SwiftData

// MARK: - Muestras de pulso

/// Muestra individual de frecuencia cardíaca asociada a la sesión.
/// Se persiste codificada dentro de `WorkoutSession` para mantener el modelo
/// retrocompatible con sesiones creadas antes de existir este campo.
public struct BPMSample: Codable, Hashable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var bpm: Double

    public init(id: UUID = UUID(), timestamp: Date, bpm: Double) {
        self.id = id
        self.timestamp = timestamp
        self.bpm = bpm
    }
}

// MARK: - Registros detallados por ejercicio y serie

/// Marca temporal y carga de una serie completada.
public struct WorkoutSetRecord: Codable, Hashable, Identifiable {
    public var id: UUID
    public var setNumber: Int
    public var weight: Double
    public var reps: Int
    public var setCompletedTime: Date
    /// Descanso real hasta la siguiente serie completada (incluye el cambio de
    /// ejercicio). Cero en la última serie de la sesión.
    public var restDuration: TimeInterval

    public init(
        id: UUID = UUID(),
        setNumber: Int,
        weight: Double,
        reps: Int,
        setCompletedTime: Date,
        restDuration: TimeInterval
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.setCompletedTime = setCompletedTime
        self.restDuration = restDuration
    }
}

/// Bloque de ejecución de un ejercicio dentro de una sesión.
public struct WorkoutExerciseRecord: Codable, Hashable, Identifiable {
    public var id: UUID
    public var exerciseID: UUID?
    public var exerciseName: String
    public var exerciseStartTime: Date
    public var exerciseEndTime: Date
    public var sets: [WorkoutSetRecord]

    public init(
        id: UUID,
        exerciseID: UUID?,
        exerciseName: String,
        exerciseStartTime: Date,
        exerciseEndTime: Date,
        sets: [WorkoutSetRecord]
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.exerciseStartTime = exerciseStartTime
        self.exerciseEndTime = exerciseEndTime
        self.sets = sets
    }
}

// MARK: - Sesión

@Model
public final class WorkoutSession {
    public var id: UUID
    public var startDate: Date
    public var endDate: Date?
    public var totalVolumeKg: Double
    /// Nombre de la rutina ejecutada. Se guarda para poder listar sesiones
    /// históricas desde el calendario sin depender de relaciones eliminadas.
    public var routineName: String = ""

    /// Datos codificados de muestras de pulso. Opcional para que SwiftData
    /// pueda migrar sesiones antiguas sin registros.
    public var bpmSamplesData: Data? = nil
    /// Datos codificados de los registros detallados por ejercicio.
    public var exerciseRecordsData: Data? = nil

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSetLog.session)
    public var setsCompleted: [WorkoutSetLog] = []

    /// Historial completo de pulsaciones de la sesión.
    ///
    /// La lectura de datos ilegibles devuelve una lista vacía para no romper la
    /// interfaz, y la escritura es **no destructiva**: si la codificación falla
    /// se conserva el valor anterior en lugar de dejar el campo a cero y perder
    /// el histórico ya guardado.
    @Transient
    public var bpmSamples: [BPMSample] {
        get {
            guard let bpmSamplesData, !bpmSamplesData.isEmpty else { return [] }
            do {
                return try JSONDecoder().decode([BPMSample].self, from: bpmSamplesData)
            } catch {
                print("[Persistence] Muestras de BPM ilegibles: \(error)")
                return []
            }
        }
        set {
            do {
                bpmSamplesData = try JSONEncoder().encode(newValue)
            } catch {
                print("[Persistence] No se pudieron codificar las muestras de BPM; se conservan las anteriores: \(error)")
            }
        }
    }

    /// Registros detallados de ejercicios y series con sus marcas temporales.
    /// Mismo criterio que `bpmSamples`: nunca se sobrescribe con datos vacíos.
    @Transient
    public var exerciseRecords: [WorkoutExerciseRecord] {
        get {
            guard let exerciseRecordsData, !exerciseRecordsData.isEmpty else { return [] }
            do {
                return try JSONDecoder().decode([WorkoutExerciseRecord].self, from: exerciseRecordsData)
            } catch {
                print("[Persistence] Registros de ejercicios ilegibles: \(error)")
                return []
            }
        }
        set {
            do {
                exerciseRecordsData = try JSONEncoder().encode(newValue)
            } catch {
                print("[Persistence] No se pudieron codificar los registros de ejercicios; se conservan los anteriores: \(error)")
            }
        }
    }

    public init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        endDate: Date? = nil,
        totalVolumeKg: Double = 0.0,
        routineName: String = "",
        setsCompleted: [WorkoutSetLog] = []
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.totalVolumeKg = totalVolumeKg
        self.routineName = routineName
        self.setsCompleted = setsCompleted
    }
}

@Model
public final class WorkoutSetLog {
    public var id: UUID
    public var date: Date
    public var workoutStartDate: Date?
    public var weight: Double
    public var reps: Int
    public var targetRepsMin: Int = 8
    public var targetRepsMax: Int = 12
    public var isCompleted: Bool
    public var routineExerciseID: UUID?
    public var setNumber: Int?

    public var exercise: Exercise?
    public var session: WorkoutSession?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        workoutStartDate: Date? = nil,
        weight: Double = 0.0,
        reps: Int = 0,
        targetRepsMin: Int = 8,
        targetRepsMax: Int = 12,
        isCompleted: Bool = false,
        routineExerciseID: UUID? = nil,
        setNumber: Int? = nil,
        exercise: Exercise? = nil,
        session: WorkoutSession? = nil
    ) {
        self.id = id
        self.date = date
        self.workoutStartDate = workoutStartDate
        self.weight = weight
        self.reps = reps
        self.targetRepsMin = targetRepsMin
        self.targetRepsMax = targetRepsMax
        self.isCompleted = isCompleted
        self.routineExerciseID = routineExerciseID
        self.setNumber = setNumber
        self.exercise = exercise
        self.session = session
    }
}
