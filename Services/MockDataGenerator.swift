import Foundation
import SwiftData

// MARK: - Definiciones del catálogo

private struct CatalogExerciseDefinition {
    let name: String
    let equipmentType: EquipmentType
    let restSeconds: Int
}

private struct CatalogRoutineEntry {
    let exerciseName: String
    let sets: Int
    let targetRepsMin: Int
    let targetRepsMax: Int
}

private struct CatalogRoutineDefinition {
    let name: String
    let entries: [CatalogRoutineEntry]
}

// MARK: - Catálogo inicial

/// Catálogo base de la app. Cada ejercicio se crea con el perfil biomecánico
/// que resuelve `ExerciseKnowledgeService` por nombre, de modo que grupo
/// muscular, tipo de movimiento, straps y rango 6-8 / 8-10 salen de una única
/// fuente de verdad.
@MainActor
public final class MockDataGenerator {

    /// Bandera del sembrado del catálogo ampliado en bases ya existentes.
    public static let extendedCatalogFlagKey: String = "didSeedExtendedExerciseCatalog_v1"

    // MARK: Sembrado

    public static func seedIfNeeded(context: ModelContext) {
        do {
            let descriptor: FetchDescriptor<Exercise> = FetchDescriptor<Exercise>()
            let existingCount: Int = try context.fetchCount(descriptor)
            guard existingCount == 0 else { return }

            var exercisesByName: [String: Exercise] = [:]
            for definition in catalog {
                let exercise: Exercise = makeExercise(from: definition)
                context.insert(exercise)
                exercisesByName[normalize(definition.name)] = exercise
            }

            for routineDefinition in routines {
                var routineExercises: [RoutineExercise] = []
                var order: Int = 0

                for entry in routineDefinition.entries {
                    guard let exercise: Exercise = exercisesByName[normalize(entry.exerciseName)] else { continue }
                    let routineExercise: RoutineExercise = RoutineExercise(
                        exercise: exercise,
                        defaultSets: entry.sets,
                        targetRepsMin: entry.targetRepsMin,
                        targetRepsMax: entry.targetRepsMax,
                        sortOrder: order
                    )
                    context.insert(routineExercise)
                    routineExercises.append(routineExercise)
                    order += 1
                }

                let routine: Routine = Routine(
                    name: routineDefinition.name,
                    isTemplate: true,
                    exercises: routineExercises
                )
                context.insert(routine)
            }

            try context.save()
        } catch {
            print("Error seeding mock data: \(error)")
        }
    }

    /// Añade una sola vez los ejercicios del catálogo que falten en una base ya
    /// existente y renombra el antiguo curl bayesiano sin perder su historial.
    public static func seedMissingCatalogExercisesIfNeeded(context: ModelContext) {
        let defaults: UserDefaults = UserDefaults.standard
        guard !defaults.bool(forKey: extendedCatalogFlagKey) else { return }

        do {
            let descriptor: FetchDescriptor<Exercise> = FetchDescriptor<Exercise>()
            let existing: [Exercise] = try context.fetch(descriptor)
            var names: Set<String> = Set(existing.map { (exercise: Exercise) -> String in
                return normalize(exercise.name)
            })

            let legacyKey: String = normalize("Curl bayesiano")
            let renamedKey: String = normalize("Curl en mancuerna")
            if !names.contains(renamedKey),
               let legacy: Exercise = existing.first(where: { (exercise: Exercise) -> Bool in
                   return normalize(exercise.name) == legacyKey
               }) {
                legacy.name = "Curl en mancuerna"
                names.remove(legacyKey)
                names.insert(renamedKey)
                ExerciseKnowledgeService.refreshKnowledge(for: legacy)
            }

            for definition in catalog where !names.contains(normalize(definition.name)) {
                let exercise: Exercise = makeExercise(from: definition)
                context.insert(exercise)
                names.insert(normalize(definition.name))
            }

            try context.save()
            defaults.set(true, forKey: extendedCatalogFlagKey)
        } catch {
            print("Error sembrando el catálogo ampliado: \(error)")
        }
    }

    // MARK: Construcción

    private static func makeExercise(from definition: CatalogExerciseDefinition) -> Exercise {
        let info: ResolvedExerciseInfo = ExerciseKnowledgeService.inferredInfo(
            named: definition.name,
            fallbackGroup: .chest,
            equipmentType: definition.equipmentType
        )
        let primary: [MuscleGroup] = info.primaryMuscles
        let range: (min: Int, max: Int) = Exercise.defaultTargetReps(for: info.isCompound)

        return Exercise(
            name: definition.name,
            muscleGroup: primary.first ?? .chest,
            equipmentType: definition.equipmentType,
            requiresStraps: info.requiresStraps,
            targetRepsMin: range.min,
            targetRepsMax: range.max,
            defaultRestCondition: .timer(seconds: definition.restSeconds),
            isCompound: info.isCompound,
            primaryMuscles: primary,
            secondaryMuscles: info.secondaryMuscles,
            whyGoodExercise: info.whyGoodExercise,
            whyBadExercise: info.whyBadExercise,
            whenRecommended: info.whenRecommended,
            whenNotRecommended: info.whenNotRecommended
        )
    }

