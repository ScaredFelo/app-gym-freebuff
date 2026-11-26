import Foundation
import SwiftData

@Model
public final class Routine {
    public var id: UUID
    public var name: String
    /// Semántica real en la app:
    /// - `true`: rutina del plan activo, visible en la lista y editable.
    /// - `false`: rutina temporal del entreno libre, nunca listada.
    /// No identifica plantillas de un catálogo externo ni la procedencia: para
    /// eso está `sourceRaw`.
    public var isTemplate: Bool
    /// Procedencia serializada. Es opcional para que SwiftData pueda añadir la
    /// columna a bases antiguas sin fallar; `nil` se interpreta como `manual`.
    public var sourceRaw: String? = nil
    public var sortOrder: Int = 0
    /// `true` cuando la rutina pertenece a una organización anterior del
    /// entrenamiento. Se archiva en lugar de borrarse para no romper las
    /// relaciones con las sesiones históricas.
    public var isArchived: Bool = false

    // La carpeta de una rutina no se guarda aquí: vive en
    // `RoutineFolder.routineIDsData`. `Routine` no cambia de forma entre la
    // versión 5 y la 6 del esquema, así que la migración solo añade la entidad
    // de carpetas y no toca la tabla de rutinas existente.

    @Relationship(deleteRule: .cascade)
    public var exercises: [RoutineExercise] = []

    /// `true` solo para las rutinas que forman parte del plan activo visible.
    public var isActivePlanRoutine: Bool {
        return isTemplate && !isArchived
    }

    /// `automatic` para las generadas por el plan W/L/U; `assisted` para las
    /// creadas por el constructor de siete días; `manual` para las creadas o
    /// guardadas por el usuario. Los registros anteriores a este campo se
    /// tratan como manuales para no archivarlos por sorpresa.
    public var source: RoutineSource {
        get { sourceRaw.flatMap(RoutineSource.init(rawValue:)) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        isTemplate: Bool = true,
        sortOrder: Int = 0,
        exercises: [RoutineExercise] = [],
        isArchived: Bool = false,
        source: RoutineSource = .manual
    ) {
        self.id = id
        self.name = name
        self.isTemplate = isTemplate
        self.sourceRaw = source.rawValue
        self.sortOrder = sortOrder
        self.exercises = exercises
        self.isArchived = isArchived
    }
}

@Model
public final class RoutineExercise {
    public var id: UUID
    public var defaultSets: Int
    public var targetRepsMin: Int = 8
    public var targetRepsMax: Int = 12
    public var sortOrder: Int
    public var defaultWeight: Double = 0.0
    public var restSeconds: Int = 90
    public var notes: String = ""
    /// `true` cuando el descanso lo ajustó el usuario en la rutina: las
    /// migraciones del catálogo no lo sobrescriben.
    public var hasCustomRest: Bool = false

    @Relationship
    public var exercise: Exercise?

    @Transient
    public var targetRepsText: String {
        "\(targetRepsMin) - \(targetRepsMax)"
    }

    public init(
        id: UUID = UUID(),
        exercise: Exercise?,
        defaultSets: Int = 3,
        targetRepsMin: Int = 8,
        targetRepsMax: Int = 12,
        sortOrder: Int = 0,
        defaultWeight: Double = 0.0,
        restSeconds: Int? = nil,
        notes: String = "",
        hasCustomRest: Bool = false
    ) {
        self.id = id
        self.exercise = exercise
        self.defaultSets = defaultSets
        let lower = max(1, min(targetRepsMin, targetRepsMax))
        self.targetRepsMin = lower
        self.targetRepsMax = max(lower, targetRepsMax)
        self.sortOrder = sortOrder
        self.defaultWeight = defaultWeight
        self.notes = notes
        self.hasCustomRest = hasCustomRest

        if let restSeconds {
            self.restSeconds = restSeconds
        } else if let exercise, case let .timer(seconds) = exercise.defaultRestCondition {
            self.restSeconds = seconds
        } else {
            self.restSeconds = 90
        }
    }
}

extension RoutineExercise {
    /// Sustituye el ejercicio de la fila conservando su identidad y toda su
    /// configuración: series, rango de repeticiones, orden, peso, descanso,
    /// `hasCustomRest` y notas.
    ///
    /// Es el único punto de mutación de la sustitución: no crea ni elimina
    /// `RoutineExercise`, no reordena la rutina y no toca los registros
    /// históricos (que apuntan al ejercicio anterior por su propia relación).
    /// Devuelve `false` cuando el ejercicio elegido ya era el de la fila.
    @discardableResult
    public func replaceExercise(with exercise: Exercise) -> Bool {
        guard self.exercise?.id != exercise.id else { return false }
        self.exercise = exercise
        return true
    }
}
