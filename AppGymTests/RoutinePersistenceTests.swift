import XCTest
import Foundation
import CoreGraphics
import SwiftData
import UserNotifications

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
        let generatedExercise: Exercise = try XCTUnwrap(exercises.first(where: { $0.name == generatedSource.name }))
        XCTAssertEqual(generatedExercise.catalogPrimaryMusclesText, generatedSource.primaryMuscleText)
        XCTAssertEqual(generatedExercise.catalogSecondaryMusclesText, generatedSource.secondaryMuscleText)
        XCTAssertFalse(generatedExercise.catalogPrimaryMusclesText.isEmpty)
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

    func testDeletionPolicyAllowsSeededRoutineWhenUnreferenced() throws {
        let context: ModelContext = try makeAssistedContext()
        let seedID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let routine: Routine = Routine(id: seedID, name: "PUSH", isTemplate: true, source: .automatic)
        context.insert(routine)
        try context.save()

        // El UUID de siembra ya no impide eliminarla.
        XCTAssertEqual(
            RoutineService.deletionPolicy(for: routine, context: context),
            .delete
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

    func testAssistedPersistenceArchivesPreviousRoutinesAndKeepsRestDaysAndHistory() throws {
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
        let previous: Routine = try XCTUnwrap(routines.first { $0.id == personalID })
        XCTAssertEqual(previous.name, "PUSH")
        XCTAssertEqual(previous.source, .automatic)
        // Sin protecciones especiales se archiva como cualquier rutina generada
        // anterior; no se borra y conserva sus ejercicios.
        XCTAssertTrue(previous.isArchived)
        XCTAssertEqual(previous.exercises.count, 1)
        XCTAssertEqual(previous.exercises.first?.exercise?.name, "Press banca")

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
        let previous: Routine = try XCTUnwrap(routines.first { $0.id == personalID })
        XCTAssertTrue(previous.isArchived)

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

    func testAssistedPersistenceArchivesSeededRoutinesLikeAnyOtherRoutine() throws {
        let context: ModelContext = try makeAssistedContext()
        let bench: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(bench)

        for (index, id) in MockDataGenerator.seededRoutineIDs.enumerated() {
            let routine: Routine = Routine(
                id: id,
                name: "INICIAL \(index)",
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
            XCTAssertEqual(routine.source, .automatic)
            // Sin proteccion por UUID se archivan como cualquier generada.
            XCTAssertTrue(routine.isArchived)
            XCTAssertFalse(routine.isActivePlanRoutine)
            XCTAssertEqual(routine.exercises.count, 1)
            XCTAssertEqual(routine.exercises.first?.exercise?.name, "Press banca")
        }
        XCTAssertEqual(routines.count, MockDataGenerator.seededRoutineIDs.count)
    }

    // MARK: - Backups e integridad

    func testBackupRoundTripPreservesRoutineExerciseAndExerciseIdentity() throws {
        let source: ModelContext = try makeAssistedContext()
        let exercise: Exercise = Exercise(
            id: UUID(),
            name: "Press banca",
            muscleGroup: .chest,
            equipmentType: .olympicBar,
            targetRepsMin: 6,
            targetRepsMax: 8,
            defaultRestCondition: .timer(seconds: 150)
        )
        source.insert(exercise)

        let routineID: UUID = UUID()
        let linkID: UUID = UUID()
        let routine: Routine = Routine(
            id: routineID,
            name: "Rutina firmada",
            isTemplate: true,
            sortOrder: 2,
            isArchived: true,
            source: .manual
        )
        source.insert(routine)
        let link: RoutineExercise = RoutineExercise(
            id: linkID,
            exercise: exercise,
            defaultSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 0,
            defaultWeight: 82.5,
            restSeconds: 150,
            notes: "nota personal",
            hasCustomRest: true
        )
        source.insert(link)
        routine.exercises = [link]
        try source.save()

        let export: BackupExportResult = try BackupManager.createBackup(context: source)
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackupData(export.document.data, in: directory)

        let destination: ModelContext = try makeAssistedContext()
        let result: BackupImportResult = try BackupManager.restoreBackup(
            from: url,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        let restored: Routine = try XCTUnwrap(routines.first { $0.id == routineID })
        XCTAssertEqual(restored.name, "Rutina firmada")
        XCTAssertEqual(restored.sortOrder, 2)
        XCTAssertEqual(restored.source, .manual)
        XCTAssertTrue(restored.isArchived)
        XCTAssertEqual(restored.exercises.count, 1)

        let restoredLink: RoutineExercise = try XCTUnwrap(restored.exercises.first)
        XCTAssertEqual(restoredLink.id, linkID)
        XCTAssertEqual(restoredLink.exercise?.id, exercise.id)
        XCTAssertEqual(restoredLink.defaultSets, 4)
        XCTAssertEqual(restoredLink.targetRepsMin, 6)
        XCTAssertEqual(restoredLink.targetRepsMax, 8)
        XCTAssertEqual(restoredLink.defaultWeight, 82.5)
        XCTAssertEqual(restoredLink.restSeconds, 150)
        XCTAssertEqual(restoredLink.notes, "nota personal")
        XCTAssertTrue(restoredLink.hasCustomRest)
        XCTAssertTrue(result.report.warnings.isEmpty)
    }

    func testExportPreservesNilExerciseLinkAndWarnsWithoutInventingExercise() throws {
        let source: ModelContext = try makeAssistedContext()
        let routine: Routine = Routine(name: "Rutina con enlace roto", isTemplate: true, source: .manual)
        source.insert(routine)
        let link: RoutineExercise = RoutineExercise(
            exercise: nil,
            defaultSets: 3,
            targetRepsMin: 8,
            targetRepsMax: 10,
            sortOrder: 1,
            defaultWeight: 12.0,
            restSeconds: 90,
            notes: "se conserva",
            hasCustomRest: true
        )
        source.insert(link)
        routine.exercises = [link]
        try source.save()

        let export: BackupExportResult = try BackupManager.createBackup(context: source)
        XCTAssertTrue(export.report.warnings.contains { $0.code == .missingExerciseRelation })

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackupData(export.document.data, in: directory)

        let destination: ModelContext = try makeAssistedContext()
        _ = try BackupManager.restoreBackup(
            from: url,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )

        let restored: Routine = try XCTUnwrap(try destination.fetch(FetchDescriptor<Routine>()).first)
        let restoredLink: RoutineExercise = try XCTUnwrap(restored.exercises.first)
        XCTAssertNil(restoredLink.exercise)
        XCTAssertEqual(restoredLink.notes, "se conserva")
        XCTAssertEqual(restoredLink.defaultWeight, 12.0)
        XCTAssertTrue(restoredLink.hasCustomRest)
    }

    func testOldBackupWithoutNewFieldsUsesSafeDefaultsAndKeepsExplicitRest() throws {
        let oldExercise: ExerciseBackupDTO = makeBackupExercise(name: "Press banca", id: nil)
        let oldLink: RoutineExerciseBackupDTO = makeBackupLink(
            exercise: oldExercise,
            exerciseID: nil,
            rest: 105,
            hasCustomRest: nil
        )
        let oldRoutine: RoutineBackupDTO = makeBackupRoutine(
            name: "Rutina antigua",
            source: nil,
            isArchived: nil,
            exercises: [oldLink]
        )
        let backup: AppBackupData = makeBackup(routines: [oldRoutine])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let destination: ModelContext = try makeAssistedContext()
        let result: BackupImportResult = try BackupManager.restoreBackup(
            from: url,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )

        let restored: Routine = try XCTUnwrap(try destination.fetch(FetchDescriptor<Routine>()).first)
        XCTAssertFalse(restored.isArchived)
        XCTAssertEqual(restored.source, .manual)
        let restoredLink: RoutineExercise = try XCTUnwrap(restored.exercises.first)
        XCTAssertFalse(restoredLink.hasCustomRest)
        XCTAssertEqual(restoredLink.restSeconds, 105)
        XCTAssertNotNil(restoredLink.exercise?.id)
        XCTAssertTrue(result.report.warnings.contains { $0.code == .missingExerciseUUID })
    }

    func testDuplicateRoutineIDsBlockImportAndLeaveDatabaseUntouched() throws {
        let duplicateID: UUID = UUID()
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(id: duplicateID, name: "Primera", exercises: []),
            makeBackupRoutine(id: duplicateID, name: "Segunda", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let destination: ModelContext = try makeAssistedContext()
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        XCTAssertThrowsError(
            try BackupManager.restoreBackup(
                from: url,
                context: destination,
                safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
            )
        ) { error in
            guard let backupError = error as? BackupError,
                  case .validationFailed(let report) = backupError else {
                XCTFail("Se esperaba un error de validación: \(error)")
                return
            }
            XCTAssertTrue(report.blockingIssues.contains { $0.code == .duplicateRoutineID })
        }

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routines.first?.id, sentinel.id)
    }

    func testDuplicateExerciseIDWithDifferentContentBlocksImport() throws {
        let sharedExerciseID: UUID = UUID()
        let firstExercise: ExerciseBackupDTO = makeBackupExercise(name: "Press banca", id: sharedExerciseID)
        let secondExercise: ExerciseBackupDTO = makeBackupExercise(name: "Sentadilla", id: sharedExerciseID)
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Uno", exercises: [
                makeBackupLink(exercise: firstExercise, exerciseID: sharedExerciseID)
            ]),
            makeBackupRoutine(name: "Dos", exercises: [
                makeBackupLink(exercise: secondExercise, exerciseID: sharedExerciseID)
            ])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let destination: ModelContext = try makeAssistedContext()

        XCTAssertThrowsError(
            try BackupManager.restoreBackup(
                from: url,
                context: destination,
                safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
            )
        ) { error in
            guard let backupError = error as? BackupError,
                  case .validationFailed(let report) = backupError else {
                XCTFail("Se esperaba un error de validación: \(error)")
                return
            }
            XCTAssertTrue(report.blockingIssues.contains { $0.code == .duplicateExerciseIDWithDifferentContent })
        }
    }

    func testMissingExerciseRelationBlocksImport() throws {
        let missingID: UUID = UUID()
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Rota", exercises: [
                makeBackupLink(exercise: nil, exerciseID: missingID)
            ])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let destination: ModelContext = try makeAssistedContext()

        XCTAssertThrowsError(
            try BackupManager.restoreBackup(
                from: url,
                context: destination,
                safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
            )
        ) { error in
            guard let backupError = error as? BackupError,
                  case .validationFailed(let report) = backupError else {
                XCTFail("Se esperaba un error de validación: \(error)")
                return
            }
            XCTAssertTrue(report.blockingIssues.contains { $0.code == .missingExerciseSnapshot })
        }
    }

    func testBackupWithoutSeededRoutinesReplacesThem() throws {
        let destination: ModelContext = try makeAssistedContext()
        let seededIDs: [UUID] = Array(MockDataGenerator.seededRoutineIDs.prefix(5))
        XCTAssertEqual(seededIDs.count, 5)
        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        destination.insert(exercise)
        for (index, id) in seededIDs.enumerated() {
            let routine: Routine = Routine(id: id, name: "INICIAL \(index)", isTemplate: true, source: .automatic)
            destination.insert(routine)
            let link: RoutineExercise = RoutineExercise(
                exercise: exercise,
                defaultSets: 4,
                targetRepsMin: 6,
                targetRepsMax: 8,
                sortOrder: 0,
                defaultWeight: 77.5,
                restSeconds: 180,
                notes: "configuracion \(index)",
                hasCustomRest: true
            )
            destination.insert(link)
            routine.exercises = [link]
        }
        try destination.save()

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let result: BackupImportResult = try BackupManager.restoreBackup(
            from: url,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routines.first?.name, "Importada")
        XCTAssertEqual(result.importedRoutineIDs, routines.map(\.id))
        for id in seededIDs {
            XCTAssertFalse(routines.contains { $0.id == id })
        }
    }

    func testSeededRoutineWithDifferentContentIsRestoredFromBackup() throws {
        let pushID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let destination: ModelContext = try makeAssistedContext()
        let exercise: Exercise = Exercise(
            id: UUID(),
            name: "Press banca",
            muscleGroup: .chest,
            equipmentType: .olympicBar,
            targetRepsMin: 6,
            targetRepsMax: 8
        )
        destination.insert(exercise)
        let current: Routine = Routine(id: pushID, name: "PUSH", isTemplate: true, source: .automatic)
        destination.insert(current)
        let currentLink: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 0,
            defaultWeight: 80.0,
            restSeconds: 150
        )
        destination.insert(currentLink)
        current.exercises = [currentLink]
        try destination.save()

        let backupExercise: ExerciseBackupDTO = makeBackupExercise(name: "Press banca", id: exercise.id)
        let changedLink: RoutineExerciseBackupDTO = makeBackupLink(
            id: currentLink.id,
            exercise: backupExercise,
            exerciseID: exercise.id,
            sets: 3,
            rest: 150
        )
        let changed: RoutineBackupDTO = makeBackupRoutine(
            id: pushID,
            name: "PUSH",
            source: "automatic",
            isArchived: false,
            exercises: [changedLink]
        )

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(makeBackup(routines: [changed]), in: directory)

        let result: BackupImportResult = try BackupManager.restoreBackup(
            from: url,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )
        XCTAssertTrue(result.report.canImport)

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        let restored: Routine = try XCTUnwrap(routines.first { $0.id == pushID })
        XCTAssertEqual(restored.exercises.count, 1)
        XCTAssertEqual(restored.exercises.first?.defaultSets, 3)
    }

    func testSeededRoutineNameDoesNotBlockImport() throws {
        let pushID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let otherID: UUID = UUID()
        let destination: ModelContext = try makeAssistedContext()
        let current: Routine = Routine(id: pushID, name: "PUSH", isTemplate: true, source: .automatic)
        destination.insert(current)
        try destination.save()

        let otherExercise: ExerciseBackupDTO = makeBackupExercise(name: "Remo", id: UUID())
        let otherLink: RoutineExerciseBackupDTO = makeBackupLink(
            exercise: otherExercise,
            exerciseID: otherExercise.id
        )
        let otherRoutine: RoutineBackupDTO = makeBackupRoutine(
            id: otherID,
            name: "PUSH",
            source: "manual",
            exercises: [otherLink]
        )

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(makeBackup(routines: [otherRoutine]), in: directory)

        let result: BackupImportResult = try BackupManager.restoreBackup(
            from: url,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )
        XCTAssertTrue(result.report.canImport)

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routines.first?.id, otherID)
        XCTAssertFalse(routines.contains { $0.id == pushID })
    }

    func testInvalidJSONDoesNotModifyDatabase() throws {
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = directory.appendingPathComponent("invalido.json")
        try Data("esto no es JSON".utf8).write(to: url)

        let destination: ModelContext = try makeAssistedContext()
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        XCTAssertThrowsError(
            try BackupManager.restoreBackup(
                from: url,
                context: destination,
                safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
            )
        ) { error in
            guard let backupError = error as? BackupError,
                  case .invalidFile = backupError else {
                XCTFail("Se esperaba invalidFile: \(error)")
                return
            }
        }

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routines.first?.id, sentinel.id)
    }

    func testUnsupportedBackupVersionDoesNotModifyDatabase() throws {
        let backup: AppBackupData = AppBackupData(
            version: AppBackupData.currentVersion + 1,
            exportDate: Date(),
            routines: [],
            sessions: [],
            settings: makeBackupSettings(),
            assistedWeeks: nil
        )

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let destination: ModelContext = try makeAssistedContext()
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        XCTAssertThrowsError(
            try BackupManager.restoreBackup(
                from: url,
                context: destination,
                safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
            )
        ) { error in
            guard let backupError = error as? BackupError,
                  case .validationFailed(let report) = backupError else {
                XCTFail("Se esperaba un error de validación: \(error)")
                return
            }
            XCTAssertTrue(report.blockingIssues.contains { $0.code == .unsupportedVersion })
        }

        XCTAssertEqual(try destination.fetch(FetchDescriptor<Routine>()).count, 1)
    }

    func testSafetyCopyFailureAbortsImportWithoutModifyingDatabase() throws {
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let blockedDirectory: URL = directory.appendingPathComponent("no-es-directorio")
        try Data("archivo, no carpeta".utf8).write(to: blockedDirectory)

        let destination: ModelContext = try makeAssistedContext()
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        XCTAssertThrowsError(
            try BackupManager.restoreBackup(
                from: url,
                context: destination,
                safetyCopyDirectory: blockedDirectory
            )
        ) { error in
            guard let backupError = error as? BackupError,
                  case .safetyCopyFailed = backupError else {
                XCTFail("Se esperaba safetyCopyFailed: \(error)")
                return
            }
        }

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routines.first?.id, sentinel.id)
    }

    func testAssistedPlanRoundTripPreservesSevenDays() throws {
        let source: ModelContext = try makeAssistedContext()
        let days: [AssistedWeekDayRecord] = (0..<7).map { index in
            AssistedWeekDayRecord(
                weekdayIndex: index,
                isRest: true,
                routineID: nil,
                routineName: "Descanso",
                variantSuffix: "",
                sessionIndex: nil
            )
        }
        let plan: AssistedWeekPlan = AssistedWeekPlan(isActivePlan: true, days: days)
        source.insert(plan)
        try source.save()

        let export: BackupExportResult = try BackupManager.createBackup(context: source)
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackupData(export.document.data, in: directory)

        let destination: ModelContext = try makeAssistedContext()
        _ = try BackupManager.restoreBackup(
            from: url,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )

        let plans: [AssistedWeekPlan] = try destination.fetch(FetchDescriptor<AssistedWeekPlan>())
        let restored: AssistedWeekPlan = try XCTUnwrap(plans.first)
        XCTAssertTrue(restored.isActivePlan)
        XCTAssertEqual(restored.days.count, 7)
        XCTAssertTrue(restored.days.allSatisfy { $0.isRest })
        XCTAssertEqual(Set(restored.days.map(\.weekdayIndex)), Set(0..<7))
    }

    func testCorruptAssistedPlanIsNotSilentlyConvertedIntoAnEmptyPlan() throws {
        let source: ModelContext = try makeAssistedContext()
        let days: [AssistedWeekDayRecord] = (0..<7).map { index in
            AssistedWeekDayRecord(
                weekdayIndex: index,
                isRest: true,
                routineID: nil,
                routineName: "Descanso",
                variantSuffix: "",
                sessionIndex: nil
            )
        }
        let plan: AssistedWeekPlan = AssistedWeekPlan(isActivePlan: true, days: days)
        plan.daysData = Data("datos ilegibles".utf8)
        source.insert(plan)
        try source.save()

        let export: BackupExportResult = try BackupManager.createBackup(context: source)
        XCTAssertTrue(export.report.warnings.contains { $0.code == .corruptAssistedPlan })

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackupData(export.document.data, in: directory)

        let destination: ModelContext = try makeAssistedContext()
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        XCTAssertThrowsError(
            try BackupManager.restoreBackup(
                from: url,
                context: destination,
                safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
            )
        ) { error in
            guard let backupError = error as? BackupError,
                  case .validationFailed(let report) = backupError else {
                XCTFail("Se esperaba un error de validación: \(error)")
                return
            }
            XCTAssertTrue(report.blockingIssues.contains { $0.code == .corruptAssistedPlan })
        }

        XCTAssertEqual(try destination.fetch(FetchDescriptor<Routine>()).count, 1)
    }

    func testValidImportPreservesWorkoutHistory() throws {
        let source: ModelContext = try makeAssistedContext()
        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        source.insert(exercise)

        let sessionID: UUID = UUID()
        let setID: UUID = UUID()
        let routineExerciseID: UUID = UUID()
        let session: WorkoutSession = WorkoutSession(
            id: sessionID,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            totalVolumeKg: 800.0,
            routineName: "PUSH"
        )
        source.insert(session)
        let log: WorkoutSetLog = WorkoutSetLog(
            id: setID,
            date: Date(timeIntervalSince1970: 1_700_000_100),
            workoutStartDate: session.startDate,
            weight: 100.0,
            reps: 8,
            targetRepsMin: 6,
            targetRepsMax: 10,
            isCompleted: true,
            routineExerciseID: routineExerciseID,
            setNumber: 1,
            exercise: exercise,
            session: session
        )
        source.insert(log)
        session.setsCompleted = [log]
        try source.save()

        let export: BackupExportResult = try BackupManager.createBackup(context: source)
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackupData(export.document.data, in: directory)

        let destination: ModelContext = try makeAssistedContext()
        _ = try BackupManager.restoreBackup(
            from: url,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )

        let sessions: [WorkoutSession] = try destination.fetch(FetchDescriptor<WorkoutSession>())
        let restored: WorkoutSession = try XCTUnwrap(sessions.first)
        XCTAssertEqual(restored.id, sessionID)
        XCTAssertEqual(restored.routineName, "PUSH")
        XCTAssertEqual(restored.totalVolumeKg, 800.0)
        XCTAssertEqual(restored.setsCompleted.count, 1)
        let restoredLog: WorkoutSetLog = try XCTUnwrap(restored.setsCompleted.first)
        XCTAssertEqual(restoredLog.id, setID)
        XCTAssertEqual(restoredLog.weight, 100.0)
        XCTAssertEqual(restoredLog.reps, 8)
        XCTAssertEqual(restoredLog.targetRepsMin, 6)
        XCTAssertEqual(restoredLog.targetRepsMax, 10)
        XCTAssertTrue(restoredLog.isCompleted)
        XCTAssertEqual(restoredLog.routineExerciseID, routineExerciseID)
        XCTAssertEqual(restoredLog.exercise?.id, exercise.id)
    }

    // MARK: - Confirmación de pérdida de historial y avisos (Prompt 06.1)

    func testPrepareImportWithoutHistoryOnEitherSideDoesNotAskForConfirmation() throws {
        let source: ModelContext = try makeAssistedContext()
        let routine: Routine = Routine(name: "Copia sin historial", isTemplate: true, source: .manual)
        source.insert(routine)
        try source.save()

        let export: BackupExportResult = try BackupManager.createBackup(context: source)
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackupData(export.document.data, in: directory)

        let destination: ModelContext = try makeAssistedContext()
        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: destination)

        XCTAssertTrue(plan.report.canImport)
        XCTAssertFalse(plan.replacesSessionHistoryWithEmpty)
        XCTAssertFalse(plan.report.issues.contains { $0.code == .missingSessionHistory })
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Routine>()), 0)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    func testPrepareImportWithSessionsOnBothSidesDoesNotAskForConfirmation() throws {
        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination)

        let source: ModelContext = try makeAssistedContext()
        try insertSession(in: source, routineName: "LEGS")

        let export: BackupExportResult = try BackupManager.createBackup(context: source)
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackupData(export.document.data, in: directory)

        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: destination)

        XCTAssertTrue(plan.report.canImport)
        XCTAssertFalse(plan.replacesSessionHistoryWithEmpty)
        XCTAssertFalse(plan.report.issues.contains { $0.code == .missingSessionHistory })
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }

    func testPrepareImportDetectsThatExistingHistoryWouldBeReplacedByAnEmptyOne() throws {
        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination)

        let source: ModelContext = try makeAssistedContext()
        let routine: Routine = Routine(name: "Copia actual", isTemplate: true, source: .manual)
        source.insert(routine)
        try source.save()

        let export: BackupExportResult = try BackupManager.createBackup(context: source)
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackupData(export.document.data, in: directory)

        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: destination)

        // La copia es importable, pero sustituiría un historial real por vacío.
        XCTAssertTrue(plan.report.canImport)
        XCTAssertTrue(plan.replacesSessionHistoryWithEmpty)
        XCTAssertTrue(plan.report.warnings.contains { $0.code == .missingSessionHistory })

        // Preparar nunca modifica la base ni crea copias automáticas.
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }

    func testCancellingTheHistoryConfirmationLeavesDataUntouched() throws {
        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination)
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let safety: URL = directory.appendingPathComponent("safety", isDirectory: true)

        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: destination)
        XCTAssertTrue(plan.replacesSessionHistoryWithEmpty)

        // Cancelar la confirmación no ejecuta la restauración: nada cambia.
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try safetyCopyFileCount(in: safety), 0)
    }

    func testConfirmingThePreparedPlanRunsTheNormalImport() throws {
        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination)

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let safety: URL = directory.appendingPathComponent("safety", isDirectory: true)

        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: destination)
        XCTAssertTrue(plan.replacesSessionHistoryWithEmpty)

        let result: BackupImportResult = try BackupManager.restoreBackup(
            using: plan,
            context: destination,
            safetyCopyDirectory: safety
        )

        XCTAssertEqual(result.importedRoutineIDs.count, 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routines.first?.name, "Importada")
        XCTAssertEqual(try safetyCopyFileCount(in: safety), 1)
    }

    func testPreparedImportAbortsWhenTheSafetyCopyCannotBeWritten() throws {
        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination)
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let blockedDirectory: URL = directory.appendingPathComponent("no-es-directorio")
        try Data("archivo, no carpeta".utf8).write(to: blockedDirectory)

        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: destination)

        XCTAssertThrowsError(
            try BackupManager.restoreBackup(
                using: plan,
                context: destination,
                safetyCopyDirectory: blockedDirectory
            )
        ) { error in
            guard let backupError = error as? BackupError,
                  case .safetyCopyFailed = backupError else {
                XCTFail("Se esperaba safetyCopyFailed: \(error)")
                return
            }
        }

        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Routine>()), 1)
    }

    func testPlanThatCannotBeImportedNeverCreatesASafetyCopyOrChangesData() throws {
        let duplicateID: UUID = UUID()
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(id: duplicateID, name: "Primera", exercises: []),
            makeBackupRoutine(id: duplicateID, name: "Segunda", exercises: [])
        ])

        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination)
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let safety: URL = directory.appendingPathComponent("safety", isDirectory: true)

        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: destination)
        XCTAssertFalse(plan.report.canImport)
        XCTAssertTrue(plan.report.blockingIssues.contains { $0.code == .duplicateRoutineID })

        // Aplicar un plan bloqueado ni copia ni sustituye nada: el rollback del
        // Prompt 06 queda intacto porque no se llega a escribir.
        XCTAssertThrowsError(
            try BackupManager.restoreBackup(
                using: plan,
                context: destination,
                safetyCopyDirectory: safety
            )
        ) { error in
            guard let backupError = error as? BackupError,
                  case .validationFailed = backupError else {
                XCTFail("Se esperaba validationFailed: \(error)")
                return
            }
        }

        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try safetyCopyFileCount(in: safety), 0)
    }

    func testPreparedPlanReportsHistoryLossWithoutReservedRoutines() throws {
        let pushID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let destination: ModelContext = try makeAssistedContext()
        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        destination.insert(exercise)
        let current: Routine = Routine(id: pushID, name: "PUSH", isTemplate: true, source: .automatic)
        destination.insert(current)
        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 0,
            restSeconds: 150
        )
        destination.insert(link)
        current.exercises = [link]
        try destination.save()
        try insertSession(in: destination)

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let safety: URL = directory.appendingPathComponent("safety", isDirectory: true)

        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: destination)

        XCTAssertTrue(plan.replacesSessionHistoryWithEmpty)
        XCTAssertTrue(plan.report.canImport)
        XCTAssertFalse(plan.report.issues.contains { (issue: BackupIssue) -> Bool in
            return issue.message.localizedCaseInsensitiveContains("protegida")
        })

        _ = try BackupManager.restoreBackup(
            using: plan,
            context: destination,
            safetyCopyDirectory: safety
        )

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.map(\.name), ["Importada"])
        XCTAssertFalse(routines.contains { $0.id == pushID })
    }

    func testOnboardingPreparationShowsWarningsWithoutImporting() throws {
        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination)

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Copia del onboarding", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: destination)

        XCTAssertEqual(viewModel.backupState, .reviewing)
        let plan: BackupImportPlan = try XCTUnwrap(viewModel.preparedBackupPlan)
        XCTAssertTrue(plan.report.canImport)
        XCTAssertTrue(plan.replacesSessionHistoryWithEmpty)
        XCTAssertTrue(plan.report.warnings.contains { $0.code == .missingSessionHistory })

        // La revisión no ha aplicado nada: el historial sigue en la base.
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Routine>()), 0)
    }

    func testOnboardingBlocksCorruptBackupBeforeImporting() throws {
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = directory.appendingPathComponent("invalido.json")
        try Data("esto no es JSON".utf8).write(to: url)

        let destination: ModelContext = try makeAssistedContext()
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: destination)

        XCTAssertNil(viewModel.preparedBackupPlan)
        guard case .failed = viewModel.backupState else {
            XCTFail("Se esperaba un estado de error: \(viewModel.backupState)")
            return
        }
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Routine>()), 1)
    }

    func testOnboardingBlocksIncompatibleBackupAndDoesNotApplyIt() throws {
        let duplicateID: UUID = UUID()
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(id: duplicateID, name: "Primera", exercises: []),
            makeBackupRoutine(id: duplicateID, name: "Segunda", exercises: [])
        ])

        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination)
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let safety: URL = directory.appendingPathComponent("safety", isDirectory: true)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: destination)

        XCTAssertEqual(viewModel.backupState, .reviewing)
        XCTAssertEqual(viewModel.preparedBackupPlan?.report.canImport, false)

        let outcome: Result<BackupImportResult, Error> = viewModel.confirmPreparedBackup(
            context: destination,
            safetyCopyDirectory: safety
        )
        guard case .failure = outcome else {
            XCTFail("Una copia bloqueada no puede confirmarse")
            return
        }

        XCTAssertNil(viewModel.preparedBackupPlan)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try safetyCopyFileCount(in: safety), 0)
    }

    func testOnboardingPreparationDoesNotReserveSeededRoutines() throws {
        let pushID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let destination: ModelContext = try makeAssistedContext()
        let current: Routine = Routine(id: pushID, name: "PUSH", isTemplate: true, source: .automatic)
        destination.insert(current)
        try destination.save()

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Rutina importada", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: destination)

        let plan: BackupImportPlan = try XCTUnwrap(viewModel.preparedBackupPlan)
        XCTAssertTrue(plan.report.canImport)
        XCTAssertFalse(plan.report.issues.contains { $0.message.localizedCaseInsensitiveContains("protegida") })
    }

    func testSelectingAnotherFileReplacesThePreparedPlan() throws {
        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination)

        let backupWithoutHistory: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Sin historial", exercises: [])
        ])
        let backupWithHistory: AppBackupData = makeBackup(
            routines: [makeBackupRoutine(name: "Con historial", exercises: [])],
            sessions: [makeBackupSession()]
        )

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL: URL = try writeBackup(backupWithoutHistory, in: directory)
        let secondURL: URL = try writeBackup(backupWithHistory, in: directory)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: firstURL, context: destination)
        let firstPlan: BackupImportPlan = try XCTUnwrap(viewModel.preparedBackupPlan)
        XCTAssertTrue(firstPlan.replacesSessionHistoryWithEmpty)

        // Elegir otro archivo invalida la preparación anterior por completo.
        viewModel.prepareBackupImport(from: secondURL, context: destination)
        let secondPlan: BackupImportPlan = try XCTUnwrap(viewModel.preparedBackupPlan)
        XCTAssertNotEqual(firstPlan.id, secondPlan.id)
        XCTAssertFalse(secondPlan.replacesSessionHistoryWithEmpty)

        let safety: URL = directory.appendingPathComponent("safety", isDirectory: true)
        _ = try BackupManager.restoreBackup(using: secondPlan, context: destination, safetyCopyDirectory: safety)

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        XCTAssertTrue(routines.contains { $0.name == "Con historial" })
        XCTAssertFalse(routines.contains { $0.name == "Sin historial" })
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }

    func testOnboardingDoesNotStartASecondImport() throws {
        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination)

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let safety: URL = directory.appendingPathComponent("safety", isDirectory: true)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: destination)

        let first: Result<BackupImportResult, Error> = viewModel.confirmPreparedBackup(
            context: destination,
            safetyCopyDirectory: safety
        )
        guard case .success = first else {
            XCTFail("La primera importación debe completarse: \(first)")
            return
        }
        XCTAssertEqual(viewModel.backupState, .imported)

        // El plan ya se ha consumido: una segunda confirmación no importa otra vez.
        let second: Result<BackupImportResult, Error> = viewModel.confirmPreparedBackup(
            context: destination,
            safetyCopyDirectory: safety
        )
        guard case .failure = second else {
            XCTFail("No debe existir un segundo plan pendiente")
            return
        }

        XCTAssertEqual(viewModel.backupState, .imported)
        XCTAssertNil(viewModel.preparedBackupPlan)
        XCTAssertEqual(try safetyCopyFileCount(in: safety), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    // MARK: - C12: el onboarding omite la organización cuando importa rutinas

    func testImportedBackupSkipsTrainingOrganizationStep() throws {
        let context: ModelContext = try makeAssistedContext()
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "PUSH propia", exercises: []),
            makeBackupRoutine(name: "PULL propia", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        XCTAssertFalse(viewModel.importedRoutinesReplaceOrganization)

        viewModel.prepareBackupImport(from: url, context: context)
        // Validar el archivo no basta: mientras no se aplique, el flujo normal
        // sigue mostrando la selección de modalidad.
        XCTAssertFalse(viewModel.importedRoutinesReplaceOrganization)

        _ = viewModel.confirmPreparedBackup(
            context: context,
            safetyCopyDirectory: directory.appendingPathComponent("copias", isDirectory: true)
        )

        XCTAssertEqual(viewModel.backupState, .imported)
        XCTAssertTrue(viewModel.importedRoutinesReplaceOrganization)
    }

    func testOnboardingWithoutImportKeepsOrganizationStep() throws {
        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.selectPreviousUse(false)
        viewModel.selectPersonalization(.useDefaults)

        XCTAssertFalse(viewModel.importedRoutinesReplaceOrganization)
        XCTAssertFalse(viewModel.shouldShowPersonalizationSteps)

        let configuration: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .initialSetup)
        XCTAssertFalse(configuration.canContinueFromOrganization)
        configuration.selectMode(.createOwn)
        XCTAssertTrue(configuration.canContinueFromOrganization)

        // Desde Ajustes → Cambiar rutina tampoco se omite la modalidad.
        let change: OnboardingViewModel = OnboardingViewModel(context: .changeRoutine)
        XCTAssertFalse(change.importedRoutinesReplaceOrganization)
    }

    func testSuccessfulImportDoesNotGenerateAnotherSplit() throws {
        let context: ModelContext = try makeAssistedContext()
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada A", exercises: []),
            makeBackupRoutine(name: "Importada B", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: context)
        _ = viewModel.confirmPreparedBackup(
            context: context,
            safetyCopyDirectory: directory.appendingPathComponent("copias", isDirectory: true)
        )

        XCTAssertTrue(viewModel.importedRoutinesReplaceOrganization)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 2)
        XCTAssertEqual(Set(routines.map(\.name)), Set(["Importada A", "Importada B"]))

        // No se ha elegido modalidad ni se ha generado ningún plan adicional.
        let configuration: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .initialSetup)
        XCTAssertNil(configuration.plan.mode)
        XCTAssertNil(configuration.automatic.week)
        XCTAssertNil(configuration.assisted.generatedWeek)
    }

    func testCancelledImportKeepsNormalFlowAndDatabase() throws {
        let context: ModelContext = try makeAssistedContext()
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        context.insert(sentinel)
        try context.save()

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Cancelada", exercises: [])
        ])
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: context)
        XCTAssertEqual(viewModel.backupState, .reviewing)

        viewModel.cancelPreparedBackup()

        XCTAssertEqual(viewModel.backupState, .idle)
        XCTAssertNil(viewModel.preparedBackupPlan)
        XCTAssertFalse(viewModel.importedRoutinesReplaceOrganization)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)
    }

    func testCorruptImportDoesNotFinishTheFlow() throws {
        let context: ModelContext = try makeAssistedContext()
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        context.insert(sentinel)
        try context.save()

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackupData(Data("esto no es JSON".utf8), in: directory)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: context)

        XCTAssertNil(viewModel.preparedBackupPlan)
        guard case .failed = viewModel.backupState else {
            XCTFail("Se esperaba un estado de error: \(viewModel.backupState)")
            return
        }
        XCTAssertFalse(viewModel.importedRoutinesReplaceOrganization)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)
    }

    func testIncompatibleImportDoesNotFinishTheFlow() throws {
        let duplicateID: UUID = UUID()
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(id: duplicateID, name: "Primera", exercises: []),
            makeBackupRoutine(id: duplicateID, name: "Segunda", exercises: [])
        ])

        let context: ModelContext = try makeAssistedContext()
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        context.insert(sentinel)
        try context.save()

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: context)

        XCTAssertEqual(viewModel.backupState, .reviewing)
        XCTAssertEqual(viewModel.preparedBackupPlan?.report.canImport, false)

        let outcome: Result<BackupImportResult, Error> = viewModel.confirmPreparedBackup(
            context: context,
            safetyCopyDirectory: directory.appendingPathComponent("copias", isDirectory: true)
        )
        guard case .failure = outcome else {
            XCTFail("Una copia incompatible no puede confirmarse")
            return
        }

        guard case .failed = viewModel.backupState else {
            XCTFail("Se esperaba un estado de error: \(viewModel.backupState)")
            return
        }
        XCTAssertFalse(viewModel.importedRoutinesReplaceOrganization)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)
    }

    func testPersonalizationSurvivesBothPaths() throws {
        let context: ModelContext = try makeAssistedContext()
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada", exercises: [])
        ])
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: context)
        _ = viewModel.confirmPreparedBackup(
            context: context,
            safetyCopyDirectory: directory.appendingPathComponent("copias", isDirectory: true)
        )

        // Los ajustes del archivo se muestran, y el usuario puede seguir
        // personalizando sin que sus rutinas importadas cambien.
        XCTAssertEqual(viewModel.multipowerBarWeight, 10.0, accuracy: 0.0001)
        viewModel.adjustMultipowerBarWeight(by: 5.0)
        viewModel.selectPersonalization(.useDefaults)

        XCTAssertEqual(viewModel.preferences.clampedMultipowerBarWeight, 15.0, accuracy: 0.0001)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)

        // Sin importación la personalización sigue igual: equipamiento y
        // pulsaciones se piden en su propio paso.
        let plain: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        plain.selectPersonalization(.customize)
        let initialEZ: Double = plain.ezBarWeight
        plain.adjustEZBarWeight(by: 2.5)

        XCTAssertTrue(plain.shouldShowPersonalizationSteps)
        XCTAssertEqual(plain.preferences.clampedEZBarWeight, min(initialEZ + 2.5, OnboardingPreferences.barWeightRange.upperBound), accuracy: 0.0001)
        XCTAssertFalse(plain.importedRoutinesReplaceOrganization)
    }

    func testCompletingImportTwiceDoesNotDuplicateRoutines() throws {
        let context: ModelContext = try makeAssistedContext()
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada A", exercises: []),
            makeBackupRoutine(name: "Importada B", exercises: [])
        ])
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let viewModel: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        viewModel.prepareBackupImport(from: url, context: context)
        _ = viewModel.confirmPreparedBackup(
            context: context,
            safetyCopyDirectory: directory.appendingPathComponent("copias-1", isDirectory: true)
        )

        let first: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(first.count, 2)

        viewModel.prepareBackupImport(from: url, context: context)
        _ = viewModel.confirmPreparedBackup(
            context: context,
            safetyCopyDirectory: directory.appendingPathComponent("copias-2", isDirectory: true)
        )

        let second: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(Set(second.map(\.id)), Set(first.map(\.id)))
        XCTAssertEqual(Set(second.map(\.name)), Set(["Importada A", "Importada B"]))
    }

    // MARK: - C13: distribución manual sin límite de siete rutinas

    func testManualDistributionCreatesSevenRoutines() throws {
        let context: ModelContext = try makeAssistedContext()
        let result: RoutineApplicationResult = try applyOwnRoutines(count: 7, context: context)

        XCTAssertEqual(result.createdRoutineCount, 7)

        let routines: [Routine] = try activeManualRoutines(in: context)
        XCTAssertEqual(routines.count, 7)
        XCTAssertEqual(routines.first?.name, "Rutina 01")
        XCTAssertEqual(routines.last?.name, "Rutina 07")
    }

    func testManualDistributionCreatesEighthRoutine() throws {
        let context: ModelContext = try makeAssistedContext()

        var plan: RoutinePlanDraft = RoutinePlanDraft()
        plan.ownRoutineCount = 8
        XCTAssertEqual(plan.clampedRoutineCount, 8)

        let result: RoutineApplicationResult = try applyOwnRoutines(count: 8, context: context)
        XCTAssertEqual(result.createdRoutineCount, 8)

        let routines: [Routine] = try activeManualRoutines(in: context)
        XCTAssertEqual(routines.count, 8)
        XCTAssertEqual(routines.last?.name, "Rutina 08")
    }

    func testManualDistributionCreatesNinthRoutine() throws {
        let context: ModelContext = try makeAssistedContext()
        _ = try applyOwnRoutines(count: 9, context: context)

        let routines: [Routine] = try activeManualRoutines(in: context)
        XCTAssertEqual(routines.count, 9)
        XCTAssertEqual(routines.map(\.name).last, "Rutina 09")
        XCTAssertEqual(routines.map(\.sortOrder), Array(0..<9))
    }

    func testManualDistributionCreatesMoreThanTenRoutines() throws {
        let context: ModelContext = try makeAssistedContext()
        let result: RoutineApplicationResult = try applyOwnRoutines(count: 12, context: context)

        XCTAssertEqual(result.createdRoutineCount, 12)

        let routines: [Routine] = try activeManualRoutines(in: context)
        XCTAssertEqual(routines.count, 12)
        XCTAssertEqual(routines.map(\.sortOrder), Array(0..<12))
        XCTAssertEqual(routines.last?.name, "Rutina 12")
    }

    func testManualDistributionAllowsTwoRoutinesForTheSameDay() throws {
        let context: ModelContext = try makeAssistedContext()
        _ = try applyOwnRoutines(count: 2, context: context)

        let routines: [Routine] = try activeManualRoutines(in: context)
        XCTAssertEqual(routines.count, 2)
        XCTAssertNotEqual(routines[0].id, routines[1].id)

        // Mañana y tarde del mismo día: dos rutinas distintas e identificables.
        routines[0].name = "Lunes · mañana"
        routines[1].name = "Lunes · tarde"
        try context.save()

        let reloaded: [Routine] = try activeManualRoutines(in: context)
        XCTAssertEqual(reloaded.map(\.name), ["Lunes · mañana", "Lunes · tarde"])
        XCTAssertEqual(Set(reloaded.map(\.id)).count, 2)
    }

    func testEditingARoutineWithMoreThanSevenRoutines() throws {
        let context: ModelContext = try makeAssistedContext()
        _ = try applyOwnRoutines(count: 9, context: context)

        let routines: [Routine] = try activeManualRoutines(in: context)
        let target: Routine = try XCTUnwrap(routines.first { (routine: Routine) -> Bool in
            return routine.name == "Rutina 09"
        })

        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(exercise)
        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 4,
            targetRepsMin: 5,
            targetRepsMax: 7,
            sortOrder: 0,
            defaultWeight: 90.0,
            restSeconds: 180,
            notes: "edición"
        )
        context.insert(link)
        target.exercises = [link]
        target.name = "Rutina 09 editada"
        try context.save()

        let reloaded: [Routine] = try activeManualRoutines(in: context)
        let edited: Routine = try XCTUnwrap(reloaded.first { (routine: Routine) -> Bool in
            return routine.id == target.id
        })
        XCTAssertEqual(edited.name, "Rutina 09 editada")
        XCTAssertEqual(edited.exercises.count, 1)
        XCTAssertEqual(edited.exercises.first?.defaultSets, 4)
        XCTAssertEqual(edited.exercises.first?.restSeconds, 180)
        XCTAssertEqual(edited.exercises.first?.exercise?.name, "Press banca")
        XCTAssertEqual(reloaded.count, 9)
    }

    func testDeletingARoutineWithMoreThanSevenRoutines() throws {
        let context: ModelContext = try makeAssistedContext()
        _ = try applyOwnRoutines(count: 10, context: context)

        let before: [Routine] = try activeManualRoutines(in: context)
        XCTAssertEqual(before.count, 10)

        let target: Routine = before[3]
        let expectedIDs: Set<UUID> = Set(before.filter { (routine: Routine) -> Bool in
            return routine.id != target.id
        }.map(\.id))

        context.delete(target)
        try context.save()

        let after: [Routine] = try activeManualRoutines(in: context)
        XCTAssertEqual(after.count, 9)
        XCTAssertEqual(Set(after.map(\.id)), expectedIDs)
    }

    func testReorderingADistributionWithMoreThanSevenRoutines() throws {
        let context: ModelContext = try makeAssistedContext()
        _ = try applyOwnRoutines(count: 9, context: context)

        let before: [Routine] = try activeManualRoutines(in: context)
        let originalIDs: [UUID] = before.map(\.id)

        for (index, routine) in before.enumerated() {
            routine.sortOrder = before.count - 1 - index
        }
        try context.save()

        let after: [Routine] = try activeManualRoutines(in: context)
        XCTAssertEqual(after.map(\.id), Array(originalIDs.reversed()))
        XCTAssertEqual(after.map(\.sortOrder), Array(0..<9))
    }

    func testMoreThanSevenRoutinesSurviveAReload() throws {
        let schema: Schema = Schema(versionedSchema: AppSchemaV5.self)
        let configuration: ModelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer = try ModelContainer(for: schema, configurations: [configuration])

        let context: ModelContext = ModelContext(container)
        _ = try applyOwnRoutines(count: 10, context: context)

        // Un contexto nuevo sobre el mismo contenedor simula reabrir la base.
        let reloaded: ModelContext = ModelContext(container)
        let routines: [Routine] = try reloaded.fetch(FetchDescriptor<Routine>())
            .sorted { (lhs: Routine, rhs: Routine) -> Bool in lhs.sortOrder < rhs.sortOrder }

        XCTAssertEqual(routines.count, 10)
        XCTAssertEqual(routines.map(\.sortOrder), Array(0..<10))
        XCTAssertEqual(routines.first?.name, "Rutina 01")
        XCTAssertEqual(routines.last?.name, "Rutina 10")
    }

    func testBackupRoundTripKeepsMoreThanSevenRoutines() throws {
        let source: ModelContext = try makeAssistedContext()
        _ = try applyOwnRoutines(count: 11, context: source)
        let exported: [Routine] = try activeManualRoutines(in: source)
        XCTAssertEqual(exported.count, 11)

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let copies: URL = directory.appendingPathComponent("copias", isDirectory: true)

        try BackupManager.saveSafetyCopy(context: source, directory: copies)
        let contents: [URL] = try FileManager.default.contentsOfDirectory(
            at: copies,
            includingPropertiesForKeys: nil
        )
        let file: URL = try XCTUnwrap(contents.first { (url: URL) -> Bool in
            return url.lastPathComponent.hasPrefix("AppGym_PreImport_")
        })

        let destination: ModelContext = try makeAssistedContext()
        let plan: BackupImportPlan = try BackupManager.prepareImport(from: file, context: destination)
        XCTAssertTrue(plan.report.canImport)

        _ = try BackupManager.restoreBackup(
            using: plan,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("copias-destino", isDirectory: true)
        )

        let imported: [Routine] = try activeManualRoutines(in: destination)
        XCTAssertEqual(imported.count, 11)
        XCTAssertEqual(Set(imported.map(\.id)), Set(exported.map(\.id)))
        XCTAssertEqual(imported.map(\.sortOrder), Array(0..<11))
    }

    func testManualDistributionKeepsEveryRoutineUUIDUnique() throws {
        let context: ModelContext = try makeAssistedContext()
        _ = try applyOwnRoutines(count: 12, context: context)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 12)
        XCTAssertEqual(Set(routines.map(\.id)).count, 12)
    }

    func testManualDistributionArchivesSeededRoutinesWithGeneralRules() throws {
        let context: ModelContext = try makeAssistedContext()
        let seededIDs: [UUID] = Array(MockDataGenerator.seededRoutineIDs.prefix(5))
        XCTAssertEqual(seededIDs.count, 5)

        for (index, id) in seededIDs.enumerated() {
            let routine: Routine = Routine(
                id: id,
                name: "INICIAL \(index + 1)",
                isTemplate: true,
                source: .automatic
            )
            context.insert(routine)
        }
        try context.save()

        _ = try applyOwnRoutines(count: 10, context: context)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        let seeded: [Routine] = routines.filter { (routine: Routine) -> Bool in
            return seededIDs.contains(routine.id)
        }

        XCTAssertEqual(seeded.count, 5)
        // Son rutinas generadas: al crear la organizacion manual se archivan
        // como cualquier otra, sin conservarlas por su UUID.
        XCTAssertTrue(seeded.allSatisfy { (routine: Routine) -> Bool in
            return routine.isArchived
        })
        XCTAssertEqual(routines.filter { (routine: Routine) -> Bool in
            return routine.source == .manual && routine.isActivePlanRoutine
        }.count, 10)
        XCTAssertEqual(routines.count, 15)
    }

    // MARK: - Cambiar rutina: confirmación y sustitución de la organización

    func testChangeRoutinePromptUsesTheRequiredCopy() {
        XCTAssertEqual(RoutineChangeMessages.title, "¿Cambiar la organización de tus rutinas?")
        XCTAssertEqual(
            RoutineChangeMessages.message,
            "Al cambiar tu organización, las rutinas actuales serán sustituidas por las nuevas. Los datos y el historial de tus entrenamientos no se perderán, pero las rutinas actuales dejarán de estar disponibles."
        )
        XCTAssertEqual(RoutineChangeMessages.cancelTitle, "Cancelar")
        XCTAssertEqual(RoutineChangeMessages.confirmTitle, "Continuar")
    }

    func testChangeRoutineGateRequiresConfirmationBeforeOpeningTheFlow() {
        var gate: RoutineChangeGate = RoutineChangeGate()

        XCTAssertFalse(gate.isAwaitingConfirmation)
        XCTAssertFalse(gate.isPresentingFlow)

        gate.requestChange()
        XCTAssertTrue(gate.isAwaitingConfirmation)
        XCTAssertFalse(gate.isPresentingFlow)

        gate.cancel()
        XCTAssertFalse(gate.isAwaitingConfirmation)
        XCTAssertFalse(gate.isPresentingFlow)

        gate.requestChange()
        gate.confirm()
        XCTAssertFalse(gate.isAwaitingConfirmation)
        XCTAssertTrue(gate.isPresentingFlow)

        gate.dismissFlow()
        XCTAssertFalse(gate.isPresentingFlow)
    }

    func testCancellingRoutineChangeKeepsRoutinesAndHistoryIntact() throws {
        let context: ModelContext = try makeAssistedContext()
        try insertSession(in: context, routineName: "PUSH")
        let routine: Routine = Routine(name: "PUSH", isTemplate: true, source: .manual)
        context.insert(routine)
        try context.save()

        // «Cancelar» solo cierra el aviso: no abre el flujo ni llama a ningún
        // servicio, así que la base no puede cambiar.
        var gate: RoutineChangeGate = RoutineChangeGate()
        gate.requestChange()
        gate.cancel()

        XCTAssertFalse(gate.isPresentingFlow)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSetLog>()), 1)
    }

    func testChangeRoutineReplacesThePreviousOrganization() throws {
        let context: ModelContext = try makeAssistedContext()
        let first: Routine = Routine(name: "Rutina 01", isTemplate: true, sortOrder: 0, source: .manual)
        let second: Routine = Routine(name: "Rutina 02", isTemplate: true, sortOrder: 1, source: .manual)
        context.insert(first)
        context.insert(second)
        try context.save()

        let result: RoutineApplicationResult = try applyOwnRoutines(
            count: 3,
            context: context,
            replacesOrganization: true
        )

        XCTAssertEqual(result.createdRoutineCount, 3)
        XCTAssertEqual(result.archivedRoutineCount, 2)

        let all: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        let active: [Routine] = all
            .filter { (routine: Routine) -> Bool in routine.isActivePlanRoutine }
            .sorted { (lhs: Routine, rhs: Routine) -> Bool in lhs.sortOrder < rhs.sortOrder }

        // La lista activa contiene solo la organización nueva.
        XCTAssertEqual(active.count, 3)
        XCTAssertEqual(active.map(\.name), ["Rutina 01", "Rutina 02", "Rutina 03"])

        // Las anteriores siguen existiendo, archivadas y con sus IDs.
        XCTAssertEqual(all.count, 5)
        for id in [first.id, second.id] {
            let stored: Routine = try XCTUnwrap(all.first { (routine: Routine) -> Bool in routine.id == id })
            XCTAssertTrue(stored.isArchived)
            XCTAssertFalse(stored.isActivePlanRoutine)
        }
    }

    func testChangeRoutineKeepsHistoricalSessionsAndSetLogs() throws {
        let context: ModelContext = try makeAssistedContext()
        try insertSession(in: context, routineName: "PUSH")
        let previous: Routine = Routine(name: "PUSH", isTemplate: true, source: .manual)
        context.insert(previous)
        try context.save()

        let before: WorkoutSession = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WorkoutSession>()).first
        )
        let startDate: Date = before.startDate
        let endDate: Date = try XCTUnwrap(before.endDate)

        _ = try applyOwnRoutines(count: 2, context: context, replacesOrganization: true)

        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.routineName, "PUSH")
        XCTAssertEqual(sessions.first?.startDate, startDate)
        XCTAssertEqual(sessions.first?.endDate, endDate)
        XCTAssertEqual(sessions.first?.totalVolumeKg, 800.0)

        let logs: [WorkoutSetLog] = try context.fetch(FetchDescriptor<WorkoutSetLog>())
        XCTAssertEqual(logs.count, 1)
        let log: WorkoutSetLog = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.weight, 100.0)
        XCTAssertEqual(log.reps, 8)
        XCTAssertEqual(log.setNumber, 1)
        XCTAssertEqual(log.isCompleted, true)
        XCTAssertEqual(log.exercise?.name, "Press banca")
        XCTAssertNotNil(log.session)
    }

    func testChangeRoutineArchivesSeededRoutinesWithoutDeletingThem() throws {
        let context: ModelContext = try makeAssistedContext()
        let seededIDs: [UUID] = Array(MockDataGenerator.seededRoutineIDs.prefix(2))
        XCTAssertEqual(seededIDs.count, 2)

        for (index, id) in seededIDs.enumerated() {
            let routine: Routine = Routine(
                id: id,
                name: "INICIAL \(index + 1)",
                isTemplate: true,
                source: .automatic
            )
            context.insert(routine)
        }
        try context.save()

        _ = try applyOwnRoutines(count: 1, context: context, replacesOrganization: true)

        let all: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(all.count, 3)

        for id in seededIDs {
            let stored: Routine = try XCTUnwrap(all.first { (routine: Routine) -> Bool in routine.id == id })
            XCTAssertTrue(stored.isArchived)
            XCTAssertFalse(stored.isActivePlanRoutine)
        }

        XCTAssertEqual(all.filter { (routine: Routine) -> Bool in routine.isActivePlanRoutine }.count, 1)
    }

    func testChangeRoutineKeepsArchivedManualRoutinesUntouched() throws {
        let context: ModelContext = try makeAssistedContext()
        let archived: Routine = Routine(
            name: "Manual archivada",
            isTemplate: true,
            sortOrder: 40,
            isArchived: true,
            source: .manual
        )
        context.insert(archived)
        try context.save()

        _ = try applyOwnRoutines(count: 2, context: context, replacesOrganization: true)

        let all: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(all.count, 3)

        let stored: Routine = try XCTUnwrap(all.first { (routine: Routine) -> Bool in routine.id == archived.id })
        XCTAssertTrue(stored.isArchived)
        XCTAssertFalse(stored.isActivePlanRoutine)
        XCTAssertEqual(stored.sortOrder, 40)
    }

    func testChangeRoutineFailureRestoresThePreviousOrganization() throws {
        let context: ModelContext = try makeAssistedContext()
        let previous: Routine = Routine(name: "Organización anterior", isTemplate: true, source: .manual)
        context.insert(previous)
        try context.save()

        // Ejercicio sin músculo primario: la importación de la semana falla
        // después de archivar la organización anterior.
        let broken = GeneratedExercise(
            id: "broken",
            name: "Ejercicio sin músculo",
            sets: 3,
            repsMin: 8,
            repsMax: 12,
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

        var plan: RoutinePlanDraft = RoutinePlanDraft()
        plan.mode = .automatic

        var preferences: OnboardingPreferences = OnboardingPreferences.defaults
        preferences.availablePlates = [1.25, 2.5, 5.0, 10.0, 20.0]

        XCTAssertThrowsError(
            try RoutineService.apply(
                plan: plan,
                preferences: preferences,
                context: context,
                generatedWeek: brokenWeek,
                replacesOrganization: true
            )
        )

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)

        let restored: Routine = try XCTUnwrap(routines.first)
        XCTAssertEqual(restored.name, "Organización anterior")
        XCTAssertFalse(restored.isArchived)
        XCTAssertTrue(restored.isActivePlanRoutine)
    }

    func testChangeRoutineDoesNotAffectTheOnboardingArchiveRules() throws {
        let context: ModelContext = try makeAssistedContext()
        let manual: Routine = Routine(name: "Rutina manual", isTemplate: true, sortOrder: 0, source: .manual)
        let generated: Routine = Routine(name: "Generada", isTemplate: true, sortOrder: 1, source: .automatic)
        context.insert(manual)
        context.insert(generated)
        try context.save()

        // En el onboarding (sin `replacesOrganization`) las manuales siguen
        // activas: el cambio de comportamiento se limita a Cambiar rutina.
        _ = try applyOwnRoutines(count: 1, context: context)

        let all: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        let storedManual: Routine = try XCTUnwrap(all.first { (routine: Routine) -> Bool in routine.id == manual.id })
        let storedGenerated: Routine = try XCTUnwrap(all.first { (routine: Routine) -> Bool in routine.id == generated.id })

        XCTAssertFalse(storedManual.isArchived)
        XCTAssertTrue(storedManual.isActivePlanRoutine)
        XCTAssertTrue(storedGenerated.isArchived)
    }

    // MARK: - Configuración: orden, numeración y acordeón

    func testSettingsSectionsFollowTheRequestedOrder() {
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            [
                "Equipamiento",
                "Discos",
                "Modo visual",
                "Pulsaciones",
                "Organización del entrenamiento",
                "Objetivo semanal",
                "Copia de seguridad",
                "Copias automáticas",
                "Compartir rutina"
            ]
        )
    }

    func testSettingsSectionCodesMatchTheirPosition() {
        XCTAssertEqual(SettingsSection.allCases.count, 9)
        XCTAssertEqual(
            SettingsSection.allCases.map(\.code),
            ["RT.01", "RT.02", "RT.03", "RT.04", "RT.05", "RT.06", "RT.07", "RT.08", "RT.09"]
        )

        for (index, section) in SettingsSection.allCases.enumerated() {
            XCTAssertEqual(section.position, index + 1)
        }

        XCTAssertEqual(Set(SettingsSection.allCases.map(\.code)).count, 9)
    }

    func testSettingsAccordionStartsClosed() {
        let state: SettingsAccordionState = SettingsAccordionState()

        XCTAssertNil(state.expandedSection)
        for section in SettingsSection.allCases {
            XCTAssertFalse(state.isExpanded(section))
        }
    }

    func testOpeningASettingsSectionClosesThePreviousOne() {
        var state: SettingsAccordionState = SettingsAccordionState()

        state.expand(.equipment)
        XCTAssertTrue(state.isExpanded(.equipment))

        state.expand(.backup)
        XCTAssertTrue(state.isExpanded(.backup))
        XCTAssertFalse(state.isExpanded(.equipment))
        XCTAssertEqual(SettingsSection.allCases.filter { (section: SettingsSection) -> Bool in
            return state.isExpanded(section)
        }.count, 1)
    }

    func testTogglingTheOpenSettingsSectionClosesIt() {
        var state: SettingsAccordionState = SettingsAccordionState()

        state.toggle(.heartRate)
        XCTAssertTrue(state.isExpanded(.heartRate))

        state.toggle(.heartRate)
        XCTAssertNil(state.expandedSection)
        XCTAssertFalse(state.isExpanded(.heartRate))
    }

    func testSettingsAccordionNeverKeepsTwoSectionsOpen() {
        var state: SettingsAccordionState = SettingsAccordionState()

        for section in SettingsSection.allCases {
            state.toggle(section)

            let open: [SettingsSection] = SettingsSection.allCases.filter { (candidate: SettingsSection) -> Bool in
                return state.isExpanded(candidate)
            }
            XCTAssertEqual(open, [section])
        }
    }

    // MARK: - Rutinas de siembra sin protección especial

    func testValidBackupWithAllSeededRoutinesIsNotBlocked() throws {
        let seededIDs: [UUID] = Array(MockDataGenerator.seededRoutineIDs.prefix(5))
        let names: [String] = ["PUSH", "PULL", "LEGS", "UPPER", "LOWER"]
        var backupRoutines: [RoutineBackupDTO] = []
        for (index, id) in seededIDs.enumerated() {
            backupRoutines.append(
                makeBackupRoutine(id: id, name: names[index], source: "automatic", exercises: [])
            )
        }

        let destination: ModelContext = try makeAssistedContext()
        let current: Routine = Routine(id: seededIDs[0], name: "PUSH personal", isTemplate: true, source: .automatic)
        destination.insert(current)
        try destination.save()

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(makeBackup(routines: backupRoutines), in: directory)

        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: destination)
        XCTAssertTrue(plan.report.canImport)

        _ = try BackupManager.restoreBackup(
            using: plan,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )

        let restored: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(restored.count, 5)
        XCTAssertEqual(Set(restored.map(\.id)), Set(seededIDs))
        XCTAssertEqual(restored.first { $0.id == seededIDs[0] }?.name, "PUSH")
    }

    func testSeededRoutineArchivedFlagFollowsTheBackup() throws {
        let pushID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let destination: ModelContext = try makeAssistedContext()
        let current: Routine = Routine(
            id: pushID,
            name: "PUSH",
            isTemplate: true,
            isArchived: false,
            source: .automatic
        )
        destination.insert(current)
        try destination.save()

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(id: pushID, name: "PUSH", source: "automatic", isArchived: true, exercises: [])
        ])
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        _ = try BackupManager.restoreBackup(
            from: url,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        let restored: Routine = try XCTUnwrap(routines.first { $0.id == pushID })
        XCTAssertTrue(restored.isArchived)
        XCTAssertFalse(restored.isActivePlanRoutine)
    }

    func testSeededRoutineCanBeArchivedNormally() throws {
        let context: ModelContext = try makeAssistedContext()
        let seedID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let routine: Routine = Routine(id: seedID, name: "PUSH", isTemplate: true, source: .automatic)
        context.insert(routine)
        try context.save()

        routine.isArchived = true
        try context.save()

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        let stored: Routine = try XCTUnwrap(routines.first { $0.id == seedID })
        XCTAssertTrue(stored.isArchived)
        XCTAssertFalse(stored.isActivePlanRoutine)
        XCTAssertEqual(routines.count, 1)
    }

    func testSeededRoutineCanBeDeletedUnderGeneralRules() throws {
        let context: ModelContext = try makeAssistedContext()
        let seedID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let routine: Routine = Routine(id: seedID, name: "PUSH", isTemplate: true, source: .automatic)
        context.insert(routine)
        try context.save()

        XCTAssertEqual(RoutineService.deletionPolicy(for: routine, context: context), .delete)

        context.delete(routine)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 0)
    }

    func testUnsupportedBackupWithSeededRoutinesIsStillBlocked() throws {
        let pushID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let backup: AppBackupData = AppBackupData(
            version: AppBackupData.currentVersion + 1,
            exportDate: Date(timeIntervalSince1970: 1_700_000_000),
            routines: [makeBackupRoutine(id: pushID, name: "PUSH", exercises: [])],
            sessions: [],
            settings: makeBackupSettings(),
            assistedWeeks: nil
        )

        let destination: ModelContext = try makeAssistedContext()
        let sentinel: Routine = Routine(name: "No tocar", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)
        let safety: URL = directory.appendingPathComponent("safety", isDirectory: true)

        XCTAssertThrowsError(
            try BackupManager.restoreBackup(from: url, context: destination, safetyCopyDirectory: safety)
        )
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try safetyCopyFileCount(in: safety), 0)
    }

    func testImportAppliesGeneralHistoryRules() throws {
        let destination: ModelContext = try makeAssistedContext()
        try insertSession(in: destination, routineName: "Historial local")
        let sentinel: Routine = Routine(name: "Rutina local", isTemplate: true, source: .manual)
        destination.insert(sentinel)
        try destination.save()

        let backup: AppBackupData = makeBackup(
            routines: [makeBackupRoutine(name: "Importada", exercises: [])],
            sessions: [makeBackupSession(routineName: "Sesion importada")]
        )
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        _ = try BackupManager.restoreBackup(
            from: url,
            context: destination,
            safetyCopyDirectory: directory.appendingPathComponent("safety", isDirectory: true)
        )

        let sessions: [WorkoutSession] = try destination.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.routineName, "Sesion importada")
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<WorkoutSetLog>()), 0)
    }

    func testImportingTheSameBackupTwiceDoesNotDuplicateRoutines() throws {
        let pushID: UUID = try XCTUnwrap(MockDataGenerator.seededRoutineIDs.first)
        let destination: ModelContext = try makeAssistedContext()
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(id: pushID, name: "PUSH", exercises: [])
        ])
        let url: URL = try writeBackup(backup, in: directory)

        for index in 0..<2 {
            _ = try BackupManager.restoreBackup(
                from: url,
                context: destination,
                safetyCopyDirectory: directory.appendingPathComponent("safety-\(index)", isDirectory: true)
            )
        }

        let routines: [Routine] = try destination.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routines.first?.id, pushID)
    }

    // MARK: - Helpers de distribución manual

    @discardableResult
    private func applyOwnRoutines(
        count: Int,
        context: ModelContext,
        replacesOrganization: Bool = false
    ) throws -> RoutineApplicationResult {
        var plan: RoutinePlanDraft = RoutinePlanDraft()
        plan.mode = .createOwn
        plan.ownRoutineCount = count

        var preferences: OnboardingPreferences = OnboardingPreferences.defaults
        preferences.availablePlates = [1.25, 2.5, 5.0, 10.0, 20.0]

        return try RoutineService.apply(
            plan: plan,
            preferences: preferences,
            context: context,
            replacesOrganization: replacesOrganization
        )
    }

    private func activeManualRoutines(in context: ModelContext) throws -> [Routine] {
        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        return routines
            .filter { (routine: Routine) -> Bool in
                return routine.source == .manual && routine.isActivePlanRoutine
            }
            .sorted { (lhs: Routine, rhs: Routine) -> Bool in
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    // MARK: - Helpers de backups

    @discardableResult
    private func insertSession(in context: ModelContext, routineName: String = "PUSH") throws -> WorkoutSession {
        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(exercise)

        let session: WorkoutSession = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_200_000),
            endDate: Date(timeIntervalSince1970: 1_700_203_600),
            totalVolumeKg: 800.0,
            routineName: routineName
        )
        context.insert(session)

        let log: WorkoutSetLog = WorkoutSetLog(
            date: Date(timeIntervalSince1970: 1_700_200_100),
            workoutStartDate: session.startDate,
            weight: 100.0,
            reps: 8,
            targetRepsMin: 6,
            targetRepsMax: 10,
            isCompleted: true,
            setNumber: 1,
            exercise: exercise,
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]
        try context.save()
        return session
    }

    private func makeBackupSession(routineName: String = "PUSH") -> WorkoutSessionBackupDTO {
        return WorkoutSessionBackupDTO(
            id: UUID(),
            routineName: routineName,
            startDate: Date(timeIntervalSince1970: 1_700_500_000),
            endDate: Date(timeIntervalSince1970: 1_700_503_600),
            totalVolumeKg: 0.0,
            exercises: [],
            bpmSamples: []
        )
    }

    private func safetyCopyFileCount(in directory: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let contents: [URL] = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return contents.filter { $0.lastPathComponent.hasPrefix("AppGym_PreImport_") }.count
    }

    private func makeBackupExercise(name: String, id: UUID?) -> ExerciseBackupDTO {
        return ExerciseBackupDTO(
            id: id,
            name: name,
            muscleGroupRaw: MuscleGroup.chest.rawValue,
            equipmentTypeRaw: EquipmentType.olympicBar.rawValue,
            requiresStraps: false,
            targetRepsMin: 6,
            targetRepsMax: 8,
            defaultRestSeconds: 150,
            defaultRestTargetBPM: nil,
            trackingModeRaw: ExerciseTrackingMode.reps.rawValue
        )
    }

    private func makeBackupLink(
        id: UUID = UUID(),
        exercise: ExerciseBackupDTO?,
        exerciseID: UUID? = nil,
        sortOrder: Int = 0,
        sets: Int = 4,
        repsMin: Int = 6,
        repsMax: Int = 8,
        weight: Double = 80.0,
        rest: Int = 150,
        notes: String = "",
        hasCustomRest: Bool? = nil
    ) -> RoutineExerciseBackupDTO {
        return RoutineExerciseBackupDTO(
            id: id,
            sortOrder: sortOrder,
            targetSets: sets,
            targetRepsMin: repsMin,
            targetRepsMax: repsMax,
            targetWeight: weight,
            restSeconds: rest,
            notes: notes,
            exercise: exercise,
            exerciseID: exerciseID,
            hasCustomRest: hasCustomRest
        )
    }

    private func makeBackupRoutine(
        id: UUID = UUID(),
        name: String,
        source: String? = nil,
        isArchived: Bool? = nil,
        sortOrder: Int = 0,
        exercises: [RoutineExerciseBackupDTO]
    ) -> RoutineBackupDTO {
        return RoutineBackupDTO(
            id: id,
            name: name,
            isTemplate: true,
            sortOrder: sortOrder,
            source: source,
            exercises: exercises,
            isArchived: isArchived
        )
    }

    private func makeBackup(
        routines: [RoutineBackupDTO],
        sessions: [WorkoutSessionBackupDTO] = [],
        plans: [AssistedWeekPlanBackupDTO]? = nil
    ) -> AppBackupData {
        return AppBackupData(
            version: AppBackupData.currentVersion,
            exportDate: Date(timeIntervalSince1970: 1_700_000_000),
            routines: routines,
            sessions: sessions,
            settings: makeBackupSettings(),
            assistedWeeks: plans
        )
    }

    private func makeBackupSettings() -> SettingsBackupDTO {
        return SettingsBackupDTO(
            isBigPictureMode: false,
            multipowerBarWeight: 10.0,
            ezBarWeight: 7.5,
            standardBarWeight: 20.0,
            availablePlates: [1.25, 2.5, 5.0, 10.0, 20.0],
            hrMax: 190.0,
            hrRest: 55.0
        )
    }

    private func writeBackup(_ backup: AppBackupData, in directory: URL) throws -> URL {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data = try encoder.encode(backup)
        return try writeBackupData(data, in: directory)
    }

    private func writeBackupData(_ data: Data, in directory: URL) throws -> URL {
        let url: URL = directory.appendingPathComponent("backup-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
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

    // MARK: - Onboarding sin rutinas (crear más tarde)

    func testOrganizationOffersLaterOptionOnlyInInitialSetup() {
        let initial: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .initialSetup)
        XCTAssertTrue(initial.availableModes.contains(.later))
        XCTAssertEqual(initial.availableModes.count, RoutineOrganizationMode.allCases.count)
        XCTAssertEqual(initial.availableModes.last, RoutineOrganizationMode.later)

        // Ajustes → Cambiar rutina conserva sus tres modalidades.
        let change: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .changeRoutine)
        XCTAssertFalse(change.availableModes.contains(.later))
        XCTAssertEqual(change.availableModes, [.createOwn, .templates, .automatic])

        // La tarjeta mantiene el mismo código, título y descripción pedidos.
        XCTAssertEqual(RoutineOrganizationMode.later.code, "ORG.D")
        XCTAssertEqual(RoutineOrganizationMode.later.title, "Crear mis rutinas más tarde")
        XCTAssertEqual(
            RoutineOrganizationMode.later.summary,
            "Puedes terminar la configuración ahora y crear tus rutinas cuando quieras desde la aplicación."
        )
        XCTAssertEqual(RoutineOrganizationMode.later.configurationTitle, "Crear mis rutinas más tarde")
        XCTAssertFalse(RoutineOrganizationMode.later.symbolName.isEmpty)
        XCTAssertEqual(RoutineOrganizationMode.fromStoredRawValue("later"), .later)
    }

    func testLaterOptionCannotBeSelectedFromChangeRoutine() {
        let change: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .changeRoutine)
        change.selectMode(.later)

        XCTAssertNil(change.plan.mode)
        XCTAssertFalse(change.canContinueFromOrganization)
        XCTAssertFalse(change.completesWithoutRoutines)
    }

    func testSelectingLaterFinishesOnboardingWithoutCreatingRoutines() async throws {
        let snapshot: DefaultsSnapshot = captureDefaults()
        defer { restoreDefaults(snapshot) }

        let context: ModelContext = try makeAssistedContext()
        let configuration: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .initialSetup)
        configuration.selectMode(.later)

        XCTAssertTrue(configuration.canContinueFromOrganization)
        XCTAssertTrue(configuration.completesWithoutRoutines)
        // Ni el generador automático ni el constructor asistido se ejecutan.
        XCTAssertNil(configuration.automatic.week)
        XCTAssertNil(configuration.assisted.generatedWeek)
        XCTAssertFalse(configuration.automatic.hasConsulted)

        let saved: Bool = await configuration.save(preferences: .defaults, modelContext: context)
        XCTAssertTrue(saved)
        XCTAssertEqual(configuration.lastResult?.mode, .later)
        XCTAssertEqual(configuration.lastResult?.createdRoutineCount, 0)
        XCTAssertEqual(configuration.lastResult?.archivedRoutineCount, 0)

        // La lista queda vacía: no hay rutinas manuales, automáticas ni
        // asistidas, ni se siembran las cinco iniciales.
        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertTrue(routines.isEmpty)
        let plans: [AssistedWeekPlan] = try context.fetch(FetchDescriptor<AssistedWeekPlan>())
        XCTAssertTrue(plans.isEmpty)

        // La elección se persiste y el onboarding se marca como completado.
        XCTAssertEqual(UserSettingsManager.routineOrganizationMode, .later)
        let onboarding: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        onboarding.completeSetupIfNeeded()
        XCTAssertTrue(OnboardingService.isCompleted)
    }

    func testLaterOptionDoesNotArchiveExistingRoutines() async throws {
        let snapshot: DefaultsSnapshot = captureDefaults()
        defer { restoreDefaults(snapshot) }

        let context: ModelContext = try makeAssistedContext()
        let existing: Routine = Routine(
            name: "Rutina previa",
            isTemplate: true,
            sortOrder: 0,
            exercises: [],
            source: .automatic
        )
        context.insert(existing)
        try context.save()

        let configuration: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .initialSetup)
        configuration.selectMode(.later)
        let saved: Bool = await configuration.save(preferences: .defaults, modelContext: context)
        XCTAssertTrue(saved)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertFalse(existing.isArchived)
        XCTAssertTrue(existing.isActivePlanRoutine)
        XCTAssertEqual(configuration.lastResult?.archivedRoutineCount, 0)
        XCTAssertEqual(configuration.lastResult?.createdRoutineCount, 0)
    }

    func testEmptyRoutineListCanCreateTheFirstManualRoutine() throws {
        let context: ModelContext = try makeAssistedContext()
        XCTAssertTrue(try context.fetch(FetchDescriptor<Routine>()).isEmpty)

        // Misma creación que ofrecen el botón «+» y el estado vacío.
        let first: Routine = RoutineService.makeManualDraftRoutine(after: [])
        XCTAssertEqual(first.name, "Nueva rutina")
        XCTAssertEqual(first.sortOrder, 0)
        XCTAssertEqual(first.source, .manual)
        XCTAssertTrue(first.isTemplate)
        XCTAssertTrue(first.exercises.isEmpty)
        XCTAssertTrue(first.isActivePlanRoutine)
        XCTAssertFalse(first.isArchived)

        context.insert(first)
        try context.save()

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routines.filter(\.isActivePlanRoutine).count, 1)

        // La creación manual sigue sin límite máximo de rutinas.
        let second: Routine = RoutineService.makeManualDraftRoutine(after: routines)
        XCTAssertEqual(second.sortOrder, 1)
    }

    func testFreshInstallSeedsNoStarterRoutines() throws {
        let context: ModelContext = try makeAssistedContext()
        MockDataGenerator.seedIfNeeded(context: context)

        let exercises: [Exercise] = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertFalse(exercises.isEmpty)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertTrue(routines.isEmpty)
        XCTAssertEqual(MockDataGenerator.seededRoutineIDs.count, 5)
    }

    func testFinishedWithoutRoutinesSurvivesRelaunchWithoutOnboarding() async throws {
        let snapshot: DefaultsSnapshot = captureDefaults()
        defer { restoreDefaults(snapshot) }

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL: URL = directory.appendingPathComponent("default.store")

        do {
            let container: ModelContainer = try XCTUnwrap(StoreBootstrap.makeContainer(storeURL: storeURL).container)
            let context: ModelContext = ModelContext(container)

            let configuration: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .initialSetup)
            configuration.selectMode(.later)
            let saved: Bool = await configuration.save(preferences: .defaults, modelContext: context)
            XCTAssertTrue(saved)

            let onboarding: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
            onboarding.completeSetupIfNeeded()
            XCTAssertTrue(OnboardingService.isCompleted)
        }

        // Reinicio: se abre el mismo store y el onboarding no vuelve a mostrarse.
        let reopened: ModelContainer = try XCTUnwrap(StoreBootstrap.makeContainer(storeURL: storeURL).container)
        let context: ModelContext = ModelContext(reopened)
        XCTAssertTrue(OnboardingService.isCompleted)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Routine>()).isEmpty)
    }

    func testCreateOwnStillCreatesRoutinesAfterFinishingWithoutRoutines() async throws {
        let snapshot: DefaultsSnapshot = captureDefaults()
        defer { restoreDefaults(snapshot) }

        let context: ModelContext = try makeAssistedContext()
        let later: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .initialSetup)
        later.selectMode(.later)
        let savedLater: Bool = await later.save(preferences: .defaults, modelContext: context)
        XCTAssertTrue(savedLater)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Routine>()).isEmpty)

        // Después, desde Ajustes → Cambiar rutina, crea sus propias rutinas.
        let own: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .changeRoutine)
        own.selectMode(.createOwn)
        own.plan.ownRoutineCount = 2
        let savedOwn: Bool = await own.save(preferences: .defaults, modelContext: context)
        XCTAssertTrue(savedOwn)
        XCTAssertEqual(own.lastResult?.createdRoutineCount, 2)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 2)
        XCTAssertTrue(routines.allSatisfy { $0.isActivePlanRoutine })
    }

    func testBackupImportKeepsImportedRoutinesAndSkipsOrganizationStep() throws {
        let context: ModelContext = try makeAssistedContext()
        let backup: AppBackupData = makeBackup(routines: [
            makeBackupRoutine(name: "Importada A", exercises: []),
            makeBackupRoutine(name: "Importada B", exercises: [])
        ])

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = try writeBackup(backup, in: directory)

        let onboarding: OnboardingViewModel = OnboardingViewModel(context: .initialSetup)
        onboarding.prepareBackupImport(from: url, context: context)
        _ = onboarding.confirmPreparedBackup(
            context: context,
            safetyCopyDirectory: directory.appendingPathComponent("copias", isDirectory: true)
        )

        // El flujo importado sigue sin preguntar por la organización y no
        // aplica «crear más tarde»: conserva las rutinas del archivo.
        XCTAssertTrue(onboarding.importedRoutinesReplaceOrganization)
        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 2)
        XCTAssertTrue(routines.allSatisfy { $0.isActivePlanRoutine })

        let configuration: RoutineConfigurationViewModel = RoutineConfigurationViewModel(context: .initialSetup)
        XCTAssertNil(configuration.plan.mode)
    }

    // MARK: - Preferencias de usuario

    private struct DefaultsSnapshot {
        let keys: [String]
        let values: [String: Any]
    }

    private func captureDefaults() -> DefaultsSnapshot {
        let keys: [String] = [
            UserSettingsManager.routineOrganizationModeKey,
            UserSettingsManager.ownRoutineCountKey,
            UserSettingsManager.automaticSplitDaysKey,
            UserSettingsManager.automaticSplitLegsKey,
            UserSettingsManager.automaticSplitUpperKey,
            UserSettingsManager.automaticSplitExpressionKey,
            UserSettingsManager.multipowerBarWeightKey,
            UserSettingsManager.ezBarWeightKey,
            UserSettingsManager.availablePlatesKey,
            UserSettingsManager.isHeartRateTrackingEnabledKey,
            UserSettingsManager.heartRateDeviceTypeKey,
            UserSettingsManager.heartRateDeviceBrandKey,
            UserSettingsManager.didCompleteOnboardingKey
        ]

        var values: [String: Any] = [:]
        for key in keys {
            if let value = UserDefaults.standard.object(forKey: key) {
                values[key] = value
            }
        }

        return DefaultsSnapshot(keys: keys, values: values)
    }

    private func restoreDefaults(_ snapshot: DefaultsSnapshot) {
        for key in snapshot.keys {
            if let value: Any = snapshot.values[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
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

// MARK: - Borrado seguro de ejercicios

/// Pruebas de `ExerciseDeletionService`.
///
/// El borrado de un ejercicio nunca puede eliminar series históricas ni dejar
/// una rutina apuntando a un ejercicio inexistente: en esos casos se bloquea
/// sin modificar ningún dato.
@MainActor
final class ExerciseDeletionServiceTests: XCTestCase {

    func testDeletingAnUnusedExerciseRemovesOnlyThatExercise() throws {
        let context: ModelContext = try makeContext()
        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(exercise)
        try context.save()

        let outcome: ExerciseDeletionService.Outcome = ExerciseDeletionService.delete(
            exercise,
            context: context
        )

        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 0)
    }

    func testExerciseUsedByARoutineIsNotDeleted() throws {
        let context: ModelContext = try makeContext()
        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(exercise)

        let routine: Routine = Routine(name: "PUSH", sortOrder: 0)
        context.insert(routine)
        let link: RoutineExercise = RoutineExercise(exercise: exercise, sortOrder: 0)
        context.insert(link)
        routine.exercises = [link]
        try context.save()

        let outcome: ExerciseDeletionService.Outcome = ExerciseDeletionService.delete(
            exercise,
            context: context
        )

        XCTAssertEqual(outcome, .blockedByRoutines(["PUSH"]))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineExercise>()), 1)
        XCTAssertEqual(routine.exercises.count, 1)
        XCTAssertEqual(routine.exercises.first?.exercise?.id, exercise.id)
    }

    func testExerciseWithHistoryIsNotDeletedAndKeepsTheSessionUntouched() throws {
        let context: ModelContext = try makeContext()
        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(exercise)

        let session: WorkoutSession = WorkoutSession(routineName: "PUSH")
        context.insert(session)
        let log: WorkoutSetLog = WorkoutSetLog(
            weight: 80.0,
            reps: 8,
            isCompleted: true,
            setNumber: 1,
            exercise: exercise,
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]
        session.totalVolumeKg = 640.0
        try context.save()

        let outcome: ExerciseDeletionService.Outcome = ExerciseDeletionService.delete(
            exercise,
            context: context
        )

        XCTAssertEqual(outcome, .blockedByHistory(1))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSetLog>()), 1)
        XCTAssertEqual(log.exercise?.id, exercise.id)
        XCTAssertEqual(session.totalVolumeKg, 640.0)
        XCTAssertEqual(session.setsCompleted.count, 1)
    }

    func testDeletingAnUnreferencedExerciseKeepsOtherHistory() throws {
        let context: ModelContext = try makeContext()

        let used: Exercise = Exercise(name: "Remo con barra", muscleGroup: .upperBack)
        let unused: Exercise = Exercise(name: "Ejercicio nuevo", muscleGroup: .biceps)
        context.insert(used)
        context.insert(unused)

        let session: WorkoutSession = WorkoutSession(routineName: "PULL")
        context.insert(session)
        let log: WorkoutSetLog = WorkoutSetLog(
            weight: 60.0,
            reps: 10,
            isCompleted: true,
            setNumber: 1,
            exercise: used,
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]
        try context.save()

        let outcome: ExerciseDeletionService.Outcome = ExerciseDeletionService.delete(
            unused,
            context: context
        )

        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSetLog>()), 1)
    }

    private func makeContext() throws -> ModelContext {
        let schema: Schema = Schema(versionedSchema: AppSchemaV6.self)
        let configuration: ModelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }
}

