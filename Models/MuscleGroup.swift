import Foundation

/// Grupos musculares usados por la base de conocimiento biomecánica y por el
/// mapa anatómico. Los `rawValue` se guardan en SwiftData, por lo que los
/// valores antiguos se resuelven con `fromStoredRawValue(_:)`.
public enum MuscleGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    case chest = "Pecho"
    case upperBack = "Espalda alta / Trapecio"
    case lats = "Dorsal ancho"
    case lowerBack = "Lumbar"
    case frontShoulders = "Deltoides anterior / lateral"
    case rearShoulders = "Deltoides posterior"
    case biceps = "Bíceps"
    case triceps = "Tríceps"
    case forearms = "Antebrazos"
    case abs = "Abdominales / Core"
    case quads = "Cuádriceps"
    case hamstrings = "Isquiotibiales"
    case glutes = "Glúteos"
    case adductors = "Aductores"
    case calves = "Gemelos"

    public var id: String { rawValue }

    /// Nombre compacto para chips, filtros y leyendas.
    public var shortName: String {
        switch self {
        case .chest:
            return "Pecho"
        case .upperBack:
            return "Trapecio"
        case .lats:
            return "Dorsal"
        case .lowerBack:
            return "Lumbar"
        case .frontShoulders:
            return "Delt. anterior"
        case .rearShoulders:
            return "Delt. posterior"
        case .biceps:
            return "Bíceps"
        case .triceps:
            return "Tríceps"
        case .forearms:
            return "Antebrazo"
        case .abs:
            return "Core"
        case .quads:
            return "Cuádriceps"
        case .hamstrings:
            return "Isquios"
        case .glutes:
            return "Glúteos"
        case .adductors:
            return "Aductores"
        case .calves:
            return "Gemelos"
        }
    }

    // MARK: - Compatibilidad con valores guardados

    /// Devuelve el grupo equivalente al valor guardado o `nil` si no existe.
    /// Acepta los nombres largos actuales y los antiguos (`"Espalda"`,
    /// `"Hombros"`, `"Biceps"`, etc.).
    public static func mappedValue(for storedRawValue: String) -> MuscleGroup? {
        if let direct: MuscleGroup = MuscleGroup(rawValue: storedRawValue) {
            return direct
        }

        switch storedRawValue {
        case "Pecho":
            return .chest
        case "Espalda":
            return .upperBack
        case "Hombros":
            return .frontShoulders
        case "Biceps":
            return .biceps
        case "Triceps":
            return .triceps
        case "Cuadriceps":
            return .quads
        case "Isquios":
            return .hamstrings
        case "Gemelos":
            return .calves
        case "Abdominales":
            return .abs
        case "Gluteos":
            return .glutes
        default:
            return nil
        }
    }

    /// Compatibilidad con los valores guardados por versiones anteriores.
    public static func fromStoredRawValue(_ storedRawValue: String) -> MuscleGroup {
        return mappedValue(for: storedRawValue) ?? .chest
    }

    // MARK: - Listas serializadas

    /// Decodifica una lista guardada en un único `String` separado por `|`.
    public static func decodeList(_ storedRawValue: String) -> [MuscleGroup] {
        guard !storedRawValue.isEmpty else { return [] }

        var result: [MuscleGroup] = []
        for token in storedRawValue.components(separatedBy: "|") {
            let trimmed: String = token.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let group: MuscleGroup = mappedValue(for: trimmed) else { continue }
            guard !result.contains(group) else { continue }
            result.append(group)
        }
        return result
    }

    /// Serializa una lista de grupos musculares para guardarla en SwiftData.
    public static func encodeList(_ groups: [MuscleGroup]) -> String {
        let values: [String] = groups.map { (group: MuscleGroup) -> String in
            return group.rawValue
        }
        return values.joined(separator: "|")
    }
}
