import XCTest
import Foundation
import SwiftData
import UniformTypeIdentifiers

@testable import AppGym

/// Pruebas de la recepción e importación de rutinas `.appgymroutine`
/// (Prompt 08B).
///
/// Cubren la validación del archivo, la confirmación (a nivel de servicio y
/// coordinador), la importación atómica y la integridad del resto de datos.
@MainActor
final class RoutineImportTests: XCTestCase {

    // MARK: - 1. Apertura y validación

    func testDocumentTypeIsRegisteredForRoutineFiles() {
        let type: UTType = RoutineImportService.documentType

        XCTAssertEqual(type.identifier, "com.jordiferres.appgym.routine")
        XCTAssertEqual(type.preferredFilenameExtension, "appgymroutine")
        XCTAssertTrue(type.conforms(to: .json))
    }

    func testValidFileOpensAndValidates() throws {
        let url: URL = try writeFile(makePayload(name: "Empuje", exerciseCount: 2))
        defer { removeDirectory(of: url) }

        XCTAssertTrue(RoutineImportService.isRoutineFile(url))

        let request: RoutineImportRequest = try RoutineImportService.makeRequest(fromFileAt: url)

        XCTAssertEqual(request.routineName, "Empuje")
        XCTAssertEqual(request.exerciseCount, 2)
        XCTAssertEqual(request.payload.format, RoutineSharePayload.formatIdentifier)
        XCTAssertEqual(request.payload.version, RoutineSharePayload.currentVersion)
    }

    func testCorruptJSONIsRejected() throws {
        let url: URL = try writeRaw("esto no es json")
        defer { removeDirectory(of: url) }

        XCTAssertThrowsError(try RoutineImportService.makeRequest(fromFileAt: url)) { error in
            XCTAssertEqual(error as? RoutineImportError, .malformedJSON)
        }
    }

    func testWrongFormatIsRejected() throws {
        var payload: RoutineSharePayload = makePayload()
        payload.format = "otra.app"

        let url: URL = try writeFile(payload)
        defer { removeDirectory(of: url) }

        XCTAssertThrowsError(try RoutineImportService.makeRequest(fromFileAt: url)) { error in
            XCTAssertEqual(error as? RoutineImportError, .invalidFormat)
        }
    }

    func testIncompatibleVersionIsRejected() throws {
        var payload: RoutineSharePayload = makePayload()
        payload.version = 2

        let url: URL = try writeFile(payload)
        defer { removeDirectory(of: url) }

        XCTAssertThrowsError(try RoutineImportService.makeRequest(fromFileAt: url)) { error in
            XCTAssertEqual(error as? RoutineImportError, .unsupportedVersion(2))
        }
    }

    func testInvalidUUIDIsRejected() throws {
        let payload: RoutineSharePayload = makePayload()
        let data: Data = try encoded(payload)
        let raw: String = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: payload.routine.id.uuidString, with: "no-es-un-uuid")

        let url: URL = try writeRaw(raw)
        defer { removeDirectory(of: url) }

