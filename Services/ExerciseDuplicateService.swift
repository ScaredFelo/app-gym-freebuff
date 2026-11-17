import Foundation
import SwiftData

// MARK: - Unificación de ejercicios duplicados

/// Detecta ejercicios que representan el mismo movimiento con distinto nombre
/// (lo habitual: uno en castellano y otro en inglés) y los unifica en un único
/// registro. Del grupo se conserva el que tiene historial de sesiones y el
/// resultado queda siempre con el nombre en castellano del catálogo.
@MainActor
public enum ExerciseDuplicateService {

    /// Bandera de la unificación, para ejecutarla una sola vez por instalación.
    public static let mergeFlagKey: String = "didMergeDuplicateExercises_v1"

    // MARK: Punto de entrada

    /// Recorre el catálogo, agrupa los ejercicios que son el mismo movimiento y
    /// fusiona cada grupo conservando series, rutinas y sesiones históricas.
    public static func mergeIfNeeded(context: ModelContext) {
        let defaults: UserDefaults = UserDefaults.standard
        guard !defaults.bool(forKey: mergeFlagKey) else { return }

        let descriptor: FetchDescriptor<Exercise> = FetchDescriptor<Exercise>()
        guard let exercises: [Exercise] = try? context.fetch(descriptor) else { return }

        let groups: [String: [Exercise]] = Dictionary(grouping: exercises) { (exercise: Exercise) -> String in
            return canonicalKey(for: exercise.name)
        }

        var didChange: Bool = false
        for group in groups.values {
            if merge(group: group, context: context) {
                didChange = true
            }
        }

        guard didChange else {
            defaults.set(true, forKey: mergeFlagKey)
            return
        }

        do {
            try context.save()
            defaults.set(true, forKey: mergeFlagKey)
        } catch {
            print("Error unificando ejercicios duplicados: \(error)")
        }
    }

    // MARK: Fusión

