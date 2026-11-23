import XCTest
import Foundation
import SwiftData

@testable import AppGym

/// Pruebas de `.appgymsplit` (Prompt 09): exportación de una carpeta completa,
/// validación del archivo recibido, importación como carpeta nueva y sustitución
/// de la organización.
@MainActor
final class SplitShareImportTests: XCTestCase {

    // MARK: - Exportación

    func testExportedSplitContainsActiveRoutinesInOrder() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Empuje/Tirón/Pierna", context: context)
        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let pull: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: context)
        let legs: Routine = makeRoutine(named: "LEGS", sortOrder: 2, context: context)
        let archived: Routine = makeRoutine(named: "OLD", sortOrder: 3, archived: true, context: context)
        folder.routineIDs = [legs.id, push.id, pull.id, archived.id]
        try context.save()

        let payload: RoutineSplitPayload = try RoutineSplitShareService.payload(for: folder, routines: allRoutines(context))

        XCTAssertEqual(payload.format, "appgym.split")
        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(payload.name, "Empuje/Tirón/Pierna")
        XCTAssertEqual(payload.routines.map(\.name), ["PUSH", "PULL", "LEGS"])
    }

    func testExportedSplitKeepsExerciseConfiguration() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let routine: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        makeLink(
            in: routine,
            name: "Press banca",
            sets: 5,
            repsMin: 3,
            repsMax: 5,
            restSeconds: 240,
            weight: 92.5,
            notes: "Tempo 3-1-1",
            order: 0,
            context: context
        )
        folder.routineIDs = [routine.id]
        try context.save()

        let payload: RoutineSplitPayload = try RoutineSplitShareService.payload(for: folder, routines: allRoutines(context))
        let shared: RoutineShareExercise = try XCTUnwrap(payload.routines.first?.exercises.first)

        XCTAssertEqual(shared.name, "Press banca")
        XCTAssertEqual(shared.sets, 5)
        XCTAssertEqual(shared.repsMin, 3)
        XCTAssertEqual(shared.repsMax, 5)
        XCTAssertEqual(shared.restSeconds, 240)
        XCTAssertEqual(shared.targetWeight, 92.5)
        XCTAssertEqual(shared.notes, "Tempo 3-1-1")
    }

    func testExportedSplitOmitsHistory() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let routine: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let link: RoutineExercise = makeLink(in: routine, name: "Press banca", order: 0, context: context)

        let session: WorkoutSession = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalVolumeKg: 1_200.0,
            routineName: routine.name
        )
        context.insert(session)
        context.insert(WorkoutSetLog(weight: 60.0, reps: 8, isCompleted: true, routineExerciseID: link.id, exercise: link.exercise, session: session))
        folder.routineIDs = [routine.id]
        try context.save()

        let data: Data = try RoutineSplitShareService.encodedData(for: folder, routines: allRoutines(context))
        let raw: String = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(raw.contains("sessions"))
        XCTAssertFalse(raw.contains("setsCompleted"))
        XCTAssertFalse(raw.contains("totalVolumeKg"))
        XCTAssertFalse(raw.contains("startDate"))
    }

    func testExportDoesNotModifyFolderOrRoutines() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let routine: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        makeLink(in: routine, name: "Press banca", order: 0, context: context)
        folder.routineIDs = [routine.id]
        try context.save()

        let folderIDs: [UUID] = folder.routineIDs
        let routineID: UUID = routine.id
        let routineName: String = routine.name
        let linkIDs: [UUID] = routine.exercises.map(\.id)

        _ = try RoutineSplitShareService.makeFile(for: folder, routines: allRoutines(context))

        XCTAssertEqual(folder.routineIDs, folderIDs)
        XCTAssertEqual(routine.id, routineID)
        XCTAssertEqual(routine.name, routineName)
        XCTAssertEqual(routine.exercises.map(\.id), linkIDs)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 1)
    }

    func testExportRejectsFolderWithoutActiveRoutines() throws {
        let context: ModelContext = try makeContext()
        let empty: RoutineFolder = try makeFolder(named: "Vacía", context: context)
        let archivedOnly: RoutineFolder = try makeFolder(named: "Archivadas", context: context)
        let archived: Routine = makeRoutine(named: "OLD", sortOrder: 0, archived: true, context: context)
        archivedOnly.routineIDs = [archived.id]
        try context.save()

        XCTAssertThrowsError(try RoutineSplitShareService.payload(for: empty, routines: allRoutines(context))) { error in
            XCTAssertEqual(error as? RoutineSplitShareError, .emptySplit)
        }
        XCTAssertThrowsError(try RoutineSplitShareService.payload(for: archivedOnly, routines: allRoutines(context))) { error in
            XCTAssertEqual(error as? RoutineSplitShareError, .emptySplit)
        }
    }

    func testExportableFoldersSkipEmptyAndArchivedOnly() throws {
        let context: ModelContext = try makeContext()
        let active: RoutineFolder = try makeFolder(named: "Activa", context: context)
        _ = try makeFolder(named: "Vacía", context: context)
        let archivedOnly: RoutineFolder = try makeFolder(named: "Archivadas", context: context)
        let routine: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let archived: Routine = makeRoutine(named: "OLD", sortOrder: 1, archived: true, context: context)
        active.routineIDs = [routine.id]
        archivedOnly.routineIDs = [archived.id]
        try context.save()

        let folders: [RoutineFolder] = RoutineSplitShareService.exportableFolders(
            try context.fetch(FetchDescriptor<RoutineFolder>()),
            routines: allRoutines(context)
        )

        XCTAssertEqual(folders.map(\.name), ["Activa"])
    }

    func testSplitFileNameIsSafeAndUsesTheExpectedExtension() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Empuje / Tirón: ¿pierna?", context: context)

        let name: String = RoutineSplitShareService.fileName(
            for: folder,
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(name.hasPrefix("AppGym_Split_"))
        XCTAssertTrue(name.hasSuffix(".appgymsplit"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("¿"))
    }

    // MARK: - Validación

    func testValidSplitFileOpensAndValidates() throws {
        let context: ModelContext = try makeContext()
        let payload: RoutineSplitPayload = makePayload(routineNames: ["PUSH", "PULL"], context: context)
        let url: URL = try writeSplitFile(payload)
        defer { removeDirectory(of: url) }

        let request: SplitImportRequest = try SplitImportService.makeRequest(fromFileAt: url)

        XCTAssertEqual(request.splitName, "Split compartido")
        XCTAssertEqual(request.routineCount, 2)
        XCTAssertEqual(request.payload.routines.map(\.name), ["PUSH", "PULL"])
    }

    func testCorruptSplitJSONIsRejected() throws {
        let url: URL = try writeRaw("no es json", fileName: "Split.appgymsplit")
        defer { removeDirectory(of: url) }

        XCTAssertThrowsError(try SplitImportService.makeRequest(fromFileAt: url)) { error in
            XCTAssertEqual(error as? SplitImportError, .malformedJSON)
        }
    }

    func testWrongSplitFormatIsRejected() throws {
        let context: ModelContext = try makeContext()
        var payload: RoutineSplitPayload = makePayload(routineNames: ["PUSH"], context: context)
        payload.format = "appgym.routine"

        XCTAssertThrowsError(try SplitImportService.validate(payload)) { error in
            XCTAssertEqual(error as? SplitImportError, .invalidFormat)
        }
    }

    func testIncompatibleSplitVersionIsRejected() throws {
        let context: ModelContext = try makeContext()
        var payload: RoutineSplitPayload = makePayload(routineNames: ["PUSH"], context: context)
        payload.version = 7

        XCTAssertThrowsError(try SplitImportService.validate(payload)) { error in
            XCTAssertEqual(error as? SplitImportError, .unsupportedVersion(7))
        }
    }

    func testEmptySplitIsRejected() throws {
        let context: ModelContext = try makeContext()
        var payload: RoutineSplitPayload = makePayload(routineNames: ["PUSH"], context: context)
        payload.routines = []

        XCTAssertThrowsError(try SplitImportService.validate(payload)) { error in
            XCTAssertEqual(error as? SplitImportError, .missingRoutines)
        }
    }

    func testTooManyRoutinesAreRejected() throws {
        let context: ModelContext = try makeContext()
        let payload: RoutineSplitPayload = makePayload(
            routineNames: (0..<31).map { "Rutina \($0)" },
            context: context
        )

        XCTAssertThrowsError(try SplitImportService.validate(payload)) { error in
            XCTAssertEqual(error as? SplitImportError, .tooManyRoutines)
        }
    }

    func testDuplicateRoutineIdentifiersAreRejected() throws {
        let context: ModelContext = try makeContext()
        var payload: RoutineSplitPayload = makePayload(routineNames: ["PUSH", "PULL"], context: context)
        payload.routines[1].id = payload.routines[0].id

        XCTAssertThrowsError(try SplitImportService.validate(payload)) { error in
            XCTAssertEqual(error as? SplitImportError, .duplicateRoutineIdentifiers)
        }
    }

    func testOneInvalidRoutineBlocksTheWholeSplit() throws {
        let context: ModelContext = try makeContext()
        var payload: RoutineSplitPayload = makePayload(routineNames: ["PUSH", "PULL"], context: context)
        payload.routines[1].exercises[0].sets = 0
        payload.routines[1].exercises[0].sortOrder = 0

        XCTAssertThrowsError(try SplitImportService.validate(payload)) { error in
            XCTAssertEqual(
                error as? SplitImportError,
                .invalidRoutine(index: 2, reason: .invalidExerciseSets(index: 1))
            )
        }

        let request: SplitImportRequest = SplitImportRequest(payload: payload)
        XCTAssertThrowsError(
            try SplitImportService.importSplit(request, mode: .newFolder(name: "Split"), into: context)
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 0)
    }

    func testOversizedSplitIsRejected() {
        let data: Data = Data(count: SplitImportService.maxFileSize + 1)

        XCTAssertThrowsError(try SplitImportService.decode(data: data)) { error in
            XCTAssertEqual(error as? SplitImportError, .fileTooLarge)
        }
    }

    // MARK: - Crear carpeta

    func testCreatingFolderUsesDefaultName() throws {
        let context: ModelContext = try makeContext()
        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH", "PULL"], context: context)

        let result: SplitImportResult = try SplitImportService.importSplit(
            request,
            mode: .newFolder(name: SplitImportService.defaultFolderName),
            into: context
        )

        XCTAssertEqual(result.folderName, "Split compartido")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 1)
    }

    func testCreatingFolderHonoursCustomName() throws {
        let context: ModelContext = try makeContext()
        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH"], context: context)

        let result: SplitImportResult = try SplitImportService.importSplit(
            request,
            mode: .newFolder(name: "  Mi split  "),
            into: context
        )

        XCTAssertEqual(result.folderName, "Mi split")
        XCTAssertEqual(try context.fetch(FetchDescriptor<RoutineFolder>()).first?.name, "Mi split")
    }

    func testFolderNameCollisionAddsSuffix() throws {
        let context: ModelContext = try makeContext()
        _ = try makeFolder(named: "Split compartido", context: context)
        _ = try makeFolder(named: "Split compartido 2", context: context)

        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH"], context: context)
        let result: SplitImportResult = try SplitImportService.importSplit(
            request,
            mode: .newFolder(name: "split COMPARTIDO"),
            into: context
        )

        XCTAssertEqual(result.folderName, "split COMPARTIDO 3")
    }

    func testRoutineNameCollisionsAreSuffixed() throws {
        let context: ModelContext = try makeContext()
        _ = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        try context.save()

        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH", "PUSH"], context: context)
        let result: SplitImportResult = try SplitImportService.importSplit(
            request,
            mode: .newFolder(name: "Split"),
            into: context
        )

        let imported: [Routine] = try context.fetch(FetchDescriptor<Routine>())
            .filter { result.routineIDs.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }

        XCTAssertEqual(imported.map(\.name), ["PUSH (2)", "PUSH (3)"])
    }

    func testAllImportedRoutinesAreInsideTheNewFolder() throws {
        let context: ModelContext = try makeContext()
        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH", "PULL", "LEGS"], context: context)

        let result: SplitImportResult = try SplitImportService.importSplit(
            request,
            mode: .newFolder(name: "Split"),
            into: context
        )

        let folder: RoutineFolder = try XCTUnwrap(
            try context.fetch(FetchDescriptor<RoutineFolder>()).first
        )

        XCTAssertEqual(folder.routineIDs, result.routineIDs)
        XCTAssertEqual(folder.routineIDs.count, 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 1)
    }

    func testImportedSplitKeepsRoutineOrder() throws {
        let context: ModelContext = try makeContext()
        let request: SplitImportRequest = makeRequest(routineNames: ["LEGS", "PUSH", "PULL"], context: context)

        let result: SplitImportResult = try SplitImportService.importSplit(
            request,
            mode: .newFolder(name: "Split"),
            into: context
        )

        let folder: RoutineFolder = try XCTUnwrap(try context.fetch(FetchDescriptor<RoutineFolder>()).first)
        let ordered: [String] = RoutineFolderService.routines(in: folder, from: allRoutines(context))
            .map(\.name)

        XCTAssertEqual(ordered, ["LEGS", "PUSH", "PULL"])
        XCTAssertEqual(result.routineIDs.count, 3)
    }

    func testImportedRoutinesGetNewIdentifiers() throws {
        let context: ModelContext = try makeContext()
        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH", "PULL"], context: context)
        let payloadIDs: Set<UUID> = Set(request.payload.routines.map(\.id))

        let result: SplitImportResult = try SplitImportService.importSplit(
            request,
            mode: .newFolder(name: "Split"),
            into: context
        )

        for id in result.routineIDs {
            XCTAssertFalse(payloadIDs.contains(id))
        }
    }

    func testOtherFoldersAreNotModified() throws {
        let context: ModelContext = try makeContext()
        let existing: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let existingRoutine: Routine = makeRoutine(named: "PIERNA", sortOrder: 0, context: context)
        existing.routineIDs = [existingRoutine.id]
        try context.save()

        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH"], context: context)
        _ = try SplitImportService.importSplit(request, mode: .newFolder(name: "Split"), into: context)

        XCTAssertEqual(existing.routineIDs, [existingRoutine.id])
        XCTAssertEqual(existing.name, "Fuerza")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 2)
    }

    func testUnambiguousExerciseIsReusedAcrossTheSplit() throws {
        let context: ModelContext = try makeContext()
        let existing: Exercise = Exercise(name: "Press banca", muscleGroup: .chest, equipmentType: .olympicBar)
        context.insert(existing)
        try context.save()

        let request: SplitImportRequest = makeRequest(
            routineNames: ["PUSH", "PULL"],
            exerciseName: "Press banca",
            context: context
        )
        let result: SplitImportResult = try SplitImportService.importSplit(
            request,
            mode: .newFolder(name: "Split"),
            into: context
        )

        let links: [RoutineExercise] = try context.fetch(FetchDescriptor<RoutineExercise>())

        XCTAssertEqual(result.routineIDs.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(links.count, 2)
        for link in links {
            XCTAssertEqual(link.exercise?.id, existing.id)
        }
    }

    // MARK: - Sustituir organización

    func testReplacingOrganizationArchivesPreviousRoutines() throws {
        let context: ModelContext = try makeContext()
        let manual: Routine = makeRoutine(named: "MANUAL", sortOrder: 0, context: context)
        let automatic: Routine = makeRoutine(named: "AUTO", sortOrder: 1, source: .automatic, context: context)
        let archived: Routine = makeRoutine(named: "OLD", sortOrder: 2, archived: true, context: context)
        try context.save()

        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH", "PULL"], context: context)
        _ = try SplitImportService.importSplit(request, mode: .replaceOrganization, into: context)

        XCTAssertTrue(manual.isArchived)
        XCTAssertTrue(automatic.isArchived)
        XCTAssertTrue(archived.isArchived)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 5)
    }

    func testReplacingOrganizationKeepsHistory() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(named: "PIERNA", sortOrder: 0, context: context)
        let link: RoutineExercise = makeLink(in: routine, name: "Sentadilla", order: 0, context: context)
        let session: WorkoutSession = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            totalVolumeKg: 2_400.0,
            routineName: routine.name
        )
        context.insert(session)
        let log: WorkoutSetLog = WorkoutSetLog(
            weight: 100.0,
            reps: 5,
            isCompleted: true,
            routineExerciseID: link.id,
            exercise: link.exercise,
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]
        try context.save()

        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH"], context: context)
        _ = try SplitImportService.importSplit(request, mode: .replaceOrganization, into: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSetLog>()), 1)
        XCTAssertEqual(session.totalVolumeKg, 2_400.0)
        XCTAssertEqual(log.weight, 100.0)
        XCTAssertEqual(log.exercise?.name, "Sentadilla")
    }

    func testReplacingOrganizationCreatesOneFolderWithAllRoutines() throws {
        let context: ModelContext = try makeContext()
        _ = try makeFolder(named: "Anterior", context: context)
        let previous: Routine = makeRoutine(named: "ANTIGUA", sortOrder: 0, context: context)
        try context.save()

        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH", "PULL", "LEGS"], context: context)
        let result: SplitImportResult = try SplitImportService.importSplit(
            request,
            mode: .replaceOrganization,
            into: context
        )

        let folders: [RoutineFolder] = try context.fetch(FetchDescriptor<RoutineFolder>())
        XCTAssertEqual(folders.count, 2)
        let newFolder: RoutineFolder = try XCTUnwrap(folders.first { $0.id == result.folderID })
        XCTAssertEqual(newFolder.routineIDs.count, 3)
        XCTAssertTrue(previous.isArchived)
    }

    func testReplacingOrganizationDeactivatesTheAssistedPlan() throws {
        let context: ModelContext = try makeContext()
        let plan: AssistedWeekPlan = AssistedWeekPlan(isActivePlan: true, days: [])
        context.insert(plan)
        try context.save()

        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH"], context: context)
        _ = try SplitImportService.importSplit(request, mode: .replaceOrganization, into: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AssistedWeekPlan>()), 1)
        XCTAssertFalse(plan.isActivePlan)
    }

    func testRollbackOnFailureLeavesNothingBehind() throws {
        let context: ModelContext = try makeContext()
        let active: Routine = makeRoutine(named: "MANUAL", sortOrder: 0, context: context)
        let plan: AssistedWeekPlan = AssistedWeekPlan(isActivePlan: true, days: [])
        context.insert(plan)
        try context.save()

        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH", "PULL"], context: context)

        XCTAssertThrowsError(
            try SplitImportService.importSplit(
                request,
                mode: .replaceOrganization,
                into: context,
                simulatePersistenceFailure: true
            )
        )

        XCTAssertFalse(active.isArchived)
        XCTAssertTrue(plan.isActivePlan)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineExercise>()), 0)
    }

    func testRollbackOnFailureForNewFolderMode() throws {
        let context: ModelContext = try makeContext()
        let existing: Routine = makeRoutine(named: "MANUAL", sortOrder: 0, context: context)
        try context.save()

        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH"], context: context)

        XCTAssertThrowsError(
            try SplitImportService.importSplit(
                request,
                mode: .newFolder(name: "Split"),
                into: context,
                simulatePersistenceFailure: true
            )
        )

        XCTAssertFalse(existing.isArchived)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 0)
    }

    // MARK: - Recepción y cola

    func testConfirmationDoesNotWriteUntilConfirmed() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()
        let url: URL = try writeSplitFile(makePayload(routineNames: ["PUSH", "PULL"], context: context))
        defer { removeDirectory(of: url) }

        coordinator.receive(url)
        coordinator.waitForPendingImport()

        XCTAssertNotNil(coordinator.pendingSplit)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 0)
    }

    func testCancellingSplitDoesNotModifySwiftData() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()
        let url: URL = try writeSplitFile(makePayload(routineNames: ["PUSH"], context: context))
        defer { removeDirectory(of: url) }

        coordinator.receive(url)
        coordinator.waitForPendingImport()
        coordinator.cancelSplit()

        XCTAssertNil(coordinator.pendingSplit)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 0)
    }

    func testCoordinatorDispatchesRoutineAndSplitSeparately() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()

        let routineURL: URL = try writeFile(
            name: "Rutina.appgymroutine",
            data: try encodeRoutinePayload(context: context)
        )
        let splitURL: URL = try writeSplitFile(makePayload(routineNames: ["PUSH"], context: context))
        defer {
            removeDirectory(of: routineURL)
            removeDirectory(of: splitURL)
        }

        let now: Date = Date()
        coordinator.receive(routineURL, now: now)
        coordinator.receive(splitURL, now: now.addingTimeInterval(1.0))
        coordinator.waitForPendingImport()

        XCTAssertNotNil(coordinator.pendingRequest)
        XCTAssertNil(coordinator.pendingSplit)
        XCTAssertEqual(coordinator.queuedCount, 1)

        coordinator.cancel()
        coordinator.routineSheetDismissed()
        coordinator.waitForPendingImport()

        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertNotNil(coordinator.pendingSplit)
        XCTAssertEqual(coordinator.queuedCount, 0)
    }

    func testReceivingTheSameSplitTwiceIsIgnored() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()
        let url: URL = try writeSplitFile(makePayload(routineNames: ["PUSH"], context: context))
        defer { removeDirectory(of: url) }

        let now: Date = Date()
        coordinator.receive(url, now: now)
        coordinator.receive(url, now: now.addingTimeInterval(1.0))
        coordinator.waitForPendingImport()

        XCTAssertNotNil(coordinator.pendingSplit)
        XCTAssertEqual(coordinator.queuedCount, 0)
    }

    func testUnknownFileTypeIsRejectedWithoutChanges() throws {
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()
        let url: URL = try writeRaw("{}", fileName: "cosa.json")
        defer { removeDirectory(of: url) }

        coordinator.receive(url)

        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertNil(coordinator.pendingSplit)
        XCTAssertEqual(coordinator.notice?.kind, .failure)
    }

    // MARK: - Auditoría de integración (09.1)

    func testQueueWaitsForDismissalBeforeStartingTheNextImport() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()

        let routineURL: URL = try writeFile(
            name: "Rutina.appgymroutine",
            data: try encodeRoutinePayload(context: context)
        )
        let splitURL: URL = try writeSplitFile(makePayload(routineNames: ["PUSH"], context: context))
        defer {
            removeDirectory(of: routineURL)
            removeDirectory(of: splitURL)
        }

        let now: Date = Date()
        coordinator.receive(routineURL, now: now)
        coordinator.receive(splitURL, now: now.addingTimeInterval(1.0))
        coordinator.waitForPendingImport()

        coordinator.cancel()

        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertNil(coordinator.pendingSplit)
        XCTAssertEqual(coordinator.queuedCount, 1)

        coordinator.routineSheetDismissed()
        coordinator.waitForPendingImport()

        XCTAssertNotNil(coordinator.pendingSplit)
        XCTAssertEqual(coordinator.queuedCount, 0)
    }

    func testDismissingTheRoutineSheetDoesNotCancelAQueuedSplit() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()

        let routineURL: URL = try writeFile(
            name: "Rutina.appgymroutine",
            data: try encodeRoutinePayload(context: context)
        )
        let splitURL: URL = try writeSplitFile(makePayload(routineNames: ["PUSH"], context: context))
        defer {
            removeDirectory(of: routineURL)
            removeDirectory(of: splitURL)
        }

        let now: Date = Date()
        coordinator.receive(routineURL, now: now)
        coordinator.receive(splitURL, now: now.addingTimeInterval(1.0))
        coordinator.waitForPendingImport()

        coordinator.cancel()
        coordinator.routineSheetDismissed()
        coordinator.waitForPendingImport()
        XCTAssertNotNil(coordinator.pendingSplit)

        // Un segundo callback (o un cierre tardío) no debe cancelar el split.
        coordinator.routineSheetDismissed()
        XCTAssertNotNil(coordinator.pendingSplit)
    }

    func testDismissingTheSplitSheetDoesNotCancelAQueuedRoutine() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()

        let splitURL: URL = try writeSplitFile(makePayload(routineNames: ["PUSH"], context: context))
        let routineURL: URL = try writeFile(
            name: "Rutina.appgymroutine",
            data: try encodeRoutinePayload(context: context)
        )
        defer {
            removeDirectory(of: splitURL)
            removeDirectory(of: routineURL)
        }

        let now: Date = Date()
        coordinator.receive(splitURL, now: now)
        coordinator.receive(routineURL, now: now.addingTimeInterval(1.0))
        coordinator.waitForPendingImport()

        coordinator.cancelSplit()
        coordinator.splitSheetDismissed()
        coordinator.waitForPendingImport()

        XCTAssertNotNil(coordinator.pendingRequest)
        XCTAssertNil(coordinator.pendingSplit)
    }

    func testQueueContinuesAfterARejectedFile() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()

        let invalid: URL = try writeRaw("no es json", fileName: "Roto.appgymsplit")
        let valid: URL = try writeFile(
            name: "Rutina.appgymroutine",
            data: try encodeRoutinePayload(context: context)
        )
        defer {
            removeDirectory(of: invalid)
            removeDirectory(of: valid)
        }

        coordinator.receive(invalid)
        coordinator.waitForPendingImport()
        XCTAssertNil(coordinator.pendingSplit)
        XCTAssertEqual(coordinator.notice?.kind, .failure)

        coordinator.receive(valid)
        XCTAssertEqual(coordinator.queuedCount, 1)

        coordinator.dismissNotice()
        coordinator.waitForPendingImport()

        XCTAssertNotNil(coordinator.pendingRequest)
        XCTAssertEqual(coordinator.queuedCount, 0)
    }

    func testUnknownFileIsQueuedWithoutLosingThePendingNotice() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()

        let routineURL: URL = try writeFile(
            name: "Rutina.appgymroutine",
            data: try encodeRoutinePayload(context: context)
        )
        let unknown: URL = try writeRaw("{}", fileName: "Cosa.json")
        defer {
            removeDirectory(of: routineURL)
            removeDirectory(of: unknown)
        }

        coordinator.receive(routineURL)
        XCTAssertNotNil(coordinator.pendingRequest)

        coordinator.receive(unknown)
        XCTAssertEqual(coordinator.queuedCount, 1)

        coordinator.confirm(in: context)
        coordinator.routineSheetDismissed()

        XCTAssertEqual(coordinator.notice?.kind, .success)

        coordinator.dismissNotice()

        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertEqual(coordinator.notice?.kind, .failure)
        XCTAssertEqual(coordinator.queuedCount, 0)
    }

    func testSplitPayloadWithRoutineExtensionIsRejected() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()

        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let url: URL = try writeFile(
            name: "Split.appgymroutine",
            data: try encoder.encode(makePayload(routineNames: ["PUSH"], context: context))
        )
        defer { removeDirectory(of: url) }

        coordinator.receive(url)

        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertNil(coordinator.pendingSplit)
        XCTAssertEqual(coordinator.notice?.kind, .failure)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 0)
    }

    func testRoutinePayloadWithSplitExtensionIsRejected() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()

        let url: URL = try writeFile(
            name: "Rutina.appgymsplit",
            data: try encodeRoutinePayload(context: context)
        )
        defer { removeDirectory(of: url) }

        coordinator.receive(url)

        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertNil(coordinator.pendingSplit)
        XCTAssertEqual(coordinator.notice?.kind, .failure)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 0)
    }

    func testImportingSplitKeepsAnExistingSplitIntact() throws {
        let context: ModelContext = try makeContext()
        let previous: RoutineFolder = try makeFolder(named: "Split anterior", context: context)
        let previousRoutine: Routine = makeRoutine(named: "ANTIGUA", sortOrder: 0, context: context)
        previous.routineIDs = [previousRoutine.id]
        try context.save()

        let request: SplitImportRequest = makeRequest(routineNames: ["PUSH", "PULL"], context: context)
        let result: SplitImportResult = try SplitImportService.importSplit(
            request,
            mode: .newFolder(name: "Split nuevo"),
            into: context
        )

        let folders: [RoutineFolder] = try context.fetch(FetchDescriptor<RoutineFolder>())
        XCTAssertEqual(folders.count, 2)
        XCTAssertEqual(previous.name, "Split anterior")
        XCTAssertEqual(previous.routineIDs, [previousRoutine.id])
        XCTAssertFalse(previousRoutine.isArchived)

        let imported: RoutineFolder = try XCTUnwrap(folders.first { $0.id == result.folderID })
        XCTAssertEqual(imported.routineIDs, result.routineIDs)
    }

    // MARK: - Utilidades

    private func makeContext() throws -> ModelContext {
        let schema: Schema = Schema(versionedSchema: AppSchemaV6.self)
        let configuration: ModelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return ModelContext(container)
    }

    private func allRoutines(_ context: ModelContext) -> [Routine] {
        return (try? context.fetch(FetchDescriptor<Routine>())) ?? []
    }

    private func makeFolder(named name: String, context: ModelContext) throws -> RoutineFolder {
        let existing: [RoutineFolder] = (try? context.fetch(FetchDescriptor<RoutineFolder>())) ?? []
        let folder: RoutineFolder = RoutineFolder(
            name: name,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(folder)
        try context.save()
        return folder
    }

    private func makeRoutine(
        named name: String,
        sortOrder: Int,
        archived: Bool = false,
        source: RoutineSource = .manual,
        context: ModelContext
    ) -> Routine {
        let routine: Routine = Routine(
            name: name,
            sortOrder: sortOrder,
            exercises: [],
            isArchived: archived,
            source: source
        )
        context.insert(routine)
        return routine
    }

    @discardableResult
    private func makeLink(
        in routine: Routine,
        name: String,
        sets: Int = 4,
        repsMin: Int = 6,
        repsMax: Int = 8,
        restSeconds: Int = 120,
        weight: Double = 40.0,
        notes: String = "nota",
        order: Int,
        context: ModelContext
    ) -> RoutineExercise {
        let exercise: Exercise = Exercise(
            name: name,
            muscleGroup: .chest,
            equipmentType: .olympicBar
        )
        context.insert(exercise)

        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: sets,
            targetRepsMin: repsMin,
            targetRepsMax: repsMax,
            sortOrder: order,
            defaultWeight: weight,
            restSeconds: restSeconds,
            notes: notes
        )
        context.insert(link)
        routine.exercises.append(link)
        return link
    }

    private func makePayload(routineNames: [String], context: ModelContext) -> RoutineSplitPayload {
        let routines: [RoutineShareRoutine] = routineNames.enumerated().map { index, name in
            return RoutineShareRoutine(
                id: UUID(),
                name: name,
                source: RoutineSource.manual.rawValue,
                exercises: [sharedExercise(name: "Ejercicio \(index)", order: 0)]
            )
        }
        return RoutineSplitPayload(
            format: RoutineSplitPayload.formatIdentifier,
            version: RoutineSplitPayload.currentVersion,
            id: UUID(),
            name: "Split compartido",
            routines: routines
        )
    }

    private func makePayload(
        routineNames: [String],
        exerciseName: String,
        context: ModelContext
    ) -> RoutineSplitPayload {
        let routines: [RoutineShareRoutine] = routineNames.map { name in
            return RoutineShareRoutine(
                id: UUID(),
                name: name,
                source: RoutineSource.manual.rawValue,
                exercises: [sharedExercise(name: exerciseName, order: 0)]
            )
        }
        return RoutineSplitPayload(
            format: RoutineSplitPayload.formatIdentifier,
            version: RoutineSplitPayload.currentVersion,
            id: UUID(),
            name: "Split compartido",
            routines: routines
        )
    }

    private func makeRequest(routineNames: [String], context: ModelContext) -> SplitImportRequest {
        return SplitImportRequest(payload: makePayload(routineNames: routineNames, context: context))
    }

    private func makeRequest(
        routineNames: [String],
        exerciseName: String,
        context: ModelContext
    ) -> SplitImportRequest {
        return SplitImportRequest(
            payload: makePayload(routineNames: routineNames, exerciseName: exerciseName, context: context)
        )
    }

    private func sharedExercise(name: String, order: Int) -> RoutineShareExercise {
        return RoutineShareExercise(
            name: name,
            muscleGroupRaw: MuscleGroup.chest.rawValue,
            equipmentTypeRaw: EquipmentType.olympicBar.rawValue,
            requiresStraps: false,
            trackingModeRaw: ExerciseTrackingMode.reps.rawValue,
            targetRepsMin: 6,
            targetRepsMax: 8,
            defaultRestSeconds: 90,
            defaultRestTargetBPM: nil,
            sets: 4,
            repsMin: 6,
            repsMax: 8,
            restSeconds: 120,
            targetWeight: 40.0,
            notes: "nota",
            sortOrder: order
        )
    }

    private func encodeRoutinePayload(context: ModelContext) throws -> Data {
        let payload: RoutineSharePayload = RoutineSharePayload(
            format: RoutineSharePayload.formatIdentifier,
            version: RoutineSharePayload.currentVersion,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            routine: RoutineShareRoutine(
                id: UUID(),
                name: "Rutina suelta",
                source: RoutineSource.manual.rawValue,
                exercises: [sharedExercise(name: "Press banca", order: 0)]
            )
        )

        let encoder: JSONEncoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private func writeSplitFile(_ payload: RoutineSplitPayload) throws -> URL {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data = try encoder.encode(payload)
        return try writeFile(name: "Split.appgymsplit", data: data)
    }

    private func writeRaw(_ contents: String, fileName: String) throws -> URL {
        return try writeFile(name: fileName, data: Data(contents.utf8))
    }

    private func writeFile(name: String, data: Data) throws -> URL {
        let directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SplitShareImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url: URL = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func removeDirectory(of url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
