import XCTest
import Foundation
import SwiftData

@testable import AppGym

@MainActor
final class RoutinePersistenceTests: XCTestCase {

    func testGeneratedWeekArchivesActivePlanAndKeepsHistory() throws {
        let context = try makeContext()

        let bench = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(bench)

        let oldRoutine = Routine(
            name: "Rutina antigua",
            isTemplate: true,
            sortOrder: 0,
            exercises: [],
            source: .automatic
        )
        context.insert(oldRoutine)

        let manualRoutine = Routine(
            name: "Rutina manual",
            isTemplate: true,
            sortOrder: 50,
            exercises: [],
            source: .manual
        )
        context.insert(manualRoutine)

        let freeRoutine = Routine(name: "Entreno libre", isTemplate: false, sortOrder: 99, exercises: [], source: .manual)
        context.insert(freeRoutine)

        let oldLink = RoutineExercise(
            exercise: bench,
            defaultSets: 3,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 0,
            restSeconds: 180
        )
        context.insert(oldLink)
        oldRoutine.exercises = [oldLink]

        let session = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            routineName: "Rutina antigua"
        )
        context.insert(session)

        let log = WorkoutSetLog(
            date: Date(timeIntervalSince1970: 1_700_000_100),
            weight: 82.5,
            reps: 8,
            targetRepsMin: 6,
            targetRepsMax: 8,
            isCompleted: true,
            setNumber: 1,
            exercise: bench,
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]

