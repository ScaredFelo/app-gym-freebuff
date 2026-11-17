import Foundation
import SwiftData

@Model
public final class Exercise {
    public var id: UUID
    public var name: String
    public var muscleGroupRaw: String
    public var equipmentTypeRaw: String
    public var requiresStraps: Bool
    public var targetRepsMin: Int = 8
    public var targetRepsMax: Int = 12
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

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSetLog.exercise)
    public var logs: [WorkoutSetLog] = []

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

    @Transient
    public var primaryMuscles: [MuscleGroup] {
        get { MuscleGroup.decodeList(primaryMusclesRaw) }
        set { primaryMusclesRaw = MuscleGroup.encodeList(newValue) }
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
        targetRepsMin: Int = 8,
        targetRepsMax: Int = 12,
        defaultRestCondition: RestCondition = .timer(seconds: 90),
        isCompound: Bool = true,
        primaryMuscles: [MuscleGroup] = [],
        secondaryMuscles: [MuscleGroup] = [],
        whyGoodExercise: String = "",
        whyBadExercise: String = "",
        whenRecommended: String = "",
        whenNotRecommended: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentTypeRaw = equipmentType.rawValue
        self.requiresStraps = requiresStraps
        let lower = max(1, min(targetRepsMin, targetRepsMax))
        self.targetRepsMin = lower
        self.targetRepsMax = max(lower, targetRepsMax)
        self.defaultRestConditionData = (try? JSONEncoder().encode(defaultRestCondition)) ?? Data()
        self.isCompound = isCompound
        self.primaryMusclesRaw = MuscleGroup.encodeList(primaryMuscles)
        self.secondaryMusclesRaw = MuscleGroup.encodeList(secondaryMuscles)
        self.whyGoodExercise = whyGoodExercise
        self.whyBadExercise = whyBadExercise
        self.whenRecommended = whenRecommended
        self.whenNotRecommended = whenNotRecommended
        self.notes = notes
    }
}
