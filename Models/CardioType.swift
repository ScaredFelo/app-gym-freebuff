import Foundation

/// Modalidad de las sesiones de cardio lanzadas desde la pantalla de rutinas.
/// Solo aporta identidad visual y el nombre con el que la sesión queda
/// registrada en el historial.
public enum CardioType: String, CaseIterable, Sendable, Identifiable {
    case treadmill
    case bike
    case elliptical
    case rower
    case stairs
    case jumpRope

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .treadmill:
            return "CINTA"
        case .bike:
            return "BICI"
        case .elliptical:
            return "ELÍPTICA"
        case .rower:
            return "REMO"
        case .stairs:
            return "ESCALERAS"
        case .jumpRope:
            return "COMBA"
        }
    }

    public var subtitle: String {
        switch self {
        case .treadmill:
            return "Cinta de correr"
        case .bike:
            return "Bici estática"
        case .elliptical:
            return "Elíptica"
        case .rower:
            return "Remo ergómetro"
        case .stairs:
            return "Máquina de escaleras"
        case .jumpRope:
            return "Salto de cuerda"
        }
    }

    public var symbolName: String {
        switch self {
        case .treadmill:
            return "figure.run"
        case .bike:
            return "bicycle"
        case .elliptical:
            return "figure.elliptical"
        case .rower:
            return "figure.rower"
        case .stairs:
            return "figure.stairs"
        case .jumpRope:
            return "figure.jumprope"
        }
    }

    /// Prefijo con el que se registran las sesiones de cardio en el historial.
    public static let sessionPrefix = "CARDIO · "
    /// Palabra con la que se reconocen las sesiones de cardio aunque el
    /// separador o las mayúsculas no coincidan con `sessionPrefix`.
    public static let sessionKeyword = "CARDIO"
    /// Separadores admitidos entre `CARDIO` y la modalidad. Una palabra suelta
    /// detrás de la clave (p. ej. "Cardio y core") no es una sesión de cardio.
    private static let sessionSeparators: CharacterSet = CharacterSet(charactersIn: "·-:•|/")

    /// Nombre con el que la sesión se guarda en el historial y el calendario.
    public var sessionName: String {
        return CardioType.sessionPrefix + title
    }

    /// `true` si el nombre corresponde a una sesión de cardio, aunque la
    /// modalidad no esté en el catálogo. Ignora mayúsculas y espacios de más y
    /// exige que `CARDIO` vaya solo o seguido de un separador (`CARDIO · CINTA`),
    /// de modo que una rutina llamada "Cardio y core" no cuente como cardio.
    public static func isCardioSessionName(_ name: String) -> Bool {
        let normalized: String = normalizedSessionName(name)
        guard normalized.hasPrefix(sessionKeyword) else { return false }

        let remainder: String = String(normalized.dropFirst(sessionKeyword.count))
            .trimmingCharacters(in: .whitespaces)
        guard let firstScalar: Unicode.Scalar = remainder.unicodeScalars.first else { return true }

        return sessionSeparators.contains(firstScalar)
    }

    /// Modalidad de una sesión guardada, o `nil` si no es de cardio o si la
    /// modalidad no se reconoce.
    public static func fromSessionName(_ name: String) -> CardioType? {
        guard isCardioSessionName(name) else { return nil }

        let normalized: String = normalizedSessionName(name)
        let remainder: String = String(normalized.dropFirst(sessionKeyword.count))
            .trimmingCharacters(in: sessionSeparators.union(.whitespaces))

        guard !remainder.isEmpty else { return nil }
        return CardioType.allCases.first { $0.title == remainder }
    }

    /// Mayúsculas y espacios simples: `" cardio ·  cinta "` → `"CARDIO · CINTA"`.
    private static func normalizedSessionName(_ name: String) -> String {
        return name
            .uppercased()
            .split(whereSeparator: { (character: Character) -> Bool in
                return character.isWhitespace
            })
            .joined(separator: " ")
    }
}

extension WorkoutSession {
    /// Modalidad de cardio de la sesión. Las sesiones de fuerza devuelven `nil`.
    public var cardioType: CardioType? {
        return CardioType.fromSessionName(routineName)
    }

    public var isCardioSession: Bool {
        return CardioType.isCardioSessionName(routineName)
    }
}
