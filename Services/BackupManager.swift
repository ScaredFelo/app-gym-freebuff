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
    case validationFailed(BackupValidationReport)

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
        case .validationFailed(let report):
            return report.localizedMessage
        }
    }
}

// MARK: - Resultado estructurado de validación

/// Categoría de una incidencia. Solo `warning` permite continuar; las demás
/// bloquean la sustitución de datos.
enum BackupIssueCategory: String, Codable, Equatable {
    case warning
    case incompatible
    case corrupt
    case conflict

    var blocksImport: Bool {
        return self != .warning
    }
}

/// Motivos estables para poder probar y presentar las incidencias sin depender
/// del texto exacto del mensaje.
enum BackupIssueCode: String, Codable, Equatable {
    case unsupportedVersion
    case tooLarge
    case duplicateRoutineID
    case duplicateRoutineExerciseID
    case duplicateExerciseIDWithDifferentContent
    case duplicateSessionID
    case duplicateSessionExerciseID
    case duplicateSetID
    case duplicateAssistedPlanID
    case missingRoutineName
    case missingExerciseName
    case invalidTargetSets
    case invalidRepetitions
    case invalidRest
    case invalidWeight
    case invalidSortOrder
    case invalidExerciseID
    case missingExerciseRelation
    case missingExerciseSnapshot
    case ambiguousExerciseName
    case invalidRoutineSource
    case protectedRoutineMissingInBackup
    case protectedRoutineContentConflict
    case protectedRoutineNameConflict
    case duplicateProtectedRoutineInCurrentStore
    case cannotReadCurrentData
    case corruptAssistedPlan
    case incompleteAssistedPlan
    case duplicateAssistedWeekday
    case invalidAssistedPlanDay
    case multipleActiveAssistedPlans
    case missingSessionHistory
    case invalidSessionData
    case invalidSettings
}

struct BackupIssue: Identifiable, Equatable {
    let id: UUID
    let category: BackupIssueCategory
    let code: BackupIssueCode
    let message: String
    let routineID: UUID?
    let exerciseID: UUID?

    init(
        id: UUID = UUID(),
        category: BackupIssueCategory,
        code: BackupIssueCode,
        message: String,
        routineID: UUID? = nil,
        exerciseID: UUID? = nil
    ) {
        self.id = id
        self.category = category
        self.code = code
        self.message = message
        self.routineID = routineID
        self.exerciseID = exerciseID
    }
}

enum BackupValidationStatus: String, Equatable {
    case valid
    case validWithWarnings
    case incompatible
    case corrupt
    case requiresUserIntervention
}

struct BackupValidationReport: Equatable {
    let issues: [BackupIssue]

    var blockingIssues: [BackupIssue] {
        return issues.filter { (issue: BackupIssue) -> Bool in issue.category.blocksImport }
    }

    var warnings: [BackupIssue] {
        return issues.filter { (issue: BackupIssue) -> Bool in issue.category == .warning }
    }

    var canImport: Bool {
        return blockingIssues.isEmpty
    }

    var status: BackupValidationStatus {
        if issues.contains(where: { $0.category == .corrupt }) { return .corrupt }
        if issues.contains(where: { $0.category == .incompatible }) { return .incompatible }
        if issues.contains(where: { $0.category == .conflict }) { return .requiresUserIntervention }
        return issues.isEmpty ? .valid : .validWithWarnings
    }

    var localizedMessage: String {
        let blocking: [BackupIssue] = blockingIssues
        guard !blocking.isEmpty else {
            return warnings.isEmpty
                ? "La copia de seguridad es válida."
                : "La copia de seguridad es válida con \(warnings.count) aviso(s)."
        }

        let details: String = blocking.prefix(3)
            .map { (issue: BackupIssue) -> String in "• \(issue.message)" }
            .joined(separator: "\n")
        let extra: String = blocking.count > 3 ? "\n• Y \(blocking.count - 3) problema(s) más." : ""
        return "La copia no se puede importar. No se ha modificado ningún dato.\n\(details)\(extra)"
    }
}

/// Resultado de exportación: incluye avisos que impiden presentar el archivo
/// como una copia íntegra, aunque el archivo se pueda generar.
struct BackupExportResult {
    let document: WorkoutBackupDocument
    let report: BackupValidationReport
}

/// Plan de importación ya validado. No contiene cambios aplicados.
struct BackupImportPlan {
    let backup: AppBackupData
    let report: BackupValidationReport
    let preservedProtectedRoutineIDs: Set<UUID>
}

/// Resultado de una importación ya aplicada.
struct BackupImportResult {
    let report: BackupValidationReport
    let preservedProtectedRoutineIDs: Set<UUID>
    let importedRoutineIDs: [UUID]
}

// MARK: - DTOs de ejercicios y rutinas

/// Snapshot completo de un `Exercise` para no depender del modelo `@Model`
/// al serializar.
struct ExerciseBackupDTO: Codable, Equatable {
    /// Identidad original del ejercicio. Es opcional para leer copias creadas
    /// antes de que el formato la guardara.
    var id: UUID? = nil
    var name: String
    var muscleGroupRaw: String
    var equipmentTypeRaw: String
    var requiresStraps: Bool
    var targetRepsMin: Int
    var targetRepsMax: Int
    var defaultRestSeconds: Int?
    var defaultRestTargetBPM: Int?
    /// Unidad de registro (`reps`, `seconds`, `minutes`). Opcional para poder
    /// leer archivos exportados antes de existir el campo.
    var trackingModeRaw: String?

    // MARK: Campos añadidos después de la versión 1
    //
    // Todos son opcionales para seguir leyendo archivos antiguos. Sin ellos la
    // importación perdía las notas y los ajustes manuales del usuario.

    var isCompound: Bool? = nil
    var primaryMusclesRaw: String? = nil
    var secondaryMusclesRaw: String? = nil
    var notes: String? = nil
    var whyGoodExercise: String? = nil
    var whyBadExercise: String? = nil
    var whenRecommended: String? = nil
    var whenNotRecommended: String? = nil
    var hasCustomRequiresStraps: Bool? = nil
    var hasCustomEquipment: Bool? = nil
    var hasCustomRestCondition: Bool? = nil
    /// Texto muscular original del catálogo (versión 3).
    var catalogPrimaryMusclesText: String? = nil
    var catalogSecondaryMusclesText: String? = nil
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
    /// Puede faltar si el enlace se quedó sin ejercicio. Se conserva el enlace
    /// para no perder series, repeticiones, descanso ni notas.
    var exercise: ExerciseBackupDTO?
    /// UUID del ejercicio relacionado, independiente del snapshot. Opcional en
    /// copias antiguas.
    var exerciseID: UUID? = nil
    /// `true` si el usuario fijó el descanso del enlace a mano.
    var hasCustomRest: Bool? = nil
}

/// Snapshot de una `Routine` con su lista ordenada de ejercicios.
struct RoutineBackupDTO: Codable {
    var id: UUID
    var name: String
    var isTemplate: Bool
    var sortOrder: Int
    /// Opcional para seguir leyendo copias creadas antes de existir la
    /// procedencia. Sin valor se restaura como manual (no se archiva sola).
    var source: String? = nil
    var exercises: [RoutineExerciseBackupDTO]
    /// Estado de archivado. Opcional para copias anteriores. En una copia
    /// antigua se restaura como no archivada, salvo que la rutina protegida
    /// actual se conserve y mantenga su estado.
    var isArchived: Bool? = nil
}

