import Foundation
import SwiftData
import CoreGraphics

// MARK: - Errores

/// Errores controlados de las carpetas. Todos exponen un mensaje en español
/// listo para mostrarse dentro del flujo de movimiento o del diálogo de nombre.
enum RoutineFolderError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "El nombre de la carpeta no puede estar vacío ni contener solo espacios."
        case .duplicateName:
            return "Ya existe una carpeta con ese nombre. Usa otro para distinguirlas."
        case .saveFailed:
            return "No se han podido guardar los cambios. Se ha restaurado el estado anterior."
        }
    }
}

// MARK: - Gesto de deslizamiento

/// Acción que corresponde a un deslizamiento horizontal sobre una rutina.
///
/// - Hacia la derecha (`> 0`): eliminación, con las mismas reglas que antes.
/// - Hacia la izquierda (`< 0`): flujo para mover la rutina a una carpeta.
enum RoutineSwipeAction: Equatable {
    case none
    case deleteRoutine
    case moveToFolder
}

// MARK: - Fila de la lista

/// Fila de la pestaña Rutinas. Se construye siempre con las carpetas primero y
/// después las rutinas, para que la vista no tenga que reordenar nada.
enum RoutineListRow: Identifiable {
    case folder(RoutineFolder)
    case routine(Routine, position: Int)

    var id: String { identifier }

    /// Identidad estable para comparar y probar el orden sin depender de la
    /// instancia del modelo.
    var identifier: String {
        switch self {
        case .folder(let folder):
            return "folder:\(folder.id.uuidString)"
        case .routine(let routine, _):
            return "routine:\(routine.id.uuidString)"
        }
    }
}

// MARK: - Servicio

/// Organización visual de las rutinas en carpetas.
///
/// Reglas:
/// - Una rutina pertenece a cero o una carpeta. La pertenencia se guarda en
///   `RoutineFolder.routineIDsData`; `Routine` no tiene ninguna propiedad de
///   carpeta, así que esta función no cambia su forma ni su historial.
/// - Mover nunca crea copias ni cambia el UUID de la rutina, sus ejercicios ni
///   sus referencias históricas: solo actualiza la pertenencia y el orden.
/// - Eliminar una carpeta elimina sus rutinas activas, salvo las que estén
///   referenciadas por un plan asistido: esas se archivan (igual que el gesto
///   de eliminación) para no romper referencias. Las rutinas ya archivadas no
///   se tocan: solo desaparecen con la carpeta. Las sesiones y sus series no se
///   tocan nunca.
/// - Todas las escrituras son atómicas: un fallo de guardado hace `rollback` y
///   deja la base como estaba.
enum RoutineFolderService {
    struct DeletionSummary: Equatable {
        let deletedRoutineCount: Int
        let archivedRoutineCount: Int

        var removedRoutineCount: Int {
            return deletedRoutineCount + archivedRoutineCount
        }
    }

    static let swipeThreshold: CGFloat = 120.0

    // MARK: - Nombres

