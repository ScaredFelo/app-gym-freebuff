import XCTest
import Foundation
import SwiftData

@testable import AppGym

/// Pruebas del selector múltiple de splits (Prompt 09.2).
///
/// Cubren el estado del selector (carpetas contraídas, despliegue múltiple,
/// casilla de carpeta con estado intermedio, selección entre orígenes), el
/// orden determinista de exportación y la reutilización del flujo de
/// importación existente. No son pruebas de interfaz: el estado de selección
/// vive en `SplitShareSelectorState`, que es código puro.
@MainActor
final class SplitShareSelectionTests: XCTestCase {

    // MARK: - Selector

    func testPickerListsFoldersWithActiveRoutinesAndIndependentRoutines() throws {
        let context: ModelContext = try makeContext()
        let pushFolder: RoutineFolder = try makeFolder(named: "Empuje", context: context)
        let legsFolder: RoutineFolder = try makeFolder(named: "Pierna", context: context)
        _ = try makeFolder(named: "Vacía", context: context)

        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let legs: Routine = makeRoutine(named: "LEGS", sortOrder: 1, context: context)
        let upper: Routine = makeRoutine(named: "UPPER", sortOrder: 2, context: context)
        let archived: Routine = makeRoutine(named: "OLD", sortOrder: 3, archived: true, context: context)
        let free: Routine = makeRoutine(named: "LIBRE", sortOrder: 4, isTemplate: false, context: context)
        pushFolder.routineIDs = [push.id, archived.id]
        legsFolder.routineIDs = [legs.id, free.id]
        try context.save()

        let routines: [Routine] = allRoutines(context)
        let folders: [RoutineFolder] = RoutineSplitShareService.exportableFolders(
            try context.fetch(FetchDescriptor<RoutineFolder>()),
            routines: routines
        )

        XCTAssertEqual(folders.map(\.name), ["Empuje", "Pierna"])
        XCTAssertEqual(
            RoutineSplitShareService.looseActiveRoutines(folders: folders, routines: routines).map(\.name),
            ["UPPER"]
        )
    }

    func testFoldersStartCollapsedAndExpandIndependently() throws {
        let context: ModelContext = try makeContext()
        let pushFolder: RoutineFolder = try makeFolder(named: "Empuje", context: context)
        let legsFolder: RoutineFolder = try makeFolder(named: "Pierna", context: context)
        try context.save()

        var state: SplitShareSelectorState = SplitShareSelectorState()
        XCTAssertFalse(state.isExpanded(pushFolder.id))
        XCTAssertFalse(state.isExpanded(legsFolder.id))

        state.toggleExpansion(pushFolder.id)
        state.toggleExpansion(legsFolder.id)
        XCTAssertTrue(state.isExpanded(pushFolder.id))
        XCTAssertTrue(state.isExpanded(legsFolder.id))

        state.toggleExpansion(pushFolder.id)
        XCTAssertFalse(state.isExpanded(pushFolder.id))
        XCTAssertTrue(state.isExpanded(legsFolder.id))
    }

    func testSelectingRoutinesFromDifferentOriginsBuildsOneSplit() throws {
        let context: ModelContext = try makeContext()
        let pushFolder: RoutineFolder = try makeFolder(named: "Empuje", context: context)
        let legsFolder: RoutineFolder = try makeFolder(named: "Pierna", context: context)

        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let legs: Routine = makeRoutine(named: "LEGS", sortOrder: 1, context: context)
        let upper: Routine = makeRoutine(named: "UPPER", sortOrder: 2, context: context)
        pushFolder.routineIDs = [push.id]
        legsFolder.routineIDs = [legs.id]
        try context.save()

        var state: SplitShareSelectorState = SplitShareSelectorState()
        state.toggleRoutine(upper)
        state.toggleRoutine(legs)
        state.toggleRoutine(push)

        XCTAssertEqual(state.selectedCount, 3)
        XCTAssertTrue(state.canShare)

        let ordered: [Routine] = RoutineSplitShareService.selectedRoutines(
            state,
            folders: [pushFolder, legsFolder],
            routines: allRoutines(context)
        )
        XCTAssertEqual(ordered.map(\.name), ["PUSH", "LEGS", "UPPER"])
    }