// MARK: - Guardar como rutina nueva

/// Pruebas de la copia de vínculos al guardar un entrenamiento como rutina
/// nueva: no puede perderse ningún ajuste personalizado.
@MainActor
final class RoutineCopyTests: XCTestCase {

    func testCopyKeepsCustomRestAndConfiguration() {
        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 2,
            defaultWeight: 60.0,
            restSeconds: 150,
            notes: "nota",
            hasCustomRest: true
        )

        let copy: RoutineExercise = ActiveWorkoutViewModel.copyOfRoutineExercise(link)

        XCTAssertNotEqual(copy.id, link.id)
        XCTAssertEqual(copy.hasCustomRest, true)
        XCTAssertEqual(copy.restSeconds, 150)
        XCTAssertEqual(copy.defaultSets, 4)
        XCTAssertEqual(copy.targetRepsMin, 6)
        XCTAssertEqual(copy.targetRepsMax, 8)
        XCTAssertEqual(copy.defaultWeight, 60.0)
        XCTAssertEqual(copy.sortOrder, 2)
        XCTAssertEqual(copy.notes, "nota")
        XCTAssertEqual(copy.exercise?.id, exercise.id)
    }

    func testCopyKeepsTheAbsenceOfCustomRest() {
        let link: RoutineExercise = RoutineExercise(
            exercise: Exercise(name: "Dominadas", muscleGroup: .lats),
            restSeconds: 120,
            hasCustomRest: false
        )

        let copy: RoutineExercise = ActiveWorkoutViewModel.copyOfRoutineExercise(link)

        XCTAssertFalse(copy.hasCustomRest)
    }
}