/// Snapshot de una semana asistida. Es opcional en la raíz para seguir leyendo
/// copias creadas antes del constructor de siete días.
struct AssistedWeekPlanBackupDTO: Codable {
    var id: UUID
    var createdAt: Date
    var isActivePlan: Bool
    var days: [AssistedWeekDayRecord]
    /// Datos originales del plan. Permite conservar un plan que no se puede
    /// decodificar en lugar de exportarlo silenciosamente como vacío.
    var daysData: Data? = nil
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
    /// Campos opcionales para conservar el estado real de `WorkoutSetLog` y
    /// seguir leyendo copias anteriores que no los incluían.
    var targetRepsMin: Int? = nil
    var targetRepsMax: Int? = nil
    var isCompleted: Bool? = nil
    var routineExerciseID: UUID? = nil
    var workoutStartDate: Date? = nil
}

/// Snapshot del bloque de ejecución de un ejercicio dentro de la sesión.
struct WorkoutExerciseBackupDTO: Codable {
    var id: UUID
    var exerciseName: String
    var exercise: ExerciseBackupDTO?
    var exerciseID: UUID? = nil
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
    /// Opcional para seguir leyendo copias anteriores. Si falta, la
    /// restauración conserva el valor actual del usuario.
    var standardBarWeight: Double? = nil
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
    var assistedWeeks: [AssistedWeekPlanBackupDTO]? = nil

    /// Comprobaciones estructurales mínimas antes de sustituir la base de datos.
    /// Un archivo con fechas invertidas o tamaños absurdos se rechaza en lugar
    /// de aplicarse y dejar el historial incoherente.
    var isStructurallyValid: Bool {
        guard routines.count <= 5_000, sessions.count <= 50_000 else { return false }

        for routine in routines where routine.exercises.count > 5_000 {
            return false
        }

        for week in assistedWeeks ?? [] where week.days.count > 7 {
            return false
        }

        for session in sessions {
            guard session.exercises.count <= 5_000 else { return false }
            if let endDate = session.endDate, endDate < session.startDate {
                return false
            }
        }

        return true
    }
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
    ///
    /// Se mantiene por compatibilidad con las llamadas existentes. Para poder
    /// mostrar avisos de integridad, usar `createBackup(context:)`.
    static func createBackupDocument(context: ModelContext) throws -> WorkoutBackupDocument {
        return try createBackup(context: context).document
    }

    /// Genera el backup y devuelve también las incidencias detectadas durante
    /// la exportación. Un aviso no impide generar el archivo, pero evita
    /// presentarlo como una copia completamente íntegra.
    static func createBackup(context: ModelContext) throws -> BackupExportResult {
        let build: BackupBuild = try makeBackupData(
            context: context,
            exportDate: Date()
        )

        do {
            let data: Data = try makeEncoder().encode(build.backup)
            return BackupExportResult(
                document: WorkoutBackupDocument(data: data),
                report: BackupValidationReport(issues: build.issues)
            )
        } catch {
            throw BackupError.encodingFailed
        }
    }

    // MARK: - Import

    /// Lee, valida y prepara la importación sin modificar SwiftData.
    ///
    /// La validación incluye la base actual porque una importación nunca puede
    /// eliminar ni sustituir una de las cinco rutinas protegidas que ya exista.
    static func prepareImport(from url: URL, context: ModelContext) throws -> BackupImportPlan {
        let data: Data = try readBackupData(from: url)

        // Un archivo enorme no puede ser una copia legítima de esta app.
        guard data.count <= maximumBackupBytes else {
            let issue: BackupIssue = BackupIssue(
                category: .incompatible,
                code: .tooLarge,
                message: "El archivo supera el tamaño máximo permitido para una copia de AppGym."
            )
            throw BackupError.validationFailed(BackupValidationReport(issues: [issue]))
        }

        let backup: AppBackupData
        do {
            backup = try makeDecoder().decode(AppBackupData.self, from: data)
        } catch {
            throw BackupError.invalidFile
        }

        let currentProtectedRoutines: [Routine]
        let currentRoutines: [Routine]
        let currentExercises: [Exercise]
        let currentSessionCount: Int
        do {
            currentRoutines = try context.fetch(FetchDescriptor<Routine>())
            currentExercises = try context.fetch(FetchDescriptor<Exercise>())
            currentSessionCount = try context.fetchCount(FetchDescriptor<WorkoutSession>())
            currentProtectedRoutines = currentRoutines.filter { (routine: Routine) -> Bool in
                return seededPersonalRoutineIDs.contains(routine.id)
            }
        } catch {
            let issue: BackupIssue = BackupIssue(
                category: .conflict,
                code: .cannotReadCurrentData,
                message: "No se ha podido leer la base actual. Para no arriesgar tus rutinas, la importación no se realizará."
            )
            return BackupImportPlan(
                backup: backup,
                report: BackupValidationReport(issues: [issue]),
                preservedProtectedRoutineIDs: []
            )
        }

        let report: BackupValidationReport = validate(
            backup,
            currentExercises: currentExercises,
            currentProtectedRoutines: currentProtectedRoutines,
            currentSessionCount: currentSessionCount
        )

        return BackupImportPlan(
            backup: backup,
            report: report,
            preservedProtectedRoutineIDs: Set(currentProtectedRoutines.map(\.id))
        )
    }

    /// Sustituye las rutinas, las sesiones y los ajustes actuales por los del
    /// archivo indicado, guardando antes una copia automática de los datos que
    /// se van a sobrescribir.
    ///
    /// La validación se ejecuta antes de crear la copia de seguridad y antes de
    /// tocar SwiftData. Si falla, no se modifica nada.
    @discardableResult
    static func restoreBackup(
        from url: URL,
        context: ModelContext,
        safetyCopyDirectory overrideDirectory: URL? = nil
    ) throws -> BackupImportResult {
        let plan: BackupImportPlan = try prepareImport(from: url, context: context)
        guard plan.report.canImport else {
            throw BackupError.validationFailed(plan.report)
        }

        // Copia automática previa: si no se puede guardar, no se toca nada.
        try saveSafetyCopy(context: context, directory: overrideDirectory)

        let importedRoutineIDs: [UUID] = try applyBackup(plan, context: context)
        return BackupImportResult(
            report: plan.report,
            preservedProtectedRoutineIDs: plan.preservedProtectedRoutineIDs,
            importedRoutineIDs: importedRoutineIDs
        )
    }

