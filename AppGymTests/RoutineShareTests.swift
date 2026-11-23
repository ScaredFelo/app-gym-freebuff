import XCTest
import Foundation
import SwiftData

@testable import AppGym

/// Pruebas del archivo `.appgymroutine` que genera el selector de
/// Configuración → Compartir rutina.
///
/// El selector en sí es interfaz; lo que se comprueba aquí es el contrato del
/// archivo y que compartir no modifica la rutina, su carpeta ni el historial.
@MainActor
final class RoutineShareTests: XCTestCase {

    func testShareFileContainsTheRoutineDefinitionWithoutHistory() throws {
        let context: ModelContext = try makeContext()

        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        context.insert(exercise)

        let routine: Routine = Routine(
            name: "Empuje",
            isTemplate: true,
            sortOrder: 0,
            exercises: [],
            source: .manual
        )
        context.insert(routine)

        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 0,
            defaultWeight: 60.0,
            restSeconds: 150,
            notes: "técnica"
        )
        context.insert(link)
        routine.exercises = [link]

        let session: WorkoutSession = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalVolumeKg: 1_200.0,
            routineName: routine.name
        )
        context.insert(session)

        let log: WorkoutSetLog = WorkoutSetLog(
            date: Date(timeIntervalSince1970: 1_700_000_120),
            weight: 60.0,
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

        let file: RoutineShareFile = try RoutineShareService.makeFile(for: routine)
        defer { try? FileManager.default.removeItem(at: file.url) }

        XCTAssertEqual(file.url.pathExtension, "appgymroutine")
        XCTAssertEqual(file.url.lastPathComponent.lowercased().hasSuffix(".appgymroutine"), true)

        let data: Data = try Data(contentsOf: file.url)
        let raw: String = String(decoding: data, as: UTF8.self)

        // Sin historial personal: ni sesiones, ni series registradas, ni BPM.
        XCTAssertFalse(raw.contains("sessions"))
        XCTAssertFalse(raw.contains("setsCompleted"))
        XCTAssertFalse(raw.contains("bpmSamples"))
        XCTAssertFalse(raw.contains("totalVolumeKg"))
        XCTAssertFalse(raw.contains("startDate"))

        let decoder: JSONDecoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: RoutineSharePayload = try decoder.decode(RoutineSharePayload.self, from: data)

        XCTAssertEqual(payload.format, "appgym.routine")
        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(payload.routine.id, routine.id)
        XCTAssertEqual(payload.routine.name, "Empuje")
        XCTAssertEqual(payload.routine.source, RoutineSource.manual.rawValue)
        XCTAssertEqual(payload.routine.exercises.count, 1)

        let shared: RoutineShareExercise = try XCTUnwrap(payload.routine.exercises.first)
        XCTAssertEqual(shared.name, "Press banca")
        XCTAssertEqual(shared.muscleGroupRaw, MuscleGroup.chest.rawValue)
        XCTAssertEqual(shared.sets, 4)
        XCTAssertEqual(shared.repsMin, 6)
        XCTAssertEqual(shared.repsMax, 8)
        XCTAssertEqual(shared.restSeconds, 150)
        XCTAssertEqual(shared.targetWeight, 60.0)
        XCTAssertEqual(shared.notes, "técnica")
    }

    func testSharingDoesNotModifyTheRoutineItsFolderOrTheHistory() throws {
        let context: ModelContext = try makeContext()

        let exercise: Exercise = Exercise(name: "Sentadilla", muscleGroup: .quads)
        context.insert(exercise)

        let routine: Routine = Routine(
            name: "Pierna",
            isTemplate: true,
            sortOrder: 3,
            exercises: [],
            source: .manual
        )
        context.insert(routine)

        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 3,
            targetRepsMin: 8,
            targetRepsMax: 10,
            sortOrder: 0
        )
        context.insert(link)
        routine.exercises = [link]

        let folder: RoutineFolder = try RoutineFolderService.createFolder(
            named: "Fuerza",
            existingFolders: [],
            context: context
        )
        try RoutineFolderService.moveRoutine(routine, to: folder, context: context)

        let session: WorkoutSession = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            totalVolumeKg: 2_400.0,
            routineName: "Pierna"
        )
        context.insert(session)
        try context.save()

        let routineID: UUID = routine.id
        let linkID: UUID = link.id
        let routineSortOrder: Int = routine.sortOrder
        let folderIDs: [UUID] = folder.routineIDs
        let folderName: String = folder.name

        let file: RoutineShareFile = try RoutineShareService.makeFile(for: routine)
        defer { try? FileManager.default.removeItem(at: file.url) }

        XCTAssertEqual(routine.id, routineID)
        XCTAssertEqual(routine.name, "Pierna")
        XCTAssertEqual(routine.sortOrder, routineSortOrder)
        XCTAssertEqual(routine.exercises.count, 1)
        XCTAssertEqual(routine.exercises.first?.id, linkID)
        XCTAssertEqual(folder.routineIDs, folderIDs)
        XCTAssertEqual(folder.name, folderName)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSetLog>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }

    func testShareFileNameIsSafeAndEndsWithTheExpectedExtension() throws {
        let context: ModelContext = try makeContext()
        let routine: Routine = Routine(
            name: "Empuje / Tirón: ¿pierna?",
            isTemplate: true,
            sortOrder: 0,
            exercises: [],
            source: .manual
        )
        context.insert(routine)

        let name: String = RoutineShareService.fileName(
            for: routine,
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(name.hasSuffix(".appgymroutine"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("?"))
        XCTAssertFalse(name.contains("¿"))
    }

    // MARK: - Rutinas individuales vacías

    /// Una rutina sin ejercicios se puede compartir y volver a importar: el
    /// destinatario decide qué ejercicios le añade después.
    func testEmptyRoutineCanBeExportedAndImported() throws {
        let sender: ModelContext = try makeContext()
        let routine: Routine = Routine(
            name: "Vacía",
            isTemplate: true,
            sortOrder: 0,
            exercises: [],
            source: .manual
        )
        sender.insert(routine)
        try sender.save()

        let file: RoutineShareFile = try RoutineShareService.makeFile(for: routine)
        defer { try? FileManager.default.removeItem(at: file.url) }

        let request: RoutineImportRequest = try RoutineImportService.makeRequest(fromFileAt: file.url)

        XCTAssertEqual(request.routineName, "Vacía")
        XCTAssertEqual(request.exerciseCount, 0)

        let receiver: ModelContext = try makeContext()
        let imported: Routine = try RoutineImportService.importRoutine(request, into: receiver)

        XCTAssertEqual(imported.name, "Vacía")
        XCTAssertTrue(imported.exercises.isEmpty)
        XCTAssertTrue(imported.isActivePlanRoutine)
        XCTAssertEqual(imported.source, .manual)
        // La identidad es nueva: el UUID del emisor no se reutiliza.
        XCTAssertNotEqual(imported.id, routine.id)
        XCTAssertEqual(try receiver.fetchCount(FetchDescriptor<Routine>()), 1)
        XCTAssertEqual(try receiver.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try receiver.fetchCount(FetchDescriptor<RoutineExercise>()), 0)
    }

    /// El caso con ejercicios sigue funcionando igual de extremo a extremo.
    func testRoutineWithExercisesSurvivesExportAndImport() throws {
        let sender: ModelContext = try makeContext()

        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest)
        sender.insert(exercise)

        let routine: Routine = Routine(
            name: "Empuje",
            isTemplate: true,
            sortOrder: 0,
            exercises: [],
            source: .manual
        )
        sender.insert(routine)

        let link: RoutineExercise = RoutineExercise(
            exercise: exercise,
            defaultSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: 0,
            defaultWeight: 60.0,
            restSeconds: 150
        )
        sender.insert(link)
        routine.exercises = [link]
        try sender.save()

        let file: RoutineShareFile = try RoutineShareService.makeFile(for: routine)
        defer { try? FileManager.default.removeItem(at: file.url) }

        let request: RoutineImportRequest = try RoutineImportService.makeRequest(fromFileAt: file.url)
        XCTAssertEqual(request.exerciseCount, 1)

        let receiver: ModelContext = try makeContext()
        let imported: Routine = try RoutineImportService.importRoutine(request, into: receiver)

        XCTAssertEqual(imported.name, "Empuje")
        XCTAssertEqual(imported.exercises.count, 1)

        let importedLink: RoutineExercise = try XCTUnwrap(imported.exercises.first)
        XCTAssertEqual(importedLink.exercise?.name, "Press banca")
        XCTAssertEqual(importedLink.defaultSets, 4)
        XCTAssertEqual(importedLink.targetRepsMin, 6)
        XCTAssertEqual(importedLink.targetRepsMax, 8)
        XCTAssertEqual(importedLink.restSeconds, 150)
        XCTAssertEqual(try receiver.fetchCount(FetchDescriptor<RoutineExercise>()), 1)
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
}
