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

    /// Nombre con el que la sesión se guarda en el historial y el calendario.
    public var sessionName: String {
        return CardioType.sessionPrefix + title
    }

    /// Modalidad de una sesión guardada, o `nil` si no es de cardio.
    public static func fromSessionName(_ name: String) -> CardioType? {
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(sessionPrefix) else { return nil }

        let title: String = String(trimmed.dropFirst(sessionPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return CardioType.allCases.first { $0.title == title }
    }
}

extension WorkoutSession {
    /// Modalidad de cardio de la sesión. Las sesiones de fuerza devuelven `nil`.
    public var cardioType: CardioType? {
        return CardioType.fromSessionName(routineName)
    }

    public var isCardioSession: Bool {
        return cardioType != nil
    }
}