// MARK: - Aviso de fin de descanso (concurrencia)

/// Pruebas del token de generación que protege el aviso de descanso.
///
/// Reproducen de forma determinista la condición de carrera: la respuesta del
/// permiso puede llegar después de cancelar, pausar o sustituir el descanso, y
/// en ningún caso puede programar un aviso.
final class RestNotificationManagerTests: XCTestCase {

    private final class AuthorizationGate {
        private var completions: [(UNAuthorizationStatus) -> Void] = []

        var requestedCount: Int { completions.count }

        func register(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
            completions.append(completion)
        }

        func complete(at index: Int, with status: UNAuthorizationStatus) {
            guard completions.indices.contains(index) else { return }
            completions[index](status)
        }
    }

    private final class Recorder {
        var added: [NotificationManager.RestNotification] = []
        var removedPending: [String] = []
        var removedDelivered: [String] = []
        private var addCompletions: [(Error?) -> Void] = []

        func recordAdd(
            _ notification: NotificationManager.RestNotification,
            completion: @escaping (Error?) -> Void
        ) {
            added.append(notification)
            addCompletions.append(completion)
        }

        func completeAdd(at index: Int, error: Error? = nil) {
            guard addCompletions.indices.contains(index) else { return }
            addCompletions[index](error)
        }
    }