    private static func merge(group: [Exercise], context: ModelContext) -> Bool {
        guard let keeper: Exercise = bestCandidate(in: group) else { return false }

        let targetName: String = displayName(for: keeper.name)
        var didChange: Bool = false

        // El nombre en castellano se aplica antes de absorber el resto para que
        // los registros históricos de sesión se reescriban ya con ese nombre.
        if keeper.name != targetName {
            keeper.name = targetName
            ExerciseKnowledgeService.fillMissingKnowledge(for: keeper)
            didChange = true
        }

        for duplicate in group where duplicate !== keeper {
            absorb(duplicate, into: keeper, context: context)
            didChange = true
        }

        return didChange
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

    // MARK: Clave canónica

    /// Clave que identifica el movimiento independientemente del idioma, los
    /// acentos, el orden de las palabras y los plurales.
    public static func canonicalKey(for name: String) -> String {
        let canonicalName: String = aliasIndex[normalize(name)] ?? name
        let tokens: String = tokenKey(from: canonicalName)
        return tokens.isEmpty ? normalize(canonicalName) : tokens
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

    private static func tokenKey(from text: String) -> String {
        let prepared: String = replacePhrases(in: normalize(text))
        let rawTokens: [String] = prepared
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { (token: String) -> Bool in return !token.isEmpty }

        var tokens: [String] = []
        for rawToken in rawTokens {
            let translated: [String] = tokenTranslations[rawToken]?.components(separatedBy: " ") ?? [rawToken]
            for token in translated {
                let cleanToken: String = singular(token)
                guard !cleanToken.isEmpty, !stopWords.contains(cleanToken) else { continue }
                if !tokens.contains(cleanToken) {
                    tokens.append(cleanToken)
                }
            }
        }

        return tokens.sorted().joined(separator: " ")
    }

    private static func replacePhrases(in text: String) -> String {
        var result: String = text
        for phrase in phraseTranslations.keys.sorted(by: { (lhs: String, rhs: String) -> Bool in
            return lhs.count > rhs.count
        }) {
            guard let replacement: String = phraseTranslations[phrase] else { continue }
            result = result.replacingOccurrences(of: phrase, with: replacement)
        }
        return result
    }

    private static func singular(_ token: String) -> String {
        if token.count > 4 && token.hasSuffix("es") {
            return String(token.dropLast(2))
        }
        if token.count > 3 && token.hasSuffix("s") {
            return String(token.dropLast())
        }
        return token
    }

    // MARK: Diccionarios de traducción

    private static let stopWords: Set<String> = [
        "de", "del", "con", "en", "el", "la", "los", "las", "un", "una", "al", "a", "y", "e", "o",
        "para", "por", "sobre", "the", "of", "with", "on", "for", "and", "to", "in", "at", "by"
    ]

    private static let phraseTranslations: [String: String] = [
        "close grip bench press": "press cerrado",
        "close grip press": "press cerrado",
        "incline bench press": "press banca inclinado",
        "decline bench press": "press declinado",
        "flat bench press": "press banca plano",
        "barbell bench press": "press banca plano",
        "dumbbell bench press": "press banca mancuerna",
        "bench press": "press banca",
        "shoulder press": "press hombro",
        "overhead press": "press sobre cabeza",
        "military press": "press militar",
        "arnold press": "press arnold",
        "leg press": "prensa",
        "leg extension": "extension de cuadriceps",
        "leg curl": "curl femoral",
        "calf raise": "elevacion de gemelos",
        "lateral raise": "elevacion lateral",
        "front raise": "elevacion frontal",
        "rear delt fly": "aperturas inversas",
        "reverse fly": "aperturas inversas",
        "pec deck": "aperturas en maquina",
        "cable fly": "aperturas en polea",
        "cable crossover": "cruces de polea",
        "pull up": "dominada",
        "chin up": "dominada",
        "romanian deadlift": "peso muerto rumano",
        "stiff leg deadlift": "peso muerto rumano",
        "hip thrust": "empuje de cadera",
        "skull crusher": "press frances",
        "upright row": "remo al menton",
        "hammer curl": "curl martillo",
        "preacher curl": "curl predicador",
        "wrist curl": "curl de muneca",
        "reverse curl": "curl invertido",
        "spider curl": "curl arana",
        "hack squat": "sentadilla hack",
        "front squat": "sentadilla frontal",
        "back squat": "sentadilla trasera",
        "glute bridge": "puente de gluteo",
        "glute kickback": "patada de gluteo",
        "hip abduction": "abduccion de cadera",
        "hip adduction": "aduccion de cadera",
        "seated row": "remo sentado",
        "bent over row": "remo inclinado",
        "t bar row": "remo en t",
        "lat pulldown": "jalon al pecho",
        "overhead extension": "extension sobre la cabeza",
        "calf press": "elevacion de gemelos"
    ]

    private static let tokenTranslations: [String: String] = [
        "bench": "banca",
        "incline": "inclinado",
        "inclined": "inclinado",
        "decline": "declinado",
        "declined": "declinado",
        "flat": "plano",
        "dumbbell": "mancuerna",
        "barbell": "barra",
        "bar": "barra",
        "cable": "polea",
        "machine": "maquina",
        "smith": "multipower",
        "seated": "sentado",
        "standing": "pie",
        "lying": "tumbado",
        "hanging": "colgado",
        "row": "remo",
        "rowing": "remo",
        "pulldown": "jalon",
        "pushdown": "extension",
        "squat": "sentadilla",
        "deadlift": "peso muerto",
        "lunge": "zancada",
        "raise": "elevacion",
        "fly": "aperturas",
        "flyes": "aperturas",
        "shrug": "encogimiento",
        "hammer": "martillo",
        "kickback": "patada",
        "thrust": "empuje",
        "crossover": "cruce",
        "dip": "fondo",
        "dips": "fondo",
        "grip": "agarre",
        "close": "cerrado",
        "wide": "ancho",
        "shoulder": "hombro",
        "overhead": "sobre cabeza",
        "front": "frontal",
        "rear": "posterior",
        "back": "espalda",
        "chest": "pecho",
        "leg": "pierna",
        "calf": "gemelo",
        "hamstring": "femoral",
        "quad": "cuadriceps",
        "glute": "gluteo",
        "abs": "abdominales",
        "wrist": "muneca",
        "preacher": "predicador",
        "pulley": "polea",
        "single": "unilateral"
    ]

    // MARK: Tabla de nombres canónicos

    /// Nombre en castellano de cada ejercicio del catálogo con sus alias
    /// (variantes en castellano y nombres en inglés habituales).
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
        "Extension tras nuca": [
            "extension tras nuca", "extension sobre la cabeza", "overhead extension",
            "overhead triceps extension", "triceps sobre cabeza",
            "extension tras nuca con mancuerna"
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
        "Sentadilla hack": [
            "hack squat", "hack", "sentadilla hack machine"
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
