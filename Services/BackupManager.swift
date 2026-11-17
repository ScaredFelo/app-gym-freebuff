import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Errores de copia de seguridad

/// Errores controlados del motor de copia de seguridad. Todos exponen un
/// mensaje en español listo para mostrarse en la alerta de resultado.
enum BackupError: LocalizedError {
    case readFailed
    case invalidFile
    case unsupportedVersion(version: Int)
    case encodingFailed
    case safetyCopyFailed
    case restoreFailed

    var errorDescription: String? {
        switch self {
        case .readFailed:
            return "No se ha podido leer el archivo seleccionado."
        case .invalidFile:
            return "El archivo no es una copia de seguridad válida de AppGym."
        case .unsupportedVersion(let version):
            return "El archivo pertenece a una versión más reciente de AppGym (v\(version)). Actualiza la app para poder importarlo."
        case .encodingFailed:
            return "No se ha podido generar el archivo de copia de seguridad."
        case .safetyCopyFailed:
            return "No se ha podido guardar la copia automática de tus datos actuales, así que la importación se ha cancelado."
        case .restoreFailed:
            return "No se ha podido aplicar la importación. Tus datos actuales se han conservado."
        }
    }
}

// MARK: - DTOs de ejercicios y rutinas

/// Snapshot completo de un `Exercise` para no depender del modelo `@Model`
/// al serializar.
struct ExerciseBackupDTO: Codable {
    var name: String
    var muscleGroupRaw: String
    var equipmentTypeRaw: String
    var requiresStraps: Bool
    var targetRepsMin: Int
    var targetRepsMax: Int
    var defaultRestSeconds: Int?
    var defaultRestTargetBPM: Int?
}

extension ExerciseBackupDTO {
    /// Reconstruye la condición de descanso original (temporizador o caída de BPM).
    var restCondition: RestCondition {
        if let targetBPM: Int = defaultRestTargetBPM {
            return .bpmDrop(targetBpm: targetBPM)
        }
        return .timer(seconds: max(0, defaultRestSeconds ?? 90))
    }
}

/// Snapshot de un `RoutineExercise` junto con los datos de su ejercicio.
struct RoutineExerciseBackupDTO: Codable {
    var id: UUID
    var sortOrder: Int
    var targetSets: Int
    var targetRepsMin: Int
    var targetRepsMax: Int
    var targetWeight: Double
    var restSeconds: Int
    var notes: String
    var exercise: ExerciseBackupDTO
}

/// Snapshot de una `Routine` con su lista ordenada de ejercicios.
struct RoutineBackupDTO: Codable {
    var id: UUID
    var name: String
    var isTemplate: Bool
    var sortOrder: Int
    var exercises: [RoutineExerciseBackupDTO]
}

// MARK: - DTOs de sesiones

/// Snapshot de una serie completada con sus marcas temporales.
struct WorkoutSetBackupDTO: Codable {
    var id: UUID
    var setNumber: Int
    var weight: Double
    var reps: Int
    var setCompletedTime: Date
    var restDuration: TimeInterval
}

/// Snapshot del bloque de ejecución de un ejercicio dentro de la sesión.
struct WorkoutExerciseBackupDTO: Codable {
    var id: UUID
    var exerciseName: String
    var exercise: ExerciseBackupDTO?
    var exerciseStartTime: Date
    var exerciseEndTime: Date
    var sets: [WorkoutSetBackupDTO]
}

/// Snapshot de una muestra de pulso.
struct BPMSampleBackupDTO: Codable {
    var id: UUID
    var timestamp: Date
    var bpm: Double
}

/// Snapshot de una `WorkoutSession` con su historial completo.
struct WorkoutSessionBackupDTO: Codable {
    var id: UUID
    var routineName: String
    var startDate: Date
    var endDate: Date?
    var totalVolumeKg: Double
    var exercises: [WorkoutExerciseBackupDTO]
    var bpmSamples: [BPMSampleBackupDTO]
}

// MARK: - DTOs de ajustes