        try context.save()

        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 3,
            l: 3,
            u: 0,
            expression: "Legs x3",
            sessions: [.legs, .legs, .legs]
        )
        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)

        var plan = RoutinePlanDraft()
        plan.mode = .automatic

        var preferences = OnboardingPreferences.defaults
        preferences.availablePlates = [1.25, 2.5, 5.0, 10.0, 20.0]

        _ = try RoutineService.apply(
            plan: plan,
            preferences: preferences,
            context: context,
            generatedWeek: week
        )

        // La rutina automática anterior se archiva; la manual y la libre no.
        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.filter { $0.isActivePlanRoutine }.count, week.sessions.count + 1)

        let archived: Routine = try XCTUnwrap(routines.first(where: { $0.name == "Rutina antigua" }))
        XCTAssertTrue(archived.isArchived)
        XCTAssertEqual(archived.source, .automatic)
        XCTAssertEqual(archived.exercises.count, 1)
        XCTAssertEqual(archived.exercises.first?.exercise?.name, "Press banca")

        let manual: Routine = try XCTUnwrap(routines.first(where: { $0.name == "Rutina manual" }))
        XCTAssertFalse(manual.isArchived)
        XCTAssertTrue(manual.isActivePlanRoutine)
        XCTAssertEqual(manual.source, .manual)

        let generated: [Routine] = routines.filter { $0.source == .automatic && $0.isActivePlanRoutine }
        XCTAssertEqual(generated.count, week.sessions.count)

        let free: Routine = try XCTUnwrap(routines.first(where: { $0.name == "Entreno libre" }))
        XCTAssertFalse(free.isArchived)
        XCTAssertFalse(free.isActivePlanRoutine)
        XCTAssertEqual(free.source, .manual)

        // Historial intacto.
        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.routineName, "Rutina antigua")

        let logs: [WorkoutSetLog] = try context.fetch(FetchDescriptor<WorkoutSetLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.weight, 82.5)
        XCTAssertEqual(logs.first?.reps, 8)
        XCTAssertEqual(logs.first?.exercise?.name, "Press banca")
        XCTAssertEqual(logs.first?.session?.routineName, "Rutina antigua")

        // El ejercicio histórico no se duplica y los nuevos conservan el texto
        // muscular original del catálogo.
        let exercises: [Exercise] = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.filter { $0.name == "Press banca" }.count, 1)

        let generatedSource = try XCTUnwrap(week.sessions.first?.exercises.first)
        let generated: Exercise = try XCTUnwrap(exercises.first(where: { $0.name == generatedSource.name }))
        XCTAssertEqual(generated.catalogPrimaryMusclesText, generatedSource.primaryMuscleText)
        XCTAssertEqual(generated.catalogSecondaryMusclesText, generatedSource.secondaryMuscleText)
        XCTAssertFalse(generated.catalogPrimaryMusclesText.isEmpty)
    }

    func testRollbackRestoresArchiveFlagsAndLeavesHistoryUntouched() throws {
        let context = try makeContext()

        let bench = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(bench)

        let oldRoutine = Routine(
            name: "Rutina antigua",
            isTemplate: true,
            sortOrder: 0,
            exercises: [],
            source: .automatic
        )
        context.insert(oldRoutine)

        let session = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            routineName: "Rutina antigua"
        )
        context.insert(session)

        let log = WorkoutSetLog(
            date: Date(timeIntervalSince1970: 1_700_000_100),
            weight: 90.0,
            reps: 6,
            targetRepsMin: 6,
            targetRepsMax: 8,
            isCompleted: true,
            setNumber: 1,
            exercise: bench,
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]

        try context.save()

        // Semana inválida a propósito: el ejercicio no tiene músculo principal,
        // así que la creación falla después de haber archivado la rutina.
        let broken = GeneratedExercise(
            id: "broken",
            name: "Sin músculo",
            sets: 3,
            repsMin: 6,
            repsMax: 8,
            restSeconds: 90,
            isCompound: true,
            primaryMuscles: [],
            secondaryMuscles: [],
            equipment: .pendingClassification,
            requiresStraps: false,
            notes: "",
            primaryMuscleText: "",
            secondaryMuscleText: "",
            unmappedMuscles: []
        )

        let brokenSession = GeneratedSession(
            id: "broken-session",
            index: 0,
            routine: .legs,
            variantSuffix: "",
            name: "Legs",
            exercises: [broken]
        )

        let brokenWeek = GeneratedWeek(
            w: 1,
            l: 1,
            u: 0,
            splitExpression: "Legs",
            sessions: [brokenSession],
            notices: [],
            limitations: []
        )

        var plan = RoutinePlanDraft()
        plan.mode = .automatic

        var preferences = OnboardingPreferences.defaults
        preferences.availablePlates = [1.25, 2.5, 5.0, 10.0, 20.0]

        XCTAssertThrowsError(
            try RoutineService.apply(
                plan: plan,
                preferences: preferences,
                context: context,
                generatedWeek: brokenWeek
            )
        )

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertFalse(try XCTUnwrap(routines.first).isArchived)

        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)

        let logs: [WorkoutSetLog] = try context.fetch(FetchDescriptor<WorkoutSetLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.weight, 90.0)
        XCTAssertEqual(logs.first?.reps, 6)

        let exercises: [Exercise] = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.count, 1)
    }

    func testManualRoutineWithSeedNameIsNotClassifiedAutomatic() throws {
        let context = try makeContext()
        let manual = Routine(name: "PUSH", isTemplate: true)
        manual.sourceRaw = nil
        context.insert(manual)
        try context.save()

        UserDefaults.standard.removeObject(forKey: MockDataGenerator.legacyRoutineSourceFlagKey)
        MockDataGenerator.classifyLegacyRoutineSourcesIfNeeded(context: context)

        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Routine>()).first(where: { $0.id == manual.id })
        )
        XCTAssertEqual(fetched.source, .manual)
        XCTAssertTrue(fetched.isActivePlanRoutine)
    }

    func testTableRewriteDoesNotTouchManualRoutineWithSeedName() throws {
        let context = try makeContext()
        let press: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(press)

        let manual: Routine = Routine(name: "PUSH", isTemplate: true, source: .manual)
        context.insert(manual)
        let link: RoutineExercise = RoutineExercise(
            exercise: press,
            defaultSets: 4,
            targetRepsMin: 5,
            targetRepsMax: 7,
            sortOrder: 0,
            notes: "nota personal"
        )
        context.insert(link)
        manual.exercises = [link]
        try context.save()

        UserDefaults.standard.removeObject(forKey: MockDataGenerator.routineTableUpdateFlagKey)
        defer {
            UserDefaults.standard.removeObject(forKey: MockDataGenerator.routineTableUpdateFlagKey)
        }
        MockDataGenerator.applyRoutineTableUpdateIfNeeded(context: context)

        let fetched: Routine = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Routine>()).first(where: { $0.id == manual.id })
        )
        XCTAssertEqual(fetched.name, "PUSH")
        XCTAssertEqual(fetched.source, .manual)
        XCTAssertFalse(fetched.isArchived)
        XCTAssertEqual(fetched.exercises.count, 1)
        XCTAssertEqual(fetched.exercises.first?.id, link.id)
        XCTAssertEqual(fetched.exercises.first?.notes, "nota personal")
        XCTAssertEqual(fetched.exercises.first?.exercise?.name, "Press banca")
    }

    func testTableSyncPreservesProtectedRoutineContentAndConfiguration() throws {
        let context: ModelContext = try makeAssistedContext()
        let seedID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let exercise: Exercise = Exercise(
            name: "Press banca inclinado",
            muscleGroup: .chest,
            equipmentType: .dumbbell
        )
        context.insert(exercise)

        let routine: Routine = Routine(
            id: seedID,
            name: "PUSH personal",
            isTemplate: true,
            sortOrder: 42,
            exercises: [],
            source: .automatic
        )
        context.insert(routine)
        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 5,
            targetRepsMin: 4,
            targetRepsMax: 6,
            sortOrder: 9,
            defaultWeight: 82.5,
            restSeconds: 222,
            notes: "configuración personal",
            hasCustomRest: true
        )
        context.insert(link)
        routine.exercises = [link]
        try context.save()

        UserDefaults.standard.removeObject(forKey: MockDataGenerator.routineTableUpdateFlagKey)
        defer {
            UserDefaults.standard.removeObject(forKey: MockDataGenerator.routineTableUpdateFlagKey)
        }
        MockDataGenerator.applyRoutineTableUpdateIfNeeded(context: context)

        let fetched: Routine = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Routine>()).first(where: { $0.id == seedID })
        )
        XCTAssertEqual(fetched.name, "PUSH personal")
        XCTAssertEqual(fetched.sortOrder, 42)
        XCTAssertEqual(fetched.source, .automatic)
        XCTAssertEqual(fetched.exercises.count, 1)
        XCTAssertEqual(fetched.exercises.first?.id, link.id)
        XCTAssertEqual(fetched.exercises.first?.defaultSets, 5)
        XCTAssertEqual(fetched.exercises.first?.targetRepsMin, 4)
        XCTAssertEqual(fetched.exercises.first?.targetRepsMax, 6)
        XCTAssertEqual(fetched.exercises.first?.sortOrder, 9)
        XCTAssertEqual(fetched.exercises.first?.defaultWeight, 82.5)
        XCTAssertEqual(fetched.exercises.first?.restSeconds, 222)
        XCTAssertEqual(fetched.exercises.first?.notes, "configuración personal")
        XCTAssertEqual(fetched.exercises.first?.exercise?.equipmentType, .dumbbell)
    }

    func testDeletionPolicyProtectsTheFivePersonalRoutines() throws {
        let context: ModelContext = try makeAssistedContext()
        let seedID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let routine: Routine = Routine(id: seedID, name: "PUSH", isTemplate: true, source: .automatic)
        context.insert(routine)
        try context.save()

        XCTAssertEqual(
            RoutineService.deletionPolicy(for: routine, context: context),
            .protectedPersonal
        )
    }

    func testDeletionPolicyArchivesRoutineReferencedByHistoricalAssistedPlan() throws {
        let context: ModelContext = try makeAssistedContext()
        let routine: Routine = Routine(name: "Rutina referenciada", isTemplate: true, source: .manual)
        context.insert(routine)

        let day: AssistedWeekDayRecord = AssistedWeekDayRecord(
            weekdayIndex: 0,
            isRest: false,
            routineID: routine.id,
            routineName: routine.name,
            variantSuffix: "",
            sessionIndex: 0
        )
        let plan: AssistedWeekPlan = AssistedWeekPlan(isActivePlan: false, days: [day])
        context.insert(plan)
        try context.save()

        XCTAssertEqual(
            RoutineService.deletionPolicy(for: routine, context: context),
            .archiveReferenced
        )
    }

    func testDeletionPolicyAllowsUnreferencedManualRoutine() throws {
        let context: ModelContext = try makeAssistedContext()
        let routine: Routine = Routine(name: "Rutina libre", isTemplate: true, source: .manual)
        context.insert(routine)
        try context.save()

        XCTAssertEqual(
            RoutineService.deletionPolicy(for: routine, context: context),
            .delete
        )
    }

    func testSeededRoutineIsRecognizedByStableID() throws {
        XCTAssertEqual(MockDataGenerator.seededRoutineIDs.count, 5)
        let seedID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)

        let context = try makeContext()
        let seeded = Routine(id: seedID, name: "Nombre cambiado por el usuario", isTemplate: true)
        seeded.sourceRaw = nil
        context.insert(seeded)
        try context.save()

        UserDefaults.standard.removeObject(forKey: MockDataGenerator.legacyRoutineSourceFlagKey)
        MockDataGenerator.classifyLegacyRoutineSourcesIfNeeded(context: context)

        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Routine>()).first(where: { $0.id == seedID })
        )
        XCTAssertEqual(fetched.source, .automatic)
    }

    func testLegacyRoutineWithoutSourceIsSafeManual() throws {
        let context = try makeContext()
        let routine = Routine(name: "Rutina heredada", isTemplate: true)
        routine.sourceRaw = nil
        context.insert(routine)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<Routine>()).first)
        XCTAssertNil(fetched.sourceRaw)
        XCTAssertEqual(fetched.source, .manual)
        XCTAssertTrue(fetched.isActivePlanRoutine)
    }

    // MARK: - Constructor asistido de siete días

    func testAssistedBuilderStartsWithSevenEmptyDays() throws {
        let viewModel: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )

        XCTAssertEqual(viewModel.days.count, 7)
        XCTAssertEqual(viewModel.configuredCount, 0)
        XCTAssertEqual(viewModel.missingWeekdays, AssistedWeekday.allCases)
        XCTAssertFalse(viewModel.canContinue)
        XCTAssertTrue(viewModel.days.allSatisfy { $0.selection == .unassigned })
    }

    func testAssistedBuilderAssignsBaseAndVariantsInChronologicalOrder() throws {
        let viewModel: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )

        configure(
            viewModel,
            selections: [.routine(.legs), .routine(.pull), .routine(.legs), .rest, .routine(.legs), .routine(.pull), .rest]
        )

        XCTAssertTrue(viewModel.canContinue)
        XCTAssertEqual(viewModel.assignedSuffix(for: .monday), "A")
        XCTAssertEqual(viewModel.assignedSuffix(for: .wednesday), "B")
        XCTAssertEqual(viewModel.assignedSuffix(for: .friday), "C")
        XCTAssertEqual(viewModel.assignedSuffix(for: .tuesday), "A")
        XCTAssertEqual(viewModel.assignedSuffix(for: .saturday), "B")

        XCTAssertTrue(viewModel.buildWeek())
        let week = try XCTUnwrap(viewModel.generatedWeek)
        XCTAssertEqual(week.sessions.count, 5)
        XCTAssertEqual(viewModel.sessionEntries.count, 5)
        XCTAssertEqual(week.sessions.map(\.name), ["Legs A", "Pull A", "Legs B", "Legs C", "Pull B"])
        XCTAssertNil(viewModel.sessionsByWeekday[.thursday])
        XCTAssertNil(viewModel.sessionsByWeekday[.sunday])
    }

    func testAssistedBuilderBlocksThreeAppearancesWithoutVariantC() throws {
        let viewModel: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )

        configure(
            viewModel,
            selections: [.routine(.push), .routine(.pull), .routine(.push), .rest, .routine(.push), .routine(.pull), .rest]
        )

        XCTAssertFalse(viewModel.canContinue)
        XCTAssertTrue(viewModel.validationErrors.contains { $0.contains("Push") && $0.contains("variante C") })
        XCTAssertFalse(viewModel.buildWeek())
        XCTAssertNil(viewModel.generatedWeek)
    }

    func testAssistedBuilderUsesBaseWhenRoutineAppearsOnce() throws {
        let viewModel: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )

        configure(
            viewModel,
            selections: [.routine(.arms), .rest, .rest, .rest, .rest, .rest, .rest]
        )

        XCTAssertTrue(viewModel.canContinue)
        XCTAssertEqual(viewModel.assignedSuffix(for: .monday), "")
        XCTAssertTrue(viewModel.buildWeek())
        XCTAssertEqual(viewModel.generatedWeek?.sessions.first?.name, "Arms")
    }

    func testAssistedBuilderRecalculatesAfterClearingADay() throws {
        let viewModel: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )

        configure(
            viewModel,
            selections: [.routine(.push), .rest, .routine(.push), .rest, .rest, .rest, .rest]
        )
        XCTAssertEqual(viewModel.assignedSuffix(for: .monday), "A")
        XCTAssertEqual(viewModel.assignedSuffix(for: .wednesday), "B")

        viewModel.clear(.monday)
        viewModel.selectRest(for: .monday)

        XCTAssertEqual(viewModel.assignedSuffix(for: .wednesday), "")
        XCTAssertTrue(viewModel.canContinue)
    }

    func testAssistedBuilderAllowsAWeekOfRestWithoutMinimumTraining() throws {
        let viewModel: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )

        configure(viewModel, selections: Array(repeating: .rest, count: 7))

        XCTAssertTrue(viewModel.canContinue)
        XCTAssertTrue(viewModel.buildWeek())
        XCTAssertEqual(viewModel.generatedWeek?.sessions.count, 0)
        XCTAssertEqual(viewModel.restDayCount, 7)
        XCTAssertEqual(viewModel.generatedWeek?.notices.count, 0)
    }

    func testAssistedAnalysisUsesRealConsecutiveAndNonConsecutiveDays() throws {
        let consecutive: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )
        configure(
            consecutive,
            selections: [.routine(.push), .routine(.push), .rest, .rest, .rest, .rest, .rest]
        )
        XCTAssertTrue(consecutive.buildWeek())
        let consecutiveWeek = try XCTUnwrap(consecutive.generatedWeek)
        XCTAssertEqual(consecutiveWeek.recoveryNotices.count, 1)
        XCTAssertEqual(consecutiveWeek.recoveryNotices.first?.involvedDays, ["LUNES", "MARTES"])

        let separated: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )
        configure(
            separated,
            selections: [.routine(.push), .rest, .routine(.push), .rest, .rest, .rest, .rest]
        )
        XCTAssertTrue(separated.buildWeek())
        let separatedWeek = try XCTUnwrap(separated.generatedWeek)
        XCTAssertTrue(separatedWeek.recoveryNotices.isEmpty)
        XCTAssertTrue(separatedWeek.fatigueNotices.contains { $0.reason.contains("MIÉRCOLES") })
        XCTAssertTrue(separatedWeek.fatigueNotices.contains { $0.reason.contains("Frecuencia como músculo principal") })
        XCTAssertTrue(separatedWeek.fatigueNotices.contains { $0.reason.contains("músculo secundario") })
        XCTAssertTrue(separated.canContinue, "Los avisos no deben bloquear la confirmación.")

        let partial: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )
        configure(
            partial,
            selections: [.routine(.pull), .rest, .rest, .rest, .rest, .rest, .rest]
        )
        XCTAssertTrue(partial.buildWeek())
        let partialWeek = try XCTUnwrap(partial.generatedWeek)
        XCTAssertTrue(partialWeek.hasPartialMuscleAnalysis)
        XCTAssertTrue(partialWeek.limitations.contains { $0.contains("Análisis muscular parcial") })
    }

    func testAssistedGenerationKeepsCompoundThenAlphabeticalOrder() throws {
        let viewModel: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )
        configure(
            viewModel,
            selections: [.routine(.legs), .rest, .rest, .rest, .rest, .rest, .rest]
        )
        XCTAssertTrue(viewModel.buildWeek())
        let session = try XCTUnwrap(viewModel.generatedWeek?.sessions.first)

        let flags: [Bool] = session.exercises.map(\.isCompound)
        let firstIsolation: Int = flags.firstIndex(of: false) ?? flags.count
        XCTAssertFalse(flags.prefix(firstIsolation).contains(false))
        XCTAssertFalse(flags.dropFirst(firstIsolation).contains(true))

        let compoundNames: [String] = session.exercises
            .filter { $0.isCompound }
            .map { ExerciseRules.normalizedName($0.name) }
        let isolationNames: [String] = session.exercises
            .filter { !$0.isCompound }
            .map { ExerciseRules.normalizedName($0.name) }
        XCTAssertEqual(compoundNames, compoundNames.sorted())
        XCTAssertEqual(isolationNames, isolationNames.sorted())

        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let variant = try XCTUnwrap(catalog.variant(for: .legs, occurrences: 1, suffix: ""))
        let expected = try XCTUnwrap(ExerciseRules.orderedExercises(from: variant.exercises).first)
        let generated = try XCTUnwrap(session.exercises.first)
        XCTAssertEqual(generated.name, expected.name)
        XCTAssertEqual(generated.sets, expected.sets)
        XCTAssertEqual(generated.repsMin, expected.repsMin)
        XCTAssertEqual(generated.repsMax, expected.repsMax)
        XCTAssertEqual(generated.restSeconds, expected.restSeconds)
    }

    func testAssistedPersistenceKeepsPersonalRoutinesRestDaysAndHistory() throws {
        let context: ModelContext = try makeAssistedContext()
        let personalID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let bench: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(bench)

        let personal: Routine = Routine(
            id: personalID,
            name: "PUSH",
            isTemplate: true,
            sortOrder: 0,
            exercises: [],
            source: .automatic
        )
        context.insert(personal)
        let link: RoutineExercise = RoutineExercise(
            exercise: bench,
            defaultSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 0,
            restSeconds: 180
        )
        context.insert(link)
        personal.exercises = [link]

        let history: WorkoutSession = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            routineName: "PUSH"
        )
        context.insert(history)
        try context.save()

        let viewModel: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )
        configure(
            viewModel,
            selections: [.routine(.legs), .routine(.pull), .rest, .routine(.legs), .rest, .routine(.pull), .rest]
        )
        XCTAssertTrue(viewModel.buildWeek())

        var plan: RoutinePlanDraft = RoutinePlanDraft()
        plan.mode = .templates
        var preferences: OnboardingPreferences = OnboardingPreferences.defaults
        preferences.availablePlates = [1.25, 2.5, 5.0, 10.0, 20.0]

        _ = try RoutineService.apply(
            plan: plan,
            preferences: preferences,
            context: context,
            assistedWeek: try XCTUnwrap(viewModel.savingDraft)
        )

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        let preserved: Routine = try XCTUnwrap(routines.first { $0.id == personalID })
        XCTAssertEqual(preserved.name, "PUSH")
        XCTAssertEqual(preserved.source, .automatic)
        XCTAssertFalse(preserved.isArchived)
        XCTAssertEqual(preserved.exercises.count, 1)
        XCTAssertEqual(preserved.exercises.first?.exercise?.name, "Press banca")

        let assisted: [Routine] = routines.filter { $0.source == .assisted && $0.isActivePlanRoutine }
        XCTAssertEqual(assisted.count, 4)
        XCTAssertEqual(Set(assisted.map(\.id)).count, 4)
        XCTAssertTrue(assisted.allSatisfy { !$0.exercises.isEmpty })
        if let firstAssisted = assisted.first, let firstLink = firstAssisted.exercises.first {
            XCTAssertGreaterThan(firstLink.defaultSets, 0)
            XCTAssertGreaterThanOrEqual(firstLink.targetRepsMax, firstLink.targetRepsMin)
            XCTAssertGreaterThan(firstLink.restSeconds, 0)
            XCTAssertEqual(firstLink.hasCustomRest, false)
        }

        let plans: [AssistedWeekPlan] = try context.fetch(FetchDescriptor<AssistedWeekPlan>())
        let savedPlan: AssistedWeekPlan = try XCTUnwrap(plans.first)
        XCTAssertTrue(savedPlan.isActivePlan)
        XCTAssertEqual(savedPlan.days.count, 7)
        XCTAssertEqual(savedPlan.days.filter { $0.isRest }.count, 3)
        XCTAssertEqual(savedPlan.days.filter { !$0.isRest }.count, 4)
        XCTAssertEqual(savedPlan.days.compactMap { $0.routineID }.count, 4)
        XCTAssertEqual(Set(savedPlan.days.filter { !$0.isRest }.map(\.variantSuffix)), Set(["A", "B"]))

        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.routineName, "PUSH")
    }

    func testAssistedReapplyArchivesOnlyPreviousAssistedRoutinesAndKeepsPlans() throws {
        let context: ModelContext = try makeAssistedContext()
        let personalID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let personal: Routine = Routine(id: personalID, name: "PUSH", isTemplate: true, source: .automatic)
        context.insert(personal)
        try context.save()

        let first: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )
        configure(
            first,
            selections: [.routine(.legs), .rest, .routine(.pull), .rest, .routine(.legs), .rest, .rest]
        )
        XCTAssertTrue(first.buildWeek())

        var plan: RoutinePlanDraft = RoutinePlanDraft()
        plan.mode = .templates
        var preferences: OnboardingPreferences = OnboardingPreferences.defaults
        preferences.availablePlates = [1.25, 2.5, 5.0, 10.0, 20.0]

        _ = try RoutineService.apply(
            plan: plan,
            preferences: preferences,
            context: context,
            assistedWeek: try XCTUnwrap(first.savingDraft)
        )

        let second: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )
        configure(second, selections: Array(repeating: .rest, count: 7))
        XCTAssertTrue(second.buildWeek())

        _ = try RoutineService.apply(
            plan: plan,
            preferences: preferences,
            context: context,
            assistedWeek: try XCTUnwrap(second.savingDraft)
        )

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.filter { $0.source == .assisted && $0.isActivePlanRoutine }.count, 0)
        XCTAssertEqual(routines.filter { $0.source == .assisted && $0.isArchived }.count, 3)
        let preserved: Routine = try XCTUnwrap(routines.first { $0.id == personalID })
        XCTAssertFalse(preserved.isArchived)

        let plans: [AssistedWeekPlan] = try context.fetch(FetchDescriptor<AssistedWeekPlan>())
        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans.filter { $0.isActivePlan }.count, 1)
        XCTAssertEqual(plans.first { $0.isActivePlan }?.days.filter { $0.isRest }.count, 7)
    }

    func testAutomaticApplyArchivesAssistedRoutinesAndDeactivatesAssistedPlan() throws {
        let context: ModelContext = try makeAssistedContext()
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()

        let assisted: AssistedSplitViewModel = AssistedSplitViewModel(catalog: catalog)
        configure(
            assisted,
            selections: [.routine(.legs), .rest, .rest, .rest, .rest, .rest, .rest]
        )
        XCTAssertTrue(assisted.buildWeek())

        var assistedPlan: RoutinePlanDraft = RoutinePlanDraft()
        assistedPlan.mode = .templates
        var preferences: OnboardingPreferences = OnboardingPreferences.defaults
        preferences.availablePlates = [1.25, 2.5, 5.0, 10.0, 20.0]

        _ = try RoutineService.apply(
            plan: assistedPlan,
            preferences: preferences,
            context: context,
            assistedWeek: try XCTUnwrap(assisted.savingDraft)
        )

        let automaticWeek: GeneratedWeek = try RoutineGenerator.generate(
            proposal: SplitProposal(w: 1, l: 1, u: 0, expression: "Legs", sessions: [.legs]),
            catalog: catalog
        )
        var automaticPlan: RoutinePlanDraft = RoutinePlanDraft()
        automaticPlan.mode = .automatic

        _ = try RoutineService.apply(
            plan: automaticPlan,
            preferences: preferences,
            context: context,
            generatedWeek: automaticWeek
        )

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertTrue(routines.filter { $0.source == .assisted }.allSatisfy { $0.isArchived })
        XCTAssertEqual(routines.filter { $0.source == .automatic && $0.isActivePlanRoutine }.count, 1)

        let plans: [AssistedWeekPlan] = try context.fetch(FetchDescriptor<AssistedWeekPlan>())
        XCTAssertEqual(plans.count, 1)
        XCTAssertFalse(try XCTUnwrap(plans.first).isActivePlan)
    }

    func testAssistedPersistenceRollsBackWhenPlanCannotBeBuilt() throws {
        let context: ModelContext = try makeAssistedContext()
        let personalID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let personal: Routine = Routine(id: personalID, name: "PUSH", isTemplate: true, source: .automatic)
        context.insert(personal)
        try context.save()

        let viewModel: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )
        configure(
            viewModel,
            selections: [.routine(.legs), .rest, .rest, .rest, .rest, .rest, .rest]
        )
        XCTAssertTrue(viewModel.buildWeek())
        let valid = try XCTUnwrap(viewModel.savingDraft)

        let brokenDays: [AssistedDayDraft] = valid.days.map { (day: AssistedDayDraft) -> AssistedDayDraft in
            return AssistedDayDraft(
                weekday: day.weekday,
                isRest: day.isRest,
                routineRaw: day.routineRaw,
                variantSuffix: day.variantSuffix,
                sessionIndex: day.isRest ? nil : 99
            )
        }
        let broken = AssistedWeekDraft(days: brokenDays, week: valid.week)

        var plan: RoutinePlanDraft = RoutinePlanDraft()
        plan.mode = .templates
        var preferences: OnboardingPreferences = OnboardingPreferences.defaults
        preferences.availablePlates = [1.25, 2.5, 5.0, 10.0, 20.0]

        XCTAssertThrowsError(
            try RoutineService.apply(
                plan: plan,
                preferences: preferences,
                context: context,
                assistedWeek: broken
            )
        )

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertFalse(try XCTUnwrap(routines.first).isArchived)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AssistedWeekPlan>()).count, 0)
    }

    func testAssistedPersistencePreservesAllFiveSeededPersonalRoutines() throws {
        let context: ModelContext = try makeAssistedContext()
        let bench: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(bench)

        for (index, id) in MockDataGenerator.seededRoutineIDs.enumerated() {
            let routine: Routine = Routine(
                id: id,
                name: "PERSONAL \(index)",
                isTemplate: true,
                sortOrder: index,
                exercises: [],
                source: .automatic
            )
            context.insert(routine)
            let link: RoutineExercise = RoutineExercise(
                exercise: bench,
                defaultSets: 3,
                targetRepsMin: 6,
                targetRepsMax: 8,
                sortOrder: 0,
                restSeconds: 150
            )
            context.insert(link)
            routine.exercises = [link]
        }
        try context.save()

        let viewModel: AssistedSplitViewModel = AssistedSplitViewModel(
            catalog: try TestResources.catalogStore()
        )
        configure(viewModel, selections: Array(repeating: .rest, count: 7))
        XCTAssertTrue(viewModel.buildWeek())

        var plan: RoutinePlanDraft = RoutinePlanDraft()
        plan.mode = .templates
        var preferences: OnboardingPreferences = OnboardingPreferences.defaults
        preferences.availablePlates = [1.25, 2.5, 5.0, 10.0, 20.0]

        _ = try RoutineService.apply(
            plan: plan,
            preferences: preferences,
            context: context,
            assistedWeek: try XCTUnwrap(viewModel.savingDraft)
        )

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        for id in MockDataGenerator.seededRoutineIDs {
            let routine: Routine = try XCTUnwrap(routines.first { $0.id == id })
            XCTAssertFalse(routine.isArchived)
            XCTAssertEqual(routine.source, .automatic)
            XCTAssertEqual(routine.exercises.count, 1)
            XCTAssertEqual(routine.exercises.first?.exercise?.name, "Press banca")
        }
        XCTAssertEqual(routines.count, MockDataGenerator.seededRoutineIDs.count)
    }

    // MARK: - StoreBootstrap y migración

    func testFailedOpenKeepsOriginalStoreAndDoesNotCreateEmptyContainer() throws {
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL: URL = directory.appendingPathComponent("default.store")
        let storeBytes: Data = Data("esto no es un store de SwiftData".utf8)
        let shmBytes: Data = Data("shm original".utf8)
        let walBytes: Data = Data("wal original".utf8)

        try storeBytes.write(to: storeURL)
        try shmBytes.write(to: URL(fileURLWithPath: storeURL.path + "-shm"))
        try walBytes.write(to: URL(fileURLWithPath: storeURL.path + "-wal"))

        let outcome: StoreBootstrap.Outcome = StoreBootstrap.makeContainer(storeURL: storeURL)

        XCTAssertNil(outcome.container)
        XCTAssertFalse(outcome.isReady)
        XCTAssertNotNil(outcome.failure)
        XCTAssertEqual(outcome.failure?.storeWasPresent, true)
        XCTAssertEqual(try Data(contentsOf: storeURL), storeBytes)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: storeURL.path + "-shm")), shmBytes)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: storeURL.path + "-wal")), walBytes)
        XCTAssertEqual(StoreBootstrap.existingStoreFiles(at: storeURL).count, 3)
        XCTAssertNotNil(StoreBootstrap.lastError)
    }

    func testCorrectMigrationPreservesRoutineAndExerciseRelationship() throws {
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL: URL = directory.appendingPathComponent("default.store")

        do {
            let schema: Schema = Schema(versionedSchema: AppSchemaV4.self)
            let configuration: ModelConfiguration = ModelConfiguration(url: storeURL)
            let container: ModelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            let context: ModelContext = ModelContext(container)

            let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
            context.insert(exercise)

            let routine: Routine = Routine(
                name: "Rutina personal",
                isTemplate: true,
                sortOrder: 3,
                exercises: [],
                source: .manual
            )
            context.insert(routine)

            let link: RoutineExercise = RoutineExercise(
                exercise: exercise,
                defaultSets: 4,
                targetRepsMin: 5,
                targetRepsMax: 7,
                sortOrder: 0,
                defaultWeight: 80.0,
                restSeconds: 150,
                notes: "no perder"
            )
            context.insert(link)
            routine.exercises = [link]

            try context.save()
        }

        let outcome: StoreBootstrap.Outcome = StoreBootstrap.makeContainer(storeURL: storeURL)
        let container: ModelContainer = try XCTUnwrap(outcome.container)
        let context: ModelContext = ModelContext(container)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        let routine: Routine = try XCTUnwrap(routines.first)
        XCTAssertEqual(routine.name, "Rutina personal")
        XCTAssertEqual(routine.sortOrder, 3)
        XCTAssertEqual(routine.source, .manual)
        XCTAssertEqual(routine.exercises.count, 1)

        let link: RoutineExercise = try XCTUnwrap(routine.exercises.first)
        XCTAssertEqual(link.defaultSets, 4)
        XCTAssertEqual(link.targetRepsMin, 5)
        XCTAssertEqual(link.targetRepsMax, 7)
        XCTAssertEqual(link.defaultWeight, 80.0)
        XCTAssertEqual(link.restSeconds, 150)
        XCTAssertEqual(link.notes, "no perder")
        XCTAssertEqual(link.exercise?.name, "Press banca")

        let plans: [AssistedWeekPlan] = try context.fetch(FetchDescriptor<AssistedWeekPlan>())
        XCTAssertTrue(plans.isEmpty)
    }

    private func configure(_ viewModel: AssistedSplitViewModel, selections: [AssistedDaySelection]) {
        XCTAssertEqual(selections.count, AssistedWeekday.allCases.count)
        for (index, selection) in selections.enumerated() {
            guard let weekday: AssistedWeekday = AssistedWeekday.from(index: index) else { continue }
            switch selection {
            case .unassigned:
                viewModel.clear(weekday)
            case .rest:
                viewModel.selectRest(for: weekday)
            case .routine(let routine):
                viewModel.selectRoutine(routine, for: weekday)
            }
        }
    }

    private func makeAssistedContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: AppSchemaV5.self)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: AppSchemaV4.self)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppGymTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