    private let now: Date = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeManager(
        gate: AuthorizationGate,
        recorder: Recorder
    ) -> NotificationManager {
        let dependencies: NotificationManager.Dependencies = NotificationManager.Dependencies(
            authorizationStatus: { completion in
                gate.register(completion)
            },
            add: { notification, completion in
                recorder.recordAdd(notification, completion: completion)
            },
            removePending: { identifier in
                recorder.removedPending.append(identifier)
            },
            removeDelivered: { identifier in
                recorder.removedDelivered.append(identifier)
            },
            now: { self.now }
        )
        return NotificationManager(dependencies: dependencies)
    }

    func testCancellingBeforeThePermissionResponseNeverSchedules() {
        let gate: AuthorizationGate = AuthorizationGate()
        let recorder: Recorder = Recorder()
        let manager: NotificationManager = makeManager(gate: gate, recorder: recorder)

        manager.scheduleRestFinishedNotification(endingAt: now.addingTimeInterval(90.0))
        XCTAssertEqual(gate.requestedCount, 1)

        manager.cancelRestFinishedNotification()
        gate.complete(at: 0, with: .authorized)

        XCTAssertTrue(recorder.added.isEmpty)
    }

    func testPausingBeforeThePermissionResponseNeverSchedules() {
        let gate: AuthorizationGate = AuthorizationGate()
        let recorder: Recorder = Recorder()
        let manager: NotificationManager = makeManager(gate: gate, recorder: recorder)

        manager.scheduleRestFinishedNotification(endingAt: now.addingTimeInterval(60.0))
        // `pauseRest()` del ViewModel cancela el aviso y cierra la generación.
        manager.cancelRestFinishedNotification()
        gate.complete(at: 0, with: .authorized)

        XCTAssertTrue(recorder.added.isEmpty)
    }

