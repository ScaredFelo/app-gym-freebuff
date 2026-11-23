import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Errores de importación

/// Motivos por los que un archivo `.appgymroutine` no se puede importar.
///
/// Todos los mensajes están pensados para mostrarse tal cual al usuario y
/// explicar el problema sin revelar rutas ni detalles internos.
enum RoutineImportError: LocalizedError, Equatable {
    case unsupportedFileType
    case unreadableFile
    case fileTooLarge
    case malformedJSON
    case invalidFormat
    case unsupportedVersion(Int)
    case invalidRoutineName
    case missingExercises
    case tooManyExercises
    case duplicateExerciseOrder
    case invalidExerciseName(index: Int)
    case invalidExerciseMuscle(index: Int)
    case invalidExerciseEquipment(index: Int)
    case invalidExerciseTrackingMode(index: Int)
    case invalidExerciseSets(index: Int)
    case invalidExerciseRepetitions(index: Int)
    case invalidExerciseRest(index: Int)
    case invalidExerciseWeight(index: Int)
    case invalidExerciseNotes(index: Int)
    case importFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "El archivo no es una rutina de AppGym. Debe tener la extensión .appgymroutine."
        case .unreadableFile:
            return "No se ha podido leer el archivo recibido. Vuelve a enviarlo o inténtalo de nuevo."
        case .fileTooLarge:
            return "El archivo es demasiado grande para ser una rutina de AppGym."
        case .malformedJSON:
            return "El archivo está dañado o no contiene una rutina válida de AppGym."
        case .invalidFormat:
            return "El archivo no es una rutina de AppGym."
        case .unsupportedVersion(let version):
            return "La rutina se creó con una versión del formato (\(version)) que esta versión de AppGym no puede leer."
        case .invalidRoutineName:
            return "La rutina no tiene un nombre válido."
        case .missingExercises:
            return "La rutina no contiene ningún ejercicio."
        case .tooManyExercises:
            return "La rutina contiene demasiados ejercicios para importarla."
        case .duplicateExerciseOrder:
            return "La rutina tiene ejercicios repetidos en la misma posición y no se puede reconstruir el orden."
        case .invalidExerciseName(let index):
            return "El ejercicio \(index) no tiene un nombre válido."
        case .invalidExerciseMuscle(let index):
            return "El ejercicio \(index) tiene un grupo muscular desconocido."
        case .invalidExerciseEquipment(let index):
            return "El ejercicio \(index) tiene un equipamiento desconocido."
        case .invalidExerciseTrackingMode(let index):
            return "El ejercicio \(index) tiene un modo de registro desconocido."
        case .invalidExerciseSets(let index):
            return "El ejercicio \(index) tiene un número de series fuera de rango."
        case .invalidExerciseRepetitions(let index):
            return "El ejercicio \(index) tiene repeticiones fuera de rango."
        case .invalidExerciseRest(let index):
            return "El ejercicio \(index) tiene un descanso fuera de rango."
        case .invalidExerciseWeight(let index):
            return "El ejercicio \(index) tiene un peso de referencia no válido."
        case .invalidExerciseNotes(let index):
            return "Las notas del ejercicio \(index) son demasiado largas."
        case .importFailed:
            return "No se ha podido importar la rutina. No se ha modificado ningún dato."
        }
    }
}

// MARK: - Petición validada

/// Archivo recibido y validado. Solo existe para documentos que han superado
/// todas las comprobaciones: mientras exista, se puede mostrar la confirmación.
struct RoutineImportRequest: Identifiable, Equatable {
    let id: UUID
    let payload: RoutineSharePayload

    init(id: UUID = UUID(), payload: RoutineSharePayload) {
        self.id = id
        self.payload = payload
    }

    var routineName: String {
        return payload.routine.name
    }

    var exerciseCount: Int {
        return payload.routine.exercises.count
    }
}

// MARK: - Reglas por formato