/// Ajustes del gimnasio y de frecuencia cardíaca gestionados por
/// `UserSettingsManager` (persistidos en `UserDefaults`).
struct SettingsBackupDTO: Codable {
    var isBigPictureMode: Bool
    var multipowerBarWeight: Double
    var ezBarWeight: Double
    var availablePlates: [Double]
    var hrMax: Double
    var hrRest: Double
}

// MARK: - Copia completa

/// Raíz del archivo JSON de copia de seguridad.
struct AppBackupData: Codable {
    /// Versión del formato de copia soportada por esta build.
    static let currentVersion: Int = 1

    var version: Int
    var exportDate: Date
    var routines: [RoutineBackupDTO]
    var sessions: [WorkoutSessionBackupDTO]
    var settings: SettingsBackupDTO
}

// MARK: - Documento para SwiftUI

/// Documento que integra el backup con `.fileExporter` / `.fileImporter`.
struct WorkoutBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents: Data = configuration.file.regularFileContents else {
            throw BackupError.invalidFile
        }
        self.data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Copias automáticas previas

/// Copia de seguridad que la app guarda en disco antes de sobrescribir los
/// datos al importar, para poder recuperarlos después.
struct PreImportBackup: Identifiable, Hashable {
    let id: String
    let url: URL
    let date: Date
    let byteCount: Int
}

// MARK: - Motor de copia de seguridad

/// Exporta e importa toda la base de datos SwiftData y los ajustes del
/// gimnasio en un único archivo JSON.
///
/// Los ajustes se leen y escriben a través de `UserSettingsManager` (utilidades
/// estáticas sobre `UserDefaults`), que es la única fuente de verdad de la
/// configuración del gimnasio.
enum BackupManager {
    // MARK: - Export

    /// Nombre por defecto del archivo: `AppGym_Backup_YYYY-MM-DD.json`.
    static func defaultFileName() -> String {
        return "AppGym_Backup_\(makeDateFormatter("yyyy-MM-dd").string(from: Date())).json"
    }

    /// Genera el documento JSON con rutinas, ejercicios, sesiones (series,
    /// tiempos y muestras de BPM) y ajustes del gimnasio.
    static func createBackupDocument(context: ModelContext) throws -> WorkoutBackupDocument {
        let backup: AppBackupData = try makeBackupData(
            context: context,
            exportDate: Date()
        )

        do {
            let data: Data = try makeEncoder().encode(backup)
            return WorkoutBackupDocument(data: data)
        } catch {
            throw BackupError.encodingFailed
        }
    }

    // MARK: - Import

    /// Sustituye las rutinas, las sesiones y los ajustes actuales por los del
    /// archivo indicado, guardando antes una copia automática de los datos que
    /// se van a sobrescribir.
    static func restoreBackup(from url: URL, context: ModelContext) throws {
        let hasAccess: Bool = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.readFailed
        }

        let backup: AppBackupData
        do {
            backup = try makeDecoder().decode(AppBackupData.self, from: data)
        } catch {
            throw BackupError.invalidFile
        }

        guard backup.version <= AppBackupData.currentVersion else {
            throw BackupError.unsupportedVersion(version: backup.version)
        }

        // Copia automática previa: si no se puede guardar, no se toca nada.
        try saveSafetyCopy(context: context)