    func testSubstitutingTheRestInvalidatesThePreviousRequest() {
        let gate: AuthorizationGate = AuthorizationGate()
        let recorder: Recorder = Recorder()
        let manager: NotificationManager = makeManager(gate: gate, recorder: recorder)

        manager.scheduleRestFinishedNotification(endingAt: now.addingTimeInterval(90.0))
        manager.scheduleRestFinishedNotification(endingAt: now.addingTimeInterval(30.0))
        XCTAssertEqual(gate.requestedCount, 2)

        // Respuesta del descanso sustituido: no programa nada.
        gate.complete(at: 0, with: .authorized)
        XCTAssertTrue(recorder.added.isEmpty)

        // Respuesta del descanso vigente: programa solo este.
        gate.complete(at: 1, with: .authorized)
        XCTAssertEqual(recorder.added.count, 1)
        XCTAssertEqual(recorder.added.first?.timeInterval ?? 0.0, 30.0, accuracy: 0.001)
    }

    func testRegistrationFinishedAfterPauseIsRemoved() {
        let gate: AuthorizationGate = AuthorizationGate()
        let recorder: Recorder = Recorder()
        let manager: NotificationManager = makeManager(gate: gate, recorder: recorder)

        manager.scheduleRestFinishedNotification(endingAt: now.addingTimeInterval(90.0))
        gate.complete(at: 0, with: .authorized)
        XCTAssertEqual(recorder.added.count, 1)

        manager.cancelRestFinishedNotification()
        let removalsAfterCancel: Int = recorder.removedPending.count

        // El registro en el centro de notificaciones termina después de la
        // pausa: el aviso recién creado debe retirarse.
        recorder.completeAdd(at: 0)
        XCTAssertGreaterThan(recorder.removedPending.count, removalsAfterCancel)
    }

    func testDeniedPermissionDoesNotSchedule() {
        let gate: AuthorizationGate = AuthorizationGate()
        let recorder: Recorder = Recorder()
        let manager: NotificationManager = makeManager(gate: gate, recorder: recorder)

        manager.scheduleRestFinishedNotification(endingAt: now.addingTimeInterval(90.0))
        gate.complete(at: 0, with: .denied)

        XCTAssertTrue(recorder.added.isEmpty)
    }

    func testRestThatAlreadyEndedDoesNotRequestPermission() {
        let gate: AuthorizationGate = AuthorizationGate()
        let recorder: Recorder = Recorder()
        let manager: NotificationManager = makeManager(gate: gate, recorder: recorder)

        manager.scheduleRestFinishedNotification(endingAt: now.addingTimeInterval(-5.0))

        XCTAssertEqual(gate.requestedCount, 0)
        XCTAssertTrue(recorder.added.isEmpty)
    }

    func testSchedulingAfterCancellingStillWorks() {
        let gate: AuthorizationGate = AuthorizationGate()
        let recorder: Recorder = Recorder()
        let manager: NotificationManager = makeManager(gate: gate, recorder: recorder)

        manager.scheduleRestFinishedNotification(endingAt: now.addingTimeInterval(90.0))
        manager.cancelRestFinishedNotification()
        manager.scheduleRestFinishedNotification(endingAt: now.addingTimeInterval(45.0))

        gate.complete(at: 0, with: .authorized)
        XCTAssertTrue(recorder.added.isEmpty)

        gate.complete(at: 1, with: .authorized)
        XCTAssertEqual(recorder.added.count, 1)
        XCTAssertEqual(recorder.added.first?.timeInterval ?? 0.0, 45.0, accuracy: 0.001)
    }
}

// MARK: - Temporizador de descanso en Big Picture

/// Pruebas de la pausa, la reanudación y el ajuste de ±15 s del temporizador de
/// descanso de Big Picture.
///
/// No hay esperas: se comprueban las fechas de finalización
/// (`restTimerEndDate`) y el tiempo guardado (`restTimeRemaining`). Donde el
/// reloj puede cruzar un segundo entre dos llamadas se usa una tolerancia de un
/// segundo; el resto de comparaciones son exactas.
@MainActor
final class BigPictureRestTimerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var previousHeartRateSetting: Any?
    /// ViewModels vivos del test, incluidos los creados al restaurar. Se
    /// detienen en `tearDown` para no dejar tareas de cuenta atrás ni avisos
    /// pendientes apuntando a sesiones ya terminadas.
    private var viewModels: [ActiveWorkoutViewModel] = []

    override func setUpWithError() throws {
        try super.setUpWithError()

        // El ViewModel pide HealthKit al arrancar si la medición está activa: se
        // desactiva durante la prueba y se restaura al terminar.
        previousHeartRateSetting = UserDefaults.standard.object(
            forKey: UserSettingsManager.isHeartRateTrackingEnabledKey
        )
        UserDefaults.standard.set(false, forKey: UserSettingsManager.isHeartRateTrackingEnabledKey)
        ActiveWorkoutStateStore.clear()

        let schema: Schema = Schema(versionedSchema: AppSchemaV6.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        // Pausar cancela la tarea de cuenta atrás y el aviso programado. Un
        // descanso ya pausado no tiene ninguno de los dos, así que se respeta.
        for viewModel in viewModels where viewModel.isResting && !viewModel.isRestPaused {
            viewModel.pauseRest()
        }
        viewModels.removeAll()

        ActiveWorkoutStateStore.clear()

        if let previousHeartRateSetting {
            UserDefaults.standard.set(
                previousHeartRateSetting,
                forKey: UserSettingsManager.isHeartRateTrackingEnabledKey
            )
        } else {
            UserDefaults.standard.removeObject(forKey: UserSettingsManager.isHeartRateTrackingEnabledKey)
        }

        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Utilidades

    /// Crea una rutina de una serie y deja el descanso ya iniciado, igual que
    /// ocurre al completar una serie en la app.
    private func makeRestingWorkout(
        restSeconds: Int
    ) throws -> (viewModel: ActiveWorkoutViewModel, session: WorkoutSession, routine: Routine) {
        let exercise: Exercise = Exercise(
            name: "Press banca",
            muscleGroup: .chest,
            defaultRestCondition: .timer(seconds: restSeconds)
        )
        context.insert(exercise)

        let routineExercise: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 1,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 0,
            defaultWeight: 80.0,
            restSeconds: restSeconds
        )
        context.insert(routineExercise)

        let routine: Routine = Routine(name: "PUSH", exercises: [routineExercise])
        context.insert(routine)

        let session: WorkoutSession = WorkoutSession(startDate: Date(), routineName: "PUSH")
        context.insert(session)

        try context.save()

        let viewModel: ActiveWorkoutViewModel = makeViewModel(session: session, routine: routine)
        viewModel.toggleSetCompletion(
            for: routineExercise.id,
            setIndex: 0,
            modelContext: context
        )

        return (viewModel, session, routine)
    }

    /// Crea un ViewModel sobre la sesión y la rutina dadas y lo registra para
    /// que `tearDown` detenga su descanso si queda en marcha.
    private func makeViewModel(
        session: WorkoutSession,
        routine: Routine
    ) -> ActiveWorkoutViewModel {
        let viewModel: ActiveWorkoutViewModel = ActiveWorkoutViewModel(
            session: session,
            routine: routine,
            modelContext: context
        )
        viewModels.append(viewModel)
        return viewModel
    }

    // MARK: - Pausa y reanudación

    func testPausingKeepsTheRemainingTime() throws {
        let workout = try makeRestingWorkout(restSeconds: 90)
        XCTAssertTrue(workout.viewModel.isResting)

        let remainingBefore: Int = workout.viewModel.restRemainingSeconds()
        workout.viewModel.pauseRest()

        XCTAssertTrue(workout.viewModel.isResting)
        XCTAssertTrue(workout.viewModel.isRestPaused)
        XCTAssertGreaterThan(workout.viewModel.restTimeRemaining, 0)
        XCTAssertEqual(
            Double(workout.viewModel.restTimeRemaining),
            Double(remainingBefore),
            accuracy: 1.0
        )
    }

    func testBigPictureKeepsTheTimerVisibleWhilePaused() throws {
        let workout = try makeRestingWorkout(restSeconds: 90)
        workout.viewModel.pauseRest()

        XCTAssertTrue(workout.viewModel.bigPictureIsTimerShowing)
        // `hasActiveRestTimer` conserva su semántica: al pausar ya no hay fecha
        // de fin, aunque Big Picture siga mostrando el panel.
        XCTAssertFalse(workout.viewModel.hasActiveRestTimer)
    }

    func testBigPictureRemainingTimeMatchesTheStoredValueWhilePaused() throws {
        let workout = try makeRestingWorkout(restSeconds: 90)
        workout.viewModel.pauseRest()

        XCTAssertEqual(workout.viewModel.bigPictureRemainingTime, workout.viewModel.restTimeRemaining)
        XCTAssertGreaterThan(workout.viewModel.bigPictureRemainingTime, 0)
    }

    func testProgressBarKeepsItsPositionWhenPaused() throws {
        let workout = try makeRestingWorkout(restSeconds: 120)
        let totalBefore: Int = workout.viewModel.totalRestSeconds
        workout.viewModel.pauseRest()

        XCTAssertEqual(workout.viewModel.totalRestSeconds, totalBefore)

        let expected: Double = Double(workout.viewModel.restTimeRemaining) / Double(totalBefore)
        XCTAssertEqual(workout.viewModel.bigPictureRestProgress, expected, accuracy: 0.0001)
        XCTAssertGreaterThan(workout.viewModel.bigPictureRestProgress, 0.0)
        XCTAssertLessThan(workout.viewModel.bigPictureRestProgress, 1.0)

        // La barra se dibuja como `1 - restProgress`: no debe aparecer consumida.
        XCTAssertGreaterThan(1.0 - workout.viewModel.bigPictureRestProgress, 0.0)
    }

    func testResumingContinuesFromTheStoredTime() throws {
        let workout = try makeRestingWorkout(restSeconds: 90)
        workout.viewModel.pauseRest()
        let paused: Int = workout.viewModel.restTimeRemaining

        workout.viewModel.resumeRest()

        XCTAssertFalse(workout.viewModel.isRestPaused)
        XCTAssertTrue(workout.viewModel.bigPictureIsTimerShowing)
        XCTAssertTrue(workout.viewModel.isRestTimerActive)
        let endDate: Date = try XCTUnwrap(workout.viewModel.restTimerEndDate)
        XCTAssertEqual(endDate.timeIntervalSinceNow, Double(paused), accuracy: 1.5)
        XCTAssertGreaterThan(workout.viewModel.restRemainingSeconds(), 0)
    }

    // MARK: - Ajuste de ±15 s

    func testAddingFifteenSecondsWhileRunningMovesTheEndDate() throws {
        let workout = try makeRestingWorkout(restSeconds: 90)
        let endBefore: Date = try XCTUnwrap(workout.viewModel.restTimerEndDate)
        let totalBefore: Int = workout.viewModel.totalRestSeconds

        workout.viewModel.adjustRestTime(by: ActiveWorkoutViewModel.bigPictureRestAdjustmentSeconds)

        let endAfter: Date = try XCTUnwrap(workout.viewModel.restTimerEndDate)
        XCTAssertEqual(endAfter.timeIntervalSince(endBefore), 15.0, accuracy: 0.001)
        XCTAssertEqual(workout.viewModel.totalRestSeconds, totalBefore + 15)
        XCTAssertFalse(workout.viewModel.isRestPaused)
        XCTAssertTrue(workout.viewModel.isResting)
    }

    func testAddingFifteenSecondsWhilePausedUpdatesTheStoredTime() throws {
        let workout = try makeRestingWorkout(restSeconds: 90)
        workout.viewModel.pauseRest()
        let paused: Int = workout.viewModel.restTimeRemaining

        workout.viewModel.adjustRestTime(by: ActiveWorkoutViewModel.bigPictureRestAdjustmentSeconds)

        XCTAssertEqual(workout.viewModel.restTimeRemaining, paused + 15)
        XCTAssertEqual(workout.viewModel.bigPictureRemainingTime, paused + 15)
        XCTAssertNil(workout.viewModel.restTimerEndDate)
        XCTAssertTrue(workout.viewModel.isRestPaused)
        XCTAssertTrue(workout.viewModel.isResting)
    }

    func testSubtractingFifteenSecondsWhileRunningReducesTheTime() throws {
        let workout = try makeRestingWorkout(restSeconds: 90)
        let endBefore: Date = try XCTUnwrap(workout.viewModel.restTimerEndDate)

        workout.viewModel.adjustRestTime(by: -ActiveWorkoutViewModel.bigPictureRestAdjustmentSeconds)

        let endAfter: Date = try XCTUnwrap(workout.viewModel.restTimerEndDate)
        XCTAssertEqual(endAfter.timeIntervalSince(endBefore), -15.0, accuracy: 0.001)
        XCTAssertTrue(workout.viewModel.isResting)
        XCTAssertFalse(workout.viewModel.isRestFinishing)
        XCTAssertFalse(workout.viewModel.isRestPaused)
    }

    func testSubtractingFifteenSecondsWhilePausedReducesTheStoredTime() throws {
        let workout = try makeRestingWorkout(restSeconds: 90)
        workout.viewModel.pauseRest()
        let paused: Int = workout.viewModel.restTimeRemaining

        workout.viewModel.adjustRestTime(by: -ActiveWorkoutViewModel.bigPictureRestAdjustmentSeconds)

        XCTAssertEqual(workout.viewModel.restTimeRemaining, paused - 15)
        XCTAssertEqual(workout.viewModel.bigPictureRemainingTime, paused - 15)
        XCTAssertNil(workout.viewModel.restTimerEndDate)
        XCTAssertTrue(workout.viewModel.isRestPaused)
    }

    func testSubtractIsDisabledWithFifteenSecondsOrLess() throws {
        let short = try makeRestingWorkout(restSeconds: 15)

        XCTAssertLessThanOrEqual(short.viewModel.bigPictureRemainingTime, 15)
        XCTAssertFalse(short.viewModel.bigPictureCanSubtractRestTime)
        // Sumar sigue disponible en el último intervalo.
        XCTAssertTrue(short.viewModel.bigPictureCanAdjustRestTime)

        let long = try makeRestingWorkout(restSeconds: 90)
        XCTAssertTrue(long.viewModel.bigPictureCanSubtractRestTime)
    }

    func testAdjustingTimeNeverFinishesOrSkipsTheRest() throws {
        let workout = try makeRestingWorkout(restSeconds: 20)

        workout.viewModel.adjustRestTime(by: -15)

        XCTAssertTrue(workout.viewModel.isResting)
        XCTAssertFalse(workout.viewModel.isRestFinishing)
        XCTAssertGreaterThan(workout.viewModel.restRemainingSeconds(), 0)

        // Segundo intento: se ignora en lugar de cerrar el descanso.
        let remainingAfterFirst: Int = workout.viewModel.restRemainingSeconds()
        workout.viewModel.adjustRestTime(by: -15)

        XCTAssertTrue(workout.viewModel.isResting)
        XCTAssertFalse(workout.viewModel.isRestFinishing)
        XCTAssertEqual(
            Double(workout.viewModel.restRemainingSeconds()),
            Double(remainingAfterFirst),
            accuracy: 1.0
        )

        // Lo mismo en pausa: restar por debajo del último intervalo no termina.
        workout.viewModel.pauseRest()
        workout.viewModel.adjustRestTime(by: -15)

        XCTAssertTrue(workout.viewModel.isResting)
        XCTAssertTrue(workout.viewModel.isRestPaused)
        XCTAssertFalse(workout.viewModel.isRestFinishing)
        XCTAssertGreaterThan(workout.viewModel.restTimeRemaining, 0)

        // Un toque tardío tampoco puede mover una fecha de fin ya vencida.
        workout.viewModel.resumeRest()
        let expired: Date = Date().addingTimeInterval(-1.0)
        workout.viewModel.restTimerEndDate = expired
        XCTAssertFalse(workout.viewModel.hasActiveRestTimer)

        let totalBeforeExpired: Int = workout.viewModel.totalRestSeconds
        workout.viewModel.adjustRestTime(by: 15)

        XCTAssertEqual(workout.viewModel.restTimerEndDate, expired)
        XCTAssertEqual(workout.viewModel.totalRestSeconds, totalBeforeExpired)
        XCTAssertFalse(workout.viewModel.isRestFinishing)
    }

    // MARK: - Compatibilidad con el temporizador normal

    func testNormalTimerKeepsItsTenSecondAdjustments() throws {
        let workout = try makeRestingWorkout(restSeconds: 90)
        let endBefore: Date = try XCTUnwrap(workout.viewModel.restTimerEndDate)
        let totalBefore: Int = workout.viewModel.totalRestSeconds

        workout.viewModel.add10Seconds()

        let endAfterAdd: Date = try XCTUnwrap(workout.viewModel.restTimerEndDate)
        XCTAssertEqual(endAfterAdd.timeIntervalSince(endBefore), 10.0, accuracy: 0.001)
        XCTAssertEqual(workout.viewModel.totalRestSeconds, totalBefore + 10)

        workout.viewModel.sub10Seconds()

        let endAfterSub: Date = try XCTUnwrap(workout.viewModel.restTimerEndDate)
        XCTAssertEqual(endAfterSub.timeIntervalSince(endAfterAdd), -10.0, accuracy: 0.001)
        XCTAssertEqual(workout.viewModel.totalRestSeconds, totalBefore)
    }

    // MARK: - Notificaciones y persistencia

    func testPauseAndResumeUpdateThePendingRestNotificationState() throws {
        let workout = try makeRestingWorkout(restSeconds: 90)

        // El aviso no se inspecciona en `UNUserNotificationCenter`: lo que se
        // fija es el estado del que depende su programación o cancelación.
        // En marcha: fecha de fin y aviso activo.
        XCTAssertNotNil(workout.viewModel.restTimerEndDate)
        XCTAssertTrue(workout.viewModel.isRestTimerActive)

        workout.viewModel.pauseRest()

        // Pausado: `pauseRest()` cancela el aviso (se queda sin fecha de fin).
        XCTAssertNil(workout.viewModel.restTimerEndDate)
        XCTAssertFalse(workout.viewModel.isRestTimerActive)

        workout.viewModel.resumeRest()

        // Reanudado: se vuelve a programar con la nueva fecha.
        XCTAssertNotNil(workout.viewModel.restTimerEndDate)
        XCTAssertTrue(workout.viewModel.isRestTimerActive)
    }

    func testRestoringAPausedRestKeepsItsTime() throws {
        let workout = try makeRestingWorkout(restSeconds: 120)
        workout.viewModel.pauseRest()
        let paused: Int = workout.viewModel.restTimeRemaining
        let total: Int = workout.viewModel.totalRestSeconds

        // `pauseRest()` persiste el estado; un ViewModel nuevo sobre la misma
        // sesión y rutina lo restaura, como al reabrir la app.
        let restored: ActiveWorkoutViewModel = makeViewModel(
            session: workout.session,
            routine: workout.routine
        )

        XCTAssertTrue(restored.isResting)
        XCTAssertTrue(restored.isRestPaused)
        XCTAssertEqual(restored.restTimeRemaining, paused)
        XCTAssertEqual(restored.bigPictureRemainingTime, paused)
        XCTAssertTrue(restored.bigPictureIsTimerShowing)
        XCTAssertEqual(restored.totalRestSeconds, total)
        XCTAssertNil(restored.restTimerEndDate)
    }
}