    func testSelectingAFolderMarksAllItsActiveRoutines() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Empuje", context: context)
        let first: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let second: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: context)
        let archived: Routine = makeRoutine(named: "OLD", sortOrder: 2, archived: true, context: context)
        let loose: Routine = makeRoutine(named: "UPPER", sortOrder: 3, context: context)
        folder.routineIDs = [first.id, second.id, archived.id]
        try context.save()

        let routines: [Routine] = allRoutines(context)
        var state: SplitShareSelectorState = SplitShareSelectorState()
        state.toggleFolder(folder, routines: routines)

        XCTAssertEqual(state.folderState(folder, routines: routines), .all)
        XCTAssertEqual(state.selectedCount, 2)
        XCTAssertTrue(state.contains(first.id))
        XCTAssertTrue(state.contains(second.id))
        XCTAssertFalse(state.contains(archived.id))
        XCTAssertFalse(state.contains(loose.id))
    }

    func testUncheckingOneRoutineLeavesTheFolderPartiallySelected() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Empuje", context: context)
        let first: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let second: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: context)
        folder.routineIDs = [first.id, second.id]
        try context.save()

        let routines: [Routine] = allRoutines(context)
        var state: SplitShareSelectorState = SplitShareSelectorState()
        state.toggleFolder(folder, routines: routines)
        state.toggleRoutine(first)

        XCTAssertEqual(state.folderState(folder, routines: routines), .partial)
        XCTAssertEqual(state.selectedCount, 1)

        // Volver a marcar la carpeta selecciona otra vez todas sus rutinas.
        state.toggleFolder(folder, routines: routines)
        XCTAssertEqual(state.folderState(folder, routines: routines), .all)
        XCTAssertTrue(state.contains(first.id))
    }

    func testUncheckingACompleteFolderClearsItsRoutines() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Empuje", context: context)
        let first: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let second: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: context)
        folder.routineIDs = [first.id, second.id]
        try context.save()

        let routines: [Routine] = allRoutines(context)
        var state: SplitShareSelectorState = SplitShareSelectorState()
        state.toggleFolder(folder, routines: routines)
        state.toggleFolder(folder, routines: routines)

        XCTAssertEqual(state.folderState(folder, routines: routines), .none)
        XCTAssertEqual(state.selectedCount, 0)
    }

    func testSelectionSurvivesCollapsingAndExpandingFolders() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Empuje", context: context)
        let routine: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        folder.routineIDs = [routine.id]
        try context.save()

        var state: SplitShareSelectorState = SplitShareSelectorState()
        state.toggleExpansion(folder.id)
        state.toggleRoutine(routine)
        state.toggleExpansion(folder.id)

        XCTAssertFalse(state.isExpanded(folder.id))
        XCTAssertTrue(state.contains(routine.id))

        state.toggleExpansion(folder.id)
        XCTAssertTrue(state.contains(routine.id))
    }

    func testDeselectingAllClearsTheSelection() throws {
        let context: ModelContext = try makeContext()
        let first: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let second: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: context)

        var state: SplitShareSelectorState = SplitShareSelectorState()
        state.toggleRoutine(first)
        state.toggleRoutine(second)
        XCTAssertEqual(state.selectedCount, 2)

        state.deselectAll()

        XCTAssertEqual(state.selectedCount, 0)
        XCTAssertTrue(state.isEmpty)
        XCTAssertFalse(state.canShare)
    }

    func testSharingRequiresAtLeastTwoRoutines() throws {
        let context: ModelContext = try makeContext()
        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let pull: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: context)

        var state: SplitShareSelectorState = SplitShareSelectorState()
        XCTAssertFalse(state.canShare)

        state.toggleRoutine(push)
        XCTAssertFalse(state.canShare)

        XCTAssertThrowsError(try RoutineSplitShareService.payload(for: [push])) { error in
            XCTAssertEqual(error as? RoutineSplitShareError, .notEnoughRoutines)
        }

        state.toggleRoutine(pull)
        XCTAssertTrue(state.canShare)
    }

    func testArchivedAndFreeWorkoutRoutinesCannotBeSelected() throws {
        let context: ModelContext = try makeContext()
        let archived: Routine = makeRoutine(named: "OLD", sortOrder: 0, archived: true, context: context)
        let free: Routine = makeRoutine(named: "LIBRE", sortOrder: 1, isTemplate: false, context: context)

        var state: SplitShareSelectorState = SplitShareSelectorState()
        state.toggleRoutine(archived)
        state.toggleRoutine(free)

        XCTAssertEqual(state.selectedCount, 0)
        XCTAssertTrue(
            RoutineSplitShareService.selectedRoutines(
                state,
                folders: [],
                routines: allRoutines(context)
            ).isEmpty
        )
    }

    // MARK: - Orden y exportación

    func testExportFollowsFolderAndRoutineOrderNotSelectionOrder() throws {
        let context: ModelContext = try makeContext()
        let second: RoutineFolder = try makeFolder(named: "Segunda", sortOrder: 5, context: context)
        let first: RoutineFolder = try makeFolder(named: "Primera", sortOrder: 1, context: context)

        let firstA: Routine = makeRoutine(named: "A1", sortOrder: 2, context: context)
        let firstB: Routine = makeRoutine(named: "A2", sortOrder: 1, context: context)
        let secondA: Routine = makeRoutine(named: "B1", sortOrder: 0, context: context)
        let loose: Routine = makeRoutine(named: "SUELTA", sortOrder: 3, context: context)
        first.routineIDs = [firstA.id, firstB.id]
        second.routineIDs = [secondA.id]
        try context.save()

        let routines: [Routine] = allRoutines(context)

        var forward: SplitShareSelectorState = SplitShareSelectorState()
        forward.toggleRoutine(firstB)
        forward.toggleRoutine(firstA)
        forward.toggleRoutine(secondA)
        forward.toggleRoutine(loose)

        var reverse: SplitShareSelectorState = SplitShareSelectorState()
        reverse.toggleRoutine(loose)
        reverse.toggleRoutine(secondA)
        reverse.toggleRoutine(firstA)
        reverse.toggleRoutine(firstB)

        XCTAssertEqual(forward.selectedRoutineIDs, reverse.selectedRoutineIDs)

        // Las carpetas se pasan desordenadas a propósito: manda su sortOrder.
        let ordered: [Routine] = RoutineSplitShareService.selectedRoutines(
            forward,
            folders: [second, first],
            routines: routines
        )
        XCTAssertEqual(ordered.map(\.name), ["A2", "A1", "B1", "SUELTA"])

        let reverseOrdered: [Routine] = RoutineSplitShareService.selectedRoutines(
            reverse,
            folders: [first, second],
            routines: routines
        )
        XCTAssertEqual(reverseOrdered.map(\.id), ordered.map(\.id))
    }

    func testExportUsesTheDefaultNameAndOnlyTheSelectedRoutines() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Empuje", context: context)
        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let pull: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: context)
        let legs: Routine = makeRoutine(named: "LEGS", sortOrder: 2, context: context)
        folder.routineIDs = [push.id, pull.id]
        try context.save()

        var state: SplitShareSelectorState = SplitShareSelectorState()
        state.toggleRoutine(push)
        state.toggleRoutine(legs)

        let ordered: [Routine] = RoutineSplitShareService.selectedRoutines(
            state,
            folders: [folder],
            routines: allRoutines(context)
        )
        let payload: RoutineSplitPayload = try RoutineSplitShareService.payload(for: ordered)

        XCTAssertEqual(payload.format, "appgym.split")
        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(payload.name, "Split compartido")
        XCTAssertEqual(payload.routines.map(\.name), ["PUSH", "LEGS"])
    }

    func testExportIgnoresArchivedAndFreeWorkoutRoutinesGivenDirectly() throws {
        let context: ModelContext = try makeContext()
        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let pull: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: context)
        let archived: Routine = makeRoutine(named: "OLD", sortOrder: 2, archived: true, context: context)
        let free: Routine = makeRoutine(named: "LIBRE", sortOrder: 3, isTemplate: false, context: context)

        let payload: RoutineSplitPayload = try RoutineSplitShareService.payload(
            for: [push, pull, archived, free]
        )

        XCTAssertEqual(payload.routines.map(\.name), ["PUSH", "PULL"])
    }

    func testTooManySelectedRoutinesCannotBeExported() throws {
        let context: ModelContext = try makeContext()
        let routines: [Routine] = (0..<(SplitImportService.maxRoutines + 1)).map { index in
            return makeRoutine(named: "RUTINA \(index)", sortOrder: index, context: context)
        }

        XCTAssertThrowsError(try RoutineSplitShareService.payload(for: routines)) { error in
            XCTAssertEqual(error as? RoutineSplitShareError, .tooManyRoutines)
        }
    }

    func testSplitFileNameKeepsTheSplitExtensionAndASafeName() {
        let name: String = RoutineSplitShareService.fileName(
            forSplitNamed: "Split compartido",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(name.hasPrefix("AppGym_Split_Split_compartido_"))
        XCTAssertTrue(name.hasSuffix(".appgymsplit"))
        XCTAssertFalse(name.contains(" "))
    }

    func testExportingASelectionDoesNotTouchTheSenderOrganisation() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Empuje", context: context)
        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 4, context: context)
        let pull: Routine = makeRoutine(named: "PULL", sortOrder: 2, context: context)
        folder.routineIDs = [push.id]
        try context.save()

        var state: SplitShareSelectorState = SplitShareSelectorState()
        state.toggleRoutine(push)
        state.toggleRoutine(pull)

        let directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SplitShareSelectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try RoutineSplitShareService.makeFile(
            for: RoutineSplitShareService.selectedRoutines(
                state,
                folders: [folder],
                routines: allRoutines(context)
            ),
            directory: directory
        )

        XCTAssertEqual(folder.routineIDs, [push.id])
        XCTAssertEqual(push.sortOrder, 4)
        XCTAssertEqual(pull.sortOrder, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RoutineFolder>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Routine>()), 2)
    }

    func testExportedSelectionCarriesNoHistory() throws {
        let context: ModelContext = try makeContext()
        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let pull: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: context)
        let link: RoutineExercise = makeLink(in: push, name: "Press banca", order: 0, context: context)

        let session: WorkoutSession = WorkoutSession(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            totalVolumeKg: 1_200.0,
            routineName: push.name
        )
        context.insert(session)
        context.insert(
            WorkoutSetLog(
                weight: 60.0,
                reps: 8,
                isCompleted: true,
                routineExerciseID: link.id,
                exercise: link.exercise,
                session: session
            )
        )
        try context.save()

        let data: Data = try RoutineSplitShareService.encodedData(for: [push, pull])
        let raw: String = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(raw.contains("totalVolumeKg"))
        XCTAssertFalse(raw.contains("startDate"))
        XCTAssertFalse(raw.contains("sessions"))
        XCTAssertFalse(raw.contains("isCompleted"))
    }

    // MARK: - Importación y compatibilidad

    func testImportingAMixedOriginSplitCreatesOneFolderInExportOrder() throws {
        let sender: ModelContext = try makeContext()
        let pushFolder: RoutineFolder = try makeFolder(named: "Empuje", context: sender)
        let legsFolder: RoutineFolder = try makeFolder(named: "Pierna", context: sender)

        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: sender)
        let legs: Routine = makeRoutine(named: "LEGS", sortOrder: 1, context: sender)
        let upper: Routine = makeRoutine(named: "UPPER", sortOrder: 2, context: sender)
        makeLink(in: push, name: "Press banca", order: 0, context: sender)
        makeLink(in: legs, name: "Sentadilla", order: 0, context: sender)
        pushFolder.routineIDs = [push.id]
        legsFolder.routineIDs = [legs.id]
        try sender.save()

        var state: SplitShareSelectorState = SplitShareSelectorState()
        state.toggleRoutine(upper)
        state.toggleRoutine(legs)
        state.toggleRoutine(push)

        let payload: RoutineSplitPayload = try RoutineSplitShareService.payload(
            for: RoutineSplitShareService.selectedRoutines(
                state,
                folders: [pushFolder, legsFolder],
                routines: allRoutines(sender)
            )
        )

        let receiver: ModelContext = try makeContext()
        let result: SplitImportResult = try SplitImportService.importSplit(
            SplitImportRequest(payload: payload),
            mode: .newFolder(name: payload.name),
            into: receiver
        )

        XCTAssertEqual(result.folderName, "Split compartido")
        XCTAssertEqual(result.routineCount, 3)

        let folder: RoutineFolder = try XCTUnwrap(
            try receiver.fetch(FetchDescriptor<RoutineFolder>()).first
        )
        XCTAssertEqual(
            RoutineFolderService.routines(in: folder, from: allRoutines(receiver)).map(\.name),
            ["PUSH", "LEGS", "UPPER"]
        )

        let payloadIDs: Set<UUID> = Set(payload.routines.map(\.id))
        for identifier in result.routineIDs {
            XCTAssertFalse(payloadIDs.contains(identifier))
        }
    }

    func testImportingAMixedOriginSplitCanReplaceTheOrganisation() throws {
        let sender: ModelContext = try makeContext()
        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: sender)
        let pull: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: sender)
        try sender.save()

        let payload: RoutineSplitPayload = try RoutineSplitShareService.payload(for: [push, pull])

        let receiver: ModelContext = try makeContext()
        let previous: Routine = makeRoutine(named: "ANTIGUA", sortOrder: 0, context: receiver)
        try receiver.save()

        let result: SplitImportResult = try SplitImportService.importSplit(
            SplitImportRequest(payload: payload),
            mode: .replaceOrganization,
            into: receiver
        )

        XCTAssertTrue(previous.isArchived)
        XCTAssertEqual(result.folderName, "Split compartido")
        XCTAssertEqual(result.routineCount, 2)
        XCTAssertEqual(try receiver.fetchCount(FetchDescriptor<RoutineFolder>()), 1)
    }

    func testFolderBasedSplitFilesFromThePreviousVersionStillImport() throws {
        let context: ModelContext = try makeContext()
        let folder: RoutineFolder = try makeFolder(named: "Empuje", context: context)
        let push: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: context)
        let pull: Routine = makeRoutine(named: "PULL", sortOrder: 1, context: context)
        folder.routineIDs = [push.id, pull.id]
        try context.save()

        let routines: [Routine] = allRoutines(context)
        let legacy: RoutineSplitPayload = try RoutineSplitShareService.payload(
            for: folder,
            routines: routines
        )
        let data: Data = try RoutineSplitShareService.encodedData(for: folder, routines: routines)

        XCTAssertEqual(try SplitImportService.decode(data: data), legacy)

        let receiver: ModelContext = try makeContext()
        let result: SplitImportResult = try SplitImportService.importSplit(
            SplitImportRequest(payload: legacy),
            mode: .newFolder(name: legacy.name),
            into: receiver
        )

        XCTAssertEqual(result.folderName, "Empuje")
        XCTAssertEqual(result.routineCount, 2)
    }

    func testRoutineFilesStillUseTheRoutineImportFlow() throws {
        let sender: ModelContext = try makeContext()
        let routine: Routine = makeRoutine(named: "PUSH", sortOrder: 0, context: sender)
        makeLink(in: routine, name: "Press banca", order: 0, context: sender)
        try sender.save()

        let url: URL = try writeFile(
            name: "Rutina.appgymroutine",
            data: try RoutineShareService.encodedData(for: routine)
        )
        defer { removeDirectory(of: url) }

        XCTAssertTrue(RoutineImportService.isRoutineFile(url))
        XCTAssertFalse(RoutineSplitShareService.isSplitFile(url))

        let request: RoutineImportRequest = try RoutineImportService.makeRequest(fromFileAt: url)
        let receiver: ModelContext = try makeContext()
        let imported: Routine = try RoutineImportService.importRoutine(request, into: receiver)

        XCTAssertEqual(imported.name, "PUSH")
        XCTAssertEqual(imported.exercises.count, 1)
        XCTAssertEqual(try receiver.fetchCount(FetchDescriptor<RoutineFolder>()), 0)
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

    private func makeFolder(
        named name: String,
        sortOrder: Int? = nil,
        context: ModelContext
    ) throws -> RoutineFolder {
        let existing: [RoutineFolder] = (try? context.fetch(FetchDescriptor<RoutineFolder>())) ?? []
        let folder: RoutineFolder = RoutineFolder(
            name: name,
            sortOrder: sortOrder ?? ((existing.map(\.sortOrder).max() ?? -1) + 1)
        )
        context.insert(folder)
        try context.save()
        return folder
    }

    private func makeRoutine(
        named name: String,
        sortOrder: Int,
        archived: Bool = false,
        isTemplate: Bool = true,
        context: ModelContext
    ) -> Routine {
        let routine: Routine = Routine(
            name: name,
            isTemplate: isTemplate,
            sortOrder: sortOrder,
            exercises: [],
            isArchived: archived
        )
        context.insert(routine)
        return routine
    }

    @discardableResult
    private func makeLink(
        in routine: Routine,
        name: String,
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
            defaultSets: 4,
            targetRepsMin: 6,
            targetRepsMax: 8,
            sortOrder: order,
            defaultWeight: 40.0,
            restSeconds: 120,
            notes: "nota"
        )
        context.insert(link)
        routine.exercises.append(link)
        return link
    }

    private func writeFile(name: String, data: Data) throws -> URL {
        let directory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SplitShareSelectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url: URL = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func removeDirectory(of url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
