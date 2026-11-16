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
    case saveFailed

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
        case .saveFailed:
            return "No se han podido guardar los datos importados."
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
    static var writableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data = Data()) {
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

// MARK: - Motor de copia de seguridad

/// Exporta e importa toda la base de datos SwiftData y los ajustes del
/// gimnasio en un único archivo JSON.
///
/// `UserSettingsManager` es un enumerado de utilidades estáticas (no tiene
/// instancias), por eso la dependencia se declara con su metatipo
/// (`UserSettingsManager.Type`) y se invoca como `UserSettingsManager.self`.
enum BackupManager {
    // MARK: - Export

    /// Nombre por defecto del archivo: `AppGym_Backup_YYYY-MM-DD.json`.
    static func defaultFileName(for date: Date = Date()) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return "AppGym_Backup_\(formatter.string(from: date)).json"
    }

    /// Genera el documento JSON con rutinas, ejercicios, sesiones (series,
    /// tiempos y muestras de BPM) y ajustes del gimnasio.
    static func createBackupDocument(
        context: ModelContext,
        settings: UserSettingsManager.Type = UserSettingsManager.self
    ) throws -> WorkoutBackupDocument {
        let backup: AppBackupData = try makeBackupData(
            context: context,
            exportDate: Date(),
            settings: settings
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
    /// archivo indicado.
    static func restoreBackup(
        from url: URL,
        context: ModelContext,
        settings: UserSettingsManager.Type = UserSettingsManager.self
    ) throws {
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

        try applyBackup(backup, context: context, settings: settings)
    }

    /// Mensaje legible para cualquier error producido por el motor.
    static func message(for error: Error) -> String {
        if let backupError: BackupError = error as? BackupError {
            return backupError.errorDescription ?? "Se ha producido un error inesperado."
        }
        return error.localizedDescription
    }

    // MARK: - Construcción del backup

    private static func makeBackupData(
        context: ModelContext,
        exportDate: Date,
        settings: UserSettingsManager.Type
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
            settings: makeSettingsDTO(settings: settings)
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
        let records: [WorkoutExerciseRecord] = session.exerciseRecords
        let exercises: [WorkoutExerciseBackupDTO]

        if records.isEmpty {
            exercises = fallbackExercises(for: session)
        } else {
            exercises = records.map { (record: WorkoutExerciseRecord) -> WorkoutExerciseBackupDTO in
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

    /// Sesiones antiguas sin `exerciseRecords`: reconstruye el historial a
    /// partir de los `WorkoutSetLog` para no perder series ni pesos.
    private static func fallbackExercises(for session: WorkoutSession) -> [WorkoutExerciseBackupDTO] {
        let logs: [WorkoutSetLog] = session.setsCompleted
            .filter { (log: WorkoutSetLog) -> Bool in
                return log.isCompleted
            }
            .sorted { (lhs: WorkoutSetLog, rhs: WorkoutSetLog) -> Bool in
                return lhs.date < rhs.date
            }

        var order: [String] = []
        var grouped: [String: [WorkoutSetLog]] = [:]
        for log in logs {
            let name: String = log.exercise?.name ?? "Ejercicio"
            if grouped[name] == nil {
                order.append(name)
                grouped[name] = []
            }
            grouped[name]?.append(log)
        }

        return order.map { (name: String) -> WorkoutExerciseBackupDTO in
            let exerciseLogs: [WorkoutSetLog] = grouped[name] ?? []
            let startDate: Date = exerciseLogs.first?.date ?? session.startDate
            let endDate: Date = exerciseLogs.last?.date ?? startDate

            let sets: [WorkoutSetBackupDTO] = exerciseLogs.enumerated().map { (index: Int, log: WorkoutSetLog) -> WorkoutSetBackupDTO in
                return WorkoutSetBackupDTO(
                    id: log.id,
                    setNumber: log.setNumber ?? (index + 1),
                    weight: log.weight,
                    reps: log.reps,
                    setCompletedTime: log.date,
                    restDuration: 0
                )
            }

            return WorkoutExerciseBackupDTO(
                id: UUID(),
                exerciseName: name,
                exercise: nil,
                exerciseStartTime: startDate,
                exerciseEndTime: endDate,
                sets: sets
            )
        }
    }

    private static func makeSettingsDTO(settings: UserSettingsManager.Type) -> SettingsBackupDTO {
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

    private static func applyBackup(
        _ backup: AppBackupData,
        context: ModelContext,
        settings: UserSettingsManager.Type
    ) throws {
        try deleteExistingData(context: context)

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

        applySettings(backup.settings)

        do {
            try context.save()
        } catch {
            throw BackupError.saveFailed
        }
    }

    private static func deleteExistingData(context: ModelContext) throws {
        do {
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

            try context.save()
        } catch {
            throw BackupError.saveFailed
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
            muscleGroup: MuscleGroup(rawValue: snapshot.muscleGroupRaw) ?? .pecho,
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

    // MARK: - Utilidades

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