        try applyBackup(backup, context: context)
    }

    // MARK: - Construcción del backup

    private static func makeBackupData(
        context: ModelContext,
        exportDate: Date
    ) throws -> AppBackupData {
        let routines: [Routine] = try context.fetch(
            FetchDescriptor<Routine>(sortBy: [SortDescriptor(\Routine.sortOrder)])
        )
        let sessions: [WorkoutSession] = try context.fetch(
            FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\WorkoutSession.startDate)])
        )
        let exercises: [Exercise] = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []

        var exerciseSnapshots: [String: ExerciseBackupDTO] = [:]
        for exercise in exercises {
            exerciseSnapshots[normalizedName(exercise.name)] = makeExerciseDTO(exercise)
        }

        let routineDTOs: [RoutineBackupDTO] = routines.map { (routine: Routine) -> RoutineBackupDTO in
            return makeRoutineDTO(routine)
        }
        let sessionDTOs: [WorkoutSessionBackupDTO] = sessions.map { (session: WorkoutSession) -> WorkoutSessionBackupDTO in
            return makeSessionDTO(session, exerciseSnapshots: exerciseSnapshots)
        }

        return AppBackupData(
            version: AppBackupData.currentVersion,
            exportDate: exportDate,
            routines: routineDTOs,
            sessions: sessionDTOs,
            settings: makeSettingsDTO()
        )
    }

    private static func makeRoutineDTO(_ routine: Routine) -> RoutineBackupDTO {
        let exercises: [RoutineExerciseBackupDTO] = routine.exercises
            .sorted { (lhs: RoutineExercise, rhs: RoutineExercise) -> Bool in
                return lhs.sortOrder < rhs.sortOrder
            }
            .compactMap { (routineExercise: RoutineExercise) -> RoutineExerciseBackupDTO? in
                guard let exercise: Exercise = routineExercise.exercise else { return nil }
                return RoutineExerciseBackupDTO(
                    id: routineExercise.id,
                    sortOrder: routineExercise.sortOrder,
                    targetSets: routineExercise.defaultSets,
                    targetRepsMin: routineExercise.targetRepsMin,
                    targetRepsMax: routineExercise.targetRepsMax,
                    targetWeight: routineExercise.defaultWeight,
                    restSeconds: routineExercise.restSeconds,
                    notes: routineExercise.notes,
                    exercise: makeExerciseDTO(exercise)
                )
            }

        return RoutineBackupDTO(
            id: routine.id,
            name: routine.name,
            isTemplate: routine.isTemplate,
            sortOrder: routine.sortOrder,
            exercises: exercises
        )
    }

    private static func makeExerciseDTO(_ exercise: Exercise) -> ExerciseBackupDTO {
        var restSeconds: Int? = nil
        var restTargetBPM: Int? = nil

        switch exercise.defaultRestCondition {
        case .timer(let seconds):
            restSeconds = seconds
        case .bpmDrop(let targetBpm):
            restTargetBPM = targetBpm
        }

        return ExerciseBackupDTO(
            name: exercise.name,
            muscleGroupRaw: exercise.muscleGroupRaw,
            equipmentTypeRaw: exercise.equipmentTypeRaw,
            requiresStraps: exercise.requiresStraps,
            targetRepsMin: exercise.targetRepsMin,
            targetRepsMax: exercise.targetRepsMax,
            defaultRestSeconds: restSeconds,
            defaultRestTargetBPM: restTargetBPM
        )
    }

    private static func makeSessionDTO(
        _ session: WorkoutSession,
        exerciseSnapshots: [String: ExerciseBackupDTO]
    ) -> WorkoutSessionBackupDTO {
        // Las sesiones antiguas sin registros detallados se reconstruyen con el
        // mismo cálculo que usa la app al finalizar un entrenamiento.
        let storedRecords: [WorkoutExerciseRecord] = session.exerciseRecords
        let records: [WorkoutExerciseRecord] = storedRecords.isEmpty
            ? WorkoutMetricsCalculator.buildExerciseRecords(for: session)
            : storedRecords

        let exercises: [WorkoutExerciseBackupDTO] = records.map { (record: WorkoutExerciseRecord) -> WorkoutExerciseBackupDTO in
            let sortedSets: [WorkoutSetRecord] = record.sets.sorted { (lhs: WorkoutSetRecord, rhs: WorkoutSetRecord) -> Bool in
                return lhs.setNumber < rhs.setNumber
            }
            let setSnapshots: [WorkoutSetBackupDTO] = sortedSets.map { (setRecord: WorkoutSetRecord) -> WorkoutSetBackupDTO in
                return WorkoutSetBackupDTO(
                    id: setRecord.id,
                    setNumber: setRecord.setNumber,
                    weight: setRecord.weight,
                    reps: setRecord.reps,
                    setCompletedTime: setRecord.setCompletedTime,
                    restDuration: setRecord.restDuration
                )
            }

            return WorkoutExerciseBackupDTO(
                id: record.id,
                exerciseName: record.exerciseName,
                exercise: exerciseSnapshots[normalizedName(record.exerciseName)],
                exerciseStartTime: record.exerciseStartTime,
                exerciseEndTime: record.exerciseEndTime,
                sets: setSnapshots
            )
        }

        let samples: [BPMSampleBackupDTO] = session.bpmSamples.map { (sample: BPMSample) -> BPMSampleBackupDTO in
            return BPMSampleBackupDTO(
                id: sample.id,
                timestamp: sample.timestamp,
                bpm: sample.bpm
            )
        }

        return WorkoutSessionBackupDTO(
            id: session.id,
            routineName: session.routineName,
            startDate: session.startDate,
            endDate: session.endDate,
            totalVolumeKg: session.totalVolumeKg,
            exercises: exercises,
            bpmSamples: samples
        )
    }

    private static func makeSettingsDTO() -> SettingsBackupDTO {
        return SettingsBackupDTO(
            isBigPictureMode: UserDefaults.standard.bool(forKey: UserSettingsManager.isBigPictureModeEnabledKey),
            multipowerBarWeight: UserSettingsManager.multipowerBarWeight,
            ezBarWeight: UserSettingsManager.ezBarWeight,
            availablePlates: UserSettingsManager.availablePlates,
            hrMax: UserSettingsManager.hrMax,
            hrRest: UserSettingsManager.hrRest
        )
    }

    // MARK: - Restauración

    /// Reemplaza el contenido de la base de datos de forma atómica: no hay
    /// ningún `save()` intermedio entre el borrado y la reconstrucción, de modo
    /// que un fallo deshace todos los cambios pendientes con `rollback()` y deja
    /// intactos los datos que el usuario ya tenía.
    private static func applyBackup(_ backup: AppBackupData, context: ModelContext) throws {
        let wasAutosaveEnabled: Bool = context.autosaveEnabled
        context.autosaveEnabled = false
        defer {
            context.autosaveEnabled = wasAutosaveEnabled
        }

        do {
            try replaceExistingData(with: backup, context: context)
            try context.save()
        } catch {
            context.rollback()
            throw BackupError.restoreFailed
        }

        // Los ajustes se escriben solo cuando la importación ya está guardada,
        // para no dejar `UserDefaults` a medias si algo falla antes.
        applySettings(backup.settings)
    }

    private static func replaceExistingData(with backup: AppBackupData, context: ModelContext) throws {
        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        for session in sessions {
            let logs: [WorkoutSetLog] = session.setsCompleted
            for log in logs {
                context.delete(log)
            }
            context.delete(session)
        }

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        for routine in routines {
            context.delete(routine)
        }

        var exerciseCache: [String: Exercise] = makeExerciseCache(context: context)

        for routineDTO in backup.routines {
            let routine: Routine = Routine(
                id: routineDTO.id,
                name: routineDTO.name,
                isTemplate: routineDTO.isTemplate,
                sortOrder: routineDTO.sortOrder
            )
            context.insert(routine)

            var routineExercises: [RoutineExercise] = []
            for exerciseDTO in routineDTO.exercises {
                let exercise: Exercise? = resolveExercise(
                    snapshot: exerciseDTO.exercise,
                    name: exerciseDTO.exercise.name,
                    cache: &exerciseCache,
                    context: context
                )

                let routineExercise: RoutineExercise = RoutineExercise(
                    id: exerciseDTO.id,
                    exercise: exercise,
                    defaultSets: exerciseDTO.targetSets,
                    targetRepsMin: exerciseDTO.targetRepsMin,
                    targetRepsMax: exerciseDTO.targetRepsMax,
                    sortOrder: exerciseDTO.sortOrder,
                    defaultWeight: exerciseDTO.targetWeight,
                    restSeconds: exerciseDTO.restSeconds,
                    notes: exerciseDTO.notes
                )
                context.insert(routineExercise)
                routineExercises.append(routineExercise)
            }
            routine.exercises = routineExercises
        }

        for sessionDTO in backup.sessions {
            insertSession(sessionDTO, cache: &exerciseCache, context: context)
        }
    }

    private static func makeExerciseCache(context: ModelContext) -> [String: Exercise] {
        let existing: [Exercise] = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var cache: [String: Exercise] = [:]
        for exercise in existing {
            cache[normalizedName(exercise.name)] = exercise
        }
        return cache
    }

    /// Reutiliza el ejercicio ya existente con el mismo nombre o lo crea a
    /// partir del snapshot del archivo.
    private static func resolveExercise(
        snapshot: ExerciseBackupDTO?,
        name: String,
        cache: inout [String: Exercise],
        context: ModelContext
    ) -> Exercise? {
        let key: String = normalizedName(name)

        if let existing: Exercise = cache[key] {
            return existing
        }

        guard let snapshot: ExerciseBackupDTO = snapshot else {
            return nil
        }

        let exercise: Exercise = Exercise(
            name: snapshot.name,
            muscleGroup: MuscleGroup.fromStoredRawValue(snapshot.muscleGroupRaw),
            equipmentType: EquipmentType.fromStoredRawValue(snapshot.equipmentTypeRaw),
            requiresStraps: snapshot.requiresStraps,
            targetRepsMin: snapshot.targetRepsMin,
            targetRepsMax: snapshot.targetRepsMax,
            defaultRestCondition: snapshot.restCondition
        )
        context.insert(exercise)
        cache[key] = exercise
        return exercise
    }

    private static func insertSession(
        _ dto: WorkoutSessionBackupDTO,
        cache: inout [String: Exercise],
        context: ModelContext
    ) {
        let session: WorkoutSession = WorkoutSession(
            id: dto.id,
            startDate: dto.startDate,
            endDate: dto.endDate,
            totalVolumeKg: dto.totalVolumeKg,
            routineName: dto.routineName
        )
        context.insert(session)

        var setLogs: [WorkoutSetLog] = []
        var records: [WorkoutExerciseRecord] = []

        for exerciseDTO in dto.exercises {
            let exercise: Exercise? = resolveExercise(
                snapshot: exerciseDTO.exercise,
                name: exerciseDTO.exerciseName,
                cache: &cache,
                context: context
            )

            var setRecords: [WorkoutSetRecord] = []
            for setDTO in exerciseDTO.sets {
                let log: WorkoutSetLog = WorkoutSetLog(
                    id: setDTO.id,
                    date: setDTO.setCompletedTime,
                    workoutStartDate: dto.startDate,
                    weight: setDTO.weight,
                    reps: setDTO.reps,
                    isCompleted: true,
                    routineExerciseID: nil,
                    setNumber: setDTO.setNumber,
                    exercise: exercise,
                    session: session
                )
                context.insert(log)
                setLogs.append(log)

                setRecords.append(
                    WorkoutSetRecord(
                        id: setDTO.id,
                        setNumber: setDTO.setNumber,
                        weight: setDTO.weight,
                        reps: setDTO.reps,
                        setCompletedTime: setDTO.setCompletedTime,
                        restDuration: setDTO.restDuration
                    )
                )
            }

            records.append(
                WorkoutExerciseRecord(
                    id: exerciseDTO.id,
                    exerciseID: exercise?.id,
                    exerciseName: exerciseDTO.exerciseName,
                    exerciseStartTime: exerciseDTO.exerciseStartTime,
                    exerciseEndTime: exerciseDTO.exerciseEndTime,
                    sets: setRecords
                )
            )
        }

        session.setsCompleted = setLogs
        session.exerciseRecords = records
        session.bpmSamples = dto.bpmSamples.map { (sample: BPMSampleBackupDTO) -> BPMSample in
            return BPMSample(
                id: sample.id,
                timestamp: sample.timestamp,
                bpm: sample.bpm
            )
        }
    }

    private static func applySettings(_ settings: SettingsBackupDTO) {
        let defaults: UserDefaults = UserDefaults.standard

        defaults.set(settings.isBigPictureMode, forKey: UserSettingsManager.isBigPictureModeEnabledKey)
        defaults.set(settings.multipowerBarWeight, forKey: UserSettingsManager.multipowerBarWeightKey)
        defaults.set(settings.ezBarWeight, forKey: UserSettingsManager.ezBarWeightKey)
        defaults.set(
            UserSettingsManager.serializePlates(Set(settings.availablePlates)),
            forKey: UserSettingsManager.availablePlatesKey
        )
        defaults.set(settings.hrMax, forKey: UserSettingsManager.hrMaxBPMKey)
        defaults.set(settings.hrRest, forKey: UserSettingsManager.hrRestBPMKey)
    }

    // MARK: - Copia automática previa a la importación

    /// Copias automáticas que se conservan en disco.
    private static let maximumSafetyCopies: Int = 3

    /// Guarda en disco un JSON con los datos actuales antes de sobrescribirlos.
    /// Es lanzado desde `restoreBackup`, de modo que cada importación deja una
    /// copia recuperable aunque sus datos originales se sustituyan.
    static func saveSafetyCopy(context: ModelContext) throws {
        do {
            let date: Date = Date()
            let backup: AppBackupData = try makeBackupData(context: context, exportDate: date)
            let data: Data = try makeEncoder().encode(backup)
            let fileName: String = "AppGym_PreImport_\(makeDateFormatter("yyyy-MM-dd_HH-mm-ss").string(from: date)).json"

            let directory: URL = try safetyCopyDirectory()
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)

            pruneSafetyCopies(in: directory)
        } catch {
            throw BackupError.safetyCopyFailed
        }
    }

    /// Copias automáticas disponibles, de la más reciente a la más antigua.
    static func availableSafetyCopies() -> [PreImportBackup] {
        let fileManager: FileManager = FileManager.default
        guard let directory: URL = try? safetyCopyDirectory(),
              let contents: [URL] = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
              ) else {
            return []
        }

        let copies: [PreImportBackup] = contents
            .filter { (url: URL) -> Bool in
                return url.lastPathComponent.hasPrefix("AppGym_PreImport_")
            }
            .compactMap { (url: URL) -> PreImportBackup? in
                let values: URLResourceValues? = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey]
                )
                return PreImportBackup(
                    id: url.lastPathComponent,
                    url: url,
                    date: values?.contentModificationDate ?? Date.distantPast,
                    byteCount: values?.fileSize ?? 0
                )
            }

        return copies.sorted { (lhs: PreImportBackup, rhs: PreImportBackup) -> Bool in
            return lhs.date > rhs.date
        }
    }

    private static func safetyCopyDirectory() throws -> URL {
        let fileManager: FileManager = FileManager.default
        guard let base: URL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw BackupError.safetyCopyFailed
        }

        let directory: URL = base.appendingPathComponent("Backups", isDirectory: true)
        guard !fileManager.fileExists(atPath: directory.path) else {
            return directory
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw BackupError.safetyCopyFailed
        }
        return directory
    }

    /// Conserva solo las copias automáticas más recientes (el nombre incluye la
    /// fecha, así que ordena lexicográficamente).
    private static func pruneSafetyCopies(in directory: URL) {
        let fileManager: FileManager = FileManager.default
        guard let contents: [URL] = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return
        }

        let copies: [URL] = contents
            .filter { (url: URL) -> Bool in
                return url.lastPathComponent.hasPrefix("AppGym_PreImport_")
            }
            .sorted { (lhs: URL, rhs: URL) -> Bool in
                return lhs.lastPathComponent > rhs.lastPathComponent
            }

        for url in copies.dropFirst(maximumSafetyCopies) {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Utilidades

    private static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }

    private static func normalizedName(_ name: String) -> String {
        return name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder: JSONDecoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