// MARK: - Filtrado compartido del catálogo

/// Pruebas del estado de filtrado compartido por la pestaña Ejercicios y por el
/// selector de sustitución. No necesitan SwiftData: los `Exercise` se crean en
/// memoria y solo se comprueban las reglas de búsqueda y combinación.
final class ExerciseFilterStateTests: XCTestCase {

    /// Catálogo de prueba. La clasificación `isCompound` es explícita en cada
    /// ejercicio para que las pruebas de TIPO no dependan de valores por
    /// defecto: compuestos = press banca, press inclinado y remo con barra;
    /// aislamiento = aperturas, curl, plancha y bici.
    private func catalog() -> [Exercise] {
        return [
            Exercise(name: "Press banca", muscleGroup: .chest, equipmentType: .olympicBar, isCompound: true, trackingMode: .reps),
            Exercise(name: "Press inclinado con mancuernas", muscleGroup: .chest, equipmentType: .dumbbell, isCompound: true, trackingMode: .reps),
            Exercise(name: "Aperturas en polea", muscleGroup: .chest, equipmentType: .cable, isCompound: false, trackingMode: .reps),
            Exercise(name: "Remo con barra", muscleGroup: .lats, equipmentType: .olympicBar, isCompound: true, trackingMode: .reps),
            Exercise(name: "Curl de bíceps", muscleGroup: .biceps, equipmentType: .dumbbell, isCompound: false, trackingMode: .reps),
            Exercise(name: "Plancha", muscleGroup: .abs, equipmentType: .bodyweight, isCompound: false, trackingMode: .seconds),
            Exercise(name: "Bici estática", muscleGroup: .cardio, equipmentType: .cardioMachine, isCompound: false, trackingMode: .minutes)
        ]
    }

    private func names(_ exercises: [Exercise]) -> [String] {
        exercises.map(\.name)
    }

    func testSearchMatchesByName() {
        var filter = ExerciseFilterState()
        filter.searchText = "press"

        XCTAssertEqual(
            names(filter.apply(to: catalog())),
            ["Press banca", "Press inclinado con mancuernas"]
        )
    }

    func testSearchIgnoresCase() {
        var filter = ExerciseFilterState(searchText: "PRESS")
        XCTAssertEqual(filter.apply(to: catalog()).count, 2)

        filter.searchText = "pReSs BaNcA"
        XCTAssertEqual(names(filter.apply(to: catalog())), ["Press banca"])

        // La búsqueda por nombre no depende de acentos de otro idioma ni del
        // orden de la lista: se conserva el orden recibido.
        filter.searchText = "remo"
        XCTAssertEqual(names(filter.apply(to: catalog())), ["Remo con barra"])
    }

    func testFilterByMuscleGroup() {
        let filter = ExerciseFilterState(selectedMuscleGroup: .chest)

        XCTAssertEqual(
            names(filter.apply(to: catalog())),
            ["Press banca", "Press inclinado con mancuernas", "Aperturas en polea"]
        )
    }

    func testFilterByEquipment() {
        let filter = ExerciseFilterState(selectedEquipment: .dumbbell)

        XCTAssertEqual(
            names(filter.apply(to: catalog())),
            ["Press inclinado con mancuernas", "Curl de bíceps"]
        )
    }

    func testFilterByCompoundClassification() {
        // COMPUESTO: solo los ejercicios marcados con `isCompound == true`.
        var filter = ExerciseFilterState(selectedIsCompound: true)
        XCTAssertEqual(
            names(filter.apply(to: catalog())),
            ["Press banca", "Press inclinado con mancuernas", "Remo con barra"]
        )
        XCTAssertTrue(filter.apply(to: catalog()).allSatisfy { $0.isCompound })

        // AISLAMIENTO: complementario exacto, sin solapamientos con el anterior.
        filter.selectedIsCompound = false
        XCTAssertEqual(
            names(filter.apply(to: catalog())),
            ["Aperturas en polea", "Curl de bíceps", "Plancha", "Bici estática"]
        )
        XCTAssertTrue(filter.apply(to: catalog()).allSatisfy { !$0.isCompound })

        // Sin selección: vuelve el catálogo completo, no una tercera categoría.
        filter.selectedIsCompound = nil
        XCTAssertEqual(filter.apply(to: catalog()).count, catalog().count)
        XCTAssertFalse(filter.hasActiveCriteria)
    }

    func testCombinedCriteriaMatchSimultaneously() {
        var filter = ExerciseFilterState(
            searchText: "press",
            selectedMuscleGroup: .chest,
            selectedEquipment: .dumbbell,
            selectedIsCompound: true
        )

        XCTAssertEqual(
            names(filter.apply(to: catalog())),
            ["Press inclinado con mancuernas"]
        )

        // El mismo filtro con la clasificación contraria no deja nada: el
        // criterio de TIPO es excluyente, no una suma de resultados.
        filter.selectedIsCompound = false
        XCTAssertTrue(filter.apply(to: catalog()).isEmpty)
        filter.selectedIsCompound = true

        // Cambiar solo el material mantiene los demás criterios.
        filter.selectedEquipment = .olympicBar
        XCTAssertEqual(names(filter.apply(to: catalog())), ["Press banca"])
    }

    func testResetClearsSearchAndFilters() {
        var filter = ExerciseFilterState(
            searchText: "press",
            selectedMuscleGroup: .chest,
            selectedEquipment: .dumbbell,
            selectedIsCompound: true
        )
        XCTAssertTrue(filter.hasActiveCriteria)

        filter.reset()

        XCTAssertEqual(filter, ExerciseFilterState())
        XCTAssertFalse(filter.hasActiveCriteria)
        XCTAssertEqual(filter.apply(to: catalog()).count, catalog().count)
    }

    func testEmptyResultWhenNoExerciseMatches() {
        let noName = ExerciseFilterState(searchText: "sentadilla bulgara")
        XCTAssertTrue(noName.apply(to: catalog()).isEmpty)
        XCTAssertTrue(noName.hasActiveCriteria)

        // Combinación imposible con el catálogo de prueba: pecho + cardio.
        let impossible = ExerciseFilterState(
            selectedMuscleGroup: .chest,
            selectedEquipment: .cardioMachine
        )
        XCTAssertTrue(impossible.apply(to: catalog()).isEmpty)
    }
}

// MARK: - Sustitución de ejercicio en una rutina

/// Pruebas del único punto de mutación de la sustitución: el mismo
/// `RoutineExercise` cambia de ejercicio sin perder su configuración, sin
/// alterar el resto de la rutina y sin tocar el historial.
final class RoutineExerciseSubstitutionTests: XCTestCase {

    /// UUID estable de la rutina personal PUSH. Se usa solo como identidad de un
    /// objeto creado en un contenedor de memoria, para comprobar que la
    /// sustitución no toca el identificador de la rutina protegida.
    private static let protectedPushID: UUID = UUID(
        uuidString: "6F0E1A10-0001-4000-8000-000000000001"
    )!

    private var container: ModelContainer!
    private var context: ModelContext!

