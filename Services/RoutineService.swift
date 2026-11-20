import Foundation
import SwiftData

/// Aplica el plan de organización elegido en el onboarding o en
/// Ajustes → Cambiar rutina.
///
/// Reglas de protección de datos:
/// - Nunca elimina rutinas ni ejercicios del catálogo.
/// - Solo se archivan (`isArchived`) rutinas activas: las generadas en el
///   onboarding y, al cambiar la organización desde Ajustes, también las
///   manuales y las cinco personales. Nunca se borran, así que las sesiones
///   históricas mantienen sus referencias.
/// - Las sesiones, series, pesos y récords no se tocan.
/// - Todo se guarda en una única transacción: ante un error se hace `rollback`
///   y la app se queda exactamente como estaba.
///
/// `replacesOrganization` solo se usa desde Ajustes → Cambiar rutina: la
/// organización actual se sustituye entera, así que también dejan de estar
/// activas sus rutinas manuales y las cinco personales. Las rutinas nunca se
/// borran y el historial sigue apuntando a ellas.
enum RoutineService {

    /// Resultado de intentar eliminar una rutina desde la interfaz.
    enum DeletionPolicy: Equatable {
        /// Se puede borrar: no está protegida ni referenciada por un plan.
        case delete
        /// Está referenciada por un plan asistido (activo o histórico). Se
        /// archiva para no dejar referencias huérfanas.
        case archiveReferenced
        /// Es una de las cinco rutinas personales protegidas.
        case protectedPersonal
    }

    static func isProtectedPersonalRoutine(_ routine: Routine) -> Bool {
        return seededPersonalRoutineIDs.contains(routine.id)
    }

    /// Decide qué hacer antes de borrar una rutina. La comprobación de planes
    /// incluye también los históricos: `AssistedWeekPlan` guarda sus referencias
    /// por UUID y no debe quedar apuntando a una rutina inexistente.
    static func deletionPolicy(for routine: Routine, context: ModelContext) -> DeletionPolicy {
        if isProtectedPersonalRoutine(routine) {
            return .protectedPersonal
        }

        let plans: [AssistedWeekPlan]
        do {
            plans = try context.fetch(FetchDescriptor<AssistedWeekPlan>())
        } catch {
            // Ante un error de lectura no se borra: se archiva de forma
            // conservadora para no romper una referencia que no se ha podido
            // comprobar.
            print("[Persistence] No se pudieron comprobar los planes asistidos: \(error)")
            return .archiveReferenced
        }

        for plan in plans {
            if plan.days.contains(where: { (day: AssistedWeekDayRecord) -> Bool in
                return day.routineID == routine.id
            }) {
                return .archiveReferenced
            }

            // Un plan con datos ilegibles también se considera una posible
            // referencia: nunca se borra una rutina sobre una comprobación
            // incompleta.
            if !plan.daysData.isEmpty && plan.days.isEmpty {
                return .archiveReferenced
            }
        }

        return .delete
    }

    // MARK: - Aplicación del plan

    static func apply(
        plan: RoutinePlanDraft,
        preferences: OnboardingPreferences,
        context: ModelContext,
        generatedWeek: GeneratedWeek? = nil,
        assistedWeek: AssistedWeekDraft? = nil,
        replacesOrganization: Bool = false
    ) throws -> RoutineApplicationResult {
        guard let mode = plan.mode else {
            throw RoutineConfigurationError.missingOrganizationMode
        }

        guard preferences.hasValidEquipment else {
            throw RoutineConfigurationError.emptyPlateSelection
        }

        let previousAutosave: Bool = context.autosaveEnabled
        context.autosaveEnabled = false

        var archivedCount: Int = 0
        var createdCount: Int = 0

        do {
            switch mode {
            case .createOwn:
                archivedCount = try archiveActiveRoutines(context: context, replacesOrganization: replacesOrganization)
                try deactivateAssistedWeekPlans(context: context)
                createdCount = try createEmptyRoutines(plan: plan, context: context)

            case .automatic:
                guard let week = generatedWeek else {
                    throw RoutineConfigurationError.missingGeneratedPlan
                }
                archivedCount = try archiveActiveRoutines(context: context, replacesOrganization: replacesOrganization)
                try deactivateAssistedWeekPlans(context: context)
                createdCount = try createGeneratedRoutines(
                    week: week,
                    source: .automatic,
                    context: context
                ).count

            case .templates:
                guard let assistedWeek else {
                    throw RoutineConfigurationError.missingAssistedWeek
                }
                guard assistedWeek.days.count == AssistedWeekday.allCases.count else {
                    throw RoutineConfigurationError.missingAssistedWeek
                }

                // Se archiva el plan anterior: en el onboarding solo el
                // generado (automático o asistido); al cambiar la organización,
                // todas las rutinas activas.
                archivedCount = try archiveActiveRoutines(context: context, replacesOrganization: replacesOrganization)
                let routines: [Routine] = try createGeneratedRoutines(
                    week: assistedWeek.week,
                    source: .assisted,
                    context: context
                )
                createdCount = routines.count
                try createAssistedWeekPlan(
                    draft: assistedWeek,
                    routines: routines,
                    context: context
                )
            }

            try context.save()
        } catch let configurationError as RoutineConfigurationError {
            context.rollback()
            context.autosaveEnabled = previousAutosave
            throw configurationError
        } catch {
            context.rollback()
            context.autosaveEnabled = previousAutosave

            if let localized = error as? LocalizedError, let message = localized.errorDescription {
                throw RoutineConfigurationError.generationFailed(message)
            }
            throw RoutineConfigurationError.persistenceFailed
        }

        context.autosaveEnabled = previousAutosave

        // Los ajustes y la modalidad se escriben solo después de que el plan
        // esté guardado en disco.
        OnboardingService.applyPreferences(preferences)
        storePlan(plan, mode: mode)

        if mode == .automatic, let week = generatedWeek {
            storeAutomaticConfiguration(week)
        }

        return RoutineApplicationResult(
            mode: mode,
            archivedRoutineCount: archivedCount,
            createdRoutineCount: createdCount
        )
    }

