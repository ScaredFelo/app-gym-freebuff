import Foundation
import UniformTypeIdentifiers

// MARK: - Errores

enum RoutineSplitShareError: LocalizedError, Equatable {
    case emptySplit
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .emptySplit:
            return "Esta carpeta no tiene rutinas activas que se puedan compartir."
        case .encodingFailed:
            return "No se ha podido preparar el split para compartirlo."
        case .writeFailed:
            return "No se ha podido generar el archivo del split. Comprueba el espacio libre del dispositivo."
        }
    }
}

// MARK: - Documento

/// Raíz del archivo `.appgymsplit`.
///
/// Reutiliza `RoutineShareRoutine` y `RoutineShareExercise` del formato
/// `.appgymroutine`: un split es una lista ordenada de rutinas con exactamente
/// los mismos datos funcionales, sin historial ni datos del emisor.
struct RoutineSplitPayload: Codable, Equatable {
    static let formatIdentifier: String = "appgym.split"
    static let currentVersion: Int = 1

    var format: String
    var version: Int
    /// Identidad del split exportado. No es el id de la carpeta del emisor.
    var id: UUID
    var name: String
    var routines: [RoutineShareRoutine]
}

// MARK: - Servicio

/// Genera el archivo `.appgymsplit` de una carpeta completa.
///
/// Solo lee el modelo: no modifica la carpeta, sus rutinas ni sus ejercicios.
/// El orden de las rutinas es el de la carpeta (mismo criterio que la pestaña
/// Rutinas) y solo se incluyen las rutinas activas.
enum RoutineSplitShareService {
    static let fileExtension: String = "appgymsplit"
    static let typeIdentifier: String = "com.jordiferres.appgym.split"

    static var documentType: UTType {
        return UTType(exportedAs: typeIdentifier, conformingTo: .json)
    }

    static func isSplitFile(_ url: URL) -> Bool {
        return url.isFileURL && url.pathExtension.lowercased() == fileExtension
    }

    // MARK: Selección

    /// Carpetas que representan un split compartible: las que tienen al menos
    /// una rutina activa. Las vacías o con solo rutinas archivadas no cuentan.
    static func exportableFolders(
        _ folders: [RoutineFolder],
        routines: [Routine]
    ) -> [RoutineFolder] {
        return RoutineFolderService.sortedFolders(folders).filter { folder in
            return RoutineFolderService.activeRoutineCount(in: folder, routines: routines) > 0
        }
    }

    static func activeRoutines(
        in folder: RoutineFolder,
        routines: [Routine]
    ) -> [Routine] {
        return RoutineFolderService.routines(
            in: folder,
            from: routines.filter { $0.isActivePlanRoutine }
        )
    }

    // MARK: Contenido

    static func payload(
        for folder: RoutineFolder,
        routines: [Routine]
    ) throws -> RoutineSplitPayload {
        let contained: [Routine] = activeRoutines(in: folder, routines: routines)
        guard !contained.isEmpty else {
            throw RoutineSplitShareError.emptySplit
        }

        return RoutineSplitPayload(
            format: RoutineSplitPayload.formatIdentifier,
            version: RoutineSplitPayload.currentVersion,
            id: UUID(),
            name: folder.name,
            routines: contained.map { RoutineShareService.sharedRoutine(for: $0) }
        )
    }

    static func encodedData(
        for folder: RoutineFolder,
        routines: [Routine]
    ) throws -> Data {
        let payload: RoutineSplitPayload = try payload(for: folder, routines: routines)

        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            return try encoder.encode(payload)
        } catch {
            throw RoutineSplitShareError.encodingFailed
        }
    }

    // MARK: Archivo

    static func fileName(for folder: RoutineFolder, date: Date = Date()) -> String {
        let safeName: String = RoutineShareService.safeName(folder.name)
        return "AppGym_Split_\(safeName)_\(RoutineShareService.dateStamp(for: date)).\(fileExtension)"
    }

    static func makeFile(
        for folder: RoutineFolder,
        routines: [Routine],
        directory: URL? = nil,
        exportedAt: Date = Date()
    ) throws -> RoutineShareFile {
        let data: Data = try encodedData(for: folder, routines: routines)
        let destination: URL = directory ?? FileManager.default.temporaryDirectory
        let url: URL = destination.appendingPathComponent(fileName(for: folder, date: exportedAt))

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RoutineSplitShareError.writeFailed
        }

        return RoutineShareFile(url: url, routineName: folder.name)
    }
}