    private struct Fixture {
        let routine: Routine
        let target: RoutineExercise
        let other: RoutineExercise
        let previousExercise: Exercise
        let replacementExercise: Exercise
        let otherExercise: Exercise
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        let schema: Schema = Schema(versionedSchema: AppSchemaV6.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    private func makeFixture() throws -> Fixture {
        let previousExercise = Exercise(
            name: "Press banca",
            muscleGroup: .chest,
            equipmentType: .olympicBar
        )
        let replacementExercise = Exercise(
            name: "Press inclinado con mancuernas",
            muscleGroup: .chest,
            equipmentType: .dumbbell
        )
        let otherExercise = Exercise(
            name: "Aperturas en polea",
            muscleGroup: .chest,
            equipmentType: .cable
        )
        context.insert(previousExercise)
        context.insert(replacementExercise)
        context.insert(otherExercise)

        let target = RoutineExercise(
            exercise: previousExercise,
            defaultSets: 5,
            targetRepsMin: 5,
            targetRepsMax: 7,
            sortOrder: 0,
            defaultWeight: 82.5,
            restSeconds: 150,
            notes: "Codos a 45 grados",
            hasCustomRest: true
        )
        let other = RoutineExercise(
            exercise: otherExercise,
            defaultSets: 3,
            targetRepsMin: 10,
            targetRepsMax: 12,
            sortOrder: 1,
            defaultWeight: 15.0,
            restSeconds: 60,
            notes: "Polea alta",
            hasCustomRest: false
        )
        context.insert(target)
        context.insert(other)

        let routine = Routine(
            id: Self.protectedPushID,
            name: "PUSH",
            exercises: [target, other]
        )
        context.insert(routine)

        try context.save()

        return Fixture(
            routine: routine,
            target: target,
            other: other,
            previousExercise: previousExercise,
            replacementExercise: replacementExercise,
            otherExercise: otherExercise
        )
    }

    private func makeReplacedFixture() throws -> Fixture {
        let fixture = try makeFixture()
        fixture.target.replaceExercise(with: fixture.replacementExercise)
        return fixture
    }

    func testReplacementSwapsTheExerciseOfTheTargetRow() throws {
        let fixture = try makeFixture()

        XCTAssertTrue(fixture.target.replaceExercise(with: fixture.replacementExercise))
        XCTAssertEqual(fixture.target.exercise?.id, fixture.replacementExercise.id)
        XCTAssertEqual(fixture.target.exercise?.name, "Press inclinado con mancuernas")

        // Elegir el mismo ejercicio no cambia nada.
        XCTAssertFalse(fixture.target.replaceExercise(with: fixture.replacementExercise))
    }

    func testReplacementKeepsTheRoutineExerciseIdentity() throws {
        let fixture = try makeFixture()
        let routineExerciseID: UUID = fixture.target.id

        fixture.target.replaceExercise(with: fixture.replacementExercise)
        try context.save()

        XCTAssertEqual(fixture.target.id, routineExerciseID)
        XCTAssertEqual(fixture.routine.id, Self.protectedPushID)
        XCTAssertEqual(fixture.routine.name, "PUSH")

        let stored: [RoutineExercise] = try context.fetch(FetchDescriptor<RoutineExercise>())
        XCTAssertEqual(stored.filter { $0.id == routineExerciseID }.count, 1)
    }

    func testReplacementKeepsTheSetCount() throws {
        let fixture = try makeReplacedFixture()
        XCTAssertEqual(fixture.target.defaultSets, 5)
    }

    func testReplacementKeepsTheRepRanges() throws {
        let fixture = try makeReplacedFixture()
        XCTAssertEqual(fixture.target.targetRepsMin, 5)
        XCTAssertEqual(fixture.target.targetRepsMax, 7)
    }

    func testReplacementKeepsTheDefaultWeight() throws {
        let fixture = try makeReplacedFixture()
        XCTAssertEqual(fixture.target.defaultWeight, 82.5, accuracy: 0.0001)
    }

    func testReplacementKeepsTheRestSeconds() throws {
        let fixture = try makeReplacedFixture()
        XCTAssertEqual(fixture.target.restSeconds, 150)
    }

    func testReplacementKeepsHasCustomRest() throws {
        let custom = try makeReplacedFixture()
        XCTAssertTrue(custom.target.hasCustomRest)
        XCTAssertFalse(custom.other.hasCustomRest)
    }

    func testReplacementKeepsTheNotes() throws {
        let fixture = try makeReplacedFixture()
        XCTAssertEqual(fixture.target.notes, "Codos a 45 grados")
    }

    func testReplacementKeepsTheSortOrder() throws {
        let fixture = try makeReplacedFixture()
        XCTAssertEqual(fixture.target.sortOrder, 0)
        XCTAssertEqual(fixture.other.sortOrder, 1)
    }

    func testReplacementDoesNotAddExercises() throws {
        let fixture = try makeReplacedFixture()
        try context.save()

        XCTAssertEqual(fixture.routine.exercises.count, 2)

        let stored: [RoutineExercise] = try context.fetch(FetchDescriptor<RoutineExercise>())
        XCTAssertEqual(stored.count, 2)
    }

    func testReplacementDoesNotTouchOtherRows() throws {
        let fixture = try makeReplacedFixture()

        XCTAssertEqual(fixture.other.exercise?.id, fixture.otherExercise.id)
        XCTAssertEqual(fixture.other.exercise?.name, "Aperturas en polea")
        XCTAssertEqual(fixture.other.defaultSets, 3)
        XCTAssertEqual(fixture.other.targetRepsMin, 10)
        XCTAssertEqual(fixture.other.targetRepsMax, 12)
        XCTAssertEqual(fixture.other.defaultWeight, 15.0, accuracy: 0.0001)
        XCTAssertEqual(fixture.other.restSeconds, 60)
        XCTAssertEqual(fixture.other.notes, "Polea alta")
    }

    func testReplacementDoesNotTouchTrainingHistory() throws {
        let fixture = try makeFixture()

        let session = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            routineName: "PUSH"
        )
        context.insert(session)

        let log = WorkoutSetLog(
            date: Date(timeIntervalSince1970: 1_700_000_100),
            weight: 80.0,
            reps: 7,
            targetRepsMin: 5,
            targetRepsMax: 7,
            isCompleted: true,
            routineExerciseID: fixture.target.id,
            setNumber: 1,
            exercise: fixture.previousExercise,
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]
        try context.save()

        let logID: UUID = log.id
        fixture.target.replaceExercise(with: fixture.replacementExercise)
        try context.save()

        XCTAssertEqual(session.setsCompleted.count, 1)
        XCTAssertEqual(session.setsCompleted.first?.id, logID)
        XCTAssertEqual(log.exercise?.id, fixture.previousExercise.id)
        XCTAssertEqual(log.weight, 80.0, accuracy: 0.0001)
        XCTAssertEqual(log.reps, 7)
        XCTAssertEqual(log.routineExerciseID, fixture.target.id)
        XCTAssertTrue(log.isCompleted)

        let stored: [WorkoutSetLog] = try context.fetch(FetchDescriptor<WorkoutSetLog>())
        XCTAssertEqual(stored.filter { $0.id == logID }.count, 1)
        XCTAssertEqual(stored.first?.exercise?.id, fixture.previousExercise.id)
    }
}

// MARK: - Reordenación de ejercicios

/// Pruebas del modo reordenación: el borrador decide cuántas posiciones cambia
/// un arrastre —la vista emite una señal háptica por cada una— y ningún
/// arrastre escribe en SwiftData: la rutina solo renumera `sortOrder` al
/// confirmar con «HECHO». Ni identidades, ni configuración, ni historial
/// cambian.
@MainActor
final class RoutineExerciseReorderTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var routine: Routine!
    private var links: [RoutineExercise]!
    private var catalog: [Exercise]!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let schema: Schema = Schema(versionedSchema: AppSchemaV6.self)
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)

        catalog = [
            Exercise(name: "Press banca", muscleGroup: .chest, equipmentType: .olympicBar),
            Exercise(name: "Press inclinado", muscleGroup: .chest, equipmentType: .dumbbell),
            Exercise(name: "Aperturas", muscleGroup: .chest, equipmentType: .cable),
            Exercise(name: "Cruces en polea", muscleGroup: .chest, equipmentType: .cable)
        ]
        for exercise in catalog {
            context.insert(exercise)
        }

        links = [
            RoutineExercise(
                exercise: catalog[0],
                defaultSets: 5,
                targetRepsMin: 5,
                targetRepsMax: 7,
                sortOrder: 0,
                defaultWeight: 82.5,
                restSeconds: 150,
                notes: "Codos a 45 grados",
                hasCustomRest: true
            ),
            RoutineExercise(
                exercise: catalog[1],
                defaultSets: 4,
                targetRepsMin: 8,
                targetRepsMax: 10,
                sortOrder: 1,
                defaultWeight: 30.0,
                restSeconds: 120,
                notes: "Banco a 30 grados",
                hasCustomRest: true
            ),
            RoutineExercise(
                exercise: catalog[2],
                defaultSets: 3,
                targetRepsMin: 12,
                targetRepsMax: 15,
                sortOrder: 2,
                defaultWeight: 15.0,
                restSeconds: 60,
                notes: "Polea alta",
                hasCustomRest: false
            ),
            RoutineExercise(
                exercise: catalog[3],
                defaultSets: 3,
                targetRepsMin: 12,
                targetRepsMax: 15,
                sortOrder: 3,
                defaultWeight: 10.0,
                restSeconds: 45,
                notes: "Cruce bajo",
                hasCustomRest: true
            )
        ]
        for link in links {
            context.insert(link)
        }

        routine = Routine(name: "PUSH", sortOrder: 0, exercises: links)
        context.insert(routine)
        try context.save()
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        routine = nil
        links = nil
        catalog = nil
        try super.tearDownWithError()
    }

    // MARK: Utilidades

    private func beginDraft() -> RoutineExerciseOrderDraft {
        var draft = RoutineExerciseOrderDraft()
        draft.begin(with: routine.exercises)
        return draft
    }

    private func names() -> [String] {
        routine.orderedExercises.map { $0.exercise?.name ?? "SIN EJERCICIO" }
    }

    private func ids() -> [UUID] {
        routine.orderedExercises.map(\.id)
    }

    // MARK: Modo

    func testEnteringAndLeavingTheModeDoesNotTouchTheRoutine() {
        var draft = RoutineExerciseOrderDraft()
        XCTAssertFalse(draft.isActive)

        XCTAssertTrue(draft.begin(with: routine.exercises))
        XCTAssertTrue(draft.isActive)
        XCTAssertEqual(draft.orderedIDs, ids())
        XCTAssertEqual(names(), ["Press banca", "Press inclinado", "Aperturas", "Cruces en polea"])

        draft.finish()
        XCTAssertFalse(draft.isActive)
        XCTAssertTrue(draft.orderedIDs.isEmpty)
        XCTAssertEqual(routine.exercises.map(\.sortOrder).sorted(), [0, 1, 2, 3])
    }

    func testTheModeCannotStartWithoutExercises() {
        var draft = RoutineExerciseOrderDraft()

        XCTAssertFalse(draft.begin(with: []))
        XCTAssertFalse(draft.isActive)
        XCTAssertTrue(draft.orderedIDs.isEmpty)
    }

    // MARK: Arrastre

    func testMovingOnePositionUpKeepsEveryOtherRowInPlace() {
        var draft = beginDraft()

        XCTAssertEqual(draft.move(from: 2, to: 1), 1)
        XCTAssertEqual(draft.orderedIDs, [links[0].id, links[2].id, links[1].id, links[3].id])

        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))
        XCTAssertEqual(names(), ["Press banca", "Aperturas", "Press inclinado", "Cruces en polea"])
        XCTAssertEqual(routine.exercises.map(\.sortOrder).sorted(), [0, 1, 2, 3])
    }

    func testMovingOnePositionDownKeepsEveryOtherRowInPlace() {
        var draft = beginDraft()

        XCTAssertEqual(draft.move(from: 0, to: 1), 1)
        XCTAssertEqual(draft.orderedIDs, [links[1].id, links[0].id, links[2].id, links[3].id])

        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))
        XCTAssertEqual(names(), ["Press inclinado", "Press banca", "Aperturas", "Cruces en polea"])
    }

    func testMovingSeveralPositionsReportsEveryCrossedPosition() {
        var draft = beginDraft()

        // De la última a la primera: tres posiciones, tres señales.
        XCTAssertEqual(draft.move(from: 3, to: 0), 3)
        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))
        XCTAssertEqual(names(), ["Cruces en polea", "Press banca", "Press inclinado", "Aperturas"])
        XCTAssertEqual(ids(), [links[3].id, links[0].id, links[1].id, links[2].id])
    }

    func testMovingTheFirstExerciseToTheEnd() {
        var draft = beginDraft()

        XCTAssertEqual(draft.move(from: 0, to: 3), 3)
        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))
        XCTAssertEqual(names(), ["Press inclinado", "Aperturas", "Cruces en polea", "Press banca"])
    }

    func testMovingToTheSamePositionChangesNothingAndDoesNotSignal() {
        var draft = beginDraft()
        let before: [Int] = routine.exercises.map(\.sortOrder)

        XCTAssertEqual(draft.move(from: 1, to: 1), 0)
        XCTAssertEqual(draft.orderedIDs, ids())

        // Sin cambio de posición no hay nada que aplicar ni que señalar.
        XCTAssertFalse(routine.applyExerciseOrder(draft.orderedIDs))
        XCTAssertEqual(routine.exercises.map(\.sortOrder), before)
    }

    func testDragTranslationMapsToAPositionOnlyWhenTheRowActuallyMoves() {
        let stride: CGFloat = RoutineReorderRowMetrics.rowStride

        // Umbral real: media separación efectiva (26 pt), no media altura.
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(startIndex: 2, translation: 25.9, rowStride: stride, count: 4),
            2
        )
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(startIndex: 2, translation: 26.0, rowStride: stride, count: 4),
            3
        )
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(startIndex: 2, translation: -25.9, rowStride: stride, count: 4),
            2
        )
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(startIndex: 2, translation: -26.0, rowStride: stride, count: 4),
            1
        )

        // Una separación completa entre filas (52 pt) equivale a una posición.
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(startIndex: 0, translation: 52.0, rowStride: stride, count: 4),
            1
        )
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(startIndex: 0, translation: 104.0, rowStride: stride, count: 4),
            2
        )

        // Tres filas de golpe: tres cambios efectivos, uno por señal.
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(startIndex: 3, translation: -156.0, rowStride: stride, count: 4),
            0
        )

        // Fuera de la lista se queda en el borde.
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(startIndex: 3, translation: 500.0, rowStride: stride, count: 4),
            3
        )
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(startIndex: 0, translation: -500.0, rowStride: stride, count: 4),
            0
        )
    }

    func testRowMetricsMatchTheCompactListSeparation() {
        // La vista usa estas mismas métricas: fila de 46 pt + 6 pt de separación.
        XCTAssertEqual(RoutineReorderRowMetrics.rowHeight, 46.0)
        XCTAssertEqual(RoutineReorderRowMetrics.rowSpacing, 6.0)
        XCTAssertEqual(RoutineReorderRowMetrics.rowStride, 52.0)
        XCTAssertEqual(RoutineReorderRowMetrics.moveThreshold, 26.0)

        // Con la métrica antigua (solo 46 pt) el umbral habría sido 23 pt: 24 pt
        // no deben mover la fila porque aún no ha llegado al punto medio real.
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(
                startIndex: 1,
                translation: 24.0,
                rowStride: RoutineReorderRowMetrics.rowStride,
                count: 4
            ),
            1
        )
    }

    // MARK: Borrador frente a SwiftData

    func testADragChangesOnlyTheDraft() {
        let storedOrder: [Int] = routine.exercises.map(\.sortOrder)
        var draft = beginDraft()

        XCTAssertEqual(draft.move(from: 3, to: 0), 3)

        // El arrastre solo ha movido el borrador...
        XCTAssertEqual(draft.orderedIDs, [links[3].id, links[0].id, links[1].id, links[2].id])
        // ...y la rutina guardada sigue exactamente igual.
        XCTAssertEqual(routine.exercises.map(\.sortOrder), storedOrder)
        XCTAssertEqual(names(), ["Press banca", "Press inclinado", "Aperturas", "Cruces en polea"])
        XCTAssertEqual(ids(), [links[0].id, links[1].id, links[2].id, links[3].id])
    }

    func testTwoDragsAccumulateInTheDraft() {
        let storedOrder: [Int] = routine.exercises.map(\.sortOrder)
        var draft = beginDraft()

        // Primer arrastre: la última fila al principio.
        XCTAssertEqual(draft.move(from: 3, to: 0), 3)
        // Segundo arrastre sobre esa misma fila, que ahora ocupa la posición 0.
        XCTAssertEqual(draft.move(from: 0, to: 2), 2)

        XCTAssertEqual(draft.orderedIDs, [links[0].id, links[1].id, links[3].id, links[2].id])
        XCTAssertEqual(routine.exercises.map(\.sortOrder), storedOrder)
    }

    func testCancellingADragRestoresOnlyItsProvisionalMove() {
        var draft = beginDraft()

        // Primer arrastre completado: se queda en el borrador.
        XCTAssertEqual(draft.move(from: 3, to: 0), 3)
        let afterFirstDrag: [UUID] = draft.orderedIDs

        // Segundo arrastre, cancelado por el sistema.
        XCTAssertEqual(draft.move(from: 0, to: 2), 2)
        XCTAssertEqual(draft.orderedIDs, [links[0].id, links[1].id, links[3].id, links[2].id])

        XCTAssertTrue(draft.restore(links[3].id, to: 0))
        XCTAssertEqual(draft.orderedIDs, afterFirstDrag)

        // Cancelar otra vez no deshace el primer arrastre.
        XCTAssertFalse(draft.restore(links[3].id, to: 0))
        XCTAssertEqual(draft.orderedIDs, afterFirstDrag)
        XCTAssertEqual(routine.exercises.map(\.sortOrder).sorted(), [0, 1, 2, 3])
    }

    func testConfirmingTheModeAppliesTheWholeDraft() {
        var draft = beginDraft()
        XCTAssertEqual(draft.move(from: 3, to: 0), 3)
        XCTAssertEqual(draft.move(from: 0, to: 2), 2)

        // «HECHO»: valida el borrador y aplica el orden completo de una vez.
        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))
        XCTAssertEqual(ids(), draft.orderedIDs)
        XCTAssertEqual(routine.orderedExercises.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(names(), ["Press banca", "Press inclinado", "Cruces en polea", "Aperturas"])

        // Aplicar de nuevo no cambia nada: el orden ya está puesto.
        XCTAssertFalse(routine.applyExerciseOrder(draft.orderedIDs))

        draft.finish()
        XCTAssertFalse(draft.isActive)
    }

    func testLeavingTheModeUnconfirmedKeepsTheStoredOrder() throws {
        var draft = beginDraft()
        XCTAssertEqual(draft.move(from: 3, to: 1), 2)

        // Abandonar sin «HECHO»: el borrador se descarta y no hay escritura.
        draft.finish()
        XCTAssertTrue(draft.orderedIDs.isEmpty)
        XCTAssertEqual(names(), ["Press banca", "Press inclinado", "Aperturas", "Cruces en polea"])

        // Ni un guardado posterior arrastra el orden descartado.
        try context.save()
        let reloadedContext = ModelContext(container)
        let storedRoutines: [Routine] = try reloadedContext.fetch(FetchDescriptor<Routine>())
        let storedRoutine: Routine = try XCTUnwrap(storedRoutines.first)

        XCTAssertEqual(
            storedRoutine.orderedExercises.compactMap { $0.exercise?.name },
            ["Press banca", "Press inclinado", "Aperturas", "Cruces en polea"]
        )
        XCTAssertEqual(storedRoutine.orderedExercises.map(\.sortOrder), [0, 1, 2, 3])
    }

    // MARK: Integridad

    func testReorderingKeepsTheIdentityOfEveryRoutineExercise() throws {
        let identities: [UUID] = links.map(\.id)
        var draft = beginDraft()

        XCTAssertEqual(draft.move(from: 3, to: 0), 3)
        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))
        try context.save()

        XCTAssertEqual(routine.exercises.count, 4)
        XCTAssertEqual(Set(ids()), Set(identities))

        let stored: [RoutineExercise] = try context.fetch(FetchDescriptor<RoutineExercise>())
        XCTAssertEqual(stored.count, 4)
        XCTAssertEqual(Set(stored.map(\.id)), Set(identities))
    }

    func testReorderingKeepsTheConfigurationOfEachRow() {
        var draft = beginDraft()

        XCTAssertEqual(draft.move(from: 0, to: 3), 3)
        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))

        let bench: RoutineExercise? = routine.orderedExercises.first { $0.id == links[0].id }
        XCTAssertEqual(bench?.defaultSets, 5)
        XCTAssertEqual(bench?.targetRepsMin, 5)
        XCTAssertEqual(bench?.targetRepsMax, 7)
        XCTAssertEqual(bench?.defaultWeight ?? 0.0, 82.5, accuracy: 0.0001)
        XCTAssertEqual(bench?.restSeconds, 150)
        XCTAssertEqual(bench?.hasCustomRest, true)
        XCTAssertEqual(bench?.notes, "Codos a 45 grados")
        XCTAssertEqual(bench?.sortOrder, 3)

        let cruces: RoutineExercise? = routine.orderedExercises.first { $0.id == links[3].id }
        XCTAssertEqual(cruces?.defaultSets, 3)
        XCTAssertEqual(cruces?.targetRepsMin, 12)
        XCTAssertEqual(cruces?.targetRepsMax, 15)
        XCTAssertEqual(cruces?.defaultWeight ?? 0.0, 10.0, accuracy: 0.0001)
        XCTAssertEqual(cruces?.restSeconds, 45)
        XCTAssertEqual(cruces?.hasCustomRest, true)
        XCTAssertEqual(cruces?.notes, "Cruce bajo")
        XCTAssertEqual(cruces?.sortOrder, 0)

        // La fila intermedia mantiene su propio descanso manual a `false`.
        let aperturas: RoutineExercise? = routine.orderedExercises.first { $0.id == links[2].id }
        XCTAssertEqual(aperturas?.hasCustomRest, false)
        XCTAssertEqual(aperturas?.restSeconds, 60)
    }

    func testReorderingKeepsTheExerciseRelationshipOfEachRow() {
        var draft = beginDraft()

        XCTAssertEqual(draft.move(from: 1, to: 2), 1)
        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))

        let ordered: [RoutineExercise] = routine.orderedExercises
        XCTAssertEqual(ordered.map { $0.exercise?.id }, [catalog[0].id, catalog[2].id, catalog[1].id, catalog[3].id])
        XCTAssertEqual(
            ordered.compactMap { $0.exercise?.name },
            ["Press banca", "Aperturas", "Press inclinado", "Cruces en polea"]
        )
        XCTAssertEqual(catalog.count, 4)
    }

    func testReorderingSurvivesSaveAndReload() throws {
        var draft = beginDraft()

        XCTAssertEqual(draft.move(from: 3, to: 1), 2)
        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))
        try context.save()

        let reloadedContext = ModelContext(container)
        let storedRoutines: [Routine] = try reloadedContext.fetch(FetchDescriptor<Routine>())
        let storedRoutine: Routine = try XCTUnwrap(storedRoutines.first)

        XCTAssertEqual(
            storedRoutine.orderedExercises.compactMap { $0.exercise?.name },
            ["Press banca", "Cruces en polea", "Press inclinado", "Aperturas"]
        )
        XCTAssertEqual(storedRoutine.orderedExercises.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(Set(storedRoutine.orderedExercises.map(\.id)), Set(links.map(\.id)))
    }

    func testReorderingDoesNotTouchTrainingHistory() throws {
        let session = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            routineName: "PUSH"
        )
        context.insert(session)

        let log = WorkoutSetLog(
            date: Date(timeIntervalSince1970: 1_700_000_100),
            weight: 80.0,
            reps: 6,
            targetRepsMin: 5,
            targetRepsMax: 7,
            isCompleted: true,
            routineExerciseID: links[0].id,
            setNumber: 1,
            exercise: catalog[0],
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]
        try context.save()

        var draft = beginDraft()
        XCTAssertEqual(draft.move(from: 3, to: 0), 3)
        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))
        try context.save()

        XCTAssertEqual(session.setsCompleted.count, 1)
        XCTAssertEqual(session.setsCompleted.first?.id, log.id)
        XCTAssertEqual(log.routineExerciseID, links[0].id)
        XCTAssertEqual(log.exercise?.id, catalog[0].id)
        XCTAssertEqual(log.reps, 6)
        XCTAssertEqual(log.weight, 80.0, accuracy: 0.0001)
        XCTAssertEqual(log.setNumber, 1)
        XCTAssertTrue(log.isCompleted)

        let storedLogs: [WorkoutSetLog] = try context.fetch(FetchDescriptor<WorkoutSetLog>())
        XCTAssertEqual(storedLogs.count, 1)
    }

    func testAnOrderThatDoesNotMatchTheRoutineIsNotApplied() {
        let before: [Int] = routine.exercises.map(\.sortOrder)
        var draft = beginDraft()
        XCTAssertEqual(draft.move(from: 3, to: 0), 3)

        // Falta un ejercicio: el orden no se escribe a medias.
        XCTAssertFalse(routine.applyExerciseOrder(Array(draft.orderedIDs.dropLast())))

        // Sobra un identificador que no pertenece a la rutina.
        XCTAssertFalse(routine.applyExerciseOrder(draft.orderedIDs + [UUID()]))

        XCTAssertEqual(routine.exercises.map(\.sortOrder), before)
        XCTAssertEqual(names(), ["Press banca", "Press inclinado", "Aperturas", "Cruces en polea"])
    }

    // MARK: Arrastre medido en un sistema de coordenadas estable

    /// Simula un arrastre fotograma a fotograma tal y como lo hace la vista: el
    /// dedo informa de su desplazamiento **total**, medido en el contenedor, y
    /// el destino se recalcula siempre desde la posición inicial.
    private func simulateDrag(
        from startIndex: Int,
        id: UUID,
        translations: [CGFloat],
        draft: inout RoutineExerciseOrderDraft
    ) -> RoutineReorderDrag {
        var drag = RoutineReorderDrag(id: id, startIndex: startIndex)
        for translation in translations {
            let destination: Int = drag.destinationIndex(
                translation: translation,
                count: draft.orderedIDs.count
            )
            draft.move(from: drag.currentIndex, to: destination)
            drag.apply(translation: translation, destination: destination)
        }
        return drag
    }

    func testTheDragDestinationOnlyDependsOnTheStartingPositionAndTheFinger() {
        var draft = beginDraft()
        let drag = simulateDrag(
            from: 0,
            id: links[0].id,
            translations: [10.0, 30.0, 55.0, 80.0],
            draft: &draft
        )

        // 80 pt = una separación completa (52 pt) más 28 pt de la siguiente.
        XCTAssertEqual(drag.startIndex, 0)
        XCTAssertEqual(drag.currentIndex, 2)
        XCTAssertEqual(drag.translation, 80.0)

        // Repetir el mismo fotograma no acumula nada: el destino coincide con
        // el que sale de la posición inicial y el desplazamiento total.
        XCTAssertEqual(drag.destinationIndex(translation: 80.0, count: 4), 2)
        XCTAssertEqual(
            RoutineExerciseOrderDraft.destinationIndex(
                startIndex: 0,
                translation: 80.0,
                rowStride: RoutineReorderRowMetrics.rowStride,
                count: 4
            ),
            2
        )

        // Volver a la altura de partida devuelve la fila a su sitio.
        XCTAssertEqual(drag.destinationIndex(translation: 0.0, count: 4), 0)
    }

    func testCrossingSeveralPositionsProducesTheExpectedDraftOrder() {
        var draft = beginDraft()
        let translations: [CGFloat] = (1...16).map { CGFloat($0) * -10.0 }
        let drag = simulateDrag(
            from: 3,
            id: links[3].id,
            translations: translations,
            draft: &draft
        )

        XCTAssertEqual(drag.currentIndex, 0)
        XCTAssertEqual(draft.orderedIDs, [links[3].id, links[0].id, links[1].id, links[2].id])

        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))
        XCTAssertEqual(names(), ["Cruces en polea", "Press banca", "Press inclinado", "Aperturas"])
    }

    func testTheResidualOffsetKeepsTheRowUnderTheFingerWithinHalfARowStride() {
        var draft = beginDraft()
        var drag = RoutineReorderDrag(id: links[0].id, startIndex: 0)

        for step in 0...30 {
            let translation: CGFloat = CGFloat(step) * 5.0
            let destination: Int = drag.destinationIndex(
                translation: translation,
                count: draft.orderedIDs.count
            )
            draft.move(from: drag.currentIndex, to: destination)
            drag.apply(translation: translation, destination: destination)

            // Coherente con la separación efectiva de 52 pt...
            XCTAssertEqual(
                drag.visualOffset,
                translation - CGFloat(destination - drag.startIndex) * RoutineReorderRowMetrics.rowStride,
                accuracy: 0.0001
            )
            // ...y nunca superior a media separación (el umbral de 26 pt).
            XCTAssertLessThanOrEqual(
                abs(drag.visualOffset),
                RoutineReorderRowMetrics.moveThreshold + 0.0001
            )
        }
    }

    func testTheDraggedRowKeepsItsIdentityForTheWholeGesture() {
        let identities: Set<UUID> = Set(links.map(\.id))
        var draft = beginDraft()
        var drag = RoutineReorderDrag(id: links[1].id, startIndex: 1)

        for step in 1...12 {
            let translation: CGFloat = CGFloat(step) * -10.0
            let destination: Int = drag.destinationIndex(
                translation: translation,
                count: draft.orderedIDs.count
            )
            draft.move(from: drag.currentIndex, to: destination)
            drag.apply(translation: translation, destination: destination)

            // Ninguna fila cambia de identidad ni desaparece al reordenar.
            XCTAssertEqual(draft.orderedIDs.count, identities.count)
            XCTAssertEqual(Set(draft.orderedIDs), identities)
            // La fila agarrada sigue estando en la posición que declara el arrastre.
            XCTAssertEqual(draft.orderedIDs[drag.currentIndex], links[1].id)
            XCTAssertEqual(drag.id, links[1].id)
        }

        XCTAssertEqual(draft.orderedIDs, [links[1].id, links[0].id, links[2].id, links[3].id])
    }

    func testCancellingTheGestureRestoresTheStartingPositionOnly() {
        let storedOrder: [Int] = routine.exercises.map(\.sortOrder)
        let storedIDs: [UUID] = ids()
        var draft = beginDraft()
        let drag = simulateDrag(
            from: 3,
            id: links[3].id,
            translations: [CGFloat(-20), CGFloat(-60), CGFloat(-120), CGFloat(-160)],
            draft: &draft
        )

        XCTAssertEqual(drag.currentIndex, 0)
        XCTAssertNotEqual(draft.orderedIDs, storedIDs)

        // Cancelación: la fila vuelve a la posición donde se agarró...
        XCTAssertTrue(draft.restore(drag.id, to: drag.startIndex))
        XCTAssertEqual(draft.orderedIDs, storedIDs)

        // ...y la rutina nunca se ha tocado mientras el gesto estaba activo.
        XCTAssertEqual(routine.exercises.map(\.sortOrder), storedOrder)
        XCTAssertEqual(ids(), storedIDs)
    }

    func testConfirmingAfterTheDragAppliesExactlyTheDraggedOrder() {
        var draft = beginDraft()
        let drag = simulateDrag(
            from: 0,
            id: links[0].id,
            translations: [CGFloat(12), CGFloat(70), CGFloat(110)],
            draft: &draft
        )

        XCTAssertEqual(drag.currentIndex, 2)
        XCTAssertTrue(routine.applyExerciseOrder(draft.orderedIDs))
        XCTAssertEqual(ids(), [links[1].id, links[2].id, links[0].id, links[3].id])
        XCTAssertEqual(routine.orderedExercises.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(names(), ["Press inclinado", "Aperturas", "Press banca", "Cruces en polea"])
    }

    // MARK: - Fase 04.1: cualquier fila, toque inofensivo, cancelar y confirmar

    /// Arranca la interacción como lo hace la vista: pulsación larga reconocida,
    /// un movimiento por debajo del umbral y el primer desplazamiento real.
    /// Devuelve el arrastre creado y aplica ese primer fotograma al borrador.
    private func gestureFirstFrame(
        id: UUID,
        translation: CGFloat,
        draft: inout RoutineExerciseOrderDraft,
        gesture: inout RoutineReorderGestureState
    ) -> RoutineReorderDrag? {
        XCTAssertEqual(gesture.longPressRecognized(id), .holding(id: id))
        XCTAssertEqual(
            gesture.moved(id, translation: RoutineReorderGestureState.startDistance - 0.1),
            .ignored
        )

        guard case .began(let draggedID, let started) = gesture.moved(id, translation: translation),
              draggedID == id,
              let startIndex = draft.index(of: id) else {
            return nil
        }

        var drag = RoutineReorderDrag(id: id, startIndex: startIndex)
        let destination: Int = drag.destinationIndex(
            translation: started,
            count: draft.orderedIDs.count
        )
        draft.move(from: drag.currentIndex, to: destination)
        drag.apply(translation: started, destination: destination)
        return drag
    }

    /// Comprueba el contrato completo de un arrastre iniciado en cualquier fila:
    /// todas siguen presentes, la agarrada conserva su identidad y el borrador
    /// se puede resolver contra la rutina sin ocultar ninguna fila.
    private func assertDragFromPosition(
        _ startIndex: Int,
        translation: CGFloat,
        expectedIndex: Int
    ) {
        var draft = beginDraft()
        var gesture = RoutineReorderGestureState()
        let identities: Set<UUID> = Set(links.map(\.id))
        let dragged: RoutineExercise = links[startIndex]

        guard let drag = gestureFirstFrame(
            id: dragged.id,
            translation: translation,
            draft: &draft,
            gesture: &gesture
        ) else {
            return XCTFail("El arrastre debe empezar desde la posición \(startIndex)")
        }

        XCTAssertEqual(drag.id, dragged.id)
        XCTAssertEqual(drag.startIndex, startIndex)
        XCTAssertEqual(drag.currentIndex, expectedIndex)
        XCTAssertTrue(gesture.isDragging)

        // Ninguna fila desaparece ni cambia de identidad.
        XCTAssertEqual(draft.orderedIDs.count, identities.count)
        XCTAssertEqual(Set(draft.orderedIDs), identities)
        XCTAssertEqual(draft.orderedIDs[expectedIndex], dragged.id)

        // El borrador se resuelve completo contra la rutina, sin huecos.
        XCTAssertEqual(draft.resolve(against: routine.exercises), .ordered(draft.orderedIDs))

        // La rutina sigue intacta: el arrastre solo ha tocado el borrador.
        XCTAssertEqual(ids(), links.map(\.id))
        XCTAssertEqual(routine.orderedExercises.map(\.sortOrder), [0, 1, 2, 3])
    }

    // MARK: A. Inicio del arrastre desde cualquier posición

    func testStartingADragFromTheFirstPositionKeepsEveryExerciseResolvable() {
        assertDragFromPosition(0, translation: 52.0, expectedIndex: 1)
    }

    func testStartingADragFromTheSecondPositionKeepsEveryExerciseResolvable() {
        assertDragFromPosition(1, translation: 52.0, expectedIndex: 2)
    }

    func testStartingADragFromTheThirdPositionKeepsEveryExerciseResolvable() {
        assertDragFromPosition(2, translation: -52.0, expectedIndex: 1)
    }

    func testStartingADragFromTheLastPositionKeepsEveryExerciseResolvable() {
        assertDragFromPosition(3, translation: -52.0, expectedIndex: 2)
    }

    // MARK: B. Toque rápido sin arrastre

    func testAQuickTapDoesNotStartADragNorChangeTheDraft() {
        var draft = beginDraft()
        var gesture = RoutineReorderGestureState()
        let before: [UUID] = draft.orderedIDs
        let storedOrder: [Int] = routine.orderedExercises.map(\.sortOrder)

        XCTAssertEqual(gesture.longPressRecognized(links[2].id), .holding(id: links[2].id))
        // Por debajo del umbral no hay arrastre: el estado sigue en `holding`.
        XCTAssertEqual(gesture.moved(links[2].id, translation: 2.9), .ignored)
        XCTAssertFalse(gesture.isDragging)

        // El dedo se levanta sin haberse movido: vuelve a reposo sin efecto.
        XCTAssertEqual(gesture.ended(links[2].id, translation: 2.9), .ignored)
        XCTAssertEqual(gesture, RoutineReorderGestureState())

        XCTAssertEqual(draft.orderedIDs, before)
        XCTAssertTrue(draft.isActive)
        XCTAssertEqual(routine.orderedExercises.map(\.sortOrder), storedOrder)

        // Un evento suelto de otra fila en reposo tampoco arranca nada.
        XCTAssertEqual(gesture.moved(links[0].id, translation: 40.0), .ignored)
        XCTAssertFalse(gesture.isDragging)
        XCTAssertEqual(draft.orderedIDs, before)
    }

    func testTheGestureSequenceCanRepeatAndALaterDragStillWorks() {
        var draft = beginDraft()
        var gesture = RoutineReorderGestureState()
        let before: [UUID] = draft.orderedIDs

        // Toque sin movimiento.
        XCTAssertEqual(gesture.longPressRecognized(links[1].id), .holding(id: links[1].id))
        XCTAssertEqual(gesture.ended(links[1].id, translation: 0.0), .ignored)

        // Toque cancelado por el sistema antes de moverse.
        XCTAssertEqual(gesture.longPressRecognized(links[2].id), .holding(id: links[2].id))
        XCTAssertEqual(gesture.cancelled(links[2].id), .ignored)

        // Tercer intento: aviso repetido del mismo gesto (no vuelve a agarrar),
        // desplazamiento real y finalización exactamente una vez.
        XCTAssertEqual(gesture.longPressRecognized(links[3].id), .holding(id: links[3].id))
        XCTAssertEqual(gesture.longPressRecognized(links[3].id), .ignored)

        guard case .began(let id, let started) = gesture.moved(links[3].id, translation: -31.0) else {
            return XCTFail("El arrastre posterior debe empezar tras el desplazamiento real")
        }
        XCTAssertEqual(id, links[3].id)
        XCTAssertEqual(started, -31.0)
        XCTAssertTrue(gesture.isDragging)

        XCTAssertEqual(
            gesture.ended(links[3].id, translation: -52.0),
            .ended(id: links[3].id, translation: -52.0)
        )
        XCTAssertFalse(gesture.isDragging)
        XCTAssertEqual(gesture, RoutineReorderGestureState())

        // Ninguno de los toques ha tocado el borrador.
        XCTAssertEqual(draft.orderedIDs, before)
    }

    func testAStaleDragDoesNotBlockTheNextInteraction() {
        var gesture = RoutineReorderGestureState()

        XCTAssertEqual(gesture.longPressRecognized(links[0].id), .holding(id: links[0].id))
        XCTAssertEqual(
            gesture.moved(links[0].id, translation: 30.0),
            .began(id: links[0].id, translation: 30.0)
        )
        XCTAssertTrue(gesture.isDragging)

        // Gesto sin aviso de fin: una pulsación nueva toma el control y declara
        // el arrastre anterior como cancelado, para que la vista lo deshaga.
        XCTAssertEqual(
            gesture.longPressRecognized(links[2].id),
            .cancelled(id: links[0].id)
        )
        XCTAssertFalse(gesture.isDragging)
        XCTAssertEqual(gesture.activeID, links[2].id)

        // Repetir el aviso del gesto ya en curso no lo interrumpe.
        XCTAssertEqual(gesture.longPressRecognized(links[2].id), .ignored)

        // Y el arrastre de la fila nueva funciona con normalidad.
        guard case .began(let id, _) = gesture.moved(links[2].id, translation: 6.0) else {
            return XCTFail("La interacción nueva debe poder arrastrar")
        }
        XCTAssertEqual(id, links[2].id)
        XCTAssertTrue(gesture.isDragging)
    }

    // MARK: C. Cancelación completa de la sesión

    func testCancellingTheWholeSessionDiscardsEveryProvisionalMove() throws {
        var draft = beginDraft()
        let originalIDs: [UUID] = draft.orderedIDs
        let storedSortOrders: [Int] = routine.exercises.map(\.sortOrder).sorted()

        XCTAssertEqual(draft.move(from: 3, to: 0), 3)
        XCTAssertEqual(draft.move(from: 1, to: 3), 2)
        XCTAssertEqual(
            draft.orderedIDs,
            [links[3].id, links[1].id, links[2].id, links[0].id]
        )
        XCTAssertNotEqual(draft.orderedIDs, originalIDs)
        XCTAssertEqual(draft.originalIDs, originalIDs)

        // Mientras la sesión está abierta, la rutina no se ha tocado.
        XCTAssertEqual(ids(), originalIDs)
        XCTAssertEqual(routine.exercises.map(\.sortOrder).sorted(), storedSortOrders)

        // Cancelar la sesión completa devuelve el borrador a la instantánea
        // original y lo desactiva.
        draft.cancel()
        XCTAssertFalse(draft.isActive)
        XCTAssertEqual(draft.orderedIDs, originalIDs)
        XCTAssertTrue(draft.originalIDs.isEmpty)

        // Sin aplicar `sortOrder` ni perder ningún ejercicio.
        XCTAssertEqual(ids(), originalIDs)
        XCTAssertEqual(routine.exercises.map(\.sortOrder).sorted(), storedSortOrders)
        XCTAssertEqual(routine.exercises.count, 4)

        // Un guardado posterior y una recarga conservan el orden original.
        try context.save()
        let reloadedContext = ModelContext(container)
        let storedRoutine: Routine = try XCTUnwrap(
            try reloadedContext.fetch(FetchDescriptor<Routine>()).first
        )
        XCTAssertEqual(storedRoutine.orderedExercises.map(\.id), originalIDs)
        XCTAssertEqual(storedRoutine.orderedExercises.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(storedRoutine.exercises.count, 4)
    }

    // MARK: D. Confirmación con «HECHO»

    func testConfirmingTheSessionAppliesExactlyTheDraftOrder() throws {
        var draft = beginDraft()
        XCTAssertEqual(draft.move(from: 0, to: 2), 2)
        XCTAssertEqual(draft.move(from: 3, to: 1), 2)

        // «HECHO» valida el borrador contra la rutina antes de aplicar nada.
        XCTAssertEqual(draft.resolve(against: routine.exercises), .ordered(draft.orderedIDs))
        let confirmed: [UUID] = draft.orderedIDs

        XCTAssertTrue(routine.applyExerciseOrder(confirmed))
        draft.finish()
        XCTAssertFalse(draft.isActive)

        XCTAssertEqual(routine.orderedExercises.map(\.id), confirmed)
        XCTAssertEqual(routine.orderedExercises.map(\.sortOrder), [0, 1, 2, 3])

        try context.save()
        let reloadedContext = ModelContext(container)
        let storedRoutine: Routine = try XCTUnwrap(
            try reloadedContext.fetch(FetchDescriptor<Routine>()).first
        )

        XCTAssertEqual(storedRoutine.orderedExercises.map(\.id), confirmed)
        XCTAssertEqual(storedRoutine.orderedExercises.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(Set(storedRoutine.exercises.map(\.id)), Set(links.map(\.id)))

        // Las propiedades individuales de cada fila siguen intactas.
        let storedByID: [UUID: RoutineExercise] = Dictionary(
            uniqueKeysWithValues: storedRoutine.orderedExercises.map { ($0.id, $0) }
        )
        let bench: RoutineExercise = try XCTUnwrap(storedByID[links[0].id])
        XCTAssertEqual(bench.defaultSets, 5)
        XCTAssertEqual(bench.targetRepsMin, 5)
        XCTAssertEqual(bench.targetRepsMax, 7)
        XCTAssertEqual(bench.defaultWeight, 82.5, accuracy: 0.0001)
        XCTAssertEqual(bench.restSeconds, 150)
        XCTAssertTrue(bench.hasCustomRest)
        XCTAssertEqual(bench.notes, "Codos a 45 grados")
        XCTAssertEqual(bench.exercise?.name, "Press banca")

        let cruces: RoutineExercise = try XCTUnwrap(storedByID[links[3].id])
        XCTAssertEqual(cruces.defaultSets, 3)
        XCTAssertEqual(cruces.defaultWeight, 10.0, accuracy: 0.0001)
        XCTAssertEqual(cruces.restSeconds, 45)
        XCTAssertEqual(cruces.exercise?.name, "Cruces en polea")
    }

    // MARK: E. Borrador inconsistente

    func testAnIncompleteDraftIsNotResolvableNorApplied() {
        var draft = beginDraft()
        XCTAssertEqual(draft.move(from: 3, to: 0), 3)
        let before: [Int] = routine.exercises.map(\.sortOrder)
        let available: [UUID] = ids()
        let incomplete: [UUID] = Array(draft.orderedIDs.dropLast())

        XCTAssertEqual(
            RoutineExerciseOrderDraft.resolve(orderedIDs: incomplete, availableIDs: available),
            .inconsistent
        )
        XCTAssertFalse(routine.applyExerciseOrder(incomplete))

        XCTAssertEqual(routine.exercises.map(\.sortOrder), before)
        XCTAssertEqual(ids(), available)
    }

    func testADuplicatedDraftIsNotResolvableNorApplied() {
        let before: [Int] = routine.exercises.map(\.sortOrder)
        let duplicated: [UUID] = [links[0].id, links[0].id, links[2].id, links[3].id]

        XCTAssertEqual(
            RoutineExerciseOrderDraft.resolve(orderedIDs: duplicated, availableIDs: ids()),
            .inconsistent
        )
        XCTAssertFalse(routine.applyExerciseOrder(duplicated))

        XCTAssertEqual(routine.exercises.map(\.sortOrder), before)
        XCTAssertEqual(Set(ids()), Set(links.map(\.id)))
        XCTAssertEqual(routine.exercises.count, 4)
    }

    func testAForeignIdentifierIsNotResolvableNorApplied() {
        var draft = beginDraft()
        XCTAssertEqual(draft.move(from: 3, to: 0), 3)
        let before: [Int] = routine.exercises.map(\.sortOrder)
        let foreign: [UUID] = draft.orderedIDs + [UUID()]

        XCTAssertEqual(
            RoutineExerciseOrderDraft.resolve(orderedIDs: foreign, availableIDs: ids()),
            .inconsistent
        )
        XCTAssertFalse(routine.applyExerciseOrder(foreign))

        XCTAssertEqual(routine.exercises.map(\.sortOrder), before)
        XCTAssertEqual(routine.exercises.count, 4)
    }
}