/// Reglas que dependen del archivo que se valida, no de los datos de la rutina.
///
/// La integridad de los campos (nombre, orden, rangos y valores de cada
/// ejercicio) es idéntica en los dos formatos; lo único que cambia es si una
/// rutina sin ejercicios es aceptable.
enum SharedRoutineValidationRules {
    /// `.appgymroutine`: una rutina individual puede estar vacía. Se puede
    /// compartir y el destinatario podrá añadirle ejercicios al importarla.
    case routineFile
    /// `.appgymsplit`: un split es un conjunto de rutinas para entrenar, así
    /// que una rutina sin ejercicios lo hace inutilizable y se rechaza.
    case splitFile
}

// MARK: - Servicio

/// Recibe, valida e importa rutinas individuales compartidas con el formato
/// `.appgymroutine` del Prompt 08A.
///
/// El archivo se trata siempre como información externa no confiable:
/// - se valida por completo antes de tocar SwiftData;
/// - el contenido nunca se ejecuta ni se interpreta como instrucciones;
/// - la importación es una única transacción con `autosave` desactivado y
///   `rollback` ante cualquier error.
///
/// No toca sesiones, series, estadísticas, planes asistidos, carpetas ni otras
/// rutinas del receptor.
enum RoutineImportService {

    /// Identificador de tipo declarado en `Info.plist`.
    static let typeIdentifier: String = "com.jordiferres.appgym.routine"
    static let fileExtension: String = RoutineShareService.fileExtension

    /// Límites de seguridad del archivo recibido.
    static let maxFileSize: Int = 2 * 1024 * 1024
    static let maxExercises: Int = 60
    static let maxRoutineNameLength: Int = 80
    static let maxExerciseNameLength: Int = 120
    static let maxNotesLength: Int = 1_000
    static let maxSets: Int = 20
    static let maxRepetitions: Int = 100
    static let maxRestSeconds: Int = 1_800
    static let maxWeightKg: Double = 1_000.0

    /// Tipo del documento, para `onOpenURL` y para la hoja de compartir.
    static var documentType: UTType {
        return UTType(exportedAs: typeIdentifier, conformingTo: .json)
    }

    static func isRoutineFile(_ url: URL) -> Bool {
        return url.isFileURL && url.pathExtension.lowercased() == fileExtension
    }

    // MARK: - Recepción

    /// Lee el archivo recibido, lo valida y devuelve la petición lista para
    /// confirmar. La URL no se conserva: el contenido se lee dentro del acceso
    /// de seguridad y no se depende de que el archivo siga en su ubicación.
    static func makeRequest(fromFileAt url: URL) throws -> RoutineImportRequest {
        guard isRoutineFile(url) else {
            throw RoutineImportError.unsupportedFileType
        }

        let didAccess: Bool = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let size: Int = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maxFileSize {
            throw RoutineImportError.fileTooLarge
        }

        let payload: RoutineSharePayload = try decode(data: readCoordinatedData(from: url))
        try validate(payload)
        return RoutineImportRequest(payload: payload)
    }

    /// Lectura coordinada: algunos proveedores de archivos (iCloud Drive,
    /// Archivos, apps de mensajería) entregan la URL a través de un coordinador.
    static func readCoordinatedData(from url: URL) throws -> Data {
        var coordinationError: NSError?
        var readResult: Result<Data, Error>?

        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            readResult = Result {
                return try Data(contentsOf: readableURL)
            }
        }

        if coordinationError != nil {
            throw RoutineImportError.unreadableFile
        }
        guard let readResult else {
            throw RoutineImportError.unreadableFile
        }