    static func normalizedName(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `false` para nombres vacíos o formados solo por espacios. Los duplicados
    /// se comparan sin distinguir mayúsculas ni acentos: dos carpetas con el
    /// mismo nombre serían indistinguibles en la lista.
    static func isNameAvailable(
        _ name: String,
        in folders: [RoutineFolder],
        excluding folderID: UUID? = nil
    ) -> Bool {
        let trimmed: String = normalizedName(name)
        guard !trimmed.isEmpty else { return false }

        return !folders.contains { folder in
            guard folder.id != folderID else { return false }
            let existing: String = normalizedName(folder.name)
            return existing.compare(
                trimmed,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    // MARK: - Orden

    private static func isOrderedBefore(
        order lhsOrder: Int,
        name lhsName: String,
        order rhsOrder: Int,
        name rhsName: String
    ) -> Bool {
        if lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }
        return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
    }

    static func sortedFolders(_ folders: [RoutineFolder]) -> [RoutineFolder] {
        return folders.sorted { lhs, rhs in
            isOrderedBefore(
                order: lhs.sortOrder,
                name: lhs.name,
                order: rhs.sortOrder,
                name: rhs.name
            )
        }
    }

    // MARK: - Pertenencia

    /// Carpeta que contiene la rutina, si existe. Si por un dato antiguo la
    /// rutina apareciera en más de una carpeta, manda la primera en el orden
    /// estable de carpetas.
    static func folder(
        containing routine: Routine,
        from folders: [RoutineFolder]
    ) -> RoutineFolder? {
        return sortedFolders(folders).first { folder in
            folder.contains(routineID: routine.id)
        }
    }

    static func routines(in folder: RoutineFolder, from routines: [Routine]) -> [Routine] {
        let contained: Set<UUID> = Set(folder.routineIDs)
        return routines
            .filter { contained.contains($0.id) }
            .sorted { lhs, rhs in
                isOrderedBefore(
                    order: lhs.sortOrder,
                    name: lhs.name,
                    order: rhs.sortOrder,
                    name: rhs.name
                )
            }
    }

    /// Identificadores que pertenecen a alguna carpeta. Un UUID que ya no
    /// corresponde a ninguna rutina no cuenta: la pertenencia se resuelve
    /// siempre contra las rutinas existentes.
    static func containedRoutineIDs(in folders: [RoutineFolder]) -> Set<UUID> {
        var ids: Set<UUID> = []
        for folder in folders {
            ids.formUnion(folder.routineIDs)
        }
        return ids
    }

    /// Rutinas sin carpeta: son las que permanecen en la pantalla principal.
    static func looseRoutines(
        from routines: [Routine],
        folders: [RoutineFolder]
    ) -> [Routine] {
        let contained: Set<UUID> = containedRoutineIDs(in: folders)
        return routines
            .filter { !contained.contains($0.id) }
            .sorted { lhs, rhs in
                isOrderedBefore(
                    order: lhs.sortOrder,
                    name: lhs.name,
                    order: rhs.sortOrder,
                    name: rhs.name
                )
            }
    }

    /// Filas de la pantalla principal: primero todas las carpetas y después las
    /// rutinas sin carpeta. Las rutinas de una carpeta no aparecen aquí.
    static func mainRows(
        folders: [RoutineFolder],
        activeRoutines: [Routine]
    ) -> [RoutineListRow] {
        let folderRows: [RoutineListRow] = sortedFolders(folders).map { folder in
            RoutineListRow.folder(folder)
        }
        let routineRows: [RoutineListRow] = looseRoutines(
            from: activeRoutines,
            folders: folders
        )
        .enumerated()
        .map { index, routine in
            RoutineListRow.routine(routine, position: index)
        }
        return folderRows + routineRows
    }

    /// Filas del interior de una carpeta: solo sus rutinas, en su orden.
    static func rows(
        in folder: RoutineFolder,
        activeRoutines: [Routine]
    ) -> [RoutineListRow] {
        return routines(in: folder, from: activeRoutines)
            .enumerated()
            .map { index, routine in
                RoutineListRow.routine(routine, position: index)
            }
    }

    /// Rutinas **activas y visibles** de la carpeta: es el número que se
    /// muestra en la tarjeta y el que cuenta la alerta de eliminación.
    ///
    /// Las rutinas archivadas nunca se contabilizan, y una carpeta que solo
    /// contiene rutinas archivadas muestra cero.
    static func activeRoutineCount(in folder: RoutineFolder, routines: [Routine]) -> Int {
        let contained: Set<UUID> = Set(folder.routineIDs)
        return routines.filter { routine in
            contained.contains(routine.id) && routine.isActivePlanRoutine
        }.count
    }

    /// Una carpeta sin rutinas visibles se elimina directamente, sin
    /// confirmación: aunque guarde rutinas archivadas, no se borra nada visible.
    static func requiresDeletionConfirmation(
        for folder: RoutineFolder,
        routines: [Routine]
    ) -> Bool {
        return activeRoutineCount(in: folder, routines: routines) > 0
    }

    // MARK: - Gesto

    static func swipeAction(
        horizontal: CGFloat,
        vertical: CGFloat,
        threshold: CGFloat = RoutineFolderService.swipeThreshold
    ) -> RoutineSwipeAction {
        guard abs(horizontal) > abs(vertical) else { return .none }
        guard abs(horizontal) >= threshold else { return .none }
        return horizontal > 0 ? .deleteRoutine : .moveToFolder
    }

    // MARK: - Crear y renombrar

    @discardableResult
    static func createFolder(
        named name: String,
        existingFolders: [RoutineFolder],
        context: ModelContext
    ) throws -> RoutineFolder {
        let trimmed: String = normalizedName(name)
        guard !trimmed.isEmpty else { throw RoutineFolderError.emptyName }
        guard isNameAvailable(trimmed, in: existingFolders) else {
            throw RoutineFolderError.duplicateName
        }

        let folder: RoutineFolder = RoutineFolder(
            name: trimmed,
            sortOrder: (existingFolders.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(folder)

        guard PersistenceService.save(context, operation: "crear la carpeta") else {
            context.rollback()
            throw RoutineFolderError.saveFailed
        }

        return folder
    }

    static func renameFolder(
        _ folder: RoutineFolder,
        to name: String,
        existingFolders: [RoutineFolder],
        context: ModelContext
    ) throws {
        let trimmed: String = normalizedName(name)
        guard !trimmed.isEmpty else { throw RoutineFolderError.emptyName }
        guard isNameAvailable(trimmed, in: existingFolders, excluding: folder.id) else {
            throw RoutineFolderError.duplicateName
        }
        guard folder.name != trimmed else { return }

        folder.name = trimmed

        guard PersistenceService.save(context, operation: "renombrar la carpeta") else {
            context.rollback()
            throw RoutineFolderError.saveFailed
        }
    }

    // MARK: - Mover

    /// Crea la carpeta y coloca la rutina dentro en una sola transacción.
    @discardableResult
    static func createFolder(
        named name: String,
        moving routine: Routine,
        existingFolders: [RoutineFolder],
        context: ModelContext
    ) throws -> RoutineFolder {
        let trimmed: String = normalizedName(name)
        guard !trimmed.isEmpty else { throw RoutineFolderError.emptyName }
        guard isNameAvailable(trimmed, in: existingFolders) else {
            throw RoutineFolderError.duplicateName
        }

        // Una rutina solo puede estar en una carpeta: se retira de las demás.
        for candidate in existingFolders {
            candidate.remove(routineID: routine.id)
        }

        let folder: RoutineFolder = RoutineFolder(
            name: trimmed,
            sortOrder: (existingFolders.map(\.sortOrder).max() ?? -1) + 1,
            routineIDs: [routine.id]
        )
        context.insert(folder)
        routine.sortOrder = 0

        guard PersistenceService.save(context, operation: "crear la carpeta y mover la rutina") else {
            context.rollback()
            throw RoutineFolderError.saveFailed
        }

        return folder
    }

    /// Mueve una rutina a una carpeta o, con `nil`, la devuelve a la lista
    /// principal. No crea copias ni toca la rutina salvo su orden.
    static func moveRoutine(
        _ routine: Routine,
        to folder: RoutineFolder?,
        context: ModelContext
    ) throws {
        let folders: [RoutineFolder] = (try? context.fetch(FetchDescriptor<RoutineFolder>())) ?? []
        let current: RoutineFolder? = RoutineFolderService.folder(containing: routine, from: folders)

        guard current?.id != folder?.id else { return }

        let allRoutines: [Routine] = (try? context.fetch(FetchDescriptor<Routine>())) ?? []

        let destinationSiblings: [Routine]
        if let folder {
            destinationSiblings = routines(in: folder, from: allRoutines)
                .filter { $0.id != routine.id }
        } else {
            destinationSiblings = looseRoutines(from: allRoutines, folders: folders)
                .filter { $0.id != routine.id }
        }

        for candidate in folders {
            candidate.remove(routineID: routine.id)
        }
        folder?.add(routineID: routine.id)

        routine.sortOrder = (destinationSiblings.map(\.sortOrder).max() ?? -1) + 1

        guard PersistenceService.save(context, operation: "mover la rutina de carpeta") else {
            context.rollback()
            throw RoutineFolderError.saveFailed
        }
    }

    // MARK: - Eliminar

    /// Elimina la carpeta y las rutinas que contiene.
    ///
    /// - Las rutinas activas no referenciadas por ningún plan se borran.
    /// - Las referenciadas por un plan asistido se archivan, siguiendo la misma
    ///   política que el gesto de eliminación: nunca se rompe una referencia.
    /// - Las rutinas ya archivadas **no se tocan**: conservan sus datos y su
    ///   historial, y solo dejan de pertenecer a la carpeta al desaparecer esta.
    /// - Las sesiones, series, pesos, fechas, muestras de BPM y estadísticas no
    ///   se tocan: `WorkoutSession` guarda el nombre de la rutina y no tiene
    ///   ninguna relación con `Routine` ni con `RoutineFolder`.
    /// - Si `save` falla se hace `rollback` y se lanza `saveFailed`; la base
    ///   queda como estaba (carpeta, pertenencia y rutinas).
    static func deleteFolder(
        _ folder: RoutineFolder,
        containedRoutines: [Routine],
        context: ModelContext,
        save: (ModelContext) -> Bool = { context in
            PersistenceService.save(context, operation: "eliminar la carpeta")
        }
    ) throws -> DeletionSummary {
        let wasAutosaveEnabled: Bool = context.autosaveEnabled
        context.autosaveEnabled = false
        defer {
            context.autosaveEnabled = wasAutosaveEnabled
        }

        var deletedCount: Int = 0
        var archivedCount: Int = 0
        let containedIDs: Set<UUID> = Set(folder.routineIDs)

        for routine in containedRoutines where containedIDs.contains(routine.id) {
            // Una rutina archivada no está en la lista: no se borra ni se
            // modifica. Su referencia histórica sigue intacta.
            guard !routine.isArchived else { continue }

            switch RoutineService.deletionPolicy(for: routine, context: context) {
            case .archiveReferenced:
                routine.isArchived = true
                archivedCount += 1

            case .delete:
                context.delete(routine)
                deletedCount += 1
            }
        }

        context.delete(folder)

        guard save(context) else {
            context.rollback()
            throw RoutineFolderError.saveFailed
        }

        return DeletionSummary(
            deletedRoutineCount: deletedCount,
            archivedRoutineCount: archivedCount
        )
    }
}
