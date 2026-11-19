import Foundation

// MARK: - Rutinas del catálogo

/// Rutinas base del catálogo Excel. El `rawValue` coincide exactamente con la
/// columna «Rutina» del catálogo, de modo que la búsqueda de variantes no
/// depende de ningún alias.
enum CatalogRoutine: String, CaseIterable, Identifiable, Hashable, Sendable {
    case arms = "Arms"
    case chestBack = "Chest+Back"
    case fullBody = "Full body"
    case hamstrings = "Hamstrings"
    case legs = "Legs"
    case lower = "Lower"
    case pull = "Pull"
    case push = "Push"
    case quads = "Quads"
    case upper = "Upper"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// Cuenta para la frecuencia de piernas (L).
    var trainsLegs: Bool {
        switch self {
        case .fullBody, .hamstrings, .legs, .lower, .quads:
            return true
        case .arms, .chestBack, .pull, .push, .upper:
            return false
        }
    }

    /// Cuenta para la frecuencia de tren superior (U).
    var trainsUpper: Bool {
        switch self {
        case .arms, .chestBack, .fullBody, .pull, .push, .upper:
            return true
        case .hamstrings, .legs, .lower, .quads:
            return false
        }
    }

    /// Traduce un token ya normalizado (minúsculas, sin espacios ni acentos).
    /// Incluye las variantes de escritura presentes en la matriz: `hamsting`,
    /// `hams`, `fullbody`, `chestback`.
    static func fromNormalizedToken(_ token: String) -> CatalogRoutine? {
        switch token {
        case "push":
            return .push
        case "pull":
            return .pull
        case "upper":
            return .upper
        case "lower":
            return .lower
        case "legs":
            return .legs
        case "quads":
            return .quads
        case "hamstrings", "hamsting", "hams":
            return .hamstrings
        case "fullbody":
            return .fullBody
        case "arms":
            return .arms
        case "chestback":
            return .chestBack
        default:
            return nil
        }
    }
}

// MARK: - Matriz W/L/U

struct SplitMatrixFile: Decodable {
    let source: String
    let sheet: String
    let duplicateWarnings: [SplitMatrixDuplicate]
    let entries: [SplitMatrixEntry]
}

struct SplitMatrixDuplicate: Decodable {
    let w: Int
    let l: Int
    let u: Int
    let rows: [Int]
}

struct SplitMatrixEntry: Decodable {
    let w: Int
    let l: Int
    let u: Int
    /// `splits` o `warning`, tal como se clasificó la fila de la hoja.
    let status: String
    let warning: String?
    let splits: [String]

    var isWarningRow: Bool {
        return status == "warning" || splits.isEmpty
    }
}

// MARK: - Resultado de la consulta

struct SplitValidationWarning {
    enum Kind {
        /// Regla absoluta W = 7.
        case weeklyRest
        /// Fila marcada con aviso en la matriz.
        case insufficientRest
    }

    let kind: Kind
    let message: String
    let w: Int
    let l: Int
    let u: Int
}

/// Propuesta de split ya interpretada. `sessions` contiene un elemento por
/// sesión de la semana, en el orden exacto de la expresión original.
struct SplitProposal: Identifiable {
    let w: Int
    let l: Int
    let u: Int
    let expression: String
    let sessions: [CatalogRoutine]

    var id: String {
        return "\(w)-\(l)-\(u)-\(expression)"
    }

    var sessionCount: Int {
        return sessions.count
    }

    /// Estructura expandida, p. ej. «Push / Pull / Legs / Legs».
    var structurePreview: String {
        return sessions.map { (routine: CatalogRoutine) -> String in
            return routine.displayName
        }
        .joined(separator: " / ")
    }

    /// Código corto de cada bloque para la interfaz.
    var blockCodes: [String] {
        return sessions.map { (routine: CatalogRoutine) -> String in
            switch routine {
            case .arms:
                return "ARM"
            case .chestBack:
                return "CHB"
            case .fullBody:
                return "FB"
            case .hamstrings:
                return "HAM"
            case .legs:
                return "LEG"
            case .lower:
                return "LOW"
            case .pull:
                return "PUL"
            case .push:
                return "PSH"
            case .quads:
                return "QUA"
            case .upper:
                return "UPP"
            }
        }
    }
}

enum SplitGenerationResult {
    case invalidInput(String)
    /// W = 7 o fila marcada con aviso: no hay rutinas que generar.
    case warning(SplitValidationWarning)
    /// Las propuestas interpretables y las incidencias detectadas.
    case proposals([SplitProposal], incidences: [String])
    /// No se puede continuar (matriz ausente, corrupción o ninguna propuesta
    /// interpretable). Nunca se sustituye por datos inventados.
    case failure(String)
}

// MARK: - Semana generada

struct GeneratedExercise: Identifiable {
    let id: String
    let name: String
    let sets: Int
    let repsMin: Int
    let repsMax: Int
    let restSeconds: Int
    let isCompound: Bool
    let primaryMuscles: [MuscleGroup]
    let secondaryMuscles: [MuscleGroup]
    let equipment: EquipmentType
    let requiresStraps: Bool
    let notes: String
    /// Texto original del catálogo, conservado sin modificar.
    let primaryMuscleText: String
    let secondaryMuscleText: String
    /// Nombres originales de músculos sin equivalencia exacta en la app.
    /// Limitan el análisis; no eliminan el dato del catálogo.
    let unmappedMuscles: [String]

    var repsLabel: String {
        return "\(repsMin)-\(repsMax)"
    }
}