        do {
            return try readResult.get()
        } catch {
            throw RoutineImportError.unreadableFile
        }
    }

    // MARK: - Decodificación

    /// Decodifica el archivo con el mismo esquema que genera
    /// `RoutineShareService` en el Prompt 08A.
    static func decode(data: Data) throws -> RoutineSharePayload {
        guard data.count <= maxFileSize else {
            throw RoutineImportError.fileTooLarge
        }

        let decoder: JSONDecoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(RoutineSharePayload.self, from: data)
        } catch {
            throw RoutineImportError.malformedJSON
        }
    }

    // MARK: - Validación

    /// Comprobaciones obligatorias antes de mostrar la confirmación.
    static func validate(_ payload: RoutineSharePayload) throws {
        guard payload.format == RoutineSharePayload.formatIdentifier else {
            throw RoutineImportError.invalidFormat
        }
        guard payload.version == RoutineSharePayload.currentVersion else {
            throw RoutineImportError.unsupportedVersion(payload.version)
        }

        try validate(sharedRoutine: payload.routine, rules: .routineFile)
    }

    /// Reglas de una rutina, compartidas por `.appgymroutine` y `.appgymsplit`.
    ///
    /// `rules` decide **solo** la regla de «sin ejercicios»: el resto de la
    /// integridad se comprueba igual en los dos formatos.
    static func validate(
        sharedRoutine routine: RoutineShareRoutine,
        rules: SharedRoutineValidationRules
    ) throws {
        let routineName: String = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !routineName.isEmpty, routineName.count <= maxRoutineNameLength else {
            throw RoutineImportError.invalidRoutineName
        }

        let exercises: [RoutineShareExercise] = routine.exercises
        switch rules {
        case .routineFile:
            // Una rutina individual vacía es válida: se comparte y el receptor
            // decide qué ejercicios le añade después.
            break
        case .splitFile:
            guard !exercises.isEmpty else {
                throw RoutineImportError.missingExercises
            }
        }
        guard exercises.count <= maxExercises else {
            throw RoutineImportError.tooManyExercises
        }

        // Cada ejercicio ocupa una posición distinta: dos posiciones repetidas
        // harían ambiguo el orden reconstruido.
        let orders: Set<Int> = Set(exercises.map(\.sortOrder))
        guard orders.count == exercises.count, orders.allSatisfy({ $0 >= 0 }) else {
            throw RoutineImportError.duplicateExerciseOrder
        }

        for (offset, exercise) in exercises.enumerated() {
            try validate(exercise, index: offset + 1)
        }
    }

    private static func validate(_ exercise: RoutineShareExercise, index: Int) throws {
        let name: String = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maxExerciseNameLength else {
            throw RoutineImportError.invalidExerciseName(index: index)
        }

        guard MuscleGroup.mappedValue(for: exercise.muscleGroupRaw) != nil else {
            throw RoutineImportError.invalidExerciseMuscle(index: index)
        }
        guard EquipmentType(rawValue: exercise.equipmentTypeRaw) != nil else {
            throw RoutineImportError.invalidExerciseEquipment(index: index)
        }
        if !exercise.trackingModeRaw.isEmpty,
           ExerciseTrackingMode(rawValue: exercise.trackingModeRaw) == nil {
            throw RoutineImportError.invalidExerciseTrackingMode(index: index)
        }

        guard exercise.sets >= 1, exercise.sets <= maxSets else {
            throw RoutineImportError.invalidExerciseSets(index: index)
        }
        guard exercise.repsMin >= 1,
              exercise.repsMax >= exercise.repsMin,
              exercise.repsMax <= maxRepetitions,
              exercise.targetRepsMin >= 0,
              exercise.targetRepsMax >= exercise.targetRepsMin,
              exercise.targetRepsMax <= maxRepetitions else {
            throw RoutineImportError.invalidExerciseRepetitions(index: index)
        }
        guard exercise.restSeconds >= 0, exercise.restSeconds <= maxRestSeconds,
              (exercise.defaultRestSeconds ?? 0) >= 0,
              (exercise.defaultRestSeconds ?? 0) <= maxRestSeconds,
              (exercise.defaultRestTargetBPM ?? 60) >= 30,
              (exercise.defaultRestTargetBPM ?? 60) <= 220 else {
            throw RoutineImportError.invalidExerciseRest(index: index)
        }
        guard exercise.targetWeight.isFinite,
              exercise.targetWeight >= 0.0,
              exercise.targetWeight <= maxWeightKg else {
            throw RoutineImportError.invalidExerciseWeight(index: index)
        }
        guard exercise.notes.count <= maxNotesLength else {
            throw RoutineImportError.invalidExerciseNotes(index: index)
        }
    }

    // MARK: - Nombres

    /// Primer nombre libre respecto a las rutinas existentes: `PUSH`,
    /// `PUSH (2)`, `PUSH (3)`… Compara sin distinguir mayúsculas ni acentos.
    static func availableName(for requestedName: String, existingRoutines: [Routine]) -> String {
        let base: String = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "Rutina importada" }

        let taken: Set<String> = Set(existingRoutines.map { normalizeName($0.name) })
        guard taken.contains(normalizeName(base)) else { return base }

        var suffix: Int = 2
        while suffix < 1_000 {
            let candidate: String = "\(base) (\(suffix))"
            if !taken.contains(normalizeName(candidate)) {
                return candidate
            }
            suffix += 1
        }
        return "\(base) (\(UUID().uuidString.prefix(4)))"
    }

    static func normalizeName(_ name: String) -> String {
        return name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
    }

    // MARK: - Importación

    /// Crea la rutina en la biblioteca del receptor de forma atómica.
    ///
    /// - Identidad nueva: el UUID del emisor nunca se reutiliza.
    /// - Sin carpeta: no se escribe en ninguna `RoutineFolder`.
    /// - Los ejercicios se reutilizan solo cuando la equivalencia es
    ///   inequívoca (mismo nombre normalizado, mismo músculo y mismo
    ///   equipamiento); en cualquier otro caso se crea uno independiente.
    /// - `simulatePersistenceFailure` solo existe para comprobar el `rollback`
    ///   en las pruebas: fuerza un error después de insertar la rutina.
    static func importRoutine(
        _ request: RoutineImportRequest,
        into context: ModelContext,
        simulatePersistenceFailure: Bool = false
    ) throws -> Routine {
        let payload: RoutineSharePayload = request.payload
        // Defensa en profundidad: nunca se escribe nada que no pase la
        // validación, aunque la petición se construya por otra vía.
        try validate(payload)

        let routines: [Routine] = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        let exercises: [Exercise] = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []

        let previousAutosave: Bool = context.autosaveEnabled
        context.autosaveEnabled = false

        do {
            var knownRoutines: [Routine] = routines
            var knownExercises: [Exercise] = exercises
            let routine: Routine = insertRoutine(
                from: payload.routine,
                into: context,
                routines: &knownRoutines,
                exercises: &knownExercises
            )

            if simulatePersistenceFailure {
                throw RoutineImportError.importFailed
            }

            try context.save()
            context.autosaveEnabled = previousAutosave
            return routine
        } catch {
            context.rollback()
            context.autosaveEnabled = previousAutosave

            if let importError = error as? RoutineImportError {
                throw importError
            }
            throw RoutineImportError.importFailed
        }
    }

    /// Inserta una rutina y sus vínculos sin guardar.
    ///
    /// Lo usan tanto la importación individual como la de splits, para que las
    /// dos compartan identidad nueva, política de nombres, resolución de
    /// ejercicios y orden. El llamador controla el `save` y el `rollback`.
    @discardableResult
    static func insertRoutine(
        from shared: RoutineShareRoutine,
        into context: ModelContext,
        routines: inout [Routine],
        exercises: inout [Exercise]
    ) -> Routine {
        let name: String = availableName(for: shared.name, existingRoutines: routines)
        let nextOrder: Int = (routines.map(\.sortOrder).max() ?? -1) + 1
        let source: RoutineSource = RoutineSource(rawValue: shared.source) ?? .manual

        let routine: Routine = Routine(
            name: name,
            isTemplate: true,
            sortOrder: nextOrder,
            exercises: [],
            isArchived: false,
            source: source
        )
        context.insert(routine)

        var links: [RoutineExercise] = []

        for item in shared.exercises.sorted(by: { lhs, rhs in lhs.sortOrder < rhs.sortOrder }) {
            let exercise: Exercise = resolveExercise(item, among: exercises, context: context)
            if !exercises.contains(where: { $0 === exercise }) {
                exercises.append(exercise)
            }

            let link: RoutineExercise = RoutineExercise(
                exercise: exercise,
                defaultSets: item.sets,
                targetRepsMin: item.repsMin,
                targetRepsMax: item.repsMax,
                sortOrder: item.sortOrder,
                defaultWeight: item.targetWeight,
                restSeconds: item.restSeconds,
                notes: item.notes,
                hasCustomRest: true
            )
            context.insert(link)
            links.append(link)
        }

        routine.exercises = links
        routines.append(routine)
        return routine
    }

    // MARK: - Resolución de ejercicios

    /// Clave conservadora de equivalencia: nombre normalizado sin mayúsculas,
    /// acentos ni puntuación. Dos nombres distintos nunca comparten clave.
    static func equivalenceKey(for name: String) -> String {
        let folded: String = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "es_ES")
        )
        let allowed: CharacterSet = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " "))
        let mapped: String = folded.unicodeScalars
            .map { scalar in allowed.contains(scalar) ? String(scalar) : " " }
            .joined()
        return mapped
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Devuelve un ejercicio local equivalente solo si la equivalencia es
    /// inequívoca; si no, crea uno nuevo sin tocar los existentes.
    private static func resolveExercise(
        _ shared: RoutineShareExercise,
        among localExercises: [Exercise],
        context: ModelContext
    ) -> Exercise {
        let key: String = equivalenceKey(for: shared.name)
        let muscle: String = shared.muscleGroupRaw
        let equipment: String = shared.equipmentTypeRaw

        let matches: [Exercise] = localExercises.filter { exercise in
            return exercise.muscleGroupRaw == muscle
                && exercise.equipmentTypeRaw == equipment
                && equivalenceKey(for: exercise.name) == key
        }

        if matches.count == 1 {
            return matches[0]
        }

        let created: Exercise = makeExercise(from: shared)
        context.insert(created)
        return created
    }

    private static func makeExercise(from shared: RoutineShareExercise) -> Exercise {
        let muscleGroup: MuscleGroup = MuscleGroup.mappedValue(for: shared.muscleGroupRaw) ?? .chest
        let equipment: EquipmentType = EquipmentType(rawValue: shared.equipmentTypeRaw) ?? .bodyweight
        let trackingMode: ExerciseTrackingMode = ExerciseTrackingMode(rawValue: shared.trackingModeRaw) ?? .reps

        let restCondition: RestCondition
        if let targetBPM: Int = shared.defaultRestTargetBPM, targetBPM > 0 {
            restCondition = .bpmDrop(targetBpm: targetBPM)
        } else {
            restCondition = .timer(seconds: shared.defaultRestSeconds ?? shared.restSeconds)
        }

        return Exercise(
            name: shared.name.trimmingCharacters(in: .whitespacesAndNewlines),
            muscleGroup: muscleGroup,
            equipmentType: equipment,
            requiresStraps: shared.requiresStraps,
            targetRepsMin: shared.targetRepsMin,
            targetRepsMax: shared.targetRepsMax,
            defaultRestCondition: restCondition,
            hasCustomRequiresStraps: true,
            hasCustomEquipment: true,
            hasCustomRestCondition: true,
            trackingMode: trackingMode
        )
    }
}
