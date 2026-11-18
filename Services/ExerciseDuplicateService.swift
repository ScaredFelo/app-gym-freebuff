import Foundation
import SwiftData

// MARK: - Unificación de ejercicios duplicados

/// Detecta ejercicios que representan el mismo movimiento con distinto nombre
/// (lo habitual: uno en castellano y otro en inglés) y los unifica en un único
/// registro. Del grupo se conserva el que tiene historial de sesiones y el
/// resultado queda siempre con el nombre en castellano del catálogo.
///
/// Sólo se fusionan dos ejercicios cuando:
/// - sus nombres están en la tabla explícita del catálogo (`canonicalGroups`) y
///   apuntan al mismo nombre canónico, o
/// - sus nombres coinciden al normalizarlos (mayúsculas, acentos y espacios).
///
/// No hay traducciones automáticas ni comparaciones por palabras sueltas: un
/// nombre fuera de la tabla nunca se agrupa con otro distinto.
///
/// Antes de renombrar o eliminar nada se escribe una copia de seguridad en
/// disco con el detalle de los ejercicios afectados (series, rutinas y
/// registros de sesión) y un resumen legible de la fusión.
@MainActor
public enum ExerciseDuplicateService {

    /// Bandera de la unificación, para ejecutarla una sola vez por instalación.
    public static let mergeFlagKey: String = "didMergeDuplicateExercises_v2"
    /// Ruta de la última copia de seguridad escrita antes de unificar.
    public static let backupPathKey: String = "lastExerciseMergeBackupPath_v2"

    // MARK: Punto de entrada

    /// Recorre el catálogo, agrupa los ejercicios que son el mismo movimiento y
    /// fusiona cada grupo conservando series, rutinas y sesiones históricas.
    public static func mergeIfNeeded(context: ModelContext) {
        let defaults: UserDefaults = UserDefaults.standard
        guard !defaults.bool(forKey: mergeFlagKey) else { return }

        let descriptor: FetchDescriptor<Exercise> = FetchDescriptor<Exercise>()
        guard let exercises: [Exercise] = try? context.fetch(descriptor) else { return }

        let plans: [MergePlan] = makePlans(from: exercises)
        guard !plans.isEmpty else {
            defaults.set(true, forKey: mergeFlagKey)
            return
        }

        // La copia de seguridad es obligatoria: si no se puede escribir no se
        // toca ningún ejercicio y la unificación se reintenta en el arranque
        // siguiente.
        guard let backupURL: URL = writeBackup(for: plans, context: context) else {
            print("Unificación de ejercicios cancelada: no se pudo guardar la copia de seguridad.")
            return
        }
        defaults.set(backupURL.path, forKey: backupPathKey)
        print("Copia de seguridad de la unificación: \(backupURL.path)")

        for plan in plans {
            apply(plan, context: context)
        }

        do {
            try context.save()
            defaults.set(true, forKey: mergeFlagKey)
        } catch {
            print("Error unificando ejercicios duplicados (la copia de seguridad está en \(backupURL.path)): \(error)")
        }
    }

    // MARK: Planes de fusión

    private struct MergePlan {
        let canonicalName: String
        let keeper: Exercise
        let targetName: String
        let duplicates: [Exercise]
    }

    /// Agrupa por clave canónica y devuelve sólo los grupos que cambian algo:
    /// fusiones reales o renombrados a la forma canónica del catálogo.
    private static func makePlans(from exercises: [Exercise]) -> [MergePlan] {
        let groups: [String: [Exercise]] = Dictionary(grouping: exercises) { (exercise: Exercise) -> String in
            return canonicalKey(for: exercise.name)
        }

        var plans: [MergePlan] = []
        for key in groups.keys.sorted() {
            guard let group: [Exercise] = groups[key],
                  let keeper: Exercise = bestCandidate(in: group) else { continue }

            let targetName: String = displayName(for: keeper.name)
            let duplicates: [Exercise] = group.filter { (exercise: Exercise) -> Bool in
                return exercise !== keeper
            }

            guard !duplicates.isEmpty || keeper.name != targetName else { continue }

            plans.append(MergePlan(
                canonicalName: key,
                keeper: keeper,
                targetName: targetName,
                duplicates: duplicates
            ))
        }

        return plans
    }