    private static func normalize(_ text: String) -> String {
        let lowered: String = text.lowercased()
        return lowered.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
    }

    // MARK: Catálogo

    private static let catalog: [CatalogExerciseDefinition] = [
        // Pecho
        CatalogExerciseDefinition(name: "Press banca plano", equipmentType: .olympicBar, restSeconds: 135),
        CatalogExerciseDefinition(name: "Press banca inclinado", equipmentType: .smithMachine, restSeconds: 135),
        CatalogExerciseDefinition(name: "Press declinado", equipmentType: .smithMachine, restSeconds: 135),
        CatalogExerciseDefinition(name: "Fondos en paralelas", equipmentType: .fixedBar, restSeconds: 135),
        CatalogExerciseDefinition(name: "Aperturas con mancuernas", equipmentType: .dumbbell, restSeconds: 120),
        CatalogExerciseDefinition(name: "Pec deck", equipmentType: .plateLoadedMachine, restSeconds: 120),
        CatalogExerciseDefinition(name: "Seated cable fly", equipmentType: .cable, restSeconds: 135),

        // Dorsal ancho
        CatalogExerciseDefinition(name: "Dominadas", equipmentType: .fixedBar, restSeconds: 135),
        CatalogExerciseDefinition(name: "Jalon al pecho", equipmentType: .cable, restSeconds: 135),
        CatalogExerciseDefinition(name: "Remo libre", equipmentType: .olympicBar, restSeconds: 135),
        CatalogExerciseDefinition(name: "Remo T-bar", equipmentType: .plateLoadedMachine, restSeconds: 135),
        CatalogExerciseDefinition(name: "Pullover en polea alta", equipmentType: .cable, restSeconds: 120),

        // Espalda alta
        CatalogExerciseDefinition(name: "Remo en maquina", equipmentType: .plateLoadedMachine, restSeconds: 135),
        CatalogExerciseDefinition(name: "Remo Pendlay", equipmentType: .olympicBar, restSeconds: 135),
        CatalogExerciseDefinition(name: "Remo al menton", equipmentType: .ezBar, restSeconds: 120),
        CatalogExerciseDefinition(name: "Encogimientos con barra", equipmentType: .olympicBar, restSeconds: 120),

        // Lumbar
        CatalogExerciseDefinition(name: "Peso muerto convencional", equipmentType: .olympicBar, restSeconds: 180),
        CatalogExerciseDefinition(name: "Hiperextensiones", equipmentType: .plateLoadedMachine, restSeconds: 180),

        // Deltoides anterior / lateral
        CatalogExerciseDefinition(name: "Press militar", equipmentType: .dumbbell, restSeconds: 135),
        CatalogExerciseDefinition(name: "Press Arnold", equipmentType: .dumbbell, restSeconds: 135),
        CatalogExerciseDefinition(name: "Press de hombros en maquina", equipmentType: .plateLoadedMachine, restSeconds: 135),
        CatalogExerciseDefinition(name: "Elevaciones laterales mancuerna", equipmentType: .cable, restSeconds: 135),
        CatalogExerciseDefinition(name: "Elevaciones laterales en polea", equipmentType: .cable, restSeconds: 120),
        CatalogExerciseDefinition(name: "Elevaciones frontales", equipmentType: .dumbbell, restSeconds: 110),

        // Deltoides posterior
        CatalogExerciseDefinition(name: "Face pull", equipmentType: .cable, restSeconds: 90),
        CatalogExerciseDefinition(name: "Pajaros con mancuernas", equipmentType: .dumbbell, restSeconds: 100),
        CatalogExerciseDefinition(name: "Aperturas inversas en maquina", equipmentType: .plateLoadedMachine, restSeconds: 100),
        CatalogExerciseDefinition(name: "Isololateral reverse fly", equipmentType: .cable, restSeconds: 135),

        // Bíceps
        CatalogExerciseDefinition(name: "Curl en mancuerna", equipmentType: .dumbbell, restSeconds: 110),
        CatalogExerciseDefinition(name: "Curl con barra EZ", equipmentType: .ezBar, restSeconds: 110),
        CatalogExerciseDefinition(name: "Curl predicador", equipmentType: .ezBar, restSeconds: 110),
        CatalogExerciseDefinition(name: "Curl en polea", equipmentType: .cable, restSeconds: 100),
        CatalogExerciseDefinition(name: "Spider curl", equipmentType: .dumbbell, restSeconds: 135),

        // Tríceps
        CatalogExerciseDefinition(name: "Triceps pushdowns", equipmentType: .cable, restSeconds: 135),
        CatalogExerciseDefinition(name: "Extension de triceps", equipmentType: .cable, restSeconds: 135),
        CatalogExerciseDefinition(name: "Press cerrado", equipmentType: .olympicBar, restSeconds: 135),
        CatalogExerciseDefinition(name: "Press frances", equipmentType: .ezBar, restSeconds: 110),
        CatalogExerciseDefinition(name: "Extension tras nuca", equipmentType: .dumbbell, restSeconds: 110),

        // Antebrazos
        CatalogExerciseDefinition(name: "Curl de muneca", equipmentType: .dumbbell, restSeconds: 90),
        CatalogExerciseDefinition(name: "Curl invertido", equipmentType: .ezBar, restSeconds: 90),

        // Core
        CatalogExerciseDefinition(name: "Crunch en polea", equipmentType: .cable, restSeconds: 90),
        CatalogExerciseDefinition(name: "Elevacion de piernas colgado", equipmentType: .fixedBar, restSeconds: 90),

        // Cuádriceps
        CatalogExerciseDefinition(name: "Sentadilla libre", equipmentType: .olympicBar, restSeconds: 180),
        CatalogExerciseDefinition(name: "Bulgaras", equipmentType: .dumbbell, restSeconds: 180),
        CatalogExerciseDefinition(name: "Prensa de piernas", equipmentType: .plateLoadedMachine, restSeconds: 180),
        CatalogExerciseDefinition(name: "Hack squat", equipmentType: .plateLoadedMachine, restSeconds: 180),
        CatalogExerciseDefinition(name: "Zancadas", equipmentType: .dumbbell, restSeconds: 180),
        CatalogExerciseDefinition(name: "Extension de quadriceps", equipmentType: .cable, restSeconds: 180),

        // Isquiotibiales
        CatalogExerciseDefinition(name: "Romanian deadlift (RDL)", equipmentType: .olympicBar, restSeconds: 180),
        CatalogExerciseDefinition(name: "Flexion de pierna estirado", equipmentType: .cable, restSeconds: 180),
        CatalogExerciseDefinition(name: "Flexion de pierna sentado", equipmentType: .cable, restSeconds: 180),

        // Glúteos
        CatalogExerciseDefinition(name: "Hip thrust con barra", equipmentType: .olympicBar, restSeconds: 180),
        CatalogExerciseDefinition(name: "Patada de gluteo en polea", equipmentType: .cable, restSeconds: 150),
        CatalogExerciseDefinition(name: "Abduccion en maquina", equipmentType: .plateLoadedMachine, restSeconds: 150),

        // Aductores
        CatalogExerciseDefinition(name: "Aduccion de cadera en maquina", equipmentType: .plateLoadedMachine, restSeconds: 150),

        // Gemelos
        CatalogExerciseDefinition(name: "Elevacion talones sentado", equipmentType: .plateLoadedMachine, restSeconds: 180),
        CatalogExerciseDefinition(name: "Elevacion de talones de pie", equipmentType: .smithMachine, restSeconds: 180)
    ]