    // MARK: - Archivado

    /// Archiva las rutinas del plan activo. No las borra: el historial de
    /// sesiones sigue apuntando a sus IDs.
    ///
    /// En el onboarding solo se archivan las generadas: las manuales se
    /// conservan aunque estén activas y la rutina temporal del entreno libre
    /// (`isTemplate == false`) nunca se archiva. `source == .manual` es también
    /// el valor seguro para filas antiguas sin procedencia. Las cinco rutinas
    /// personales sembradas se excluyen por ID aunque su origen sea `automatic`.
    ///
    /// Al cambiar la organización desde Ajustes (`replacesOrganization`) se
    /// archivan todas las rutinas activas, incluidas las manuales y las cinco
    /// personales: forman parte de la organización que se sustituye. Solo se
    /// desactivan; sus datos y su historial permanecen.
    private static func archiveActiveRoutines(context: ModelContext, replacesOrganization: Bool) throws -> Int {
        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        var archived: Int = 0

        for routine in routines where routine.isActivePlanRoutine {
            if !replacesOrganization && (routine.source == .manual || isProtectedPersonalRoutine(routine)) {
                continue
            }
            routine.isArchived = true
            archived += 1
        }

        return archived
    }

    // MARK: - Creación de estructuras vacías

    private static func createEmptyRoutines(plan: RoutinePlanDraft, context: ModelContext) throws -> Int {
        let count: Int = plan.clampedRoutineCount

        for index in 0..<count {
            let routine: Routine = Routine(
                name: plan.routineName(at: index),
                isTemplate: true,
                sortOrder: index,
                exercises: [],
                source: .manual
            )
            context.insert(routine)
        }

        return count
    }

    // MARK: - Creación de la semana generada

    /// Crea una rutina por sesión con sus ejercicios, series, repeticiones y
    /// descansos del catálogo. Reutiliza ejercicios existentes por nombre
    /// normalizado para no duplicar la biblioteca del usuario.
    private static func createGeneratedRoutines(
        week: GeneratedWeek,
        source: RoutineSource,
        context: ModelContext
    ) throws -> [Routine] {
        let existing: [Exercise] = try context.fetch(FetchDescriptor<Exercise>())
        var cache: [String: Exercise] = [:]
        for exercise in existing {
            cache[ExerciseRules.normalizedName(exercise.name)] = exercise
        }

        var routines: [Routine] = []

        for session in week.sessions {
            let routine: Routine = Routine(
                name: session.name,
                isTemplate: true,
                sortOrder: session.index,
                exercises: [],
                source: source
            )
            context.insert(routine)
            routines.append(routine)

            var links: [RoutineExercise] = []

            for (order, generated) in session.exercises.enumerated() {
                let exercise: Exercise = try resolveExercise(
                    generated,
                    cache: &cache,
                    context: context
                )

                let link: RoutineExercise = RoutineExercise(
                    exercise: exercise,
                    defaultSets: generated.sets,
                    targetRepsMin: generated.repsMin,
                    targetRepsMax: generated.repsMax,
                    sortOrder: order,
                    defaultWeight: 0.0,
                    restSeconds: generated.restSeconds,
                    notes: generated.notes,
                    hasCustomRest: false
                )
                context.insert(link)
                links.append(link)
            }

            routine.exercises = links
        }

        return routines
    }