    private static func apply(_ plan: MergePlan, context: ModelContext) {
        // El nombre en castellano se aplica antes de absorber el resto para que
        // los registros históricos de sesión se reescriban ya con ese nombre.
        if plan.keeper.name != plan.targetName {
            plan.keeper.name = plan.targetName
            ExerciseKnowledgeService.fillMissingKnowledge(for: plan.keeper)
        }

        for duplicate in plan.duplicates {
            absorb(duplicate, into: plan.keeper, context: context)
        }
    }

    /// Gana el que más series registradas tiene; en empate, el que ya está con
    /// el nombre canónico y, si no, el primero por orden alfabético.
    private static func bestCandidate(in group: [Exercise]) -> Exercise? {
        return group.max { (lhs: Exercise, rhs: Exercise) -> Bool in
            let lhsScore: Int = score(for: lhs)
            let rhsScore: Int = score(for: rhs)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return lhs.name > rhs.name
        }
    }

    private static func score(for exercise: Exercise) -> Int {
        let history: Int = exercise.logs.count
        let isCanonicalName: Bool = normalize(displayName(for: exercise.name)) == normalize(exercise.name)
        return history * 100 + (isCanonicalName ? 1 : 0)
    }

    /// Traslada historial, rutinas, notas y configuración del duplicado al
    /// ejercicio que se conserva y después lo elimina.
    private static func absorb(_ duplicate: Exercise, into keeper: Exercise, context: ModelContext) {
        for log in duplicate.logs {
            log.exercise = keeper
        }
        duplicate.logs = []

        mergeRoutines(from: duplicate, into: keeper, context: context)
        remapSessionRecords(from: duplicate, to: keeper, context: context)

        if keeper.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keeper.notes = duplicate.notes
        }

        if duplicate.hasCustomRequiresStraps && !keeper.hasCustomRequiresStraps {
            keeper.hasCustomRequiresStraps = true
            keeper.requiresStraps = duplicate.requiresStraps
        }