    private static func readBackupData(from url: URL) throws -> Data {
        let hasAccess: Bool = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            throw BackupError.readFailed
        }
    }

    // MARK: - Construcción del backup

    private struct BackupBuild {
        let backup: AppBackupData
        let issues: [BackupIssue]
    }

    private static func makeBackupData(
        context: ModelContext,
        exportDate: Date
    ) throws -> BackupBuild {
        let routines: [Routine] = try context.fetch(
            FetchDescriptor<Routine>(sortBy: [SortDescriptor(\Routine.sortOrder)])
        )
        let sessions: [WorkoutSession] = try context.fetch(
            FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\WorkoutSession.startDate)])
        )
        let exercises: [Exercise] = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let assistedPlans: [AssistedWeekPlan] = (try? context.fetch(FetchDescriptor<AssistedWeekPlan>())) ?? []

        var issues: [BackupIssue] = []
        var exerciseSnapshotsByName: [String: ExerciseBackupDTO] = [:]
        var exerciseSnapshotsByID: [UUID: ExerciseBackupDTO] = [:]
        for exercise in exercises {
            let snapshot: ExerciseBackupDTO = makeExerciseDTO(exercise)
            let nameKey: String = normalizedName(exercise.name)
            if exerciseSnapshotsByName[nameKey] != nil {
                issues.append(
                    BackupIssue(
                        category: .warning,
                        code: .ambiguousExerciseName,
                        message: "Hay varios ejercicios con el nombre «\(exercise.name)». Se conserva cada UUID, pero los registros históricos antiguos sin UUID de ejercicio no pueden resolver el nombre con certeza."
                    )
                )
            }
            exerciseSnapshotsByName[nameKey] = snapshot
            exerciseSnapshotsByID[exercise.id] = snapshot
        }

        var routineDTOs: [RoutineBackupDTO] = []
        routineDTOs.reserveCapacity(routines.count)
        for routine in routines {
            routineDTOs.append(makeRoutineDTO(routine, issues: &issues))
        }
        let sessionDTOs: [WorkoutSessionBackupDTO] = sessions.map { (session: WorkoutSession) -> WorkoutSessionBackupDTO in
            return makeSessionDTO(
                session,
                exerciseSnapshotsByName: exerciseSnapshotsByName,
                exerciseSnapshotsByID: exerciseSnapshotsByID
            )
        }
        let assistedDTOs: [AssistedWeekPlanBackupDTO] = assistedPlans.map { (plan: AssistedWeekPlan) -> AssistedWeekPlanBackupDTO in
            if !plan.daysData.isEmpty, decodePlanDays(plan.daysData) == nil {
                issues.append(
                    BackupIssue(
                        category: .warning,
                        code: .corruptAssistedPlan,
                        message: "El plan asistido «\(plan.id.uuidString)» tiene datos ilegibles. Se conservarán sus datos originales en la copia, pero no se puede interpretar en esta exportación.",
                        routineID: nil
                    )
                )
            }
            return AssistedWeekPlanBackupDTO(
                id: plan.id,
                createdAt: plan.createdAt,
                isActivePlan: plan.isActivePlan,
                days: plan.days,
                daysData: plan.daysData
            )
        }

        let backup: AppBackupData = AppBackupData(
            version: AppBackupData.currentVersion,
            exportDate: exportDate,
            routines: routineDTOs,
            sessions: sessionDTOs,
            settings: makeSettingsDTO(),
            assistedWeeks: assistedDTOs
        )
        return BackupBuild(backup: backup, issues: issues)
    }

    private static func makeRoutineDTO(_ routine: Routine, issues: inout [BackupIssue]) -> RoutineBackupDTO {
        let exercises: [RoutineExerciseBackupDTO] = routine.exercises
            .sorted { (lhs: RoutineExercise, rhs: RoutineExercise) -> Bool in
                return lhs.sortOrder < rhs.sortOrder
            }
            .map { (routineExercise: RoutineExercise) -> RoutineExerciseBackupDTO in
                let exercise: Exercise? = routineExercise.exercise
                if exercise == nil {
                    issues.append(
                        BackupIssue(
                            category: .warning,
                            code: .missingExerciseRelation,
                            message: "La rutina «\(routine.name)» tiene un enlace sin ejercicio (orden \(routineExercise.sortOrder)). Se conservará el enlace con sus series, repeticiones, descanso y notas, pero sin inventar un ejercicio.",
                            routineID: routine.id
                        )
                    )
                }
                return RoutineExerciseBackupDTO(
                    id: routineExercise.id,
                    sortOrder: routineExercise.sortOrder,
                    targetSets: routineExercise.defaultSets,
                    targetRepsMin: routineExercise.targetRepsMin,
                    targetRepsMax: routineExercise.targetRepsMax,
                    targetWeight: routineExercise.defaultWeight,
                    restSeconds: routineExercise.restSeconds,
                    notes: routineExercise.notes,
                    exercise: exercise.map(makeExerciseDTO),
                    exerciseID: exercise?.id,
                    hasCustomRest: routineExercise.hasCustomRest
                )
            }

        return RoutineBackupDTO(
            id: routine.id,
            name: routine.name,
            isTemplate: routine.isTemplate,
            sortOrder: routine.sortOrder,
            source: routine.source.rawValue,
            exercises: exercises,
            isArchived: routine.isArchived
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
            id: exercise.id,
            name: exercise.name,
            muscleGroupRaw: exercise.muscleGroupRaw,
            equipmentTypeRaw: exercise.equipmentTypeRaw,
            requiresStraps: exercise.requiresStraps,
            targetRepsMin: exercise.targetRepsMin,
            targetRepsMax: exercise.targetRepsMax,
            defaultRestSeconds: restSeconds,
            defaultRestTargetBPM: restTargetBPM,
            trackingModeRaw: exercise.trackingModeRaw,
            isCompound: exercise.isCompound,
            primaryMusclesRaw: exercise.primaryMusclesRaw,
            secondaryMusclesRaw: exercise.secondaryMusclesRaw,
            notes: exercise.notes,
            whyGoodExercise: exercise.whyGoodExercise,
            whyBadExercise: exercise.whyBadExercise,
            whenRecommended: exercise.whenRecommended,
            whenNotRecommended: exercise.whenNotRecommended,
            hasCustomRequiresStraps: exercise.hasCustomRequiresStraps,
            hasCustomEquipment: exercise.hasCustomEquipment,
            hasCustomRestCondition: exercise.hasCustomRestCondition,
            catalogPrimaryMusclesText: exercise.catalogPrimaryMusclesText,
            catalogSecondaryMusclesText: exercise.catalogSecondaryMusclesText
        )
    }

    private static func makeSessionDTO(
        _ session: WorkoutSession,
        exerciseSnapshotsByName: [String: ExerciseBackupDTO],
        exerciseSnapshotsByID: [UUID: ExerciseBackupDTO]
    ) -> WorkoutSessionBackupDTO {
        // Las sesiones antiguas sin registros detallados se reconstruyen con el
        // mismo cálculo que usa la app al finalizar un entrenamiento.
        let storedRecords: [WorkoutExerciseRecord] = session.exerciseRecords
        let records: [WorkoutExerciseRecord] = storedRecords.isEmpty
            ? WorkoutMetricsCalculator.buildExerciseRecords(for: session)
            : storedRecords

        var setLogsByID: [UUID: WorkoutSetLog] = [:]
        for log in session.setsCompleted {
            setLogsByID[log.id] = log
        }

        let exercises: [WorkoutExerciseBackupDTO] = records.map { (record: WorkoutExerciseRecord) -> WorkoutExerciseBackupDTO in
            let sortedSets: [WorkoutSetRecord] = record.sets.sorted { (lhs: WorkoutSetRecord, rhs: WorkoutSetRecord) -> Bool in
                return lhs.setNumber < rhs.setNumber
            }
            let setSnapshots: [WorkoutSetBackupDTO] = sortedSets.map { (setRecord: WorkoutSetRecord) -> WorkoutSetBackupDTO in
                let log: WorkoutSetLog? = setLogsByID[setRecord.id]
                return WorkoutSetBackupDTO(
                    id: setRecord.id,
                    setNumber: setRecord.setNumber,
                    weight: setRecord.weight,
                    reps: setRecord.reps,
                    setCompletedTime: setRecord.setCompletedTime,
                    restDuration: setRecord.restDuration,
                    targetRepsMin: log?.targetRepsMin,
                    targetRepsMax: log?.targetRepsMax,
                    isCompleted: log?.isCompleted,
                    routineExerciseID: log?.routineExerciseID,
                    workoutStartDate: log?.workoutStartDate
                )
            }

            let snapshot: ExerciseBackupDTO? = record.exerciseID.flatMap { exerciseSnapshotsByID[$0] }
                ?? exerciseSnapshotsByName[normalizedName(record.exerciseName)]
            return WorkoutExerciseBackupDTO(
                id: record.id,
                exerciseName: record.exerciseName,
                exercise: snapshot,
                exerciseID: record.exerciseID ?? snapshot?.id,
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
            standardBarWeight: UserSettingsManager.standardBarWeight,
            availablePlates: UserSettingsManager.availablePlates,
            hrMax: UserSettingsManager.hrMax,
            hrRest: UserSettingsManager.hrRest
        )
    }

    // MARK: - Validación de integridad

    private static func validate(
        _ backup: AppBackupData,
        currentExercises: [Exercise],
        currentProtectedRoutines: [Routine],
        currentSessionCount: Int
    ) -> BackupValidationReport {
        var issues: [BackupIssue] = []

        func add(
            _ category: BackupIssueCategory,
            _ code: BackupIssueCode,
            _ message: String,
            routineID: UUID? = nil,
            exerciseID: UUID? = nil
        ) {
            issues.append(
                BackupIssue(
                    category: category,
                    code: code,
                    message: message,
                    routineID: routineID,
                    exerciseID: exerciseID
                )
            )
        }

        if backup.version < 1 || backup.version > AppBackupData.currentVersion {
            add(
                .incompatible,
                .unsupportedVersion,
                "La versión del archivo (\(backup.version)) no es compatible con esta versión de AppGym."
            )
        }

        guard backup.routines.count <= 5_000, backup.sessions.count <= 50_000 else {
            add(.incompatible, .tooLarge, "El archivo contiene más rutinas o sesiones de las que AppGym puede importar de forma segura.")
            return BackupValidationReport(issues: issues)
        }

        let currentExerciseIDs: Set<UUID> = Set(currentExercises.map(\.id))
        let currentExercisesByName: [String: [Exercise]] = Dictionary(
            grouping: currentExercises,
            by: { (exercise: Exercise) -> String in normalizedName(exercise.name) }
        )

        var currentProtectedByID: [UUID: Routine] = [:]
        for routine in currentProtectedRoutines {
            if currentProtectedByID[routine.id] != nil {
                add(
                    .conflict,
                    .duplicateProtectedRoutineInCurrentStore,
                    "La base actual contiene más de una rutina con el UUID protegido \(routine.id.uuidString). Para no elegir la incorrecta, la importación no se realizará.",
                    routineID: routine.id
                )
            } else {
                currentProtectedByID[routine.id] = routine
            }
        }

        var currentProtectedByName: [String: Routine] = [:]
        var currentProtectedLinkIDs: Set<UUID> = []
        for routine in currentProtectedRoutines {
            currentProtectedByName[normalizedName(routine.name)] = routine
            currentProtectedLinkIDs.formUnion(routine.exercises.map(\.id))
        }

        // Rutinas y enlaces.
        var routineByID: [UUID: RoutineBackupDTO] = [:]
        var allRoutineExerciseIDs: Set<UUID> = []
        var exerciseByID: [UUID: ExerciseBackupDTO] = [:]
        var routineExerciseSnapshotIDs: Set<UUID> = []

        func registerExerciseSnapshot(
            _ snapshot: ExerciseBackupDTO,
            id: UUID,
            routineID: UUID?,
            isRoutineSnapshot: Bool
        ) {
            // Un mismo ejercicio puede aparecer con el nombre histórico en
            // una sesión y con el nombre actual en una rutina. Eso no es un
            // UUID duplicado conflictivo: la identidad manda. Solo se bloquea
            // si dos rutinas distintas describen el mismo UUID de forma
            // incompatible.
            if isRoutineSnapshot {
                let hadRoutineSnapshot: Bool = routineExerciseSnapshotIDs.contains(id)
                if hadRoutineSnapshot,
                   let existing: ExerciseBackupDTO = exerciseByID[id],
                   existing != snapshot {
                    add(
                        .incompatible,
                        .duplicateExerciseIDWithDifferentContent,
                        "El UUID de ejercicio \(id.uuidString) aparece con datos distintos en dos rutinas de la copia. No se puede elegir una identidad de forma segura.",
                        routineID: routineID,
                        exerciseID: id
                    )
                }
                routineExerciseSnapshotIDs.insert(id)
                if !hadRoutineSnapshot || exerciseByID[id] == nil {
                    exerciseByID[id] = snapshot
                }
            } else if exerciseByID[id] == nil {
                exerciseByID[id] = snapshot
            }
        }

        func validateExerciseSnapshot(
            _ snapshot: ExerciseBackupDTO,
            routineID: UUID?
        ) {
            if snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                add(
                    .incompatible,
                    .missingExerciseName,
                    "Hay un ejercicio sin nombre en la copia de seguridad.",
                    routineID: routineID,
                    exerciseID: snapshot.id
                )
            }
            if snapshot.targetRepsMin < 0 || snapshot.targetRepsMax < snapshot.targetRepsMin {
                add(
                    .incompatible,
                    .invalidRepetitions,
                    "El ejercicio «\(snapshot.name)» tiene un rango de repeticiones inválido.",
                    routineID: routineID,
                    exerciseID: snapshot.id
                )
            }
            if let rest = snapshot.defaultRestSeconds, rest < 0 {
                add(
                    .incompatible,
                    .invalidRest,
                    "El ejercicio «\(snapshot.name)» tiene un descanso negativo.",
                    routineID: routineID,
                    exerciseID: snapshot.id
                )
            }
        }

        for routine in backup.routines {
            if routineByID[routine.id] != nil {
                add(
                    .incompatible,
                    .duplicateRoutineID,
                    "El UUID de rutina \(routine.id.uuidString) aparece más de una vez en la copia.",
                    routineID: routine.id
                )
                continue
            }
            routineByID[routine.id] = routine

            if routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                add(
                    .incompatible,
                    .missingRoutineName,
                    "Hay una rutina sin nombre en la copia de seguridad.",
                    routineID: routine.id
                )
            }
            if routine.exercises.count > 5_000 {
                add(
                    .incompatible,
                    .tooLarge,
                    "La rutina «\(routine.name)» contiene demasiados ejercicios.",
                    routineID: routine.id
                )
            }
            if let source = routine.source, RoutineSource(rawValue: source) == nil {
                add(
                    .warning,
                    .invalidRoutineSource,
                    "La rutina «\(routine.name)» tiene una procedencia desconocida; se restaurará como manual.",
                    routineID: routine.id
                )
            }

            var sortOrders: Set<Int> = []
            for link in routine.exercises {
                if !allRoutineExerciseIDs.insert(link.id).inserted {
                    add(
                        .incompatible,
                        .duplicateRoutineExerciseID,
                        "El UUID de enlace \(link.id.uuidString) aparece más de una vez en la copia.",
                        routineID: routine.id
                    )
                }
                if currentProtectedLinkIDs.contains(link.id) {
                    // El mismo enlace de una rutina protegida que se conserva no
                    // se reconstruye, así que repetir su UUID es correcto. En
                    // cualquier otra rutina sí crearía una colisión.
                    let belongsToPreservedRoutine: Bool = currentProtectedByID[routine.id]?
                        .exercises.contains(where: { $0.id == link.id }) ?? false
                    if !belongsToPreservedRoutine {
                        add(
                            .conflict,
                            .duplicateRoutineExerciseID,
                            "El UUID de enlace \(link.id.uuidString) ya pertenece a una rutina protegida de esta instalación y la copia lo usa en otra rutina.",
                            routineID: routine.id
                        )
                    }
                }
                if link.targetSets < 0 {
                    add(
                        .incompatible,
                        .invalidTargetSets,
                        "La rutina «\(routine.name)» tiene un enlace con series negativas.",
                        routineID: routine.id
                    )
                } else if link.targetSets == 0 {
                    add(
                        .warning,
                        .invalidTargetSets,
                        "La rutina «\(routine.name)» tiene un enlace con cero series; se conservará tal cual.",
                        routineID: routine.id
                    )
                }
                if link.targetRepsMin < 0 || link.targetRepsMax < link.targetRepsMin {
                    add(
                        .incompatible,
                        .invalidRepetitions,
                        "La rutina «\(routine.name)» tiene un enlace con repeticiones inválidas.",
                        routineID: routine.id
                    )
                }
                if link.restSeconds < 0 {
                    add(
                        .incompatible,
                        .invalidRest,
                        "La rutina «\(routine.name)» tiene un enlace con descanso negativo.",
                        routineID: routine.id
                    )
                }
                if !link.targetWeight.isFinite || link.targetWeight < 0 {
                    add(
                        .incompatible,
                        .invalidWeight,
                        "La rutina «\(routine.name)» tiene un enlace con un peso no válido.",
                        routineID: routine.id
                    )
                }
                if !sortOrders.insert(link.sortOrder).inserted {
                    add(
                        .warning,
                        .invalidSortOrder,
                        "La rutina «\(routine.name)» tiene dos enlaces con el mismo orden (\(link.sortOrder)). Se conservará el orden guardado.",
                        routineID: routine.id
                    )
                }

                if let snapshot = link.exercise {
                    validateExerciseSnapshot(snapshot, routineID: routine.id)
                    if let declared = link.exerciseID,
                       let snapshotID = snapshot.id,
                       declared != snapshotID {
                        add(
                            .incompatible,
                            .invalidExerciseID,
                            "El enlace de la rutina «\(routine.name)» declara un UUID de ejercicio distinto al de su snapshot.",
                            routineID: routine.id,
                            exerciseID: declared
                        )
                    }
                }

                let effectiveExerciseID: UUID? = link.exerciseID ?? link.exercise?.id
                if let exerciseID = effectiveExerciseID {
                    if let snapshot = link.exercise {
                        registerExerciseSnapshot(
                            snapshot,
                            id: exerciseID,
                            routineID: routine.id,
                            isRoutineSnapshot: true
                        )
                    } else if !currentExerciseIDs.contains(exerciseID) {
                        add(
                            .incompatible,
                            .missingExerciseSnapshot,
                            "La rutina «\(routine.name)» referencia el ejercicio \(exerciseID.uuidString), que no existe en la copia ni en la base actual.",
                            routineID: routine.id,
                            exerciseID: exerciseID
                        )
                    }
                } else if link.exercise == nil {
                    add(
                        .warning,
                        .missingExerciseRelation,
                        "La rutina «\(routine.name)» contiene un enlace sin ejercicio. Se conservará el enlace con sus datos, sin inventar un ejercicio.",
                        routineID: routine.id
                    )
                } else {
                    add(
                        .warning,
                        .missingExerciseUUID,
                        "La rutina «\(routine.name)» contiene un ejercicio sin UUID (copia antigua). Se resolverá por nombre solo si hay una coincidencia única.",
                        routineID: routine.id
                    )
                }
            }
        }

        // Conflictos con las cinco rutinas protegidas actuales.
        for current in currentProtectedRoutines {
            guard let backupRoutine: RoutineBackupDTO = routineByID[current.id] else {
                add(
                    .warning,
                    .protectedRoutineMissingInBackup,
                    "La copia no contiene la rutina protegida «\(current.name)» (\(current.id.uuidString)). Se conservará la rutina actual con su UUID, ejercicios y configuración.",
                    routineID: current.id
                )
                continue
            }

            let differences: [String] = protectedRoutineDifferences(backupRoutine, current)
            if !differences.isEmpty {
                let detail: String = differences.prefix(5).joined(separator: "; ")
                add(
                    .conflict,
                    .protectedRoutineContentConflict,
                    "La rutina protegida «\(current.name)» existe en la copia con el mismo UUID, pero su contenido no coincide: \(detail). No se sustituirá sin una decisión explícita.",
                    routineID: current.id
                )
            }
        }

        for backupRoutine in backup.routines {
            if let protected = currentProtectedByName[normalizedName(backupRoutine.name)],
               protected.id != backupRoutine.id {
                add(
                    .warning,
                    .protectedRoutineNameConflict,
                    "La copia contiene una rutina llamada «\(backupRoutine.name)» con un UUID distinto al de la rutina protegida actual. No se reasignará por nombre; se conservará la protegida y se importará la de la copia como otra rutina.",
                    routineID: backupRoutine.id
                )
            }
        }

        // Ejercicios sin UUID en copias antiguas: si el nombre es ambiguo, no se
        // puede elegir una identidad de forma segura.
        for routine in backup.routines {
            for link in routine.exercises where link.exerciseID == nil {
                guard let snapshot = link.exercise, snapshot.id == nil else { continue }
                let key: String = normalizedName(snapshot.name)
                if let matches = currentExercisesByName[key], matches.count > 1 {
                    add(
                        .conflict,
                        .ambiguousExerciseName,
                        "El ejercicio «\(snapshot.name)» de una copia antigua coincide con varios ejercicios actuales. No se puede resolver por nombre sin intervención.",
                        routineID: routine.id
                    )
                }
            }
        }

        // Planes asistidos. Solo cuentan las rutinas que existirán después de
        // aplicar la importación: las del backup y las protegidas actuales que
        // se conservan. Las rutinas actuales no protegidas se sustituyen.
        let availableRoutineIDs: Set<UUID> = Set(routineByID.keys)
            .union(currentProtectedRoutines.map(\.id))
        var planIDs: Set<UUID> = []
        var activePlanCount: Int = 0

        for plan in backup.assistedWeeks ?? [] {
            if !planIDs.insert(plan.id).inserted {
                add(
                    .incompatible,
                    .duplicateAssistedPlanID,
                    "El UUID de plan asistido \(plan.id.uuidString) aparece más de una vez en la copia."
                )
            }
            if plan.isActivePlan {
                activePlanCount += 1
            }

            let resolvedDays: [AssistedWeekDayRecord]
            if let rawData = plan.daysData {
                if let decoded = decodePlanDays(rawData) {
                    resolvedDays = decoded
                    if !plan.days.isEmpty && plan.days != decoded {
                        add(
                            .warning,
                            .corruptAssistedPlan,
                            "El plan asistido \(plan.id.uuidString) contiene días distintos entre su representación y sus datos originales. Se usarán los datos originales."
                        )
                    }
                } else {
                    add(
                        .corrupt,
                        .corruptAssistedPlan,
                        "El plan asistido \(plan.id.uuidString) tiene datos ilegibles. No se convertirá en un plan vacío."
                    )
                    resolvedDays = plan.days
                }
            } else {
                resolvedDays = plan.days
            }

            if resolvedDays.count != AssistedWeekday.allCases.count {
                add(
                    .incompatible,
                    .incompleteAssistedPlan,
                    "El plan asistido \(plan.id.uuidString) debe tener exactamente 7 días y tiene \(resolvedDays.count)."
                )
            }

            var weekdays: Set<Int> = []
            for day in resolvedDays {
                guard day.weekdayIndex >= 0,
                      day.weekdayIndex < AssistedWeekday.allCases.count else {
                    add(
                        .incompatible,
                        .invalidAssistedPlanDay,
                        "El plan asistido \(plan.id.uuidString) contiene un día fuera de rango (\(day.weekdayIndex))."
                    )
                    continue
                }
                if !weekdays.insert(day.weekdayIndex).inserted {
                    add(
                        .incompatible,
                        .duplicateAssistedWeekday,
                        "El plan asistido \(plan.id.uuidString) contiene el día \(day.weekdayIndex) más de una vez."
                    )
                }

                if day.isRest {
                    if day.routineID != nil {
                        add(
                            .incompatible,
                            .invalidAssistedPlanDay,
                            "El plan asistido \(plan.id.uuidString) tiene un día de descanso con rutina asociada."
                        )
                    }
                } else {
                    guard let routineID = day.routineID else {
                        add(
                            .incompatible,
                            .invalidAssistedPlanDay,
                            "El plan asistido \(plan.id.uuidString) tiene un día de entrenamiento sin rutina."
                        )
                        continue
                    }
                    if !availableRoutineIDs.contains(routineID) {
                        add(
                            .incompatible,
                            .missingExerciseRelation,
                            "El plan asistido \(plan.id.uuidString) referencia la rutina \(routineID.uuidString), que no existe en la copia ni en la base actual."
                        )
                    }
                    if day.routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        add(
                            .incompatible,
                            .invalidAssistedPlanDay,
                            "El plan asistido \(plan.id.uuidString) tiene un día de entrenamiento sin nombre de rutina."
                        )
                    }
                    if day.sessionIndex == nil {
                        add(
                            .incompatible,
                            .invalidAssistedPlanDay,
                            "El plan asistido \(plan.id.uuidString) tiene un día de entrenamiento sin índice de sesión."
                        )
                    }
                    if let sessionIndex = day.sessionIndex, sessionIndex < 0 {
                        add(
                            .incompatible,
                            .invalidAssistedPlanDay,
                            "El plan asistido \(plan.id.uuidString) tiene un índice de sesión negativo."
                        )
                    }
                    if !["", "A", "B", "C"].contains(day.variantSuffix) {
                        add(
                            .warning,
                            .invalidAssistedPlanDay,
                            "El plan asistido \(plan.id.uuidString) tiene una variante desconocida «\(day.variantSuffix)»; se conservará tal cual."
                        )
                    }
                }
            }

            let expectedWeekdays: Set<Int> = Set(AssistedWeekday.allCases.map(\.rawValue))
            if weekdays != expectedWeekdays {
                add(
                    .incompatible,
                    .incompleteAssistedPlan,
                    "El plan asistido \(plan.id.uuidString) no identifica exactamente los siete días esperados."
                )
            }
        }

        if activePlanCount > 1 {
            add(
                .conflict,
                .multipleActiveAssistedPlans,
                "La copia contiene más de un plan asistido activo. Debe existir como máximo uno para no dejar el estado ambiguo."
            )
        }

        // Historial de sesiones.
        if backup.sessions.isEmpty, currentSessionCount > 0 {
            add(
                .warning,
                .missingSessionHistory,
                "La copia no contiene sesiones de entrenamiento. La importación sustituirá el historial actual por vacío; la copia automática previa permitirá recuperarlo."
            )
        }
        var sessionIDs: Set<UUID> = []
        var recordIDs: Set<UUID> = []
        var setIDs: Set<UUID> = []
        for session in backup.sessions {
            if !sessionIDs.insert(session.id).inserted {
                add(
                    .incompatible,
                    .duplicateSessionID,
                    "El UUID de sesión \(session.id.uuidString) aparece más de una vez en la copia."
                )
            }
            if let endDate = session.endDate, endDate < session.startDate {
                add(
                    .warning,
                    .invalidSessionData,
                    "La sesión \(session.id.uuidString) termina antes de empezar; se normalizará al importar."
                )
            }
            if !session.totalVolumeKg.isFinite || session.totalVolumeKg < 0 {
                add(
                    .warning,
                    .invalidSessionData,
                    "La sesión \(session.id.uuidString) tiene un volumen no válido; se normalizará al importar."
                )
            }
            if session.exercises.count > 5_000 {
                add(
                    .incompatible,
                    .tooLarge,
                    "La sesión \(session.id.uuidString) contiene demasiados ejercicios."
                )
            }

            for record in session.exercises {
                if !recordIDs.insert(record.id).inserted {
                    add(
                        .incompatible,
                        .duplicateSessionExerciseID,
                        "El UUID de registro de ejercicio \(record.id.uuidString) aparece más de una vez en la copia."
                    )
                }
                if let snapshot = record.exercise {
                    validateExerciseSnapshot(snapshot, routineID: nil)
                    if let declared = record.exerciseID,
                       let snapshotID = snapshot.id,
                       declared != snapshotID {
                        add(
                            .incompatible,
                            .invalidExerciseID,
                            "Un registro de sesión declara un UUID de ejercicio distinto al de su snapshot.",
                            exerciseID: declared
                        )
                    }
                }
                let effectiveExerciseID: UUID? = record.exerciseID ?? record.exercise?.id
                if let exerciseID = effectiveExerciseID, let snapshot = record.exercise {
                    registerExerciseSnapshot(
                        snapshot,
                        id: exerciseID,
                        routineID: nil,
                        isRoutineSnapshot: false
                    )
                } else if let exerciseID = effectiveExerciseID {
                    add(
                        .warning,
                        .missingExerciseSnapshot,
                        "Un registro histórico de la sesión \(session.id.uuidString) referencia el ejercicio \(exerciseID.uuidString) sin snapshot; se resolverá por UUID si existe en la base actual."
                    )
                } else if record.exercise != nil {
                    add(
                        .warning,
                        .missingExerciseUUID,
                        "Un registro histórico de la sesión \(session.id.uuidString) no conserva el UUID de su ejercicio (copia antigua); se resolverá por nombre solo si hay una coincidencia única."
                    )
                } else {
                    add(
                        .warning,
                        .missingExerciseRelation,
                        "Un registro histórico de la sesión \(session.id.uuidString) no tiene ejercicio; se conservará su nombre y sus series."
                    )
                }

                for set in record.sets {
                    if !setIDs.insert(set.id).inserted {
                        add(
                            .incompatible,
                            .duplicateSetID,
                            "El UUID de serie \(set.id.uuidString) aparece más de una vez en la copia."
                        )
                    }
                    if set.setNumber < 1 {
                        add(
                            .warning,
                            .invalidSessionData,
                            "Una serie de la sesión \(session.id.uuidString) tiene un número inválido."
                        )
                    }
                    if let targetMin = set.targetRepsMin, targetMin < 0 {
                        add(
                            .warning,
                            .invalidSessionData,
                            "Una serie de la sesión \(session.id.uuidString) tiene repeticiones objetivo negativas."
                        )
                    }
                    if let targetMin = set.targetRepsMin,
                       let targetMax = set.targetRepsMax,
                       targetMax < targetMin {
                        add(
                            .warning,
                            .invalidSessionData,
                            "Una serie de la sesión \(session.id.uuidString) tiene un rango de repeticiones objetivo invertido."
                        )
                    }
                    if !set.weight.isFinite || set.weight < 0 {
                        add(
                            .warning,
                            .invalidSessionData,
                            "Una serie de la sesión \(session.id.uuidString) tiene un peso no válido."
                        )
                    }
                    if set.reps < 0 {
                        add(
                            .warning,
                            .invalidSessionData,
                            "Una serie de la sesión \(session.id.uuidString) tiene repeticiones negativas."
                        )
                    }
                    if !set.restDuration.isFinite || set.restDuration < 0 {
                        add(
                            .warning,
                            .invalidSessionData,
                            "Una serie de la sesión \(session.id.uuidString) tiene un descanso no válido."
                        )
                    }
                }
            }

            for sample in session.bpmSamples where !sample.bpm.isFinite || sample.bpm < 0 {
                add(
                    .warning,
                    .invalidSessionData,
                    "Una muestra de BPM de la sesión \(session.id.uuidString) no es válida."
                )
            }
        }

        let settings: SettingsBackupDTO = backup.settings
        let numericSettings: [Double] = [
            settings.multipowerBarWeight,
            settings.ezBarWeight,
            settings.standardBarWeight ?? 0.0,
            settings.hrMax,
            settings.hrRest
        ]
        if numericSettings.contains(where: { (value: Double) -> Bool in !value.isFinite })
            || settings.availablePlates.contains(where: { (value: Double) -> Bool in !value.isFinite || value <= 0 }) {
            add(
                .warning,
                .invalidSettings,
                "La copia contiene ajustes numéricos no válidos; se aplicarán los valores admitidos por la app."
            )
        }

        return BackupValidationReport(issues: issues)
    }

    private static func decodePlanDays(_ data: Data) -> [AssistedWeekDayRecord]? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([AssistedWeekDayRecord].self, from: data)
    }

    /// Compara el contenido que define una rutina protegida. Se comparan los
    /// enlaces por UUID y los campos que el usuario puede configurar; nunca se
    /// usa el nombre para decidir si dos rutinas son la misma.
    private static func protectedRoutineDifferences(
        _ backup: RoutineBackupDTO,
        _ current: Routine
    ) -> [String] {
        var differences: [String] = []

        if backup.name != current.name {
            differences.append("nombre")
        }
        if backup.isTemplate != current.isTemplate {
            differences.append("tipo de rutina")
        }
        if backup.sortOrder != current.sortOrder {
            differences.append("orden de rutina")
        }
        if let backupSource = backup.source, backupSource != current.source.rawValue {
            differences.append("procedencia")
        }
        if let backupArchived = backup.isArchived, backupArchived != current.isArchived {
            differences.append("archivado")
        }
        if backup.exercises.count != current.exercises.count {
            differences.append("número de ejercicios")
        }

        var currentLinksByID: [UUID: RoutineExercise] = [:]
        for link in current.exercises {
            if currentLinksByID[link.id] != nil {
                differences.append("enlace duplicado \(link.id.uuidString)")
            } else {
                currentLinksByID[link.id] = link
            }
        }

        var backupLinkIDs: Set<UUID> = []
        for backupLink in backup.exercises {
            backupLinkIDs.insert(backupLink.id)
            guard let currentLink: RoutineExercise = currentLinksByID[backupLink.id] else {
                differences.append("falta el enlace \(backupLink.id.uuidString)")
                continue
            }

            if backupLink.sortOrder != currentLink.sortOrder { differences.append("orden de enlace") }
            if backupLink.targetSets != currentLink.defaultSets { differences.append("series") }
            if backupLink.targetRepsMin != currentLink.targetRepsMin
                || backupLink.targetRepsMax != currentLink.targetRepsMax { differences.append("repeticiones") }
            if backupLink.targetWeight != currentLink.defaultWeight { differences.append("peso") }
            if backupLink.restSeconds != currentLink.restSeconds { differences.append("descanso") }
            if backupLink.notes != currentLink.notes { differences.append("notas") }
            if let backupCustomRest = backupLink.hasCustomRest,
               backupCustomRest != currentLink.hasCustomRest {
                differences.append("descanso personalizado")
            }

            let backupExerciseID: UUID? = backupLink.exerciseID ?? backupLink.exercise?.id
            if let backupExerciseID {
                if backupExerciseID != currentLink.exercise?.id {
                    differences.append("ejercicio relacionado")
                }
            } else if let backupExercise = backupLink.exercise, let currentExercise = currentLink.exercise {
                // Copia antigua sin UUID de ejercicio: para comparar una rutina
                // protegida que se va a conservar se admite el nombre como
                // última señal, sin usarlo para reasignar ninguna identidad.
                if normalizedName(backupExercise.name) != normalizedName(currentExercise.name) {
                    differences.append("ejercicio relacionado")
                }
            } else if backupLink.exercise != nil || currentLink.exercise != nil {
                differences.append("ejercicio relacionado")
            }
            if let backupExercise = backupLink.exercise, let currentExercise = currentLink.exercise {
                if backupExercise.name != currentExercise.name { differences.append("nombre del ejercicio") }
                if backupExercise.equipmentTypeRaw != currentExercise.equipmentTypeRaw { differences.append("equipamiento del ejercicio") }
                if backupExercise.targetRepsMin != currentExercise.targetRepsMin
                    || backupExercise.targetRepsMax != currentExercise.targetRepsMax { differences.append("objetivo del ejercicio") }
            }
        }

        for currentLink in current.exercises where !backupLinkIDs.contains(currentLink.id) {
            differences.append("enlace sobrante \(currentLink.id.uuidString)")
        }

        return differences
    }

    // MARK: - Restauración

    /// Reemplaza el contenido de la base de datos de forma atómica: no hay
    /// ningún `save()` intermedio entre el borrado y la reconstrucción, de modo
    /// que un fallo deshace todos los cambios pendientes con `rollback()` y deja
    /// intactos los datos que el usuario ya tenía.
    private static func applyBackup(_ plan: BackupImportPlan, context: ModelContext) throws -> [UUID] {
        let wasAutosaveEnabled: Bool = context.autosaveEnabled
        context.autosaveEnabled = false
        defer {
            context.autosaveEnabled = wasAutosaveEnabled
        }

        let importedRoutineIDs: [UUID]
        do {
            importedRoutineIDs = try replaceExistingData(
                with: plan.backup,
                preservedProtectedRoutineIDs: plan.preservedProtectedRoutineIDs,
                context: context
            )
            try context.save()
        } catch {
            context.rollback()
            throw BackupError.restoreFailed
        }

        // Los ajustes se escriben solo cuando la importación ya está guardada,
        // para no dejar `UserDefaults` a medias si algo falla antes.
        applySettings(plan.backup.settings)

        // Las sesiones restauradas alimentan la racha y el widget semanal.
        let restoredSessions: [WorkoutSession] = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        WidgetStreakStore.recalculateAndSave(
            sessions: restoredSessions,
            weeklyGoal: UserSettingsManager.weeklyWorkoutGoal
        )

        return importedRoutineIDs
    }

    private static func replaceExistingData(
        with backup: AppBackupData,
        preservedProtectedRoutineIDs: Set<UUID>,
        context: ModelContext
    ) throws -> [UUID] {
        let assistedPlans: [AssistedWeekPlan] = try context.fetch(FetchDescriptor<AssistedWeekPlan>())
        for plan in assistedPlans {
            context.delete(plan)
        }

        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        for session in sessions {
            let logs: [WorkoutSetLog] = session.setsCompleted
            for log in logs {
                context.delete(log)
            }
            context.delete(session)
        }

        let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
        var currentProtectedIDs: Set<UUID> = preservedProtectedRoutineIDs
        // Recalcular en el momento de aplicar evita borrar una rutina protegida
        // que se hubiera añadido después de la fase de validación.
        for routine in routines where seededPersonalRoutineIDs.contains(routine.id) {
            currentProtectedIDs.insert(routine.id)
        }
        for routine in routines where !currentProtectedIDs.contains(routine.id) {
            context.delete(routine)
        }

        var exerciseLookup: ExerciseLookup = try ExerciseLookup(context: context)
        var importedRoutineIDs: [UUID] = []

        for routineDTO in backup.routines {
            // La rutina protegida actual nunca se borra ni se reconstruye. Si
            // el backup contiene el mismo UUID, la validación ya comprobó que el
            // contenido coincide; se conserva la instancia actual.
            guard !currentProtectedIDs.contains(routineDTO.id) else { continue }

            let routine: Routine = Routine(
                id: routineDTO.id,
                name: routineDTO.name,
                isTemplate: routineDTO.isTemplate,
                sortOrder: routineDTO.sortOrder,
                isArchived: routineDTO.isArchived ?? false,
                source: routineDTO.source.flatMap(RoutineSource.init(rawValue:)) ?? .manual
            )
            context.insert(routine)
            importedRoutineIDs.append(routine.id)

            var routineExercises: [RoutineExercise] = []
            for exerciseDTO in routineDTO.exercises {
                let exerciseName: String = exerciseDTO.exercise?.name ?? ""
                let exercise: Exercise? = exerciseLookup.resolve(
                    snapshot: exerciseDTO.exercise,
                    explicitID: exerciseDTO.exerciseID,
                    name: exerciseName,
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
                    notes: exerciseDTO.notes,
                    hasCustomRest: exerciseDTO.hasCustomRest ?? false
                )
                context.insert(routineExercise)
                routineExercises.append(routineExercise)
            }
            routine.exercises = routineExercises
        }

        for sessionDTO in backup.sessions {
            try insertSession(sessionDTO, lookup: &exerciseLookup, context: context)
        }

        for weekDTO in backup.assistedWeeks ?? [] {
            let resolvedDays: [AssistedWeekDayRecord] = weekDTO.daysData.flatMap(decodePlanDays) ?? weekDTO.days
            let plan: AssistedWeekPlan = AssistedWeekPlan(
                id: weekDTO.id,
                createdAt: weekDTO.createdAt,
                isActivePlan: weekDTO.isActivePlan,
                days: resolvedDays
            )
            if let rawData = weekDTO.daysData, decodePlanDays(rawData) != nil {
                plan.daysData = rawData
            }
            context.insert(plan)
        }

        return importedRoutineIDs
    }

    /// Índice de ejercicios por UUID y por nombre. La identidad manda: el
    /// nombre solo se usa como respaldo controlado para copias antiguas sin
    /// UUID de ejercicio.
    private struct ExerciseLookup {
        var byID: [UUID: Exercise] = [:]
        var byName: [String: [Exercise]] = [:]

        init(context: ModelContext) throws {
            let existing: [Exercise] = try context.fetch(FetchDescriptor<Exercise>())
            for exercise in existing {
                byID[exercise.id] = exercise
                byName[BackupManager.normalizedName(exercise.name), default: []].append(exercise)
            }
        }

        mutating func resolve(
            snapshot: ExerciseBackupDTO?,
            explicitID: UUID?,
            name: String,
            context: ModelContext
        ) -> Exercise? {
            if let id = explicitID ?? snapshot?.id {
                if let existing = byID[id] {
                    return existing
                }
                guard let snapshot else { return nil }
                return create(snapshot, id: id, context: context)
            }

            let key: String = BackupManager.normalizedName(name.isEmpty ? (snapshot?.name ?? "") : name)
            let matches: [Exercise] = byName[key] ?? []

            // Copia antigua sin UUID: solo se reutiliza una coincidencia única.
            if matches.count == 1 {
                return matches[0]
            }
            guard matches.isEmpty, let snapshot else { return nil }
            return create(snapshot, id: UUID(), context: context)
        }

        private mutating func create(
            _ snapshot: ExerciseBackupDTO,
            id: UUID,
            context: ModelContext
        ) -> Exercise {
            let exercise: Exercise = Exercise(
                id: id,
                name: snapshot.name,
                muscleGroup: MuscleGroup.fromStoredRawValue(snapshot.muscleGroupRaw),
                equipmentType: EquipmentType.fromStoredRawValue(snapshot.equipmentTypeRaw),
                requiresStraps: snapshot.requiresStraps,
                targetRepsMin: snapshot.targetRepsMin,
                targetRepsMax: snapshot.targetRepsMax,
                defaultRestCondition: snapshot.restCondition,
                trackingMode: ExerciseTrackingMode.fromStoredRawValue(snapshot.trackingModeRaw ?? "")
            )

            if let isCompound = snapshot.isCompound { exercise.isCompound = isCompound }
            if let primary = snapshot.primaryMusclesRaw { exercise.primaryMusclesRaw = primary }
            if let secondary = snapshot.secondaryMusclesRaw { exercise.secondaryMusclesRaw = secondary }
            if let text = snapshot.catalogPrimaryMusclesText { exercise.catalogPrimaryMusclesText = text }
            if let text = snapshot.catalogSecondaryMusclesText { exercise.catalogSecondaryMusclesText = text }
            if let notes = snapshot.notes { exercise.notes = notes }
            if let value = snapshot.whyGoodExercise { exercise.whyGoodExercise = value }
            if let value = snapshot.whyBadExercise { exercise.whyBadExercise = value }
            if let value = snapshot.whenRecommended { exercise.whenRecommended = value }
            if let value = snapshot.whenNotRecommended { exercise.whenNotRecommended = value }
            exercise.hasCustomRequiresStraps = snapshot.hasCustomRequiresStraps ?? false
            exercise.hasCustomEquipment = snapshot.hasCustomEquipment ?? false
            exercise.hasCustomRestCondition = snapshot.hasCustomRestCondition ?? false

            context.insert(exercise)
            byID[id] = exercise
            byName[BackupManager.normalizedName(exercise.name), default: []].append(exercise)
            return exercise
        }
    }

    private static func insertSession(
        _ dto: WorkoutSessionBackupDTO,
        lookup: inout ExerciseLookup,
        context: ModelContext
    ) throws {
        // Una fecha de fin anterior al inicio dejaría duraciones negativas en
        // las estadísticas: se normaliza al importar.
        let normalizedEndDate: Date? = dto.endDate.map { max($0, dto.startDate) }
        let session: WorkoutSession = WorkoutSession(
            id: dto.id,
            startDate: dto.startDate,
            endDate: normalizedEndDate,
            totalVolumeKg: max(0, dto.totalVolumeKg),
            routineName: dto.routineName
        )
        context.insert(session)

        var setLogs: [WorkoutSetLog] = []
        var records: [WorkoutExerciseRecord] = []

        for exerciseDTO in dto.exercises {
            let exercise: Exercise? = lookup.resolve(
                snapshot: exerciseDTO.exercise,
                explicitID: exerciseDTO.exerciseID,
                name: exerciseDTO.exerciseName,
                context: context
            )

            var setRecords: [WorkoutSetRecord] = []
            for setDTO in exerciseDTO.sets {
                let log: WorkoutSetLog = WorkoutSetLog(
                    id: setDTO.id,
                    date: setDTO.setCompletedTime,
                    workoutStartDate: setDTO.workoutStartDate ?? dto.startDate,
                    weight: setDTO.weight,
                    reps: setDTO.reps,
                    targetRepsMin: setDTO.targetRepsMin ?? 8,
                    targetRepsMax: setDTO.targetRepsMax ?? 12,
                    isCompleted: setDTO.isCompleted ?? true,
                    routineExerciseID: setDTO.routineExerciseID,
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
                    // Si el UUID venía en la copia pero ya no existe el objeto,
                    // se conserva el identificador histórico en lugar de
                    // borrarlo silenciosamente.
                    exerciseID: exercise?.id ?? exerciseDTO.exerciseID,
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
        if let standardBarWeight = settings.standardBarWeight {
            defaults.set(
                UserSettingsManager.clampedBarWeight(standardBarWeight),
                forKey: UserSettingsManager.standardBarWeightKey
            )
        }
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

    /// Tamaño máximo aceptado para un archivo de importación (64 MB).
    private static let maximumBackupBytes: Int = 64 * 1024 * 1024

    /// Guarda en disco un JSON con los datos actuales antes de sobrescribirlos.
    /// Es lanzado desde `restoreBackup`, de modo que cada importación deja una
    /// copia recuperable aunque sus datos originales se sustituyan.
    static func saveSafetyCopy(context: ModelContext, directory overrideDirectory: URL? = nil) throws {
        do {
            let date: Date = Date()
            let build: BackupBuild = try makeBackupData(context: context, exportDate: date)
            let data: Data = try makeEncoder().encode(build.backup)
            let stamp: String = makeDateFormatter("yyyy-MM-dd_HH-mm-ss-SSS").string(from: date)
            let uniqueSuffix: String = String(UUID().uuidString.prefix(6))
            let fileName: String = "AppGym_PreImport_\(stamp)_\(uniqueSuffix).json"

            let directory: URL = try safetyCopyDirectoryURL(override: overrideDirectory)
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)

            pruneSafetyCopies(in: directory)
        } catch {
            throw BackupError.safetyCopyFailed
        }
    }

    /// Copias automáticas disponibles, de la más reciente a la más antigua.
    static func availableSafetyCopies() -> [PreImportBackup] {
        let fileManager: FileManager = FileManager.default
        guard let directory: URL = try? safetyCopyDirectoryURL(override: nil),
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

    private static func safetyCopyDirectoryURL(override: URL?) throws -> URL {
        let fileManager: FileManager = FileManager.default
        if let override {
            try fileManager.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }

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

    /// Conserva solo las copias automáticas más recientes. El nombre incluye
    /// fecha con milisegundos y un sufijo único para no sobrescribir otra copia.
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
