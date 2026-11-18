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
    let restSeconds: Int
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

            for (routineIndex, routineDefinition) in routines.enumerated() {
                var routineExercises: [RoutineExercise] = []
                var order: Int = 0

                for entry in routineDefinition.entries {
                    guard let exercise: Exercise = exercisesByName[normalize(entry.exerciseName)] else { continue }
                    let routineExercise: RoutineExercise = RoutineExercise(
                        exercise: exercise,
                        defaultSets: entry.sets,
                        targetRepsMin: entry.targetRepsMin,
                        targetRepsMax: entry.targetRepsMax,
                        sortOrder: order,
                        restSeconds: entry.restSeconds
                    )
                    context.insert(routineExercise)
                    routineExercises.append(routineExercise)
                    order += 1
                }

                let routine: Routine = Routine(
                    name: routineDefinition.name,
                    isTemplate: true,
                    sortOrder: routineIndex,
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
            // Evita crear un duplicado cuando ya existe el mismo ejercicio con
            // otro nombre (por ejemplo, en inglés).
            var canonicalKeys: Set<String> = Set(existing.map { (exercise: Exercise) -> String in
                return ExerciseDuplicateService.canonicalKey(for: exercise.name)
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
                let definitionKey: String = ExerciseDuplicateService.canonicalKey(for: definition.name)
                guard !canonicalKeys.contains(definitionKey) else { continue }

                let exercise: Exercise = makeExercise(from: definition)
                context.insert(exercise)
                names.insert(normalize(definition.name))
                canonicalKeys.insert(definitionKey)
            }

            try context.save()
            defaults.set(true, forKey: extendedCatalogFlagKey)
        } catch {
            print("Error sembrando el catálogo ampliado: \(error)")
        }
    }

    // MARK: Sincronización con la tabla de rutinas

    /// Bandera de la sincronización de rutinas y ejercicios con la tabla
    /// vigente (series, repeticiones, descansos y equipamiento).
    public static let routineTableUpdateFlagKey: String = "didApplyRoutineTableUpdate_v1"

    /// Nombres heredados que la tabla escribe de otra forma. Se renombran en
    /// lugar de crear un duplicado, así el historial de series se conserva.
    private static let legacyNames: [(old: String, new: String, equipment: EquipmentType)] = [
        (old: "Extension tras nuca", new: "Extensión de tríceps sobre la cabeza", equipment: .cable),
        (old: "Sentadilla hack", new: "Sentadilla en máquina", equipment: .plateLoadedMachine)
    ]

    /// Sincroniza una base ya existente con la tabla: renombra los ejercicios
    /// heredados, crea los que falten, ajusta equipamiento y descanso, y
    /// reescribe las cinco rutinas con sus series y repeticiones.
    public static func applyRoutineTableUpdateIfNeeded(context: ModelContext) {
        let defaults: UserDefaults = UserDefaults.standard
        guard !defaults.bool(forKey: routineTableUpdateFlagKey) else { return }
        // Con un entrenamiento reanudable en curso no se tocan las rutinas: sus
        // series guardadas siguen apuntando a los mismos identificadores.
        guard !ActiveWorkoutStateStore.hasActiveWorkout else { return }

        do {
            let descriptor: FetchDescriptor<Exercise> = FetchDescriptor<Exercise>()
            var exercises: [Exercise] = try context.fetch(descriptor)

            for legacy in legacyNames {
                renameLegacyExercise(legacy, exercises: &exercises)
            }

            ensureTableExercisesExist(context: context, exercises: &exercises)
            applyTableSettings(to: exercises)
            try rewriteRoutines(context: context, exercises: exercises)

            try context.save()
            defaults.set(true, forKey: routineTableUpdateFlagKey)
        } catch {
            print("Error sincronizando las rutinas de la tabla: \(error)")
        }
    }

    private static func renameLegacyExercise(
        _ legacy: (old: String, new: String, equipment: EquipmentType),
        exercises: inout [Exercise]
    ) {
        let oldKey: String = normalize(legacy.old)
        let newKey: String = normalize(legacy.new)
        guard let exercise: Exercise = exercises.first(where: { (candidate: Exercise) -> Bool in
            return normalize(candidate.name) == oldKey
        }) else { return }

        let alreadyExists: Bool = exercises.contains { (candidate: Exercise) -> Bool in
            return candidate !== exercise && normalize(candidate.name) == newKey
        }

        if !alreadyExists {
            exercise.name = legacy.new
            ExerciseKnowledgeService.refreshKnowledge(for: exercise)
        }
        if !exercise.hasCustomEquipment {
            exercise.equipmentType = legacy.equipment
        }
    }

    /// Crea los ejercicios de la tabla que no estén todavía en la base.
    private static func ensureTableExercisesExist(context: ModelContext, exercises: inout [Exercise]) {
        for name in tableExerciseNames {
            let key: String = ExerciseDuplicateService.canonicalKey(for: name)
            let alreadyExists: Bool = exercises.contains { (candidate: Exercise) -> Bool in
                return ExerciseDuplicateService.canonicalKey(for: candidate.name) == key
            }
            guard !alreadyExists else { continue }
            guard let definition: CatalogExerciseDefinition = catalogDefinition(for: name) else { continue }

            let exercise: Exercise = makeExercise(from: definition)
            context.insert(exercise)
            exercises.append(exercise)
        }
    }

    /// Alinea equipamiento y descanso de los ejercicios de la tabla. Un
    /// descanso por bajada de BPM lo eligió el usuario y no se toca.
    private static func applyTableSettings(to exercises: [Exercise]) {
        for name in tableExerciseNames {
            guard let definition: CatalogExerciseDefinition = catalogDefinition(for: name),
                  let exercise: Exercise = exercises.first(where: { (candidate: Exercise) -> Bool in
                      return ExerciseDuplicateService.canonicalKey(for: candidate.name)
                          == ExerciseDuplicateService.canonicalKey(for: name)
                  }) else { continue }

            if !exercise.hasCustomEquipment {
                exercise.equipmentType = definition.equipmentType
            }

            // Un descanso elegido por el usuario (o por bajada de BPM) manda.
            guard !exercise.hasCustomRestCondition else { continue }
            if case .bpmDrop = exercise.defaultRestCondition { continue }
            exercise.defaultRestCondition = .timer(seconds: definition.restSeconds)
        }
    }

    /// Rehace cada rutina de la tabla conservando las notas y el peso por
    /// defecto de los ejercicios que ya estaban en ella.
    private static func rewriteRoutines(context: ModelContext, exercises: [Exercise]) throws {
        let descriptor: FetchDescriptor<Routine> = FetchDescriptor<Routine>()
        let existingRoutines: [Routine] = try context.fetch(descriptor)

        for (routineIndex, definition) in routines.enumerated() {
            let routineKey: String = normalize(definition.name)
            guard let routine: Routine = existingRoutines.first(where: { (candidate: Routine) -> Bool in
                return normalize(candidate.name) == routineKey
            }) else { continue }

            routine.sortOrder = routineIndex
            var pending: [RoutineExercise] = routine.exercises
            var entries: [RoutineExercise] = []

            for (order, entry) in definition.entries.enumerated() {
                let entryKey: String = ExerciseDuplicateService.canonicalKey(for: entry.exerciseName)
                guard let exercise: Exercise = exercises.first(where: { (candidate: Exercise) -> Bool in
                    return ExerciseDuplicateService.canonicalKey(for: candidate.name) == entryKey
                }) else { continue }

                if let position: Int = pending.firstIndex(where: { (candidate: RoutineExercise) -> Bool in
                    return candidate.exercise?.id == exercise.id
                }) {
                    let routineExercise: RoutineExercise = pending.remove(at: position)
                    routineExercise.exercise = exercise
                    routineExercise.defaultSets = entry.sets
                    routineExercise.targetRepsMin = entry.targetRepsMin
                    routineExercise.targetRepsMax = entry.targetRepsMax
                    if !routineExercise.hasCustomRest {
                        routineExercise.restSeconds = entry.restSeconds
                    }
                    routineExercise.sortOrder = order
                    entries.append(routineExercise)
                } else {
                    let routineExercise: RoutineExercise = RoutineExercise(
                        exercise: exercise,
                        defaultSets: entry.sets,
                        targetRepsMin: entry.targetRepsMin,
                        targetRepsMax: entry.targetRepsMax,
                        sortOrder: order,
                        restSeconds: entry.restSeconds
                    )
                    context.insert(routineExercise)
                    entries.append(routineExercise)
                }
            }

            for leftover in pending {
                routine.exercises.removeAll { (candidate: RoutineExercise) -> Bool in
                    return candidate.id == leftover.id
                }
                context.delete(leftover)
            }

            routine.exercises = entries
        }
    }

    /// Nombres de ejercicio que aparecen en la tabla, sin repetir.
    private static var tableExerciseNames: [String] {
        var names: [String] = []
        for definition in routines {
            for entry in definition.entries where !names.contains(entry.exerciseName) {
                names.append(entry.exerciseName)
            }
        }
        return names
    }

    private static func catalogDefinition(for name: String) -> CatalogExerciseDefinition? {
        let key: String = ExerciseDuplicateService.canonicalKey(for: name)
        return catalog.first { (definition: CatalogExerciseDefinition) -> Bool in
            return ExerciseDuplicateService.canonicalKey(for: definition.name) == key
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
        CatalogExerciseDefinition(name: "Aperturas en máquina", equipmentType: .plateLoadedMachine, restSeconds: 120),
        CatalogExerciseDefinition(name: "Cruces de polea sentado", equipmentType: .cable, restSeconds: 135),

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
        CatalogExerciseDefinition(name: "Hiperextensiones", equipmentType: .dumbbell, restSeconds: 180),

        // Deltoides anterior / lateral
        CatalogExerciseDefinition(name: "Press militar", equipmentType: .dumbbell, restSeconds: 135),
        CatalogExerciseDefinition(name: "Press Arnold", equipmentType: .dumbbell, restSeconds: 135),
        CatalogExerciseDefinition(name: "Press de hombros en maquina", equipmentType: .plateLoadedMachine, restSeconds: 135),
        CatalogExerciseDefinition(name: "Elevaciones laterales en máquina", equipmentType: .plateLoadedMachine, restSeconds: 135),
        CatalogExerciseDefinition(name: "Elevaciones laterales mancuerna", equipmentType: .dumbbell, restSeconds: 135),
        CatalogExerciseDefinition(name: "Elevaciones laterales en polea", equipmentType: .cable, restSeconds: 120),
        CatalogExerciseDefinition(name: "Elevaciones frontales", equipmentType: .dumbbell, restSeconds: 110),

        // Deltoides posterior
        CatalogExerciseDefinition(name: "Jalón a la cara", equipmentType: .cable, restSeconds: 90),
        CatalogExerciseDefinition(name: "Pajaros con mancuernas", equipmentType: .dumbbell, restSeconds: 100),
        CatalogExerciseDefinition(name: "Aperturas inversas en maquina", equipmentType: .plateLoadedMachine, restSeconds: 100),
        CatalogExerciseDefinition(name: "Aperturas inversas en polea", equipmentType: .cable, restSeconds: 135),

        // Bíceps
        CatalogExerciseDefinition(name: "Curl en mancuerna", equipmentType: .dumbbell, restSeconds: 135),
        CatalogExerciseDefinition(name: "Curl con barra EZ", equipmentType: .ezBar, restSeconds: 110),
        CatalogExerciseDefinition(name: "Curl predicador", equipmentType: .ezBar, restSeconds: 110),
        CatalogExerciseDefinition(name: "Curl en polea", equipmentType: .cable, restSeconds: 100),
        CatalogExerciseDefinition(name: "Curl araña", equipmentType: .dumbbell, restSeconds: 135),

        // Tríceps
        CatalogExerciseDefinition(name: "Extensión de tríceps en polea", equipmentType: .cable, restSeconds: 135),
        CatalogExerciseDefinition(name: "Press cerrado", equipmentType: .olympicBar, restSeconds: 135),
        CatalogExerciseDefinition(name: "Press frances", equipmentType: .ezBar, restSeconds: 110),
        CatalogExerciseDefinition(name: "Extensión de tríceps sobre la cabeza", equipmentType: .cable, restSeconds: 135),

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
        CatalogExerciseDefinition(name: "Sentadilla en máquina", equipmentType: .plateLoadedMachine, restSeconds: 180),
        CatalogExerciseDefinition(name: "Zancadas", equipmentType: .dumbbell, restSeconds: 180),
        CatalogExerciseDefinition(name: "Extension de quadriceps", equipmentType: .cable, restSeconds: 180),

        // Isquiotibiales
        CatalogExerciseDefinition(name: "Peso muerto rumano (RDL)", equipmentType: .olympicBar, restSeconds: 180),
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
        CatalogExerciseDefinition(name: "Elevacion de talones de pie", equipmentType: .plateLoadedMachine, restSeconds: 180)
    ]

    // MARK: Rutinas base

    /// Tabla de entrenamiento vigente. El orden de las rutinas, el orden de
    /// los ejercicios, las series, el rango de repeticiones y el descanso
    /// salen literalmente de la hoja de cálculo del usuario.
    private static let routines: [CatalogRoutineDefinition] = [
        CatalogRoutineDefinition(name: "PUSH", entries: [
            CatalogRoutineEntry(exerciseName: "Press banca inclinado", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Elevaciones laterales en máquina", sets: 3, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Extensión de tríceps sobre la cabeza", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Cruces de polea sentado", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Press militar", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Extensión de tríceps en polea", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135)
        ]),
        CatalogRoutineDefinition(name: "PULL", entries: [
            CatalogRoutineEntry(exerciseName: "Jalon al pecho", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Curl en mancuerna", sets: 3, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Remo en maquina", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Curl araña", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Remo libre", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Aperturas inversas en polea", sets: 3, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135)
        ]),
        CatalogRoutineDefinition(name: "LEGS", entries: [
            CatalogRoutineEntry(exerciseName: "Hiperextensiones", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Flexion de pierna estirado", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Bulgaras", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Elevacion talones sentado", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Peso muerto rumano (RDL)", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Extension de quadriceps", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180)
        ]),
        CatalogRoutineDefinition(name: "UPPER", entries: [
            CatalogRoutineEntry(exerciseName: "Press banca inclinado", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Cruces de polea sentado", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Jalon al pecho", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Elevaciones laterales en máquina", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Remo libre", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Extensión de tríceps sobre la cabeza", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Curl en mancuerna", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Aperturas inversas en polea", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135)
        ]),
        CatalogRoutineDefinition(name: "LOWER", entries: [
            CatalogRoutineEntry(exerciseName: "Hiperextensiones", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Flexion de pierna sentado", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Sentadilla en máquina", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Elevacion de talones de pie", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Peso muerto rumano (RDL)", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Extension de quadriceps", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180)
        ])
    ]
}