        XCTAssertThrowsError(try RoutineImportService.makeRequest(fromFileAt: url)) { error in
            XCTAssertEqual(error as? RoutineImportError, .malformedJSON)
        }
    }

    func testOutOfRangeSetsAndRepetitionsAreRejected() throws {
        var invalidSets: RoutineSharePayload = makePayload()
        invalidSets.routine.exercises[0].sets = 0
        XCTAssertThrowsError(try RoutineImportService.validate(invalidSets))

        var tooManySets: RoutineSharePayload = makePayload()
        tooManySets.routine.exercises[0].sets = 21
        XCTAssertThrowsError(try RoutineImportService.validate(tooManySets))

        var invalidReps: RoutineSharePayload = makePayload()
        invalidReps.routine.exercises[0].repsMin = 0
        XCTAssertThrowsError(try RoutineImportService.validate(invalidReps))

        var invertedReps: RoutineSharePayload = makePayload()
        invertedReps.routine.exercises[0].repsMin = 10
        invertedReps.routine.exercises[0].repsMax = 8
        XCTAssertThrowsError(try RoutineImportService.validate(invertedReps))

        var invalidRest: RoutineSharePayload = makePayload()
        invalidRest.routine.exercises[0].restSeconds = 5_000
        XCTAssertThrowsError(try RoutineImportService.validate(invalidRest))

        var invalidWeight: RoutineSharePayload = makePayload()
        invalidWeight.routine.exercises[0].targetWeight = -5.0
        XCTAssertThrowsError(try RoutineImportService.validate(invalidWeight))
    }

    func testIncompleteExercisesAreRejected() throws {
        var emptyName: RoutineSharePayload = makePayload()
        emptyName.routine.exercises[0].name = "   "
        XCTAssertThrowsError(try RoutineImportService.validate(emptyName))

        var unknownMuscle: RoutineSharePayload = makePayload()
        unknownMuscle.routine.exercises[0].muscleGroupRaw = "Grupo inexistente"
        XCTAssertThrowsError(try RoutineImportService.validate(unknownMuscle))

        var unknownEquipment: RoutineSharePayload = makePayload()
        unknownEquipment.routine.exercises[0].equipmentTypeRaw = "Máquina inventada"
        XCTAssertThrowsError(try RoutineImportService.validate(unknownEquipment))

        var duplicateOrder: RoutineSharePayload = makePayload()
        duplicateOrder.routine.exercises[1].sortOrder = duplicateOrder.routine.exercises[0].sortOrder
        XCTAssertThrowsError(try RoutineImportService.validate(duplicateOrder)) { error in
            XCTAssertEqual(error as? RoutineImportError, .duplicateExerciseOrder)
        }
    }

    // MARK: - 2. Confirmación

    func testConfirmationIsOnlyRequestedAfterValidation() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()

        let invalid: URL = try writeRaw("{ \"format\": \"appgym.routine\" }")
        coordinator.receive(invalid)
        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertNotNil(coordinator.notice)

        coordinator.dismissNotice()

        let valid: URL = try writeFile(makePayload(name: "Empuje"))
        coordinator.receive(valid)

        XCTAssertNotNil(coordinator.pendingRequest)
        XCTAssertNil(coordinator.notice)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 0)

        defer {
            removeDirectory(of: invalid)
            removeDirectory(of: valid)
        }
    }

    func testCancellingDoesNotModifySwiftData() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()
        let url: URL = try writeFile(makePayload(name: "Empuje"))
        defer { removeDirectory(of: url) }

        coordinator.receive(url)
        XCTAssertNotNil(coordinator.pendingRequest)

        coordinator.cancel()

        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineExercise>()), 0)
    }

    func testConfirmingImportsTheRoutine() throws {
        let context: ModelContext = try makeContext()
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()
        let url: URL = try writeFile(makePayload(name: "Empuje"))
        defer { removeDirectory(of: url) }

        coordinator.receive(url)
        coordinator.confirm(in: context)
        // La hoja se cierra y solo entonces se publica el aviso.
        coordinator.cancelIfPending()

        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertEqual(coordinator.notice?.kind, .success)
        XCTAssertTrue(coordinator.revealRoutines)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)
    }

    // MARK: - 3. Importación

    func testImportedRoutineGetsANewIdentifier() throws {
        let context: ModelContext = try makeContext()
        let payload: RoutineSharePayload = makePayload()
        let routine: Routine = try importRoutine(payload, into: context)

        XCTAssertNotEqual(routine.id, payload.routine.id)
        XCTAssertEqual(routine.name, payload.routine.name)
    }

    func testImportedRoutineKeepsNameAndContent() throws {
        let context: ModelContext = try makeContext()
        let payload: RoutineSharePayload = makePayload(name: "Empuje", exerciseCount: 3)
        let routine: Routine = try importRoutine(payload, into: context)

        XCTAssertEqual(routine.name, "Empuje")
        XCTAssertTrue(routine.isTemplate)
        XCTAssertFalse(routine.isArchived)
        XCTAssertEqual(routine.source, .manual)
        XCTAssertEqual(routine.exercises.count, 3)
        XCTAssertEqual(
            routine.exercises.sorted { $0.sortOrder < $1.sortOrder }.map { $0.exercise?.name },
            payload.routine.exercises.sorted { $0.sortOrder < $1.sortOrder }.map { $0.name }
        )
    }

    func testImportedRoutineKeepsExerciseOrder() throws {
        let context: ModelContext = try makeContext()
        var payload: RoutineSharePayload = makePayload(exerciseCount: 4)
        // El archivo puede venir en cualquier orden: manda `sortOrder`.
        payload.routine.exercises = Array(payload.routine.exercises.reversed())
        payload.routine.exercises[0].sortOrder = 3
        payload.routine.exercises[1].sortOrder = 2
        payload.routine.exercises[2].sortOrder = 1
        payload.routine.exercises[3].sortOrder = 0

        let routine: Routine = try importRoutine(payload, into: context)
        let ordered: [String] = routine.exercises
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.exercise?.name ?? "" }

        XCTAssertEqual(ordered, ["Ejercicio 0", "Ejercicio 1", "Ejercicio 2", "Ejercicio 3"])
    }

    func testImportedRoutineKeepsExercisesConfiguration() throws {
        let context: ModelContext = try makeContext()
        var payload: RoutineSharePayload = makePayload(exerciseCount: 1)
        payload.routine.exercises[0].sets = 5
        payload.routine.exercises[0].repsMin = 3
        payload.routine.exercises[0].repsMax = 5
        payload.routine.exercises[0].restSeconds = 240
        payload.routine.exercises[0].targetWeight = 92.5
        payload.routine.exercises[0].notes = "Tempo 3-1-1"

        let routine: Routine = try importRoutine(payload, into: context)
        let link: RoutineExercise = try XCTUnwrap(routine.exercises.first)

        XCTAssertEqual(link.defaultSets, 5)
        XCTAssertEqual(link.targetRepsMin, 3)
        XCTAssertEqual(link.targetRepsMax, 5)
        XCTAssertEqual(link.restSeconds, 240)
        XCTAssertEqual(link.defaultWeight, 92.5)
        XCTAssertEqual(link.notes, "Tempo 3-1-1")
    }

    func testImportedRoutineIsNotAssignedToAnyFolder() throws {
        let context: ModelContext = try makeContext()
        let existing: Routine = Routine(name: "Pierna", sortOrder: 0, exercises: [], source: .manual)
        context.insert(existing)

        let folder: RoutineFolder = try RoutineFolderService.createFolder(
            named: "Fuerza",
            existingFolders: [],
            context: context
        )
        try RoutineFolderService.moveRoutine(existing, to: folder, context: context)
        try context.save()

        let routine: Routine = try importRoutine(makePayload(name: "Empuje"), into: context)

        XCTAssertFalse(folder.routineIDs.contains(routine.id))
        XCTAssertEqual(folder.routineIDs, [existing.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 1)
    }

    func testImportingAnExistingNameAddsASuffix() throws {
        let context: ModelContext = try makeContext()
        context.insert(Routine(name: "PUSH", sortOrder: 0, exercises: [], source: .manual))
        try context.save()

        let routine: Routine = try importRoutine(makePayload(name: "PUSH"), into: context)

        XCTAssertEqual(routine.name, "PUSH (2)")
    }

    func testImportingTheSameNameTwiceKeepsBothRoutines() throws {
        let context: ModelContext = try makeContext()

        let first: Routine = try importRoutine(makePayload(name: "PUSH"), into: context)
        let second: Routine = try importRoutine(makePayload(name: "PUSH"), into: context)

        XCTAssertEqual(first.name, "PUSH")
        XCTAssertEqual(second.name, "PUSH (2)")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 2)
    }

    func testUnambiguousExerciseIsReused() throws {
        let context: ModelContext = try makeContext()
        let existing: Exercise = Exercise(
            name: "Press banca",
            muscleGroup: .chest,
            equipmentType: .olympicBar
        )
        context.insert(existing)
        try context.save()

        let payload: RoutineSharePayload = makePayload(
            name: "Empuje",
            exercises: [sharedExercise(name: "Press banca", muscle: .chest, equipment: .olympicBar, order: 0)]
        )
        let routine: Routine = try importRoutine(payload, into: context)
        let link: RoutineExercise = try XCTUnwrap(routine.exercises.first)

        XCTAssertEqual(link.exercise?.id, existing.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }

    func testAmbiguousExerciseIsNotMerged() throws {
        let context: ModelContext = try makeContext()
        let first: Exercise = Exercise(name: "Press banca", muscleGroup: .chest, equipmentType: .olympicBar)
        let second: Exercise = Exercise(name: "Press banca", muscleGroup: .chest, equipmentType: .olympicBar)
        context.insert(first)
        context.insert(second)
        try context.save()

        let payload: RoutineSharePayload = makePayload(
            name: "Empuje",
            exercises: [sharedExercise(name: "Press banca", muscle: .chest, equipment: .olympicBar, order: 0)]
        )
        let routine: Routine = try importRoutine(payload, into: context)
        let link: RoutineExercise = try XCTUnwrap(routine.exercises.first)

        XCTAssertNotEqual(link.exercise?.id, first.id)
        XCTAssertNotEqual(link.exercise?.id, second.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 3)
        XCTAssertEqual(first.name, "Press banca")
        XCTAssertEqual(second.name, "Press banca")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineExercise>()), 1)
    }

    // MARK: - 4. Integridad

    func testExistingRoutinesAreNotModified() throws {
        let context: ModelContext = try makeContext()
        let existingExercise: Exercise = Exercise(name: "Sentadilla", muscleGroup: .quads)
        context.insert(existingExercise)
        let existing: Routine = Routine(name: "Pierna", sortOrder: 4, exercises: [], source: .manual)
        context.insert(existing)
        let link: RoutineExercise = RoutineExercise(exercise: existingExercise, defaultSets: 3, sortOrder: 0)
        context.insert(link)
        existing.exercises = [link]
        try context.save()

        let existingName: String = existing.name
        let existingOrder: Int = existing.sortOrder
        let existingLinkIDs: [UUID] = existing.exercises.map(\.id)

        _ = try importRoutine(makePayload(name: "Empuje"), into: context)

        XCTAssertEqual(existing.name, existingName)
        XCTAssertEqual(existing.sortOrder, existingOrder)
        XCTAssertEqual(existing.exercises.map(\.id), existingLinkIDs)
        XCTAssertEqual(existingExercise.name, "Sentadilla")
    }

    func testHistoryIsNotModified() throws {
        let context: ModelContext = try makeContext()
        let exercise: Exercise = Exercise(name: "Sentadilla", muscleGroup: .quads)
        context.insert(exercise)
        let session: WorkoutSession = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            totalVolumeKg: 2_400.0,
            routineName: "Pierna"
        )
        context.insert(session)
        let log: WorkoutSetLog = WorkoutSetLog(
            date: Date(timeIntervalSince1970: 1_700_000_120),
            weight: 100.0,
            reps: 5,
            isCompleted: true,
            exercise: exercise,
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]
        try context.save()

        _ = try importRoutine(makePayload(name: "Empuje"), into: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSetLog>()), 1)
        XCTAssertEqual(session.totalVolumeKg, 2_400.0)
        XCTAssertEqual(log.weight, 100.0)
        XCTAssertEqual(session.setsCompleted.count, 1)
    }

    func testAssistedPlansAreNotModified() throws {
        let context: ModelContext = try makeContext()
        let plan: AssistedWeekPlan = AssistedWeekPlan(isActivePlan: true, days: [])
        context.insert(plan)
        try context.save()

        let planID: UUID = plan.id
        let daysData: Data = plan.daysData

        _ = try importRoutine(makePayload(name: "Empuje"), into: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AssistedWeekPlan>()), 1)
        XCTAssertEqual(plan.id, planID)
        XCTAssertTrue(plan.isActivePlan)
        XCTAssertEqual(plan.daysData, daysData)
    }

    func testImportDoesNotLeaveOrphanExercises() throws {
        let context: ModelContext = try makeContext()
        let existingIDs: Set<UUID> = Set(try context.fetch(FetchDescriptor<Exercise>()).map(\.id))

        _ = try importRoutine(makePayload(name: "Empuje", exerciseCount: 3), into: context)

        let exercises: [Exercise] = try context.fetch(FetchDescriptor<Exercise>())
        let linked: Set<UUID> = Set(
            try context.fetch(FetchDescriptor<RoutineExercise>()).compactMap { $0.exercise?.id }
        )

        for exercise in exercises where !existingIDs.contains(exercise.id) {
            XCTAssertTrue(linked.contains(exercise.id), "Ejercicio importado sin rutina: \(exercise.name)")
        }
    }

    func testRollbackLeavesNoPartialData() throws {
        let context: ModelContext = try makeContext()
        let url: URL = try writeFile(makePayload(name: "Empuje", exerciseCount: 2))
        defer { removeDirectory(of: url) }

        let request: RoutineImportRequest = try RoutineImportService.makeRequest(fromFileAt: url)

        XCTAssertThrowsError(
            try RoutineImportService.importRoutine(
                request,
                into: context,
                simulatePersistenceFailure: true
            )
        ) { error in
            XCTAssertEqual(error as? RoutineImportError, .importFailed)
        }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineExercise>()), 0)
    }

    // MARK: - 5. Varios archivos

    func testReceivingTheSameURLTwiceOnlyQueuesOneImport() throws {
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()
        let url: URL = try writeFile(makePayload(name: "Empuje"))
        defer { removeDirectory(of: url) }

        let now: Date = Date()
        coordinator.receive(url, now: now)
        coordinator.receive(url, now: now.addingTimeInterval(1.0))

        XCTAssertNotNil(coordinator.pendingRequest)
        XCTAssertEqual(coordinator.queuedCount, 0)
    }

    func testConsecutiveFilesAreQueuedAndProcessedOneByOne() throws {
        let coordinator: RoutineImportCoordinator = RoutineImportCoordinator()
        let first: URL = try writeFile(makePayload(name: "Empuje"), fileName: "Primera.appgymroutine")
        let second: URL = try writeFile(makePayload(name: "Tirón"), fileName: "Segunda.appgymroutine")
        defer {
            removeDirectory(of: first)
            removeDirectory(of: second)
        }

        let now: Date = Date()
        coordinator.receive(first, now: now)
        coordinator.receive(second, now: now.addingTimeInterval(1.0))

        XCTAssertEqual(coordinator.pendingRequest?.routineName, "Empuje")
        XCTAssertEqual(coordinator.queuedCount, 1)

        coordinator.cancel()
        // La siguiente importación arranca cuando la hoja termina de cerrarse.
        coordinator.routineSheetDismissed()

        XCTAssertEqual(coordinator.pendingRequest?.routineName, "Tirón")
        XCTAssertEqual(coordinator.queuedCount, 0)
    }

    // MARK: - Utilidades

    private func makePayload(
        name: String = "Empuje",
        exerciseCount: Int = 2,
        source: String = RoutineSource.manual.rawValue,
        exercises: [RoutineShareExercise]? = nil
    ) -> RoutineSharePayload {
        let items: [RoutineShareExercise] = exercises ?? (0..<max(exerciseCount, 1)).map { index in
            return sharedExercise(
                name: "Ejercicio \(index)",
                muscle: .chest,
                equipment: .olympicBar,
                order: index
            )
        }

        return RoutineSharePayload(
            format: RoutineSharePayload.formatIdentifier,
            version: RoutineSharePayload.currentVersion,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            routine: RoutineShareRoutine(
                id: UUID(),
                name: name,
                source: source,
                exercises: items
            )
        )
    }

    private func sharedExercise(
        name: String,
        muscle: MuscleGroup,
        equipment: EquipmentType,
        order: Int
    ) -> RoutineShareExercise {
        return RoutineShareExercise(
            name: name,
            muscleGroupRaw: muscle.rawValue,
            equipmentTypeRaw: equipment.rawValue,
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

    private func importRoutine(_ payload: RoutineSharePayload, into context: ModelContext) throws -> Routine {
        let request: RoutineImportRequest = RoutineImportRequest(payload: payload)
        return try RoutineImportService.importRoutine(request, into: context)
    }

    private func encoded(_ payload: RoutineSharePayload) throws -> Data {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private func writeFile(
        _ payload: RoutineSharePayload,
        fileName: String = "Rutina.appgymroutine"
    ) throws -> URL {
        let data: Data = try encoded(payload)
        return try write(data: data, fileName: fileName)
    }

    private func writeRaw(_ contents: String) throws -> URL {
        return try write(data: Data(contents.utf8), fileName: "Rutina.appgymroutine")
    }

    private func write(data: Data, fileName: String) throws -> URL {
        let directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutineImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url: URL = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func removeDirectory(of url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
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
