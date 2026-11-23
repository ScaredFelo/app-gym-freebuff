import Foundation
import UniformTypeIdentifiers

// MARK: - Errores

enum RoutineSplitShareError: LocalizedError, Equatable {
    case emptySplit
    case notEnoughRoutines
    case tooManyRoutines
    /// Una de las rutinas del split no tiene ejercicios.
    case emptyRoutine(name: String)
    /// Una de las rutinas del split incumple el resto de la integridad.
    case invalidRoutine(name: String, reason: RoutineImportError)
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .emptySplit:
            return "Esta carpeta no tiene rutinas activas que se puedan compartir."
        case .notEnoughRoutines:
            return "Selecciona al menos dos rutinas para compartir un split."
        case .tooManyRoutines:
            return "Un split no puede contener más de \(SplitImportService.maxRoutines) rutinas."
        case .emptyRoutine(let name):
            return "La rutina «\(name)» no contiene ningún ejercicio. Añade al menos uno antes de compartir el split."
        case .invalidRoutine(let name, let reason):
            return "La rutina «\(name)» no se puede compartir: \(reason.errorDescription ?? "contiene datos no válidos.")"
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

// MARK: - Selección

/// Estado de la casilla de una carpeta: vacía, intermedia o completa.
enum SplitFolderSelectionState: Equatable {
    case none
    case partial
    case all
}

/// Estado temporal del selector de splits.
///
/// Guarda solo dos cosas de interfaz: qué rutinas están marcadas y qué
/// carpetas están desplegadas. No conoce SwiftData ni escribe nada, así que se
/// puede probar sin levantar la vista.
struct SplitShareSelectorState: Equatable {
    private(set) var selectedRoutineIDs: Set<UUID> = []
    private(set) var expandedFolderIDs: Set<UUID> = []

    init(
        selectedRoutineIDs: Set<UUID> = [],
        expandedFolderIDs: Set<UUID> = []
    ) {
        self.selectedRoutineIDs = selectedRoutineIDs
        self.expandedFolderIDs = expandedFolderIDs
    }

    // MARK: Selección

    var selectedCount: Int {
        return selectedRoutineIDs.count
    }

    var isEmpty: Bool {
        return selectedRoutineIDs.isEmpty
    }

    /// Un split necesita al menos dos rutinas.
    var canShare: Bool {
        return selectedRoutineIDs.count >= RoutineSplitShareService.minimumRoutineCount
    }

    func contains(_ routineID: UUID) -> Bool {
        return selectedRoutineIDs.contains(routineID)
    }

    /// Las rutinas archivadas y las temporales del entreno libre nunca se
    /// pueden marcar: no forman parte del plan visible.
    mutating func toggleRoutine(_ routine: Routine) {
        guard routine.isActivePlanRoutine else { return }
        toggleRoutine(routine.id)
    }

    mutating func toggleRoutine(_ routineID: UUID) {
        if selectedRoutineIDs.contains(routineID) {
            selectedRoutineIDs.remove(routineID)
        } else {
            selectedRoutineIDs.insert(routineID)
        }
    }

    mutating func deselectAll() {
        selectedRoutineIDs.removeAll()
    }

    // MARK: Carpetas

    func isExpanded(_ folderID: UUID) -> Bool {
        return expandedFolderIDs.contains(folderID)
    }

    /// Varias carpetas pueden estar desplegadas a la vez.
    mutating func toggleExpansion(_ folderID: UUID) {
        if expandedFolderIDs.contains(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
    }

    func folderState(_ folder: RoutineFolder, routines: [Routine]) -> SplitFolderSelectionState {
        let identifiers: [UUID] = RoutineSplitShareService.activeRoutines(in: folder, routines: routines).map(\.id)
        guard !identifiers.isEmpty else { return .none }

        let selected: Int = identifiers.filter { selectedRoutineIDs.contains($0) }.count
        if selected == 0 { return .none }
        return selected == identifiers.count ? .all : .partial
    }

    /// La casilla de la carpeta marca todas sus rutinas activas; si ya están
    /// todas marcadas, las desmarca. No afecta a otras carpetas.
    mutating func toggleFolder(_ folder: RoutineFolder, routines: [Routine]) {
        let identifiers: [UUID] = RoutineSplitShareService.activeRoutines(in: folder, routines: routines).map(\.id)
        guard !identifiers.isEmpty else { return }

        if identifiers.allSatisfy({ selectedRoutineIDs.contains($0) }) {
            selectedRoutineIDs.subtract(identifiers)
        } else {
            selectedRoutineIDs.formUnion(identifiers)
        }
    }
}

// MARK: - Servicio

/// Genera el archivo `.appgymsplit` de una selección de rutinas.
///
/// Solo lee el modelo: no modifica carpetas, rutinas ni ejercicios, y no crea
/// carpetas en el dispositivo del emisor. El orden es siempre el de la pestaña
/// Rutinas (carpetas, interior de cada carpeta y rutinas independientes) y solo
/// se incluyen rutinas activas.
///
/// Se mantienen las funciones basadas en una carpeta completa para seguir
/// leyendo y generando los archivos del formato anterior.
enum RoutineSplitShareService {
    static let fileExtension: String = "appgymsplit"
    static let typeIdentifier: String = "com.jordiferres.appgym.split"
    /// Nombre inicial del split: al mezclar carpetas no hay uno que heredar.
    static let defaultSplitName: String = "Split compartido"
    /// Un split se construye con al menos dos rutinas.
    static let minimumRoutineCount: Int = 2

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

