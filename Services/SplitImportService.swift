import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Errores

/// Motivos por los que un archivo `.appgymsplit` no se puede importar.
enum SplitImportError: LocalizedError, Equatable {
    case unsupportedFileType
    case unreadableFile
    case fileTooLarge
    case malformedJSON
    case invalidFormat
    case unsupportedVersion(Int)
    case invalidSplitName
    case missingRoutines
    case tooManyRoutines
    case duplicateRoutineIdentifiers
    case invalidRoutine(index: Int, reason: RoutineImportError)
    case invalidFolderName
    case importFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "El archivo no es un split de AppGym. Debe tener la extensión .appgymsplit."
        case .unreadableFile:
            return "No se ha podido leer el archivo recibido. Vuelve a enviarlo o inténtalo de nuevo."
        case .fileTooLarge:
            return "El archivo es demasiado grande para ser un split de AppGym."
        case .malformedJSON:
            return "El archivo está dañado o no contiene un split válido de AppGym."
        case .invalidFormat:
            return "El archivo no es un split de AppGym."
        case .unsupportedVersion(let version):
            return "El split se creó con una versión del formato (\(version)) que esta versión de AppGym no puede leer."
        case .invalidSplitName:
            return "El split no tiene un nombre válido."
        case .missingRoutines:
            return "El split no contiene ninguna rutina."
        case .tooManyRoutines:
            return "El split contiene demasiadas rutinas para importarlo."
        case .duplicateRoutineIdentifiers:
            return "El split contiene rutinas repetidas y no se puede reconstruir."
        case .invalidRoutine(index: let index, reason: let reason):
            return "La rutina \(index) del split no es válida: \(reason.errorDescription ?? "datos incompletos")"
        case .invalidFolderName:
            return "El nombre de la carpeta no es válido."
        case .importFailed:
            return "No se ha podido importar el split. No se ha modificado ningún dato."
        }
    }
}

// MARK: - Petición

/// Split recibido y validado, pendiente de confirmación.
struct SplitImportRequest: Identifiable, Equatable {
    let id: UUID
    let payload: RoutineSplitPayload

    init(id: UUID = UUID(), payload: RoutineSplitPayload) {
        self.id = id
        self.payload = payload
    }

    var splitName: String {
        return payload.name
    }

    var routineCount: Int {
        return payload.routines.count
    }
}

/// Cómo se aplica el split recibido. En ambos casos se crea una carpeta nueva
/// con el modelo real `RoutineFolder`.
enum SplitImportMode: Equatable {
    /// Opción A: convive con la organización actual.
    case newFolder(name: String)
    /// Opción B: archiva las rutinas activas y deja el split como organización
    /// vigente. No borra nada ni toca el historial.
    case replaceOrganization
}

struct SplitImportResult: Equatable {
    let folderID: UUID
    let folderName: String
    let routineIDs: [UUID]

    var routineCount: Int {
        return routineIDs.count
    }
}

// MARK: - Servicio

/// Valida e importa splits completos (`.appgymsplit`) de forma atómica.
///
/// Reutiliza `RoutineImportService` para las rutinas (validación, nombres,
/// resolución de ejercicios y creación de vínculos) y `RoutineService` para la
/// sustitución de organización. No duplica reglas ni crea otro sistema de
/// carpetas: la pertenencia se guarda en `RoutineFolder.routineIDsData`.
enum SplitImportService {
    static let defaultFolderName: String = "Split compartido"
    static let maxFileSize: Int = 10 * 1024 * 1024
    static let maxRoutines: Int = 30
    static let maxNameLength: Int = 80

    static var documentType: UTType {
        return RoutineSplitShareService.documentType
    }

    static func isSplitFile(_ url: URL) -> Bool {
        return RoutineSplitShareService.isSplitFile(url)
    }

    // MARK: - Recepción

    static func makeRequest(fromFileAt url: URL) throws -> SplitImportRequest {
        guard isSplitFile(url) else {
            throw SplitImportError.unsupportedFileType
        }

        let didAccess: Bool = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let size: Int = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maxFileSize {
            throw SplitImportError.fileTooLarge
        }

        let payload: RoutineSplitPayload = try decode(
            data: RoutineImportService.readCoordinatedData(from: url)
        )
        try validate(payload)
        return SplitImportRequest(payload: payload)
    }

    // MARK: - Decodificación y validación

    static func decode(data: Data) throws -> RoutineSplitPayload {
        guard data.count <= maxFileSize else {
            throw SplitImportError.fileTooLarge
        }

        do {
            return try JSONDecoder().decode(RoutineSplitPayload.self, from: data)
        } catch {
            throw SplitImportError.malformedJSON
        }
    }

