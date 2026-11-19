import Foundation

public enum EquipmentType: String, Codable, CaseIterable, Sendable, Identifiable {
    case cable = "Poleas"
    case dumbbell = "Mancuernas"
    case fixedBar = "Barra fija"
    case plateLoadedMachine = "Discos para máquina"
    case smithMachine = "Multipower"
    case olympicBar = "Barra olímpica"
    case ezBar = "Barra EZ"
    case bodyweight = "Peso corporal"
    case cardioMachine = "Máquina de cardio"

    public var id: String { rawValue }

    /// Equipamientos que se cargan con discos y necesitan calculadora.
    public var usesPlates: Bool {
        switch self {
        case .plateLoadedMachine, .smithMachine, .olympicBar, .ezBar:
            return true
        case .cable, .dumbbell, .fixedBar, .bodyweight, .cardioMachine:
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
        case .plateLoadedMachine, .cable, .dumbbell, .fixedBar, .bodyweight, .cardioMachine:
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

/// Dispositivo que el usuario usa para medir la frecuencia cardíaca.
///
/// - `airPods`: AirPods Pro (o Apple Watch). Las lecturas llegan a través de
///   Apple Salud / HealthKit.
/// - `heartRateBand`: pulsera, banda o sensor óptico (Amazfit, Polar, Garmin,
///   Coospo...) que emite el servicio BLE estándar de pulso (`0x180D`).
public enum HeartRateDeviceType: String, Codable, CaseIterable, Sendable, Identifiable {
    case airPods = "airPods"
    case heartRateBand = "heartRateBand"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .airPods:
            return "AirPods Pro 3"
        case .heartRateBand:
            return "Pulsera / sensor BPM"
        }
    }

    public var subtitle: String {
        switch self {
        case .airPods:
            return "Pulsaciones vía Apple Salud"
        case .heartRateBand:
            return "Bluetooth · servicio HR 0x180D"
        }
    }

    public var symbolName: String {
        switch self {
        case .airPods:
            return "airpodspro"
        case .heartRateBand:
            return "heart.circle"
        }
    }

    /// Los sensores BLE se conectan directamente; los AirPods solo entregan
    /// datos a través de HealthKit.
    public var usesBluetoothSensor: Bool {
        return self == .heartRateBand
    }

    /// Compatibilidad con valores guardados antiguos o desconocidos.
    public static func fromStoredRawValue(_ rawValue: String) -> HeartRateDeviceType {
        return HeartRateDeviceType(rawValue: rawValue) ?? .heartRateBand
    }
}

/// Unidad con la que se registra el objetivo y cada serie de un ejercicio.
///
/// - `reps`: series de fuerza o hipertrofia medidas en repeticiones.
/// - `seconds`: isométricos mantenidos (plancha, hollow hold...).
/// - `minutes`: trabajo continuo de cardio (bici, cinta, escaleras, remo).
public enum ExerciseTrackingMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case reps = "reps"
    case seconds = "seconds"
    case minutes = "minutes"

    public var id: String { rawValue }

    /// Etiqueta corta que acompaña al rango objetivo.
    public var unitLabel: String {
        switch self {
        case .reps:
            return "REPS"
        case .seconds:
            return "SEG"
        case .minutes:
            return "MIN"
        }
    }

    /// Nombre de la unidad en minúsculas para textos descriptivos.
    public var unitName: String {
        switch self {
        case .reps:
            return "repeticiones"
        case .seconds:
            return "segundos"
        case .minutes:
            return "minutos"
        }
    }

    public var isTimeBased: Bool {
        return self != .reps
    }

    /// Compatibilidad con ejercicios guardados antes de existir este campo.
    public static func fromStoredRawValue(_ storedRawValue: String) -> ExerciseTrackingMode {
        return ExerciseTrackingMode(rawValue: storedRawValue) ?? .reps
    }
}