        context.delete(duplicate)
    }

    /// Apunta a la versión que se conserva las rutinas que usaban el duplicado,
    /// evitando que una misma rutina acabe con el ejercicio repetido.
    private static func mergeRoutines(from duplicate: Exercise, into keeper: Exercise, context: ModelContext) {
        let descriptor: FetchDescriptor<Routine> = FetchDescriptor<Routine>()
        guard let routines: [Routine] = try? context.fetch(descriptor) else { return }

        for routine in routines {
            var hasKeeper: Bool = routine.exercises.contains { (item: RoutineExercise) -> Bool in
                return item.exercise === keeper
            }
            var removable: [RoutineExercise] = []

            for item in routine.exercises where item.exercise === duplicate {
                if hasKeeper {
                    removable.append(item)
                } else {
                    item.exercise = keeper
                    hasKeeper = true
                }
            }

            for item in removable {
                routine.exercises.removeAll { (candidate: RoutineExercise) -> Bool in
                    return candidate === item
                }
                context.delete(item)
            }
        }
    }

    /// Los registros codificados de las sesiones guardan identificador y nombre
    /// del ejercicio: se reapuntan para que el historial no se quede huérfano.
    private static func remapSessionRecords(from duplicate: Exercise, to keeper: Exercise, context: ModelContext) {
        let descriptor: FetchDescriptor<WorkoutSession> = FetchDescriptor<WorkoutSession>()
        guard let sessions: [WorkoutSession] = try? context.fetch(descriptor) else { return }

        let duplicateKey: String = canonicalKey(for: duplicate.name)

        for session in sessions {
            var records: [WorkoutExerciseRecord] = session.exerciseRecords
            guard !records.isEmpty else { continue }

            var didChange: Bool = false
            for index in records.indices {
                let record: WorkoutExerciseRecord = records[index]
                let matchesIdentifier: Bool = record.exerciseID == duplicate.id
                let matchesName: Bool = canonicalKey(for: record.exerciseName) == duplicateKey
                guard matchesIdentifier || matchesName else { continue }

                records[index].exerciseID = keeper.id
                records[index].exerciseName = keeper.name
                didChange = true
            }

            if didChange {
                session.exerciseRecords = records
            }
        }
    }

    // MARK: Copia de seguridad

    private struct Backup: Codable {
        let generatedAt: Date
        let reason: String
        let totalGroups: Int
        let totalRemoved: Int
        let totalLogsMoved: Int
        let summary: [String]
        let groups: [BackupGroup]
    }

    private struct BackupGroup: Codable {
        let canonicalName: String
        let keptName: String
        let finalName: String
        let kept: BackupExercise
        let removed: [BackupExercise]
    }

    private struct BackupExercise: Codable {
        let id: UUID
        let name: String
        let muscleGroup: String
        let equipment: String
        let requiresStraps: Bool
        let hasCustomRequiresStraps: Bool
        let isCompound: Bool
        let targetReps: String
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let notes: String
        let logs: [BackupLog]
        let routines: [BackupRoutineEntry]
        let sessionRecords: [BackupSessionRecord]
    }

    private struct BackupLog: Codable {
        let id: UUID
        let date: Date
        let weight: Double
        let reps: Int
        let setNumber: Int?
        let isCompleted: Bool
        let sessionID: UUID?
    }

    private struct BackupRoutineEntry: Codable {
        let routineID: UUID
        let routineName: String
        let defaultSets: Int
        let targetRepsMin: Int
        let targetRepsMax: Int
        let sortOrder: Int
        let defaultWeight: Double
    }

    private struct BackupSessionRecord: Codable {
        let sessionID: UUID
        let startDate: Date
        let recordID: UUID
        let exerciseName: String
        let sets: Int
    }

    /// Escribe la copia de seguridad (JSON con todo el detalle y TXT con el
    /// resumen) y devuelve la ruta del JSON, o `nil` si no se pudo guardar.
    private static func writeBackup(for plans: [MergePlan], context: ModelContext) -> URL? {
        let routinesDescriptor: FetchDescriptor<Routine> = FetchDescriptor<Routine>()
        let routines: [Routine] = (try? context.fetch(routinesDescriptor)) ?? []
        let sessionsDescriptor: FetchDescriptor<WorkoutSession> = FetchDescriptor<WorkoutSession>()
        let sessions: [WorkoutSession] = (try? context.fetch(sessionsDescriptor)) ?? []

        var groups: [BackupGroup] = []
        var summary: [String] = []
        var totalRemoved: Int = 0
        var totalLogsMoved: Int = 0

        for plan in plans {
            let keptSnapshot: BackupExercise = snapshot(of: plan.keeper, routines: routines, sessions: sessions)
            let removedSnapshots: [BackupExercise] = plan.duplicates.map { (exercise: Exercise) -> BackupExercise in
                return snapshot(of: exercise, routines: routines, sessions: sessions)
            }
            let movedLogs: Int = removedSnapshots.reduce(0) { (partial: Int, item: BackupExercise) -> Int in
                return partial + item.logs.count
            }

            groups.append(BackupGroup(
                canonicalName: plan.canonicalName,
                keptName: keptSnapshot.name,
                finalName: plan.targetName,
                kept: keptSnapshot,
                removed: removedSnapshots
            ))

            if plan.duplicates.isEmpty {
                summary.append("Renombrado «\(keptSnapshot.name)» → «\(plan.targetName)» (sin duplicados).")
            } else {
                let removedNames: String = removedSnapshots
                    .map { (item: BackupExercise) -> String in return "«\(item.name)»" }
                    .joined(separator: ", ")
                totalRemoved += removedSnapshots.count
                totalLogsMoved += movedLogs
                summary.append("«\(plan.targetName)»: se conserva «\(keptSnapshot.name)» con \(keptSnapshot.logs.count) series y se absorbe \(removedNames) (\(movedLogs) series).")
            }
        }

        let backup: Backup = Backup(
            generatedAt: Date(),
            reason: "Unificación de ejercicios duplicados: sólo nombres de la tabla explícita del catálogo o el mismo nombre normalizado.",
            totalGroups: groups.count,
            totalRemoved: totalRemoved,
            totalLogsMoved: totalLogsMoved,
            summary: summary,
            groups: groups
        )

        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data: Data = try? encoder.encode(backup) else { return nil }
        guard let directory: URL = backupDirectory() else { return nil }

        let fileStamp: String = "\(timestamp())-\(String(UUID().uuidString.prefix(4)))"
        let jsonURL: URL = directory.appendingPathComponent("Ejercicios-unificados-\(fileStamp).json")
        let textURL: URL = directory.appendingPathComponent("Ejercicios-unificados-\(fileStamp).txt")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: jsonURL, options: .atomic)
            _ = try? summaryText(for: backup).write(to: textURL, atomically: true, encoding: String.Encoding.utf8)
            return jsonURL
        } catch {
            print("No se pudo escribir la copia de seguridad de la unificación: \(error)")
            return nil
        }
    }

    private static func backupDirectory() -> URL? {
        let fileManager: FileManager = FileManager.default
        guard let base: URL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("AppGym", isDirectory: true)
            .appendingPathComponent("CopiasEjercicios", isDirectory: true)
    }

    private static func timestamp() -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: Date())
    }

    private static func summaryText(for backup: Backup) -> String {
        let isoFormatter: ISO8601DateFormatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("AppGym · copia de seguridad de la unificación de ejercicios")
        lines.append("Generada: \(isoFormatter.string(from: backup.generatedAt))")
        lines.append("Grupos afectados: \(backup.totalGroups)")
        lines.append("Ejercicios eliminados: \(backup.totalRemoved)")
        lines.append("Series trasladadas: \(backup.totalLogsMoved)")
        lines.append("")
        lines.append("Detalle:")
        for line in backup.summary {
            lines.append("- \(line)")
        }
        lines.append("")
        lines.append("El JSON junto a este archivo contiene las series, las rutinas y los registros de sesión de cada ejercicio afectado.")
        return lines.joined(separator: "\n")
    }

    private static func snapshot(of exercise: Exercise, routines: [Routine], sessions: [WorkoutSession]) -> BackupExercise {
        var routineEntries: [BackupRoutineEntry] = []
        for routine in routines {
            for item in routine.exercises where item.exercise === exercise {
                routineEntries.append(BackupRoutineEntry(
                    routineID: routine.id,
                    routineName: routine.name,
                    defaultSets: item.defaultSets,
                    targetRepsMin: item.targetRepsMin,
                    targetRepsMax: item.targetRepsMax,
                    sortOrder: item.sortOrder,
                    defaultWeight: item.defaultWeight
                ))
            }
        }

        let exerciseKey: String = canonicalKey(for: exercise.name)
        var sessionRecords: [BackupSessionRecord] = []
        for session in sessions {
            for record in session.exerciseRecords {
                let matchesIdentifier: Bool = record.exerciseID == exercise.id
                let matchesName: Bool = canonicalKey(for: record.exerciseName) == exerciseKey
                guard matchesIdentifier || matchesName else { continue }
                sessionRecords.append(BackupSessionRecord(
                    sessionID: session.id,
                    startDate: session.startDate,
                    recordID: record.id,
                    exerciseName: record.exerciseName,
                    sets: record.sets.count
                ))
            }
        }

        let logs: [BackupLog] = exercise.logs.map { (log: WorkoutSetLog) -> BackupLog in
            return BackupLog(
                id: log.id,
                date: log.date,
                weight: log.weight,
                reps: log.reps,
                setNumber: log.setNumber,
                isCompleted: log.isCompleted,
                sessionID: log.session?.id
            )
        }

        return BackupExercise(
            id: exercise.id,
            name: exercise.name,
            muscleGroup: exercise.muscleGroupRaw,
            equipment: exercise.equipmentTypeRaw,
            requiresStraps: exercise.requiresStraps,
            hasCustomRequiresStraps: exercise.hasCustomRequiresStraps,
            isCompound: exercise.isCompound,
            targetReps: exercise.targetRepsText,
            primaryMuscles: exercise.primaryMuscles.map { (muscle: MuscleGroup) -> String in return muscle.rawValue },
            secondaryMuscles: exercise.secondaryMuscles.map { (muscle: MuscleGroup) -> String in return muscle.rawValue },
            notes: exercise.notes,
            logs: logs,
            routines: routineEntries,
            sessionRecords: sessionRecords
        )
    }

    // MARK: Clave canónica

    /// Clave del movimiento: el nombre canónico del catálogo cuando el nombre
    /// aparece en la tabla explícita y, si no, el propio nombre normalizado.
    /// Dos nombres distintos nunca comparten clave por traducción.
    public static func canonicalKey(for name: String) -> String {
        let normalizedName: String = normalize(name)
        return aliasIndex[normalizedName] ?? normalizedName
    }

    /// Nombre en castellano del catálogo para un nombre conocido, si existe.
    public static func canonicalName(for name: String) -> String? {
        return aliasIndex[normalize(name)]
    }

    private static func displayName(for name: String) -> String {
        return aliasIndex[normalize(name)] ?? name
    }

    // MARK: Normalización

    private static func normalize(_ text: String) -> String {
        let lowered: String = text.lowercased()
        let folded: String = lowered.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
        let collapsed: String = folded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { (part: String) -> Bool in return !part.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    // MARK: Tabla de nombres canónicos

    /// Nombre en castellano de cada ejercicio del catálogo con sus alias
    /// (variantes en castellano y nombres en inglés habituales). Es la única
    /// fuente de equivalencias: lo que no esté aquí sólo casa consigo mismo.
    private static let canonicalGroups: [String: [String]] = [
        "Press banca plano": [
            "press banca", "press de banca", "press plano", "bench press",
            "flat bench press", "barbell bench press", "press banca con barra"
        ],
        "Press banca inclinado": [
            "press inclinado", "incline press", "incline bench press", "incline bench",
            "press banca superior", "press inclinado con barra"
        ],
        "Press declinado": [
            "press banca declinado", "decline press", "decline bench press"
        ],
        "Fondos en paralelas": [
            "fondos", "dips", "chest dips", "fondos en paralela", "parallel dips", "fondos en barra"
        ],
        "Aperturas con mancuernas": [
            "aperturas con mancuerna", "dumbbell fly", "dumbbell flyes", "aperturas planas",
            "fly con mancuernas", "aperturas"
        ],
        "Aperturas en máquina": [
            "pec deck", "pec-deck", "contractor", "mariposa", "butterfly",
            "aperturas en maquina", "machine fly"
        ],
        "Cruces de polea sentado": [
            "cruces de polea", "seated cable fly", "cable fly sentado", "crossover",
            "aperturas en polea sentado", "cable crossover"
        ],
        "Dominadas": [
            "dominada", "pull up", "pull-up", "pullup", "chin up", "chin-up",
            "tracciones en barra", "dominadas pronas"
        ],
        "Jalon al pecho": [
            "jalon al pecho", "jalon pecho", "lat pulldown", "pulldown", "jalon al frente"
        ],
        "Remo libre": [
            "remo con barra", "barbell row", "remo barra", "bent over row",
            "remo inclinado con barra"
        ],
        "Remo T-bar": [
            "remo t bar", "t-bar row", "t bar row", "remo en t"
        ],
        "Pullover en polea alta": [
            "pullover", "pullover en polea", "cable pullover", "pull over"
        ],
        "Remo en maquina": [
            "remo maquina", "remo sentado", "seated row", "machine row",
            "remo con pecho apoyado", "remo apoyado"
        ],
        "Remo Pendlay": [
            "pendlay row", "remo pendlay", "pendlay"
        ],
        "Remo al menton": [
            "remo al menton", "upright row"
        ],
        "Encogimientos con barra": [
            "encogimientos", "shrug", "barbell shrug", "encogimiento de hombros", "shrugs"
        ],
        "Peso muerto convencional": [
            "peso muerto", "deadlift", "conventional deadlift", "peso muerto clasico"
        ],
        "Hiperextensiones": [
            "hiperextension", "hyperextension", "back extension", "extension lumbar",
            "banco romano", "extension de espalda"
        ],
        "Press militar": [
            "press de hombros", "press hombro", "shoulder press", "overhead press",
            "military press", "press de hombro"
        ],
        "Press Arnold": [
            "arnold press", "press arnold"
        ],
        "Press de hombros en maquina": [
            "press hombros en maquina", "machine shoulder press",
            "press en maquina de hombros", "press militar en maquina"
        ],
        "Elevaciones laterales mancuerna": [
            "elevaciones laterales", "elevacion lateral", "elevaciones laterales con mancuernas",
            "lateral raise", "lateral raises", "vuelos laterales",
            "elevaciones laterales con mancuerna"
        ],
        "Elevaciones laterales en polea": [
            "elevacion lateral en polea", "elevaciones laterales polea", "cable lateral raise",
            "lateral raise cable"
        ],
        "Elevaciones laterales en máquina": [
            "elevaciones laterales maquina", "elevacion lateral en maquina",
            "machine lateral raise", "lateral raise machine"
        ],
        "Elevaciones frontales": [
            "elevacion frontal", "front raise", "front raises", "elevaciones frontales con mancuernas"
        ],
        "Jalón a la cara": [
            "jalon a la cara", "face pull", "face pulls", "tiron a la cara", "face pull en polea"
        ],
        "Pajaros con mancuernas": [
            "pajaros", "reverse fly", "rear delt fly", "aperturas inversas con mancuernas",
            "dumbbell reverse fly", "pajaros con mancuerna"
        ],
        "Aperturas inversas en maquina": [
            "aperturas inversas", "aperturas inversas maquina", "reverse pec deck",
            "rear delt machine", "machine reverse fly"
        ],
        "Aperturas inversas en polea": [
            "isololateral reverse fly", "aperturas inversas polea", "reverse fly en polea",
            "cable reverse fly", "reverse fly polea"
        ],
        "Curl en mancuerna": [
            "curl con mancuernas", "curl con mancuerna", "curl mancuerna", "dumbbell curl",
            "curl biceps con mancuernas", "curl alterno con mancuernas"
        ],
        "Curl con barra EZ": [
            "curl con barra", "curl ez", "ez bar curl", "barbell curl",
            "curl de biceps con barra", "curl barra"
        ],
        "Curl predicador": [
            "preacher curl", "curl scott", "curl en banco scott"
        ],
        "Curl en polea": [
            "curl polea", "cable curl", "curl en polea baja", "curl biceps en polea"
        ],
        "Curl araña": [
            "spider curl", "curl arana", "curl en banco inclinado prono"
        ],
        "Extensión de tríceps en polea": [
            "triceps pushdowns", "triceps pushdown", "pushdown", "extension de triceps",
            "extension de triceps en polea", "triceps en polea", "cable pushdown",
            "extension triceps polea"
        ],
        "Press cerrado": [
            "close grip bench press", "close grip press", "press banca cerrado",
            "press de banca cerrado", "press cerrado al pecho"
        ],
        "Press frances": [
            "press frances", "skull crusher", "skullcrusher", "press frances con barra",
            "extension de triceps tumbado"
        ],
        "Extensión de tríceps sobre la cabeza": [
            "extension tras nuca", "extension sobre la cabeza", "overhead extension",
            "overhead triceps extension", "triceps sobre cabeza",
            "extension tras nuca con mancuerna", "extension de triceps sobre la cabeza",
            "extension de triceps por encima de la cabeza", "extension de triceps sobre cabeza"
        ],
        "Curl de muneca": [
            "curl de muneca", "wrist curl", "curl muneca", "curl de munecas"
        ],
        "Curl invertido": [
            "reverse curl", "curl inverso", "curl con barra invertido"
        ],
        "Crunch en polea": [
            "crunch polea", "cable crunch", "abdominales en polea", "crunch con polea"
        ],
        "Elevacion de piernas colgado": [
            "elevacion de piernas", "hanging leg raise", "leg raise",
            "elevacion de piernas en barra", "elevaciones de piernas colgado"
        ],
        "Sentadilla libre": [
            "sentadilla", "squat", "back squat", "barbell squat",
            "sentadilla con barra", "sentadilla trasera"
        ],
        "Bulgaras": [
            "bulgaras", "bulgara", "split squat", "sentadilla bulgara",
            "bulgarian split squat", "zancada bulgara"
        ],
        "Prensa de piernas": [
            "prensa", "leg press", "prensa 45", "prensa inclinada"
        ],
        "Sentadilla en máquina": [
            "sentadilla hack", "hack squat", "hack", "sentadilla hack machine",
            "sentadilla maquina", "sentadilla guiada", "sentadilla en multipower"
        ],
        "Zancadas": [
            "zancada", "lunge", "lunges", "zancadas con mancuernas"
        ],
        "Extension de quadriceps": [
            "extension de quadriceps", "leg extension", "extension de piernas",
            "extension de cuadriceps en maquina"
        ],
        "Peso muerto rumano (RDL)": [
            "peso muerto rumano", "rdl", "romanian deadlift", "stiff leg deadlift",
            "peso muerto piernas rigidas"
        ],
        "Flexion de pierna estirado": [
            "curl femoral tumbado", "leg curl tumbado", "lying leg curl",
            "curl femoral estirado", "femoral tumbado"
        ],
        "Flexion de pierna sentado": [
            "curl femoral sentado", "seated leg curl", "femoral sentado", "leg curl sentado"
        ],
        "Hip thrust con barra": [
            "hip thrust", "empuje de cadera", "barbell hip thrust", "puente de gluteo con barra"
        ],
        "Patada de gluteo en polea": [
            "patada de gluteo", "glute kickback", "patada gluteo polea", "kickback de gluteo"
        ],
        "Abduccion en maquina": [
            "abduccion de cadera", "abductor en maquina", "hip abduction",
            "abduccion cadera maquina", "abductores"
        ],
        "Aduccion de cadera en maquina": [
            "aduccion de cadera", "hip adduction", "aductores en maquina", "aduccion en maquina"
        ],
        "Elevacion talones sentado": [
            "elevacion de talones sentado", "gemelos sentado", "seated calf raise",
            "elevacion de gemelos sentado"
        ],
        "Elevacion de talones de pie": [
            "elevacion de talones", "gemelos de pie", "standing calf raise",
            "elevacion de gemelos", "calf raise"
        ]
    ]

    /// Índice nombre normalizado → nombre canónico en castellano.
    private static let aliasIndex: [String: String] = {
        var index: [String: String] = [:]

        for canonical in canonicalGroups.keys.sorted() {
            index[normalize(canonical)] = canonical
        }

        for canonical in canonicalGroups.keys.sorted() {
            for alias in canonicalGroups[canonical] ?? [] {
                let key: String = normalize(alias)
                if index[key] == nil {
                    index[key] = canonical
                }
            }
        }

        // Los nombres canónicos siempre mandan sobre cualquier alias.
        for canonical in canonicalGroups.keys.sorted() {
            index[normalize(canonical)] = canonical
        }

        return index
    }()
}