    /// Valida el split completo antes de tocar SwiftData. Si una sola rutina
    /// no es válida, se rechaza el split entero.
    static func validate(_ payload: RoutineSplitPayload) throws {
        guard payload.format == RoutineSplitPayload.formatIdentifier else {
            throw SplitImportError.invalidFormat
        }
        guard payload.version == RoutineSplitPayload.currentVersion else {
            throw SplitImportError.unsupportedVersion(payload.version)
        }

        let name: String = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maxNameLength else {
            throw SplitImportError.invalidSplitName
        }

        guard !payload.routines.isEmpty else {
            throw SplitImportError.missingRoutines
        }
        guard payload.routines.count <= maxRoutines else {
            throw SplitImportError.tooManyRoutines
        }

        // El orden del array es el orden del split; sus identidades no pueden
        // repetirse o la reconstrucción sería ambigua.
        let identifiers: [UUID] = payload.routines.map(\.id)
        guard Set(identifiers).count == identifiers.count else {
            throw SplitImportError.duplicateRoutineIdentifiers
        }

        for (offset, routine) in payload.routines.enumerated() {
            do {
                try RoutineImportService.validate(sharedRoutine: routine)
            } catch let reason as RoutineImportError {
                throw SplitImportError.invalidRoutine(index: offset + 1, reason: reason)
            }
        }
    }

    // MARK: - Nombres de carpeta

    /// Primer nombre libre: `Split compartido`, `Split compartido 2`,
    /// `Split compartido 3`… Compara sin distinguir mayúsculas ni acentos.
    static func availableFolderName(
        for requested: String,
        existingFolders: [RoutineFolder]
    ) throws -> String {
        var base: String = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            base = defaultFolderName
        }
        guard base.count <= maxNameLength else {
            throw SplitImportError.invalidFolderName
        }

        if RoutineFolderService.isNameAvailable(base, in: existingFolders) {
            return base
        }

        var suffix: Int = 2
        while suffix < 1_000 {
            let candidate: String = "\(base) \(suffix)"
            if RoutineFolderService.isNameAvailable(candidate, in: existingFolders) {
                return candidate
            }
            suffix += 1
        }
        return "\(base) \(UUID().uuidString.prefix(4))"
    }

    // MARK: - Importación

    /// Importa el split completo en una carpeta nueva, en una sola transacción.
    ///
    /// - Identidades nuevas para todas las rutinas.
    /// - Ejercicios resueltos con la misma política segura que 08B.
    /// - `replaceOrganization` archiva antes las rutinas activas y desactiva el
    ///   plan asistido vigente, sin borrar nada ni tocar el historial.
    /// - `simulatePersistenceFailure` solo existe para probar el `rollback`.
    static func importSplit(
        _ request: SplitImportRequest,
        mode: SplitImportMode,
        into context: ModelContext,
        simulatePersistenceFailure: Bool = false
    ) throws -> SplitImportResult {
        let payload: RoutineSplitPayload = request.payload
        try validate(payload)

        let folders: [RoutineFolder] = (try? context.fetch(FetchDescriptor<RoutineFolder>())) ?? []

        let requestedName: String
        switch mode {
        case .newFolder(let name):
            requestedName = name
        case .replaceOrganization:
            requestedName = payload.name
        }
        let folderName: String = try availableFolderName(for: requestedName, existingFolders: folders)

        let previousAutosave: Bool = context.autosaveEnabled
        context.autosaveEnabled = false

        do {
            if case .replaceOrganization = mode {
                try RoutineService.archiveActiveRoutinesForOrganizationReplacement(context: context)
            }

            var routines: [Routine] = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
            var exercises: [Exercise] = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            let nextFolderOrder: Int = (folders.map(\.sortOrder).max() ?? -1) + 1

            let folder: RoutineFolder = RoutineFolder(name: folderName, sortOrder: nextFolderOrder)
            context.insert(folder)

            var routineIDs: [UUID] = []

            for (index, shared) in payload.routines.enumerated() {
                let routine: Routine = RoutineImportService.insertRoutine(
                    from: shared,
                    into: context,
                    routines: &routines,
                    exercises: &exercises
                )
                // El orden dentro de la carpeta manda: es el orden del split.
                routine.sortOrder = index
                routineIDs.append(routine.id)
            }

            folder.routineIDs = routineIDs

            if simulatePersistenceFailure {
                throw SplitImportError.importFailed
            }

            try context.save()
            context.autosaveEnabled = previousAutosave

            return SplitImportResult(
                folderID: folder.id,
                folderName: folderName,
                routineIDs: routineIDs
            )
        } catch {
            context.rollback()
            context.autosaveEnabled = previousAutosave

            if let splitError = error as? SplitImportError {
                throw splitError
            }
            throw SplitImportError.importFailed
        }
    }
}