    // MARK: Rutinas base

    private static let routines: [CatalogRoutineDefinition] = [
        CatalogRoutineDefinition(name: "PUSH", entries: [
            CatalogRoutineEntry(exerciseName: "Press banca inclinado", sets: 3, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Elevaciones laterales mancuerna", sets: 3, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Triceps pushdowns", sets: 3, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Seated cable fly", sets: 2, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Press militar", sets: 2, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Extension de triceps", sets: 2, targetRepsMin: 8, targetRepsMax: 10)
        ]),
        CatalogRoutineDefinition(name: "PULL", entries: [
            CatalogRoutineEntry(exerciseName: "Jalon al pecho", sets: 3, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Curl en mancuerna", sets: 3, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Remo en maquina", sets: 2, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Spider curl", sets: 2, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Remo libre", sets: 2, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Isololateral reverse fly", sets: 3, targetRepsMin: 8, targetRepsMax: 10)
        ]),
        CatalogRoutineDefinition(name: "LEGS", entries: [
            CatalogRoutineEntry(exerciseName: "Hiperextensiones", sets: 2, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Flexion de pierna estirado", sets: 3, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Bulgaras", sets: 2, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Elevacion talones sentado", sets: 2, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Romanian deadlift (RDL)", sets: 2, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Extension de quadriceps", sets: 2, targetRepsMin: 8, targetRepsMax: 10)
        ]),
        CatalogRoutineDefinition(name: "UPPER", entries: [
            CatalogRoutineEntry(exerciseName: "Press banca inclinado", sets: 3, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Seated cable fly", sets: 2, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Jalon al pecho", sets: 3, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Elevaciones laterales mancuerna", sets: 2, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Remo libre", sets: 2, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Extension de triceps", sets: 2, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Curl en mancuerna", sets: 2, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Isololateral reverse fly", sets: 2, targetRepsMin: 8, targetRepsMax: 10)
        ]),
        CatalogRoutineDefinition(name: "LOWER", entries: [
            CatalogRoutineEntry(exerciseName: "Hiperextensiones", sets: 2, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Flexion de pierna sentado", sets: 3, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Bulgaras", sets: 2, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Elevacion talones sentado", sets: 2, targetRepsMin: 8, targetRepsMax: 10),
            CatalogRoutineEntry(exerciseName: "Romanian deadlift (RDL)", sets: 2, targetRepsMin: 6, targetRepsMax: 8),
            CatalogRoutineEntry(exerciseName: "Extension de quadriceps", sets: 2, targetRepsMin: 8, targetRepsMax: 10)
        ])
    ]
}
