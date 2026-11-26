import XCTest
import Foundation
import SwiftData

@testable import AppGym

/// Pruebas del sistema de carpetas de la pestaña Rutinas.
///
/// Cubren los 27 puntos del prompt 07 más las comprobaciones de la auditoría
/// 07.1: conservación real de los registros históricos al borrar una carpeta,
/// contador de rutinas activas, migración V5 → V6 y copias de seguridad.
///
/// La pertenencia se guarda en `RoutineFolder.routineIDsData`, así que las
/// comprobaciones usan `folderContaining(_:in:)` en lugar de una propiedad de
/// `Routine`.
@MainActor
final class RoutineFolderTests: XCTestCase {

    // MARK: - 1. Crear una carpeta

    func testCreateFolderStoresATrimmedName() throws {
        let context: ModelContext = try makeContext()

        let folder: RoutineFolder = try RoutineFolderService.createFolder(
            named: "   Empuje / Tirón / Pierna   ",
            existingFolders: [],
            context: context
        )

        XCTAssertEqual(folder.name, "Empuje / Tirón / Pierna")
        XCTAssertEqual(folder.sortOrder, 0)
        XCTAssertTrue(folder.routineIDs.isEmpty)

        let stored: [RoutineFolder] = try context.fetch(FetchDescriptor<RoutineFolder>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.id, folder.id)
    }

    // MARK: - 2. Renombrar una carpeta