struct GeneratedSession: Identifiable {
    let id: String
    let index: Int
    let routine: CatalogRoutine
    /// Sufijo de variante asignado: vacío (base), `A`, `B` o `C`.
    let variantSuffix: String
    let name: String
    let exercises: [GeneratedExercise]

    var isRestDay: Bool { return false }

    var muscleNames: [String] {
        var seen: [String] = []
        for exercise in exercises {
            for muscle in exercise.primaryMuscles + exercise.secondaryMuscles {
                if !seen.contains(muscle.rawValue) {
                    seen.append(muscle.rawValue)
                }
            }
        }
        return seen
    }

    var primaryMuscleNames: [String] {
        var seen: [String] = []
        for exercise in exercises {
            for muscle in exercise.primaryMuscles where !seen.contains(muscle.rawValue) {
                seen.append(muscle.rawValue)
            }
        }
        return seen
    }

    var totalSets: Int {
        return exercises.reduce(0) { (partial: Int, exercise: GeneratedExercise) -> Int in
            return partial + exercise.sets
        }
    }
}

/// Semana completa lista para guardar. Los avisos de recuperación y fatiga son
/// informativos y no bloquean la confirmación.
struct GeneratedWeek {
    let w: Int
    let l: Int
    let u: Int
    let splitExpression: String
    let sessions: [GeneratedSession]
    let notices: [RoutineNotice]
    let limitations: [String]

    var splitName: String {
        return splitExpression
    }

    var sessionNames: [String] {
        return sessions.map { (session: GeneratedSession) -> String in
            return session.name
        }
    }

    var totalExercises: Int {
        return sessions.reduce(0) { (partial: Int, session: GeneratedSession) -> Int in
            return partial + session.exercises.count
        }
    }

    /// Días del ciclo sin sesión asignada (el ciclo nunca supera 7 días).
    var restDays: Int {
        return max(0, 7 - sessions.count)
    }

    /// Nombres originales sin equivalencia exacta, sin duplicados.
    var unmappedMuscleTokens: [String] {
        var tokens: [String] = []
        for session in sessions {
            for exercise in session.exercises {
                for token in exercise.unmappedMuscles where !tokens.contains(token) {
                    tokens.append(token)
                }
            }
        }
        return tokens
    }

    /// `true` cuando el análisis de recuperación no cubre todo el catálogo.
    var hasPartialMuscleAnalysis: Bool {
        return !unmappedMuscleTokens.isEmpty
    }

    var recoveryNotices: [RoutineNotice] {
        return notices.filter { (notice: RoutineNotice) -> Bool in
            if case .muscleRecovery = notice.kind { return true }
            return false
        }
    }

    var fatigueNotices: [RoutineNotice] {
        return notices.filter { (notice: RoutineNotice) -> Bool in
            if case .fatigue = notice.kind { return true }
            return false
        }
    }
}

// MARK: - Catálogo de ejercicios

struct ExerciseCatalogFile: Decodable {
    let source: String
    let levels: ExerciseCatalogLevels
    let uniqueExercises: [CatalogUniqueExerciseRecord]
}

struct ExerciseCatalogLevels: Decodable {
    let single: [CatalogRoutineVariant]
    let double: [CatalogRoutineVariant]
    let triple: [CatalogRoutineVariant]
}

struct CatalogRoutineVariant: Decodable, Identifiable {
    let routineRaw: String
    let variantLabel: String
    let exercises: [CatalogExerciseRecord]

    var id: String { routineRaw }
}

/// Fila de la hoja «Ejercicios únicos». No incluye `sets` porque esa hoja no
/// tiene columna de series; sus textos de biomecánica se conservan en lugar de
/// descartarlos para encajar en `CatalogExerciseRecord`.
struct CatalogUniqueExerciseRecord: Decodable {
    let name: String
    let primaryRaw: String
    let secondaryRaw: String
    let typeRaw: String
    let repsMin: Int
    let repsMax: Int
    let restSeconds: Int
    let requiresStraps: Bool
    let notations: String
    let whyGood: String
    let whyBad: String
    let whenRecommended: String
    let whenNotRecommended: String
}

struct CatalogExerciseRecord: Decodable {
    let name: String
    let primaryRaw: String
    let secondaryRaw: String
    let typeRaw: String
    let sets: Int
    let repsMin: Int
    let repsMax: Int
    let restSeconds: Int
    let requiresStraps: Bool
    let notes: String
    let whyGood: String
    let whyBad: String
    let whenRecommended: String
    let whenNotRecommended: String

    var isCompound: Bool {
        return typeRaw.lowercased().contains("complej")
    }
}

// MARK: - Errores

enum SplitGenerationError: LocalizedError {
    case matrixUnavailable
    case decodingFailed
    case catalogUnavailable
    case catalogDecodingFailed
    case integrity(String)
    case unknownBlock(String)
    case tooManyRepetitions(String)

    var errorDescription: String? {
        switch self {
        case .matrixUnavailable:
            return "No se ha podido cargar la matriz W/L/U de la aplicación."
        case .decodingFailed:
            return "La matriz W/L/U no tiene el formato esperado."
        case .catalogUnavailable:
            return "No se ha podido cargar el catálogo de ejercicios de la aplicación."
        case .catalogDecodingFailed:
            return "El catálogo de ejercicios no tiene el formato esperado."
        case .integrity(let detail):
            return "La matriz W/L/U no supera la comprobación de integridad: \(detail)"
        case .unknownBlock(let token):
            return "El bloque «\(token)» no corresponde a ninguna rutina del catálogo."
        case .tooManyRepetitions(let expression):
            return "La propuesta «\(expression)» repite un bloque más veces de las que permite el catálogo de variantes."
        }
    }
}