    private static func createAssistedWeekPlan(
        draft: AssistedWeekDraft,
        routines: [Routine],
        context: ModelContext
    ) throws {
        try deactivateAssistedWeekPlans(context: context)

        var records: [AssistedWeekDayRecord] = []

        for day in draft.days {
            if day.isRest {
                records.append(
                    AssistedWeekDayRecord(
                        weekdayIndex: day.weekday.rawValue,
                        isRest: true,
                        routineID: nil,
                        routineName: "Descanso",
                        variantSuffix: "",
                        sessionIndex: nil
                    )
                )
                continue
            }

            guard let sessionIndex = day.sessionIndex,
                  sessionIndex >= 0,
                  sessionIndex < draft.week.sessions.count,
                  sessionIndex < routines.count else {
                throw RoutineConfigurationError.persistenceFailed
            }

            let session: GeneratedSession = draft.week.sessions[sessionIndex]
            records.append(
                AssistedWeekDayRecord(
                    weekdayIndex: day.weekday.rawValue,
                    isRest: false,
                    routineID: routines[sessionIndex].id,
                    routineName: session.name,
                    variantSuffix: session.variantSuffix,
                    sessionIndex: sessionIndex
                )
            )
        }

        guard records.count == AssistedWeekday.allCases.count,
              Set(records.map(\.weekdayIndex)).count == AssistedWeekday.allCases.count else {
            throw RoutineConfigurationError.missingAssistedWeek
        }

        let plan: AssistedWeekPlan = AssistedWeekPlan(days: records)
        context.insert(plan)
    }

    /// Un plan semanal solo puede estar activo si la modalidad vigente es el
    /// constructor asistido. Al aplicar un plan automático o manual se conserva
    /// el registro histórico, pero deja de estar activo.
    private static func deactivateAssistedWeekPlans(context: ModelContext) throws {
        let plans: [AssistedWeekPlan] = (try? context.fetch(FetchDescriptor<AssistedWeekPlan>())) ?? []
        for plan in plans where plan.isActivePlan {
            plan.isActivePlan = false
        }
    }

    private static func resolveExercise(
        _ generated: GeneratedExercise,
        cache: inout [String: Exercise],
        context: ModelContext
    ) throws -> Exercise {
        let key: String = ExerciseRules.normalizedName(generated.name)

        if let existing: Exercise = cache[key] {
            return existing
        }

        guard let primary: MuscleGroup = generated.primaryMuscles.first else {
            throw RoutineGenerationError.unmappedPrimaryMuscle(exercise: generated.name, raw: "")
        }

        let exercise: Exercise = Exercise(
            name: generated.name,
            muscleGroup: primary,
            equipmentType: generated.equipment,
            requiresStraps: generated.requiresStraps,
            targetRepsMin: generated.repsMin,
            targetRepsMax: generated.repsMax,
            defaultRestCondition: .timer(seconds: generated.restSeconds),
            isCompound: generated.isCompound,
            primaryMuscles: generated.primaryMuscles,
            secondaryMuscles: generated.secondaryMuscles,
            notes: generated.notes,
            trackingMode: .reps,
            catalogPrimaryMusclesText: generated.primaryMuscleText,
            catalogSecondaryMusclesText: generated.secondaryMuscleText
        )

        context.insert(exercise)
        cache[key] = exercise
        return exercise
    }

    // MARK: - Persistencia de la modalidad

    static func storePlan(_ plan: RoutinePlanDraft, mode: RoutineOrganizationMode) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.set(mode.rawValue, forKey: UserSettingsManager.routineOrganizationModeKey)
        defaults.set(plan.clampedRoutineCount, forKey: UserSettingsManager.ownRoutineCountKey)
    }

    /// Guarda los parámetros y el split elegidos para poder mostrarlos en
    /// ajustes y auditorías posteriores.
    static func storeAutomaticConfiguration(_ week: GeneratedWeek) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.set(week.w, forKey: UserSettingsManager.automaticSplitDaysKey)
        defaults.set(week.l, forKey: UserSettingsManager.automaticSplitLegsKey)
        defaults.set(week.u, forKey: UserSettingsManager.automaticSplitUpperKey)
        defaults.set(week.splitExpression, forKey: UserSettingsManager.automaticSplitExpressionKey)
    }
}
