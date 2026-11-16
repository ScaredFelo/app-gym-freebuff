import Foundation

enum UserSettingsManager {
    // MARK: - Persistence keys

    static let multipowerBarWeightKey = "multipowerBarWeight"
    static let ezBarWeightKey = "ezBarWeight"
    static let availablePlatesKey = "availablePlates"
    static let isBigPictureModeEnabledKey = "isBigPictureModeEnabled"
    static let hrMaxBPMKey = "hrMaxBPM"
    static let hrRestBPMKey = "hrRestBPM"

    // MARK: - Defaults

    /// Peso de barra Multipower por defecto (kg).
    static let defaultMultipowerBarWeight: Double = 15.0

    /// Peso de barra EZ por defecto (kg).
    static let defaultEZBarWeight: Double = 10.0

    /// Todos los discos estándar del gimnasio, de mayor a menor.
    static let plateOptions: [Double] = [
        25.0,
        20.0,
        15.0,
        10.0,
        5.0,
        2.5,
        2.0,
        1.5,
        1.25,
        1.0,
        0.5
    ]

    /// Alias de compatibilidad con código anterior.
    static let defaultBarWeight: Double = defaultMultipowerBarWeight

    /// Valores base seguros usados cuando el usuario todavía no ha configurado
    /// sus pulsaciones máximas o de reposo.
    static let defaultHRMax: Double = 190
    static let defaultHRRest: Double = 60

    // MARK: - Gym equipment

    /// Peso configurado de la barra Multipower del gimnasio.
    static var multipowerBarWeight: Double {
        guard UserDefaults.standard.object(forKey: multipowerBarWeightKey) != nil else {
            return defaultMultipowerBarWeight
        }
        return max(0.0, UserDefaults.standard.double(forKey: multipowerBarWeightKey))
    }

    /// Peso configurado de la barra EZ del gimnasio.
    static var ezBarWeight: Double {
        guard UserDefaults.standard.object(forKey: ezBarWeightKey) != nil else {
            return defaultEZBarWeight
        }
        return max(0.0, UserDefaults.standard.double(forKey: ezBarWeightKey))
    }

    /// Discos disponibles configurados, ordenados de mayor a menor.
    static var availablePlates: [Double] {
        guard let raw = UserDefaults.standard.string(forKey: availablePlatesKey) else {
            return plateOptions
        }
        return parsePlates(raw)
    }

    // MARK: - Heart rate

    /// Pulsaciones máximas configuradas (190 BPM si no hay valor válido).
    static var hrMax: Double {
        let stored: Double = UserDefaults.standard.double(forKey: hrMaxBPMKey)
        return stored > 0 ? stored : defaultHRMax
    }

    /// Pulsaciones de reposo configuradas (60 BPM si no hay valor válido).
    static var hrRest: Double {
        let stored: Double = UserDefaults.standard.double(forKey: hrRestBPMKey)
        return stored > 0 ? stored : defaultHRRest
    }

    // MARK: - Plate persistence helpers

    /// Representación serializada por defecto con todos los discos activados.
    static var defaultAvailablePlates: String {
        return serializePlates(Set(plateOptions))
    }

    /// Convierte la cadena persistida en una lista de discos ordenada de mayor a menor.
    static func parsePlates(_ raw: String) -> [Double] {
        let values: [Double] = raw.split(separator: ",").compactMap { (part: Substring) -> Double? in
            let cleaned: String = String(part)
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")
            return Double(cleaned)
        }
        return values.sorted(by: { (lhs: Double, rhs: Double) -> Bool in
            return lhs > rhs
        })
    }

    /// Serializa un conjunto de discos usando punto decimal para poder
    /// recuperarlo con `parsePlates`.
    static func serializePlates(_ plates: Set<Double>) -> String {
        let sorted: [Double] = plates.sorted(by: { (lhs: Double, rhs: Double) -> Bool in
            return lhs > rhs
        })
        let pieces: [String] = sorted.map { (plate: Double) -> String in
            return serialized(plate)
        }
        return pieces.joined(separator: ",")
    }

    /// Formato estable para almacenamiento (punto decimal).
    static func serialized(_ weight: Double) -> String {
        if abs(weight - weight.rounded()) < 0.0001 {
            return String(Int(weight.rounded()))
        }
        return String(weight)
    }

    /// Formato legible en español (coma decimal) para la interfaz.
    static func formatted(_ weight: Double) -> String {
        if abs(weight - weight.rounded()) < 0.0001 {
            return String(Int(weight.rounded()))
        }

        var text: String = String(weight)
        if text.contains(".") {
            while text.hasSuffix("0") {
                text.removeLast()
            }
            if text.hasSuffix(".") {
                text.removeLast()
            }
        }
        return text.replacingOccurrences(of: ".", with: ",")
    }
}
