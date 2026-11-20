import Foundation
import SwiftData

/// Identificadores estables de las cinco rutinas iniciales sembradas. Solo
/// sirven para reconocerlas al sembrar la base y en las migraciones: no
/// otorgan ninguna protección ni trato especial frente al resto de rutinas.
let seededRoutineIdentifiers: Set<UUID> = [
    UUID(uuidString: "6F0E1A10-0001-4000-8000-000000000001")!,
    UUID(uuidString: "6F0E1A10-0002-4000-8000-000000000002")!,
    UUID(uuidString: "6F0E1A10-0003-4000-8000-000000000003")!,
    UUID(uuidString: "6F0E1A10-0004-4000-8000-000000000004")!,
    UUID(uuidString: "6F0E1A10-0005-4000-8000-000000000005")!
]

// MARK: - Definiciones del catálogo

private struct CatalogExerciseDefinition {
    let name: String
    let equipmentType: EquipmentType
    let restSeconds: Int
    /// Unidad de registro: repeticiones por defecto, o tiempo en isométricos
    /// y cardio.
    var trackingMode: ExerciseTrackingMode = .reps
    /// Rango objetivo propio cuando no se mide en repeticiones.
    var targetRange: (min: Int, max: Int)? = nil
}

private struct CatalogRoutineEntry {
    let exerciseName: String
    let sets: Int
    let targetRepsMin: Int
    let targetRepsMax: Int
    let restSeconds: Int
}

private struct CatalogRoutineDefinition {
    /// Identificador estable de la rutina sembrada. No cambia entre
    /// instalaciones ni depende del nombre visible.
    let id: UUID
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

            for definition in catalog {
                let exercise: Exercise = makeExercise(from: definition)
                context.insert(exercise)
            }

            // Las cinco rutinas de ejemplo ya no se siembran. La organización
            // del entrenamiento la elige el usuario en el onboarding —que
            // puede terminarlo sin ninguna rutina—, así que una instalación
            // nueva empieza con la lista vacía. Las definiciones de `routines`
            // se conservan para sincronizar bases antiguas en
            // `applyRoutineTableUpdateIfNeeded`.
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

    /// Bandera del sembrado de cardio y core isométrico en bases ya existentes.
    public static let cardioAndIsometricCatalogFlagKey: String = "didSeedCardioAndIsometricCatalog_v2"

    /// Añade una sola vez los ejercicios de cardio y de core isométrico a una
    /// base ya existente, sin tocar rutinas, notas ni historial.
    public static func seedCardioAndIsometricExercisesIfNeeded(context: ModelContext) {
        let defaults: UserDefaults = UserDefaults.standard
        guard !defaults.bool(forKey: cardioAndIsometricCatalogFlagKey) else { return }

        do {
            let descriptor: FetchDescriptor<Exercise> = FetchDescriptor<Exercise>()
            let existing: [Exercise] = try context.fetch(descriptor)

            for definition in cardioAndIsometricCatalog {
                let definitionKey: String = ExerciseDuplicateService.canonicalKey(for: definition.name)

                // Si el usuario ya tenía el ejercicio con otro nombre conocido,
                // se adopta su unidad y rango en vez de crear un duplicado.
                if let match: Exercise = existing.first(where: { (candidate: Exercise) -> Bool in
                    return ExerciseDuplicateService.canonicalKey(for: candidate.name) == definitionKey
                }) {
                    applyCardioAndIsometricSettings(definition, to: match)
                    continue
                }

                let exercise: Exercise = makeExercise(from: definition)
                context.insert(exercise)
            }

            try context.save()
            defaults.set(true, forKey: cardioAndIsometricCatalogFlagKey)
        } catch {
            print("Error sembrando el catálogo de cardio e isométricos: \(error)")
        }
    }

