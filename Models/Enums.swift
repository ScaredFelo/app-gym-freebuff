import Foundation

public enum MuscleGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    case pecho = "Pecho"
    case espalda = "Espalda"
    case hombros = "Hombros"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case cuadriceps = "Cuadriceps"
    case isquios = "Isquios"
    case gemelos = "Gemelos"
    case abdominales = "Abdominales"
    case gluteos = "Gluteos"

    public var id: String { rawValue }
}

public enum EquipmentType: String, Codable, CaseIterable, Sendable, Identifiable {
    case cable = "Poleas"
    case dumbbell = "Mancuernas"
    case fixedBar = "Barra fija"
    case plateLoadedMachine = "Discos para máquina"
    case smithMachine = "Multipower"
    case olympicBar = "Barra olímpica"
    case ezBar = "Barra EZ"

    public var id: String { rawValue }

    /// Equipamientos que se cargan con discos y necesitan calculadora.
    public var usesPlates: Bool {
        switch self {
        case .plateLoadedMachine, .smithMachine, .olympicBar, .ezBar:
            return true
        case .cable, .dumbbell, .fixedBar:
            return false
        }
    }

    /// Peso de la estructura del equipamiento sin discos.
    public var baseWeight: Double {
        switch self {
        case .smithMachine:
            return UserSettingsManager.multipowerBarWeight
        case .olympicBar:
            return 20.0
        case .ezBar:
            return UserSettingsManager.ezBarWeight
        case .plateLoadedMachine, .cable, .dumbbell, .fixedBar:
            return 0.0
        }
    }

    /// Compatibilidad con los valores guardados por versiones anteriores.
    public static func fromStoredRawValue(_ rawValue: String) -> EquipmentType {
        if let direct = EquipmentType(rawValue: rawValue) {
            return direct
        }

        switch rawValue {
        case "Barra Fija":
            return .fixedBar
        case "Discos para Máquina":
            return .plateLoadedMachine
        case "Barra Olímpica":
            return .olympicBar
        default:
            return .olympicBar
        }
    }
}

public enum RestCondition: Codable, Sendable, Hashable {
    case timer(seconds: Int)
    case bpmDrop(targetBpm: Int)
}