    /// Rutinas activas que no pertenecen a ninguna carpeta, en su orden.
    static func looseActiveRoutines(
        folders: [RoutineFolder],
        routines: [Routine]
    ) -> [Routine] {
        return RoutineFolderService.looseRoutines(
            from: routines.filter { $0.isActivePlanRoutine },
            folders: folders
        )
    }

    /// Rutinas seleccionadas en el orden visual de la pestaña Rutinas:
    /// carpetas en su orden, rutinas dentro de cada carpeta y después las
    /// rutinas independientes.
    ///
    /// El resultado no depende del orden en que se marcaron las casillas, así
    /// que dos exportaciones con la misma selección producen el mismo archivo.
    static func selectedRoutines(
        _ selection: SplitShareSelectorState,
        folders: [RoutineFolder],
        routines: [Routine]
    ) -> [Routine] {
        let active: [Routine] = routines.filter { $0.isActivePlanRoutine }
        var ordered: [Routine] = []
        var included: Set<UUID> = []

        for folder in RoutineFolderService.sortedFolders(folders) {
            for routine in RoutineFolderService.routines(in: folder, from: active) {
                guard selection.contains(routine.id), !included.contains(routine.id) else { continue }
                included.insert(routine.id)
                ordered.append(routine)
            }
        }

        for routine in looseActiveRoutines(folders: folders, routines: active) {
            guard selection.contains(routine.id), !included.contains(routine.id) else { continue }
            included.insert(routine.id)
            ordered.append(routine)
        }

        return ordered
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
        return try encode(try payload(for: folder, routines: routines))
    }

    /// Payload de un conjunto ya ordenado de rutinas.
    ///
    /// El nombre por defecto es «Split compartido»: el emisor no elige nombre y
    /// el receptor puede cambiarlo al importar.
    static func payload(
        for routines: [Routine],
        name: String = defaultSplitName
    ) throws -> RoutineSplitPayload {
        let exportable: [Routine] = routines.filter { $0.isActivePlanRoutine }

        guard exportable.count >= minimumRoutineCount else {
            throw RoutineSplitShareError.notEnoughRoutines
        }
        // El archivo generado tiene que poder importarse: se respeta el mismo
        // límite que la validación de recepción.
        guard exportable.count <= SplitImportService.maxRoutines else {
            throw RoutineSplitShareError.tooManyRoutines
        }

        let sharedRoutines: [RoutineShareRoutine] = exportable.map {
            RoutineShareService.sharedRoutine(for: $0)
        }
        // El archivo generado tiene que poder importarse: se aplican las mismas
        // reglas que la validación de recepción de un split.
        try validateExportable(sharedRoutines)

        let trimmedName: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return RoutineSplitPayload(
            format: RoutineSplitPayload.formatIdentifier,
            version: RoutineSplitPayload.currentVersion,
            id: UUID(),
            name: trimmedName.isEmpty ? defaultSplitName : trimmedName,
            routines: sharedRoutines
        )
    }

    /// Comprueba cada rutina del split antes de escribir el archivo.
    ///
    /// Un split es un conjunto de rutinas para entrenar: si una está vacía el
    /// receptor no puede usarla. Se informa del nombre de la primera rutina que
    /// incumple la regla, y se reutiliza la validación compartida para no
    /// duplicar el resto de comprobaciones.
    private static func validateExportable(_ routines: [RoutineShareRoutine]) throws {
        for routine in routines {
            guard !routine.exercises.isEmpty else {
                throw RoutineSplitShareError.emptyRoutine(name: routine.name)
            }

            do {
                try RoutineImportService.validate(sharedRoutine: routine, rules: .splitFile)
            } catch let reason as RoutineImportError {
                throw RoutineSplitShareError.invalidRoutine(name: routine.name, reason: reason)
            }
        }
    }

    static func encodedData(
        for routines: [Routine],
        name: String = defaultSplitName
    ) throws -> Data {
        return try encode(try payload(for: routines, name: name))
    }

    private static func encode(_ payload: RoutineSplitPayload) throws -> Data {
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

    static func fileName(forSplitNamed name: String, date: Date = Date()) -> String {
        let safeName: String = RoutineShareService.safeName(name)
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

    /// Genera el `.appgymsplit` de una selección ya ordenada de rutinas.
    static func makeFile(
        for routines: [Routine],
        name: String = defaultSplitName,
        directory: URL? = nil,
        exportedAt: Date = Date()
    ) throws -> RoutineShareFile {
        let data: Data = try encodedData(for: routines, name: name)
        let destination: URL = directory ?? FileManager.default.temporaryDirectory
        let url: URL = destination.appendingPathComponent(fileName(forSplitNamed: name, date: exportedAt))

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RoutineSplitShareError.writeFailed
        }

        return RoutineShareFile(url: url, routineName: name)
    }
}
