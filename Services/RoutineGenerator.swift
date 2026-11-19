import Foundation

enum RoutineGenerationError: LocalizedError {
    case catalogUnavailable
    case tooManyOccurrences(routine: CatalogRoutine, count: Int)
    case missingVariant(routine: CatalogRoutine, suffix: String)
    case noExercises(routine: String)
    case unmappedPrimaryMuscle(exercise: String, raw: String)
    case invalidSessionCount(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            return "No se ha podido cargar el catálogo de ejercicios de la aplicación."
        case .tooManyOccurrences(let routine, let count):
            return "«\(routine.displayName)» aparece \(count) veces en la semana y el catálogo solo define variantes hasta 3 apariciones."
        case .missingVariant(let routine, let suffix):
            let label: String = suffix.isEmpty ? "base" : "variante \(suffix)"
            return "El catálogo no dispone de la \(label) de «\(routine.displayName)». No se generará una rutina con una variante inventada."
        case .noExercises(let routine):
            return "La variante «\(routine)» no contiene ejercicios en el catálogo."
        case .unmappedPrimaryMuscle(let exercise, let raw):
            return "No se puede relacionar el músculo principal «\(raw)» del ejercicio «\(exercise)» con ningún grupo de la app."
        case .invalidSessionCount(let expected, let actual):
            return "La semana generada tiene \(actual) sesiones y debería tener \(expected)."
        }
    }
}

/// Convierte una propuesta de split en una semana de sesiones con ejercicios.
enum RoutineGenerator {
    static func generate(
        proposal: SplitProposal,
        catalog: ExerciseCatalogStore? = ExerciseCatalogStore.shared
    ) throws -> GeneratedWeek {
        guard let catalog: ExerciseCatalogStore = catalog else {
            throw RoutineGenerationError.catalogUnavailable
        }

        var totalOccurrences: [String: Int] = [:]
        for routine in proposal.sessions {
            totalOccurrences[routine.rawValue, default: 0] += 1
        }

        var assignedOccurrences: [String: Int] = [:]
        var sessions: [GeneratedSession] = []

        for (index, routine) in proposal.sessions.enumerated() {
            let total: Int = totalOccurrences[routine.rawValue] ?? 1
            guard total <= 3 else {
                throw RoutineGenerationError.tooManyOccurrences(routine: routine, count: total)
            }

            let occurrence: Int = (assignedOccurrences[routine.rawValue] ?? 0) + 1
            assignedOccurrences[routine.rawValue] = occurrence

            let suffixes: [String] = ExerciseCatalogStore.suffixes(for: total)
            guard occurrence <= suffixes.count else {
                throw RoutineGenerationError.missingVariant(routine: routine, suffix: "")
            }

            let suffix: String = suffixes[occurrence - 1]

            guard let variant: CatalogRoutineVariant = catalog.variant(
                for: routine,
                occurrences: total,
                suffix: suffix
            ) else {
                throw RoutineGenerationError.missingVariant(routine: routine, suffix: suffix)
            }

            let records: [CatalogExerciseRecord] = ExerciseRules.orderedExercises(from: variant.exercises)
            guard !records.isEmpty else {
                throw RoutineGenerationError.noExercises(routine: variant.routineRaw)
            }

            var exercises: [GeneratedExercise] = []

            for (order, record) in records.enumerated() {
                let primary: [MuscleGroup] = ExerciseRules.primaryMuscles(for: record)
                guard !primary.isEmpty else {
                    throw RoutineGenerationError.unmappedPrimaryMuscle(
                        exercise: record.name,
                        raw: record.primaryRaw
                    )
                }

                let equipment: EquipmentType = ExerciseRules.equipment(for: record.name)

                var unmapped: [String] = ExerciseRules.unmappedMuscles(in: record.primaryRaw)
                for token in ExerciseRules.unmappedMuscles(in: record.secondaryRaw) where !unmapped.contains(token) {
                    unmapped.append(token)
                }

                exercises.append(
                    GeneratedExercise(
                        id: "\(index)-\(order)-\(ExerciseRules.normalizedName(record.name))",
                        name: record.name,
                        sets: record.sets,
                        repsMin: record.repsMin,
                        repsMax: record.repsMax,
                        restSeconds: record.restSeconds,
                        isCompound: record.isCompound,
                        primaryMuscles: primary,
                        secondaryMuscles: ExerciseRules.secondaryMuscles(for: record),
                        equipment: equipment,
                        requiresStraps: record.requiresStraps,
                        notes: record.notes,
                        primaryMuscleText: record.primaryRaw,
                        secondaryMuscleText: record.secondaryRaw,
                        unmappedMuscles: unmapped
                    )
                )
            }

            let name: String = suffix.isEmpty
                ? routine.displayName
                : "\(routine.displayName) \(suffix)"

            sessions.append(
                GeneratedSession(
                    id: "\(index)-\(routine.rawValue)-\(suffix)",
                    index: index,
                    routine: routine,
                    variantSuffix: suffix,
                    name: name,
                    exercises: exercises
                )
            )
        }

        guard sessions.count == proposal.w else {
            throw RoutineGenerationError.invalidSessionCount(expected: proposal.w, actual: sessions.count)
        }

        let notices: [RoutineNotice] = RecoveryAnalysisService.analyze(sessions: sessions)
            + FatigueAnalysisService.analyze(sessions: sessions)

        var limitations: [String] = [
            "El orden de las sesiones es el del split. La app no asigna días concretos del calendario."
        ]

        if 7 - sessions.count > 0 {
            limitations.append("Quedan \(7 - sessions.count) días sin sesión en el ciclo de 7 días.")
        }

        var unmapped: [String] = []
        for session in sessions {
            for exercise in session.exercises {
                for token in exercise.unmappedMuscles where !unmapped.contains(token) {
                    unmapped.append(token)
                }
            }
        }

        if !unmapped.isEmpty {
            let detail: String = unmapped.map { (token: String) -> String in
                return "«\(token)»"
            }
            .joined(separator: ", ")

            limitations.append("Análisis muscular parcial: el catálogo usa \(detail), sin equivalencia exacta en la app. La recuperación de esos músculos no se evalúa; el dato original se conserva en la ficha del ejercicio.")
        }

        return GeneratedWeek(
            w: proposal.w,
            l: proposal.l,
            u: proposal.u,
            splitExpression: proposal.expression,
            sessions: sessions,
            notices: notices,
            limitations: limitations
        )
    }
}