    /// Alinea la unidad de registro, el rango objetivo y el descanso de un
    /// ejercicio de cardio o isométrico ya existente con el catálogo.
    private static func applyCardioAndIsometricSettings(
        _ definition: CatalogExerciseDefinition,
        to exercise: Exercise
    ) {
        exercise.trackingMode = definition.trackingMode

        if let range: (min: Int, max: Int) = definition.targetRange {
            exercise.targetRepsMin = range.min
            exercise.targetRepsMax = range.max
        }

        if !exercise.hasCustomRestCondition, case .timer = exercise.defaultRestCondition {
            exercise.defaultRestCondition = .timer(seconds: definition.restSeconds)
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

    /// Bandera de la alineación del equipamiento con el catálogo vigente.
    public static let catalogEquipmentAlignmentFlagKey: String = "didAlignCatalogEquipment_v2"

    /// Corrige el equipamiento de los ejercicios que ya existían con las reglas
    /// antiguas (poleas aproximadas, barras olímpicas genéricas, paralelas como
    /// barra fija). Solo actúa sobre nombres del catálogo y nunca sobre un
    /// equipamiento que el usuario haya fijado a mano.
    @MainActor
    public static func alignCatalogEquipmentIfNeeded(context: ModelContext) {
        let defaults: UserDefaults = UserDefaults.standard
        guard !defaults.bool(forKey: catalogEquipmentAlignmentFlagKey) else { return }
        guard let catalog: ExerciseCatalogStore = ExerciseCatalogStore.shared else { return }

        let variants: [CatalogRoutineVariant] = catalog.file.levels.single
            + catalog.file.levels.double
            + catalog.file.levels.triple
        var catalogNames: Set<String> = Set(variants.flatMap { (variant: CatalogRoutineVariant) -> [String] in
            return variant.exercises.map { (record: CatalogExerciseRecord) -> String in
                return ExerciseRules.normalizedName(record.name)
            }
        })
        for record in catalog.file.uniqueExercises {
            catalogNames.insert(ExerciseRules.normalizedName(record.name))
        }

        do {
            let exercises: [Exercise] = try context.fetch(FetchDescriptor<Exercise>())
            for exercise in exercises where !exercise.hasCustomEquipment {
                guard catalogNames.contains(ExerciseRules.normalizedName(exercise.name)) else { continue }
                exercise.equipmentType = ExerciseRules.equipment(for: exercise.name)
            }

            try context.save()
            defaults.set(true, forKey: catalogEquipmentAlignmentFlagKey)
        } catch {
            print("Error alineando el equipamiento del catálogo: \(error)")
        }
    }

    /// Bandera de la clasificación de procedencia de rutinas antiguas.
    public static let legacyRoutineSourceFlagKey: String = "didClassifyLegacyRoutineSources_v1"

    /// Identificadores estables de las cinco rutinas sembradas. Son la única
    /// señal inequívoca para reconocerlas al sembrar la base: el nombre visible
    /// puede coincidir con una rutina creada a mano. No implican protección.
    static var seededRoutineIDs: Set<UUID> {
        return seededRoutineIdentifiers
    }

    /// Las filas anteriores a `sourceRaw` no tienen procedencia. El valor
    /// seguro es `manual` (nunca se archivan por sorpresa). Solo se marcan como
    /// automáticas las que conservan el UUID estable de una rutina sembrada;
    /// las antiguas con UUID aleatorio quedan como manuales.
    @MainActor
    public static func classifyLegacyRoutineSourcesIfNeeded(context: ModelContext) {
        let defaults: UserDefaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyRoutineSourceFlagKey) else { return }

        let seededIDs: Set<UUID> = seededRoutineIDs

        do {
            let stored: [Routine] = try context.fetch(FetchDescriptor<Routine>())
            for routine in stored where routine.sourceRaw == nil {
                if seededIDs.contains(routine.id) {
                    routine.source = .automatic
                }
            }

            try context.save()
            defaults.set(true, forKey: legacyRoutineSourceFlagKey)
        } catch {
            print("Error clasificando la procedencia de las rutinas: \(error)")
        }
    }

    /// Sincroniza una base ya existente con la tabla: renombra los ejercicios
    /// heredados, crea los que falten y ajusta equipamiento y descanso de los
    /// ejercicios del catálogo. Ninguna rutina queda excluida por su UUID.
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

    /// Rehace las rutinas de la tabla. Ninguna rutina queda excluida por su UUID.
    private static func rewriteRoutines(context: ModelContext, exercises: [Exercise]) throws {
        let descriptor: FetchDescriptor<Routine> = FetchDescriptor<Routine>()
        let existingRoutines: [Routine] = try context.fetch(descriptor)

        for (routineIndex, definition) in routines.enumerated() {
            // La identidad de una rutina sembrada es su UUID estable, nunca el
            // nombre visible: el usuario puede renombrarla y puede tener una
            // rutina manual llamada «PUSH». Buscar por nombre reescribiría esa
            // rutina personal y borraría sus ejercicios no presentes en la tabla.
            guard let routine: Routine = existingRoutines.first(where: { (candidate: Routine) -> Bool in
                return candidate.id == definition.id
            }) else { continue }

            routine.sortOrder = routineIndex
            // Solo se marca una rutina heredada si conserva el UUID estable
            // de una rutina sembrada. Nunca por nombre: una rutina manual
            // llamada «PUSH» debe seguir siendo manual.
            if routine.sourceRaw == nil, seededRoutineIDs.contains(routine.id) {
                routine.source = .automatic
            }
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
        let range: (min: Int, max: Int) = definition.targetRange
            ?? Exercise.defaultTargetReps(for: info.isCompound)

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
            whenNotRecommended: info.whenNotRecommended,
            trackingMode: definition.trackingMode
        )
    }

    private static func normalize(_ text: String) -> String {
        let lowered: String = text.lowercased()
        return lowered.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
    }

    // MARK: Catálogo

    private static let baseCatalog: [CatalogExerciseDefinition] = [
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

    // MARK: Catálogo de cardio y core isométrico

    /// Ejercicios medidos en tiempo: el cardio se registra en minutos y los
    /// isométricos en segundos. Se siembran aparte para que las bases ya
    /// existentes los reciban sin reescribir sus rutinas.
    private static let cardioAndIsometricCatalog: [CatalogExerciseDefinition] = [
        // Cardio
        CatalogExerciseDefinition(
            name: "Bicicleta estática",
            equipmentType: .cardioMachine,
            restSeconds: 60,
            trackingMode: .minutes,
            targetRange: (min: 20, max: 40)
        ),
        CatalogExerciseDefinition(
            name: "Cinta de correr",
            equipmentType: .cardioMachine,
            restSeconds: 60,
            trackingMode: .minutes,
            targetRange: (min: 20, max: 30)
        ),
        CatalogExerciseDefinition(
            name: "Subir escaleras",
            equipmentType: .cardioMachine,
            restSeconds: 90,
            trackingMode: .minutes,
            targetRange: (min: 10, max: 20)
        ),
        CatalogExerciseDefinition(
            name: "Máquina de remar",
            equipmentType: .cardioMachine,
            restSeconds: 90,
            trackingMode: .minutes,
            targetRange: (min: 10, max: 20)
        ),

        // Core isométrico
        CatalogExerciseDefinition(
            name: "Plancha frontal",
            equipmentType: .bodyweight,
            restSeconds: 60,
            trackingMode: .seconds,
            targetRange: (min: 30, max: 60)
        ),
        CatalogExerciseDefinition(
            name: "Plancha lateral",
            equipmentType: .bodyweight,
            restSeconds: 60,
            trackingMode: .seconds,
            targetRange: (min: 20, max: 45)
        ),
        CatalogExerciseDefinition(
            name: "Hollow hold",
            equipmentType: .bodyweight,
            restSeconds: 60,
            trackingMode: .seconds,
            targetRange: (min: 20, max: 40)
        ),
        CatalogExerciseDefinition(
            name: "Dead bug",
            equipmentType: .bodyweight,
            restSeconds: 60,
            targetRange: (min: 8, max: 12)
        ),
        CatalogExerciseDefinition(
            name: "Bird dog",
            equipmentType: .bodyweight,
            restSeconds: 60,
            targetRange: (min: 8, max: 12)
        )
    ]

    /// Catálogo completo de la app.
    private static var catalog: [CatalogExerciseDefinition] {
        return baseCatalog + cardioAndIsometricCatalog
    }

    // MARK: Rutinas base

    /// Tabla de entrenamiento vigente. El orden de las rutinas, el orden de
    /// los ejercicios, las series, el rango de repeticiones y el descanso
    /// salen literalmente de la hoja de cálculo del usuario.
    private static let routines: [CatalogRoutineDefinition] = [
        CatalogRoutineDefinition(id: UUID(uuidString: "6F0E1A10-0001-4000-8000-000000000001")!, name: "PUSH", entries: [
            CatalogRoutineEntry(exerciseName: "Press banca inclinado", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Elevaciones laterales en máquina", sets: 3, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Extensión de tríceps sobre la cabeza", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Cruces de polea sentado", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Press militar", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Extensión de tríceps en polea", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135)
        ]),
        CatalogRoutineDefinition(id: UUID(uuidString: "6F0E1A10-0002-4000-8000-000000000002")!, name: "PULL", entries: [
            CatalogRoutineEntry(exerciseName: "Jalon al pecho", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Curl en mancuerna", sets: 3, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Remo en maquina", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Curl araña", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Remo libre", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Aperturas inversas en polea", sets: 3, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135)
        ]),
        CatalogRoutineDefinition(id: UUID(uuidString: "6F0E1A10-0003-4000-8000-000000000003")!, name: "LEGS", entries: [
            CatalogRoutineEntry(exerciseName: "Hiperextensiones", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Flexion de pierna estirado", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Bulgaras", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Elevacion talones sentado", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Peso muerto rumano (RDL)", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Extension de quadriceps", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180)
        ]),
        CatalogRoutineDefinition(id: UUID(uuidString: "6F0E1A10-0004-4000-8000-000000000004")!, name: "UPPER", entries: [
            CatalogRoutineEntry(exerciseName: "Press banca inclinado", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Cruces de polea sentado", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Jalon al pecho", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Elevaciones laterales en máquina", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Remo libre", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Extensión de tríceps sobre la cabeza", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Curl en mancuerna", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135),
            CatalogRoutineEntry(exerciseName: "Aperturas inversas en polea", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 135)
        ]),
        CatalogRoutineDefinition(id: UUID(uuidString: "6F0E1A10-0005-4000-8000-000000000005")!, name: "LOWER", entries: [
            CatalogRoutineEntry(exerciseName: "Hiperextensiones", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Flexion de pierna sentado", sets: 3, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Sentadilla en máquina", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Elevacion de talones de pie", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Peso muerto rumano (RDL)", sets: 2, targetRepsMin: 6, targetRepsMax: 8, restSeconds: 180),
            CatalogRoutineEntry(exerciseName: "Extension de quadriceps", sets: 2, targetRepsMin: 8, targetRepsMax: 10, restSeconds: 180)
        ])
    ]
}
