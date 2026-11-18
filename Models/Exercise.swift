import Foundation
import SwiftData

@Model
public final class Exercise {
    public var id: UUID
    public var name: String
    public var muscleGroupRaw: String
    public var equipmentTypeRaw: String
    public var requiresStraps: Bool
    public var targetRepsMin: Int = 6
    public var targetRepsMax: Int = 8
    public var defaultRestConditionData: Data

    // MARK: - Conocimiento biomecánico (retrocompatible con datos antiguos)

    /// `true` = Complejo / Compuesto, `false` = Aislamiento.
    public var isCompound: Bool = true
    /// Músculos principales serializados para mantener la migración ligera.
    public var primaryMusclesRaw: String = ""
    /// Músculos secundarios serializados para mantener la migración ligera.
    public var secondaryMusclesRaw: String = ""
    public var whyGoodExercise: String = ""
    public var whyBadExercise: String = ""
    public var whenRecommended: String = ""
    public var whenNotRecommended: String = ""
    /// Notas libres del usuario sobre el ejercicio.
    public var notes: String = ""
    /// `true` cuando el usuario ha decidido manualmente el aviso de straps.
    public var hasCustomRequiresStraps: Bool = false
    /// `true` cuando el equipamiento lo eligió el usuario: las migraciones del
    /// catálogo no lo sobrescriben.
    public var hasCustomEquipment: Bool = false
    /// `true` cuando el descanso lo configuró el usuario.
    public var hasCustomRestCondition: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSetLog.exercise)
    public var logs: [WorkoutSetLog] = []

    // MARK: - Regla global de repeticiones objetivo

    /// Rango objetivo de los ejercicios complejos.
    public static let compoundTargetReps: (min: Int, max: Int) = (min: 6, max: 8)
    /// Rango objetivo de los ejercicios de aislamiento.
    public static let isolationTargetReps: (min: Int, max: Int) = (min: 8, max: 10)

    public static func defaultTargetReps(for isCompound: Bool) -> (min: Int, max: Int) {
        return isCompound ? Exercise.compoundTargetReps : Exercise.isolationTargetReps
    }

    /// `true` si el rango guardado coincide con alguno de los valores por
    /// defecto (el actual o el antiguo `8-12`).
    public var hasDefaultTargetReps: Bool {
        if targetRepsMin == 6 && targetRepsMax == 8 {
            return true
        }
        if targetRepsMin == 8 && targetRepsMax == 10 {
            return true
        }
        if targetRepsMin == 8 && targetRepsMax == 12 {
            return true
        }
        return false
    }

    // MARK: - Propiedades derivadas

    @Transient
    public var muscleGroup: MuscleGroup {
        get { MuscleGroup.fromStoredRawValue(muscleGroupRaw) }
        set { muscleGroupRaw = newValue.rawValue }
    }

    @Transient
    public var equipmentType: EquipmentType {
        get { EquipmentType.fromStoredRawValue(equipmentTypeRaw) }
        set { equipmentTypeRaw = newValue.rawValue }
    }

    @Transient
    public var defaultRestCondition: RestCondition {
        get {
            (try? JSONDecoder().decode(RestCondition.self, from: defaultRestConditionData)) ?? .timer(seconds: 90)
        }
        set {
            defaultRestConditionData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    @Transient
    public var targetRepsText: String {
        "\(targetRepsMin)-\(targetRepsMax)"
    }

    /// Los músculos principales mantienen sincronizado el grupo muscular
    /// objetivo (el primero de la lista) con el que se filtran y agrupan los
    /// ejercicios en toda la app.
    @Transient
    public var primaryMuscles: [MuscleGroup] {
        get { MuscleGroup.decodeList(primaryMusclesRaw) }
        set {
            primaryMusclesRaw = MuscleGroup.encodeList(newValue)
            if let first: MuscleGroup = newValue.first {
                muscleGroupRaw = first.rawValue
            }
        }
    }

    @Transient
    public var secondaryMuscles: [MuscleGroup] {
        get { MuscleGroup.decodeList(secondaryMusclesRaw) }
        set { secondaryMusclesRaw = MuscleGroup.encodeList(newValue) }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: MuscleGroup,
        equipmentType: EquipmentType = .olympicBar,
        requiresStraps: Bool = false,
        targetRepsMin: Int? = nil,
        targetRepsMax: Int? = nil,
        defaultRestCondition: RestCondition = .timer(seconds: 90),
        isCompound: Bool = true,
        primaryMuscles: [MuscleGroup] = [],
        secondaryMuscles: [MuscleGroup] = [],
        whyGoodExercise: String = "",
        whyBadExercise: String = "",
        whenRecommended: String = "",
        whenNotRecommended: String = "",
        notes: String = "",
        hasCustomRequiresStraps: Bool = false,
        hasCustomEquipment: Bool = false,
        hasCustomRestCondition: Bool = false
    ) {
        self.id = id
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentTypeRaw = equipmentType.rawValue
        self.requiresStraps = requiresStraps

        let ruleRange: (min: Int, max: Int) = Exercise.defaultTargetReps(for: isCompound)
        let requestedMin: Int = targetRepsMin ?? ruleRange.min
        let requestedMax: Int = targetRepsMax ?? ruleRange.max
        let lower: Int = max(1, min(requestedMin, requestedMax))
        self.targetRepsMin = lower
        self.targetRepsMax = max(lower, requestedMax)

        self.defaultRestConditionData = (try? JSONEncoder().encode(defaultRestCondition)) ?? Data()
        self.isCompound = isCompound
        self.primaryMusclesRaw = MuscleGroup.encodeList(primaryMuscles)
        self.secondaryMusclesRaw = MuscleGroup.encodeList(secondaryMuscles)
        self.whyGoodExercise = whyGoodExercise
        self.whyBadExercise = whyBadExercise
        self.whenRecommended = whenRecommended
        self.whenNotRecommended = whenNotRecommended
        self.notes = notes
        self.hasCustomRequiresStraps = hasCustomRequiresStraps
        self.hasCustomEquipment = hasCustomEquipment
        self.hasCustomRestCondition = hasCustomRestCondition

        if let firstMuscle: MuscleGroup = primaryMuscles.first {
            self.muscleGroupRaw = firstMuscle.rawValue
        }
    }
}