    func testRenameFolderChangesTheStoredName() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)

        try RoutineFolderService.renameFolder(
            folder,
            to: " Fuerza base ",
            existingFolders: [folder],
            context: context
        )

        let reloaded: [RoutineFolder] = try context.fetch(FetchDescriptor<RoutineFolder>())
        XCTAssertEqual(reloaded.first?.name, "Fuerza base")
    }

    // MARK: - 3. Persistencia después de reiniciar

    func testFolderMembershipAndOrderSurviveReopeningTheStore() throws {
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL: URL = directory.appendingPathComponent("default.store")

        let folderID: UUID
        let routineIDs: [UUID]

        do {
            let container: ModelContainer = try XCTUnwrap(
                StoreBootstrap.makeContainer(storeURL: storeURL).container
            )
            let context: ModelContext = ModelContext(container)

            let first: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
            let second: Routine = makeRoutine(name: "Tirón", sortOrder: 1, context: context)
            let folder: RoutineFolder = try RoutineFolderService.createFolder(
                named: "Fuerza",
                existingFolders: [],
                context: context
            )
            try RoutineFolderService.moveRoutine(first, to: folder, context: context)
            try RoutineFolderService.moveRoutine(second, to: folder, context: context)

            folderID = folder.id
            routineIDs = [first.id, second.id]
        }

        // Reabrir el mismo store simula cerrar y volver a abrir la app.
        let reopened: ModelContainer = try XCTUnwrap(
            StoreBootstrap.makeContainer(storeURL: storeURL).container
        )
        let context: ModelContext = ModelContext(reopened)

        let folders: [RoutineFolder] = try context.fetch(FetchDescriptor<RoutineFolder>())
        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())

        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.id, folderID)
        XCTAssertEqual(Set(routines.map(\.id)), Set(routineIDs))

        let stored: RoutineFolder = try XCTUnwrap(folders.first)
        XCTAssertEqual(
            RoutineFolderService.routines(in: stored, from: routines).map(\.id),
            routineIDs
        )
    }

    // MARK: - 4. Carpetas antes que rutinas

    func testMainRowsListFoldersBeforeLooseRoutines() throws {
        let context: ModelContext = try makeContext()

        let loose: Routine = makeRoutine(name: "Brazos", sortOrder: 5, context: context)
        let inside: Routine = makeRoutine(name: "Torso", sortOrder: 0, context: context)

        let folderB: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let folderA: RoutineFolder = try makeFolder(named: "Empuje / Tirón / Pierna", context: context)
        try RoutineFolderService.moveRoutine(inside, to: folderA, context: context)

        let rows: [RoutineListRow] = RoutineFolderService.mainRows(
            folders: [folderB, folderA],
            activeRoutines: [loose, inside]
        )

        XCTAssertEqual(
            rows.map(\.identifier),
            [
                "folder:\(folderB.id.uuidString)",
                "folder:\(folderA.id.uuidString)",
                "routine:\(loose.id.uuidString)"
            ]
        )
    }

    // MARK: - 5. Rutinas sin carpeta visibles en la lista principal

    func testLooseRoutinesRemainInTheMainList() throws {
        let context: ModelContext = try makeContext()
        let loose: Routine = makeRoutine(name: "Piernas", sortOrder: 2, context: context)
        _ = try makeFolder(named: "Fuerza", context: context)

        let rows: [RoutineListRow] = RoutineFolderService.mainRows(
            folders: try context.fetch(FetchDescriptor<RoutineFolder>()),
            activeRoutines: [loose]
        )

        XCTAssertTrue(rows.map(\.identifier).contains("routine:\(loose.id.uuidString)"))
    }

    // MARK: - 6. Rutinas con carpeta ocultas de la lista principal

    func testRoutinesInsideAFolderAreHiddenFromTheMainList() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Torso", sortOrder: 0, context: context)
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        let rows: [RoutineListRow] = RoutineFolderService.mainRows(
            folders: [folder],
            activeRoutines: [routine]
        )

        XCTAssertFalse(rows.map(\.identifier).contains("routine:\(routine.id.uuidString)"))
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - 7. Entrar en una carpeta y ver sus rutinas

    func testFolderRowsShowOnlyItsOwnRoutinesInOrder() throws {
        let context: ModelContext = try makeContext()

        let first: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        let second: Routine = makeRoutine(name: "Tirón", sortOrder: 1, context: context)
        let outside: Routine = makeRoutine(name: "Piernas", sortOrder: 2, context: context)

        let folder: RoutineFolder = try makeFolder(named: "PPL", context: context)
        try RoutineFolderService.moveRoutine(first, to: folder, context: context)
        try RoutineFolderService.moveRoutine(second, to: folder, context: context)

        let rows: [RoutineListRow] = RoutineFolderService.rows(
            in: folder,
            activeRoutines: [first, second, outside]
        )

        XCTAssertEqual(
            rows.map(\.identifier),
            ["routine:\(first.id.uuidString)", "routine:\(second.id.uuidString)"]
        )
    }

    // MARK: - 8. Mover a una carpeta nueva

    func testMovingARoutineToANewFolderCreatesTheFolderAndKeepsTheRoutine() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)

        let folder: RoutineFolder = try RoutineFolderService.createFolder(
            named: "Fuerza",
            moving: routine,
            existingFolders: [],
            context: context
        )

        XCTAssertEqual(try containingFolderID(of: routine, in: context), folder.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 1)
    }

    // MARK: - 9. Mover a una carpeta existente

    func testMovingARoutineToAnExistingFolder() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Brazos", sortOrder: 0, context: context)
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)

        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        XCTAssertEqual(try containingFolderID(of: routine, in: context), folder.id)
        let reloaded: RoutineFolder = try XCTUnwrap(
            try context.fetch(FetchDescriptor<RoutineFolder>()).first
        )
        XCTAssertEqual(reloaded.routineIDs, [routine.id])
    }

    // MARK: - 10. Cancelar el movimiento

    func testCancellingTheMoveLeavesEverythingUntouched() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Brazos", sortOrder: 3, context: context)
        _ = try makeFolder(named: "Fuerza", context: context)

        // Cancelar es cerrar la hoja sin llamar al servicio. Además, mover a la
        // ubicación actual es una operación nula y no crea carpetas.
        let foldersBefore: Int = try context.fetchCount(FetchDescriptor<RoutineFolder>())
        try RoutineFolderService.moveRoutine(routine, to: nil, context: context)

        XCTAssertNil(try containingFolderID(of: routine, in: context))
        XCTAssertEqual(routine.sortOrder, 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), foldersBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)
    }

    // MARK: - 11. Mover entre carpetas

    func testMovingARoutineBetweenFolders() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Torso", sortOrder: 0, context: context)
        let origin: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let destination: RoutineFolder = try makeFolder(named: "Volumen", context: context)

        try RoutineFolderService.moveRoutine(routine, to: origin, context: context)
        try RoutineFolderService.moveRoutine(routine, to: destination, context: context)

        XCTAssertEqual(try containingFolderID(of: routine, in: context), destination.id)
        XCTAssertTrue(RoutineFolderService.routines(in: origin, from: [routine]).isEmpty)
        XCTAssertEqual(RoutineFolderService.routines(in: destination, from: [routine]).count, 1)
        XCTAssertEqual(origin.routineIDs.contains(routine.id), false)
        XCTAssertEqual(destination.routineIDs, [routine.id])
    }

    // MARK: - 12. Sacar una rutina de una carpeta

    func testRemovingARoutineFromAFolderReturnsItToTheMainList() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Torso", sortOrder: 0, context: context)
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)

        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)
        try RoutineFolderService.moveRoutine(routine, to: nil, context: context)

        XCTAssertNil(try containingFolderID(of: routine, in: context))
        XCTAssertTrue(folder.routineIDs.isEmpty)

        let rows: [RoutineListRow] = RoutineFolderService.mainRows(
            folders: [folder],
            activeRoutines: [routine]
        )
        XCTAssertTrue(rows.map(\.identifier).contains("routine:\(routine.id.uuidString)"))
    }

    // MARK: - 13. Sin duplicados al mover

    func testMovingARoutineNeverDuplicatesIt() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Torso", sortOrder: 0, context: context)
        let first: RoutineFolder = try makeFolder(named: "A", context: context)
        let second: RoutineFolder = try makeFolder(named: "B", context: context)

        try RoutineFolderService.moveRoutine(routine, to: first, context: context)
        try RoutineFolderService.moveRoutine(routine, to: second, context: context)
        try RoutineFolderService.moveRoutine(routine, to: nil, context: context)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routines.first?.id, routine.id)
        XCTAssertTrue(first.routineIDs.isEmpty)
        XCTAssertTrue(second.routineIDs.isEmpty)
    }

    // MARK: - 14. UUID e historial intactos al mover

    func testMovingARoutineKeepsItsUUIDAndItsWorkoutHistory() throws {
        let context: ModelContext = try makeContext()
        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(exercise)

        let routine: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 0,
            restSeconds: 120
        )
        context.insert(link)
        routine.exercises = [link]

        let session: WorkoutSession = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            routineName: routine.name
        )
        context.insert(session)
        let log: WorkoutSetLog = WorkoutSetLog(
            date: Date(timeIntervalSince1970: 1_700_000_100),
            workoutStartDate: session.startDate,
            weight: 80.0,
            reps: 8,
            isCompleted: true,
            routineExerciseID: link.id,
            setNumber: 1,
            exercise: exercise,
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]
        try context.save()

        let routineID: UUID = routine.id
        let linkID: UUID = link.id
        let sessionID: UUID = session.id

        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        XCTAssertEqual(routine.id, routineID)
        XCTAssertEqual(routine.exercises.count, 1)
        XCTAssertEqual(routine.exercises.first?.id, linkID)
        XCTAssertEqual(routine.exercises.first?.defaultSets, 4)

        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, sessionID)
        XCTAssertEqual(sessions.first?.setsCompleted.count, 1)
        XCTAssertEqual(sessions.first?.totalVolumeKg, 0.0)
    }

    // MARK: - 15. Eliminar una carpeta vacía sin confirmación

    func testEmptyFolderNeedsNoConfirmationAndIsDeletedDirectly() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Vacía", context: context)

        XCTAssertFalse(
            RoutineFolderService.requiresDeletionConfirmation(for: folder, routines: [])
        )

        let summary: RoutineFolderService.DeletionSummary = try RoutineFolderService.deleteFolder(
            folder,
            containedRoutines: try context.fetch(FetchDescriptor<Routine>()),
            context: context
        )

        XCTAssertEqual(summary.deletedRoutineCount, 0)
        XCTAssertEqual(summary.archivedRoutineCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 0)
    }

    // MARK: - 16. Confirmación con rutinas dentro

    func testFolderWithRoutinesRequiresConfirmationWithADynamicCount() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let first: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        let second: Routine = makeRoutine(name: "Tirón", sortOrder: 1, context: context)
        let third: Routine = makeRoutine(name: "Pierna", sortOrder: 2, context: context)

        try RoutineFolderService.moveRoutine(first, to: folder, context: context)
        try RoutineFolderService.moveRoutine(second, to: folder, context: context)

        XCTAssertTrue(
            RoutineFolderService.requiresDeletionConfirmation(for: folder, routines: [first, second, third])
        )
        XCTAssertEqual(
            RoutineFolderService.activeRoutineCount(in: folder, routines: [first, second, third]),
            2
        )
    }

    // MARK: - 17. Cancelar la eliminación

    func testCancellingFolderDeletionKeepsAllData() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let routine: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        // Cancelar en la alerta no ejecuta el servicio: se comprueba que los
        // datos siguen exactamente igual.
        let routineCount: Int = try context.fetchCount(FetchDescriptor<Routine>())
        let folderCount: Int = try context.fetchCount(FetchDescriptor<RoutineFolder>())

        XCTAssertEqual(routineCount, 1)
        XCTAssertEqual(folderCount, 1)
        XCTAssertEqual(folder.routineIDs, [routine.id])
    }

    // MARK: - 18. Confirmar la eliminación

    func testDeletingAFolderDeletesTheContainedRoutines() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let first: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        let second: Routine = makeRoutine(name: "Tirón", sortOrder: 1, context: context)
        let outside: Routine = makeRoutine(name: "Piernas", sortOrder: 2, context: context)

        try RoutineFolderService.moveRoutine(first, to: folder, context: context)
        try RoutineFolderService.moveRoutine(second, to: folder, context: context)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        let summary: RoutineFolderService.DeletionSummary = try RoutineFolderService.deleteFolder(
            folder,
            containedRoutines: routines,
            context: context
        )

        XCTAssertEqual(summary.deletedRoutineCount, 2)
        XCTAssertEqual(summary.archivedRoutineCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 0)

        let remaining: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(remaining.map(\.id), [outside.id])
    }

    // MARK: - 19. Historial intacto al eliminar la carpeta

    func testDeletingAFolderKeepsSessionsAndSetLogs() throws {
        let context: ModelContext = try makeContext()
        let exercise: Exercise = Exercise(name: "Sentadilla", muscleGroup: .quads)
        context.insert(exercise)

        let folder: RoutineFolder = try makeFolder(named: "Pierna", context: context)
        let routine: Routine = makeRoutine(name: "Pierna", sortOrder: 0, context: context)
        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 3,
            targetRepsMin: 8,
            targetRepsMax: 10,
            sortOrder: 0
        )
        context.insert(link)
        routine.exercises = [link]
        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        let session: WorkoutSession = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            totalVolumeKg: 2_400.0,
            routineName: "Pierna"
        )
        context.insert(session)

        let log: WorkoutSetLog = WorkoutSetLog(
            date: Date(timeIntervalSince1970: 1_700_000_100),
            workoutStartDate: session.startDate,
            weight: 100.0,
            reps: 8,
            isCompleted: true,
            routineExerciseID: link.id,
            setNumber: 1,
            exercise: exercise,
            session: session
        )
        context.insert(log)
        session.setsCompleted = [log]
        try context.save()

        _ = try RoutineFolderService.deleteFolder(
            folder,
            containedRoutines: try context.fetch(FetchDescriptor<Routine>()),
            context: context
        )

        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        let logs: [WorkoutSetLog] = try context.fetch(FetchDescriptor<WorkoutSetLog>())

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.routineName, "Pierna")
        XCTAssertEqual(sessions.first?.totalVolumeKg, 2_400.0)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.weight, 100.0)
        XCTAssertEqual(logs.first?.reps, 8)

        // El ejercicio del catálogo tampoco se borra.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }

    /// Auditoría 07.1 §1: la eliminación de la carpeta no puede perder ni
    /// degradar ningún registro histórico, no solo el nombre de la rutina.
    func testDeletingAFolderKeepsEveryHistoricalRecordIntact() throws {
        let context: ModelContext = try makeContext()

        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(exercise)

        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let routine: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 2,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 0,
            defaultWeight: 82.5,
            restSeconds: 150,
            notes: "técnica"
        )
        context.insert(link)
        routine.exercises = [link]
        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        let start: Date = Date(timeIntervalSince1970: 1_700_000_000)
        let end: Date = start.addingTimeInterval(3_600)
        let session: WorkoutSession = WorkoutSession(
            startDate: start,
            endDate: end,
            totalVolumeKg: 1_980.0,
            routineName: "Empuje"
        )
        context.insert(session)

        let firstDate: Date = start.addingTimeInterval(120)
        let secondDate: Date = start.addingTimeInterval(420)

        let firstLog: WorkoutSetLog = WorkoutSetLog(
            date: firstDate,
            workoutStartDate: start,
            weight: 82.5,
            reps: 6,
            targetRepsMin: 6,
            targetRepsMax: 8,
            isCompleted: true,
            routineExerciseID: link.id,
            setNumber: 1,
            exercise: exercise,
            session: session
        )
        let secondLog: WorkoutSetLog = WorkoutSetLog(
            date: secondDate,
            workoutStartDate: start,
            weight: 82.5,
            reps: 6,
            targetRepsMin: 6,
            targetRepsMax: 8,
            isCompleted: true,
            routineExerciseID: link.id,
            setNumber: 2,
            exercise: exercise,
            session: session
        )
        context.insert(firstLog)
        context.insert(secondLog)
        session.setsCompleted = [firstLog, secondLog]
        session.bpmSamples = [
            BPMSample(timestamp: firstDate, bpm: 120.0),
            BPMSample(timestamp: secondDate, bpm: 128.0)
        ]
        session.exerciseRecords = WorkoutMetricsCalculator.buildExerciseRecords(for: session)
        try context.save()

        let sessionID: UUID = session.id
        let firstLogID: UUID = firstLog.id
        let secondLogID: UUID = secondLog.id
        let linkID: UUID = link.id
        let recordsData: Data = try XCTUnwrap(session.exerciseRecordsData)
        let bpmData: Data = try XCTUnwrap(session.bpmSamplesData)
        let storedRecords: [WorkoutExerciseRecord] = session.exerciseRecords

        XCTAssertFalse(recordsData.isEmpty)
        XCTAssertFalse(storedRecords.isEmpty)

        let summary: RoutineFolderService.DeletionSummary = try RoutineFolderService.deleteFolder(
            folder,
            containedRoutines: try context.fetch(FetchDescriptor<Routine>()),
            context: context
        )
        XCTAssertEqual(summary.deletedRoutineCount, 1)

        // Sesión: identidad, fechas, volumen, nombre y datos serializados.
        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        let restoredSession: WorkoutSession = try XCTUnwrap(sessions.first)
        XCTAssertEqual(restoredSession.id, sessionID)
        XCTAssertEqual(restoredSession.startDate, start)
        XCTAssertEqual(restoredSession.endDate, end)
        XCTAssertEqual(restoredSession.totalVolumeKg, 1_980.0)
        XCTAssertEqual(restoredSession.routineName, "Empuje")
        XCTAssertEqual(restoredSession.exerciseRecordsData, recordsData)
        XCTAssertEqual(restoredSession.bpmSamplesData, bpmData)
        XCTAssertEqual(restoredSession.bpmSamples.map(\.bpm), [120.0, 128.0])
        XCTAssertEqual(restoredSession.exerciseRecords.first?.sets.count, 2)
        XCTAssertEqual(restoredSession.exerciseRecords.first?.exerciseName, "Press banca")
        XCTAssertEqual(restoredSession.setsCompleted.count, 2)

        // Series: identidad, peso, repeticiones, fechas, objetivos y enlaces.
        let logs: [WorkoutSetLog] = try context.fetch(FetchDescriptor<WorkoutSetLog>())
        XCTAssertEqual(Set(logs.map(\.id)), Set([firstLogID, secondLogID]))

        let restoredFirst: WorkoutSetLog = try XCTUnwrap(logs.first { $0.id == firstLogID })
        XCTAssertEqual(restoredFirst.weight, 82.5)
        XCTAssertEqual(restoredFirst.reps, 6)
        XCTAssertEqual(restoredFirst.date, firstDate)
        XCTAssertEqual(restoredFirst.workoutStartDate, start)
        XCTAssertEqual(restoredFirst.targetRepsMin, 6)
        XCTAssertEqual(restoredFirst.targetRepsMax, 8)
        XCTAssertEqual(restoredFirst.setNumber, 1)
        XCTAssertEqual(restoredFirst.isCompleted, true)
        XCTAssertEqual(restoredFirst.exercise?.id, exercise.id)
        XCTAssertEqual(restoredFirst.session?.id, sessionID)
        // El enlace a la rutina eliminada se conserva como UUID; no se corrompe.
        XCTAssertEqual(restoredFirst.routineExerciseID, linkID)

        let restoredSecond: WorkoutSetLog = try XCTUnwrap(logs.first { $0.id == secondLogID })
        XCTAssertEqual(restoredSecond.setNumber, 2)
        XCTAssertEqual(restoredSecond.date, secondDate)
        XCTAssertEqual(restoredSecond.session?.id, sessionID)

        // Catálogo intacto y relación ejercicio ↔ series conservada.
        let exercises: [Exercise] = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises.first?.logs.count, 2)
    }

    // MARK: - 20. Rollback ante un error

    func testDeletingAFolderRollsBackWhenSavingFails() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let routine: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())

        XCTAssertThrowsError(
            try RoutineFolderService.deleteFolder(
                folder,
                containedRoutines: routines,
                context: context,
                save: { _ in false }
            )
        ) { error in
            XCTAssertEqual(error as? RoutineFolderError, .saveFailed)
        }

        // La base queda exactamente como estaba: carpeta, pertenencia y rutina.
        let foldersAfter: [RoutineFolder] = try context.fetch(FetchDescriptor<RoutineFolder>())
        let routinesAfter: [Routine] = try context.fetch(FetchDescriptor<Routine>())

        XCTAssertEqual(foldersAfter.count, 1)
        XCTAssertEqual(foldersAfter.first?.id, folder.id)
        XCTAssertEqual(foldersAfter.first?.routineIDs, [routine.id])
        XCTAssertEqual(routinesAfter.count, 1)
        XCTAssertEqual(routinesAfter.first?.id, routine.id)
        XCTAssertFalse(routinesAfter.first?.isArchived ?? true)
    }

    // MARK: - 21. Rutinas manuales

    func testManualRoutineCanBeMoved() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Manual", sortOrder: 0, source: .manual, context: context)
        let folder: RoutineFolder = try makeFolder(named: "Mis rutinas", context: context)

        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        XCTAssertEqual(try containingFolderID(of: routine, in: context), folder.id)
        XCTAssertEqual(routine.source, .manual)
    }

    // MARK: - 22. Rutinas automáticas

    func testAutomaticRoutineCanBeMoved() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Push", sortOrder: 0, source: .automatic, context: context)
        let folder: RoutineFolder = try makeFolder(named: "Split W/L/U", context: context)

        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        XCTAssertEqual(try containingFolderID(of: routine, in: context), folder.id)
        XCTAssertEqual(routine.source, .automatic)
        XCTAssertTrue(routine.isActivePlanRoutine)
    }

    // MARK: - 23. Rutinas asistidas

    func testAssistedRoutineCanBeMoved() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Lunes", sortOrder: 0, source: .assisted, context: context)
        let folder: RoutineFolder = try makeFolder(named: "Semana", context: context)

        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        XCTAssertEqual(try containingFolderID(of: routine, in: context), folder.id)
        XCTAssertEqual(routine.source, .assisted)
    }

    // MARK: - 24. Las rutinas nuevas aparecen sin carpeta

    func testNewRoutinesAreCreatedWithoutFolder() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let inside: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        try RoutineFolderService.moveRoutine(inside, to: folder, context: context)

        let draft: Routine = RoutineService.makeManualDraftRoutine(after: [inside])

        XCTAssertNil(try containingFolderID(of: draft, in: context))
        XCTAssertGreaterThan(draft.sortOrder, inside.sortOrder)
    }

    // MARK: - 25. El botón «+» sigue creando rutinas

    func testPlusStillCreatesALooseRoutineThatAppearsInTheMainList() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)
        let inside: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        try RoutineFolderService.moveRoutine(inside, to: folder, context: context)

        let active: [Routine] = [inside]
        let draft: Routine = RoutineService.makeManualDraftRoutine(after: active)
        context.insert(draft)
        try context.save()

        XCTAssertTrue(draft.isActivePlanRoutine)
        XCTAssertNil(try containingFolderID(of: draft, in: context))

        let rows: [RoutineListRow] = RoutineFolderService.mainRows(
            folders: [folder],
            activeRoutines: [inside, draft]
        )
        XCTAssertTrue(rows.map(\.identifier).contains("routine:\(draft.id.uuidString)"))
    }

    // MARK: - 26. El gesto hacia la derecha sigue eliminando

    func testRightSwipeKeepsTheExistingDeletionRules() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)

        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: 140.0, vertical: 6.0),
            .deleteRoutine
        )
        XCTAssertEqual(
            RoutineService.deletionPolicy(for: routine, context: context),
            .delete
        )

        // Referenciada por un plan asistido: se archiva, no se borra.
        let plan: AssistedWeekPlan = AssistedWeekPlan(days: [
            AssistedWeekDayRecord(
                weekdayIndex: 0,
                isRest: false,
                routineID: routine.id,
                routineName: routine.name,
                variantSuffix: "",
                sessionIndex: 0
            )
        ])
        context.insert(plan)
        try context.save()

        XCTAssertEqual(
            RoutineService.deletionPolicy(for: routine, context: context),
            .archiveReferenced
        )
    }

    // MARK: - 27. El gesto hacia la izquierda abre el movimiento

    func testLeftSwipeOpensTheMoveFlow() throws {
        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: -140.0, vertical: 6.0),
            .moveToFolder
        )
        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: -40.0, vertical: 0.0),
            .none
        )
        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: -140.0, vertical: 300.0),
            .none
        )
    }

    // MARK: - 28. El umbral del deslizamiento es exactamente la distancia guardada

    func testTheSwipeThresholdRequiresCrossingTheStoredDistance() {
        XCTAssertEqual(RoutineFolderService.swipeThreshold, 120.0)

        // Sin alcanzar el umbral no se ejecuta ninguna acción, en ninguna dirección.
        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: 119.9, vertical: 0.0),
            .none
        )
        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: -119.9, vertical: 0.0),
            .none
        )

        // Justo en el umbral, cada dirección mantiene su acción.
        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: 120.0, vertical: 0.0),
            .deleteRoutine
        )
        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: -120.0, vertical: 0.0),
            .moveToFolder
        )
    }

    // MARK: - 29. Un gesto vertical nunca se interpreta como deslizamiento

    func testAVerticalGestureNeverProducesASwipeAction() {
        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: 0.0, vertical: 200.0),
            .none
        )
        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: 200.0, vertical: -260.0),
            .none
        )
        XCTAssertEqual(
            RoutineFolderService.swipeAction(horizontal: -200.0, vertical: 260.0),
            .none
        )
    }

    // MARK: - Nombres

    func testFolderNamesCannotBeEmptyOrOnlySpaces() throws {
        let context: ModelContext = try makeContext()

        XCTAssertThrowsError(
            try RoutineFolderService.createFolder(named: "   ", existingFolders: [], context: context)
        ) { error in
            XCTAssertEqual(error as? RoutineFolderError, .emptyName)
        }

        XCTAssertFalse(RoutineFolderService.isNameAvailable("", in: []))
        XCTAssertFalse(RoutineFolderService.isNameAvailable("   ", in: []))
    }

    func testDuplicateFolderNamesAreRejected() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)

        XCTAssertThrowsError(
            try RoutineFolderService.createFolder(
                named: " fuerza ",
                existingFolders: [folder],
                context: context
            )
        ) { error in
            XCTAssertEqual(error as? RoutineFolderError, .duplicateName)
        }

        // Renombrar a su propio nombre no es un duplicado.
        try RoutineFolderService.renameFolder(
            folder,
            to: "Fuerza",
            existingFolders: [folder],
            context: context
        )
    }

    // MARK: - Auditoría 07.1 §2 · contador de rutinas

    func testFolderCounterOnlyCountsActiveVisibleRoutines() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Fuerza", context: context)

        let active: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        let second: Routine = makeRoutine(name: "Tirón", sortOrder: 1, context: context)
        let archived: Routine = makeRoutine(name: "Antigua", sortOrder: 2, context: context)
        let freeWorkout: Routine = Routine(name: "ENTRENO LIBRE", isTemplate: false, sortOrder: 3)

        archived.isArchived = true
        context.insert(freeWorkout)
        try RoutineFolderService.moveRoutine(active, to: folder, context: context)
        try RoutineFolderService.moveRoutine(second, to: folder, context: context)

        // Datos heredados: la pertenencia puede contener rutinas ya archivadas
        // o la rutina contenedora del entreno libre. Ninguna debe contar.
        XCTAssertTrue(folder.add(routineID: archived.id))
        XCTAssertTrue(folder.add(routineID: freeWorkout.id))
        try context.save()

        let allRoutines: [Routine] = [active, second, archived, freeWorkout]

        XCTAssertEqual(RoutineFolderService.activeRoutineCount(in: folder, routines: allRoutines), 2)
        XCTAssertEqual(
            RoutineFolderService.routines(in: folder, from: allRoutines.filter(\.isActivePlanRoutine)).count,
            2
        )
        XCTAssertTrue(
            RoutineFolderService.requiresDeletionConfirmation(for: folder, routines: allRoutines)
        )
    }

    func testFolderWithOnlyArchivedRoutinesShowsZeroAndNeedsNoConfirmation() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Archivo", context: context)
        let archived: Routine = makeRoutine(name: "Antigua", sortOrder: 0, context: context)
        archived.isArchived = true
        try context.save()

        XCTAssertTrue(folder.add(routineID: archived.id))
        try context.save()

        let allRoutines: [Routine] = [archived]

        XCTAssertEqual(RoutineFolderService.activeRoutineCount(in: folder, routines: allRoutines), 0)
        XCTAssertFalse(
            RoutineFolderService.requiresDeletionConfirmation(for: folder, routines: allRoutines)
        )

        let summary: RoutineFolderService.DeletionSummary = try RoutineFolderService.deleteFolder(
            folder,
            containedRoutines: allRoutines,
            context: context
        )

        XCTAssertEqual(summary.removedRoutineCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 0)
    }

    /// Las rutinas archivadas no se borran ni se modifican al eliminar su
    /// carpeta: conservan su estado y su historial.
    func testArchivedRoutinesAreNotDeletedWhenTheirFolderIsDeleted() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Mixta", context: context)
        let active: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: context)
        let archived: Routine = makeRoutine(name: "Antigua", sortOrder: 1, context: context)
        archived.isArchived = true
        try context.save()

        try RoutineFolderService.moveRoutine(active, to: folder, context: context)
        XCTAssertTrue(folder.add(routineID: archived.id))
        try context.save()

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        let summary: RoutineFolderService.DeletionSummary = try RoutineFolderService.deleteFolder(
            folder,
            containedRoutines: routines,
            context: context
        )

        XCTAssertEqual(summary.deletedRoutineCount, 1)
        XCTAssertEqual(summary.archivedRoutineCount, 0)

        let remaining: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, archived.id)
        XCTAssertEqual(remaining.first?.isArchived, true)
    }

    // MARK: - Migración V5 → V6

    func testMigrationFromV5KeepsRoutinesSessionsAndLogs() throws {
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL: URL = directory.appendingPathComponent("default.store")

        let routineID: UUID
        let sessionID: UUID
        let logID: UUID

        do {
            let schema: Schema = Schema(versionedSchema: AppSchemaV5.self)
            let configuration: ModelConfiguration = ModelConfiguration(url: storeURL)
            let container: ModelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            let context: ModelContext = ModelContext(container)

            let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
            context.insert(exercise)

            let routine: Routine = Routine(
                name: "Rutina anterior",
                isTemplate: true,
                sortOrder: 2,
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
                restSeconds: 150
            )
            context.insert(link)
            routine.exercises = [link]

            let session: WorkoutSession = WorkoutSession(
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600),
                totalVolumeKg: 1_600.0,
                routineName: routine.name
            )
            context.insert(session)

            let log: WorkoutSetLog = WorkoutSetLog(
                date: Date(timeIntervalSince1970: 1_700_000_120),
                workoutStartDate: session.startDate,
                weight: 80.0,
                reps: 5,
                isCompleted: true,
                routineExerciseID: link.id,
                setNumber: 1,
                exercise: exercise,
                session: session
            )
            context.insert(log)
            session.setsCompleted = [log]

            try context.save()

            routineID = routine.id
            sessionID = session.id
            logID = log.id
        }

        let outcome: StoreBootstrap.Outcome = StoreBootstrap.makeContainer(storeURL: storeURL)
        let container: ModelContainer = try XCTUnwrap(outcome.container)
        let context: ModelContext = ModelContext(container)

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        let routine: Routine = try XCTUnwrap(routines.first)

        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routine.id, routineID)
        XCTAssertEqual(routine.name, "Rutina anterior")
        XCTAssertEqual(routine.sortOrder, 2)
        XCTAssertTrue(routine.isActivePlanRoutine)
        XCTAssertEqual(routine.exercises.count, 1)

        // Ninguna rutina heredada pertenece a una carpeta.
        XCTAssertTrue(try context.fetch(FetchDescriptor<RoutineFolder>()).isEmpty)
        XCTAssertTrue(
            RoutineFolderService.looseRoutines(
                from: routines,
                folders: try context.fetch(FetchDescriptor<RoutineFolder>())
            ).map(\.id) == [routineID]
        )

        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        let session: WorkoutSession = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.id, sessionID)
        XCTAssertEqual(session.totalVolumeKg, 1_600.0)
        XCTAssertEqual(session.routineName, "Rutina anterior")

        let logs: [WorkoutSetLog] = try context.fetch(FetchDescriptor<WorkoutSetLog>())
        let log: WorkoutSetLog = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.id, logID)
        XCTAssertEqual(log.weight, 80.0)
        XCTAssertEqual(log.reps, 5)
        XCTAssertEqual(log.session?.id, sessionID)
        XCTAssertEqual(log.exercise?.name, "Press banca")
    }

    // MARK: - Copias de seguridad

    func testBackupRoundTripKeepsFoldersMembershipAndOrder() throws {
        let source: ModelContext = try makeContext()
        let first: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: source)
        let second: Routine = makeRoutine(name: "Tirón", sortOrder: 1, context: source)
        let loose: Routine = makeRoutine(name: "Piernas", sortOrder: 2, context: source)

        let folder: RoutineFolder = try RoutineFolderService.createFolder(
            named: "Fuerza",
            existingFolders: [],
            context: source
        )
        try RoutineFolderService.moveRoutine(first, to: folder, context: source)
        try RoutineFolderService.moveRoutine(second, to: folder, context: source)

        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url: URL = directory.appendingPathComponent("copia.json")

        let exported: BackupExportResult = try BackupManager.createBackup(context: source)
        try exported.document.data.write(to: url)

        let target: ModelContext = try makeContext()
        try BackupManager.restoreBackup(
            from: url,
            context: target,
            safetyCopyDirectory: try makeDirectory(
                at: directory.appendingPathComponent("copias", isDirectory: true)
            )
        )

        let folders: [RoutineFolder] = try target.fetch(FetchDescriptor<RoutineFolder>())
        let routines: [Routine] = try target.fetch(FetchDescriptor<Routine>())
        let restored: RoutineFolder = try XCTUnwrap(folders.first)

        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(restored.id, folder.id)
        XCTAssertEqual(restored.name, "Fuerza")
        XCTAssertEqual(restored.sortOrder, folder.sortOrder)
        XCTAssertEqual(routines.count, 3)
        XCTAssertEqual(Set(routines.map(\.id)), Set([first.id, second.id, loose.id]))

        XCTAssertEqual(
            RoutineFolderService.routines(in: restored, from: routines).map(\.id),
            [first.id, second.id]
        )
        XCTAssertTrue(
            RoutineFolderService.looseRoutines(from: routines, folders: folders)
                .map(\.id)
                .contains(loose.id)
        )
    }

    func testBackupExportWritesFolderNamesAndRoutineFolderIDs() throws {
        let source: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(name: "Empuje", sortOrder: 0, context: source)
        let folder: RoutineFolder = try RoutineFolderService.createFolder(
            named: "Fuerza",
            existingFolders: [],
            context: source
        )
        try RoutineFolderService.moveRoutine(routine, to: folder, context: source)

        let exported: BackupExportResult = try BackupManager.createBackup(context: source)
        let decoded: AppBackupData = try makeDecoder().decode(
            AppBackupData.self,
            from: exported.document.data
        )

        let folders: [RoutineFolderBackupDTO] = try XCTUnwrap(decoded.folders)
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.id, folder.id)
        XCTAssertEqual(folders.first?.name, "Fuerza")
        XCTAssertEqual(folders.first?.sortOrder, folder.sortOrder)
        XCTAssertEqual(decoded.routines.first?.folderID, folder.id)
    }

    func testImportingLegacyBackupWithoutFolderFieldsLeavesRoutinesLoose() throws {
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let backup: AppBackupData = AppBackupData(
            version: AppBackupData.currentVersion,
            exportDate: Date(timeIntervalSince1970: 1_700_000_000),
            routines: [
                RoutineBackupDTO(
                    id: UUID(),
                    name: "Rutina antigua",
                    isTemplate: true,
                    sortOrder: 0,
                    source: "manual",
                    exercises: []
                )
            ],
            sessions: [],
            settings: makeBackupSettings(),
            assistedWeeks: nil
        )

        let url: URL = directory.appendingPathComponent("antigua.json")
        try makeEncoder().encode(backup).write(to: url)

        let target: ModelContext = try makeContext()
        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: target)
        XCTAssertTrue(plan.report.canImport)

        try BackupManager.restoreBackup(
            using: plan,
            context: target,
            safetyCopyDirectory: try makeDirectory(
                at: directory.appendingPathComponent("copias", isDirectory: true)
            )
        )

        XCTAssertTrue(try target.fetch(FetchDescriptor<RoutineFolder>()).isEmpty)
        let routines: [Routine] = try target.fetch(FetchDescriptor<Routine>())
        XCTAssertEqual(routines.count, 1)
    }

    func testImportingBackupWithUnknownFolderReferenceLeavesRoutineLoose() throws {
        let directory: URL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let routineID: UUID = UUID()
        let unknownFolderID: UUID = UUID()

        let backup: AppBackupData = AppBackupData(
            version: AppBackupData.currentVersion,
            exportDate: Date(timeIntervalSince1970: 1_700_000_000),
            routines: [
                RoutineBackupDTO(
                    id: routineID,
                    name: "Rutina huérfana",
                    isTemplate: true,
                    sortOrder: 0,
                    source: "manual",
                    exercises: [],
                    folderID: unknownFolderID
                )
            ],
            sessions: [],
            settings: makeBackupSettings(),
            assistedWeeks: nil,
            folders: [
                RoutineFolderBackupDTO(id: UUID(), name: "Fuerza", sortOrder: 0)
            ]
        )

        let url: URL = directory.appendingPathComponent("huerfana.json")
        try makeEncoder().encode(backup).write(to: url)

        let target: ModelContext = try makeContext()
        let plan: BackupImportPlan = try BackupManager.prepareImport(from: url, context: target)

        // Se avisa pero no se bloquea: la rutina se restaura sin carpeta.
        XCTAssertTrue(plan.report.canImport)
        XCTAssertFalse(plan.report.warnings.isEmpty)

        try BackupManager.restoreBackup(
            using: plan,
            context: target,
            safetyCopyDirectory: try makeDirectory(
                at: directory.appendingPathComponent("copias", isDirectory: true)
            )
        )

        let folders: [RoutineFolder] = try target.fetch(FetchDescriptor<RoutineFolder>())
        let routines: [Routine] = try target.fetch(FetchDescriptor<Routine>())

        XCTAssertEqual(folders.count, 1)
        XCTAssertTrue(folders.first?.routineIDs.isEmpty ?? false)
        XCTAssertEqual(routines.count, 1)
        XCTAssertEqual(routines.first?.id, routineID)

        let rows: [RoutineListRow] = RoutineFolderService.mainRows(
            folders: folders,
            activeRoutines: routines
        )
        XCTAssertTrue(rows.map(\.identifier).contains("routine:\(routineID.uuidString)"))
        XCTAssertFalse(rows.map(\.identifier).contains("folder:\(unknownFolderID.uuidString)"))
    }

    // MARK: - Utilidades

    private func containingFolderID(
        of routine: Routine,
        in context: ModelContext
    ) throws -> UUID? {
        let folders: [RoutineFolder] = try context.fetch(FetchDescriptor<RoutineFolder>())
        return RoutineFolderService.folder(containing: routine, from: folders)?.id
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

    @discardableResult
    private func makeRoutine(
        name: String,
        sortOrder: Int,
        source: RoutineSource = .manual,
        context: ModelContext
    ) -> Routine {
        let routine: Routine = Routine(
            name: name,
            isTemplate: true,
            sortOrder: sortOrder,
            exercises: [],
            source: source
        )
        context.insert(routine)
        return routine
    }

    private func makeFolder(named name: String, context: ModelContext) throws -> RoutineFolder {
        let existing: [RoutineFolder] = try context.fetch(FetchDescriptor<RoutineFolder>())
        return try RoutineFolderService.createFolder(
            named: name,
            existingFolders: existing,
            context: context
        )
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder: JSONDecoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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

    private func makeTemporaryDirectory() throws -> URL {
        let directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppGymFolderTests-\(UUID().uuidString)", isDirectory: true)
        try makeDirectory(at: directory)
        return directory
    }

    @discardableResult
    private func makeDirectory(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}
