import Foundation

enum UserSettingsManager {
    // MARK: - Persistence keys

    static let multipowerBarWeightKey = "multipowerBarWeight"
    static let ezBarWeightKey = "ezBarWeight"
    static let standardBarWeightKey = "standardBarWeight"
    static let availablePlatesKey = "availablePlates"
    static let isBigPictureModeEnabledKey = "isBigPictureModeEnabled"
    static let hrMaxBPMKey = "hrMaxBPM"
    static let hrRestBPMKey = "hrRestBPM"

    // Objetivo semanal de entrenamiento (días por semana)
    static let weeklyWorkoutGoalKey = "weeklyWorkoutGoal"

    // Onboarding (primera apertura)
    static let didCompleteOnboardingKey = "didCompleteOnboarding_v1"

    // Organización del entrenamiento
    static let routineOrganizationModeKey = "routineOrganizationMode"
    static let ownRoutineCountKey = "ownRoutineCount"
    static let automaticSplitDaysKey = "automaticSplitDays"
    static let automaticSplitLegsKey = "automaticSplitLegs"
    static let automaticSplitUpperKey = "automaticSplitUpper"
    static let automaticSplitExpressionKey = "automaticSplitExpression"

    // Medición de pulsaciones
    static let isHeartRateTrackingEnabledKey = "isHeartRateTrackingEnabled"
    /// Zona de pulso (Z1–Z5) para el aviso opcional al salir de ella en cardio.
    /// `0` desactiva el aviso.
    static let cardioAlertZoneKey = "cardioAlertZone"
    /// Avisos de mitad y último minuto en cardio. La campana del objetivo no
    /// depende de este ajuste.
    static let cardioMilestoneAlertsKey = "cardioMilestoneAlerts"
    /// Último tipo de cardio y minutos usados, para prellenar la preparación.
    static let cardioLastTypeKey = "cardioLastType"
    static let cardioLastMinutesKey = "cardioLastMinutes"

    // MARK: - Cardio

    /// Rango de minutos que ofrece la pantalla de preparación.
    static let cardioMinutesRange: ClosedRange<Int> = 5...180

    static var lastCardioType: CardioType {
        guard let raw: String = UserDefaults.standard.string(forKey: cardioLastTypeKey),
              let type: CardioType = CardioType(rawValue: raw) else {
            return .treadmill
        }
        return type
    }

    static var lastCardioMinutes: Int {
        guard UserDefaults.standard.object(forKey: cardioLastMinutesKey) != nil else {
            return 20
        }
        let stored: Int = UserDefaults.standard.integer(forKey: cardioLastMinutesKey)
        return min(max(stored, cardioMinutesRange.lowerBound), cardioMinutesRange.upperBound)
    }

    /// Guarda la configuración con la que arrancó la última sesión.
    static func storeCardioDefaults(type: CardioType, minutes: Int) {
        UserDefaults.standard.set(type.rawValue, forKey: cardioLastTypeKey)
        let clamped: Int = min(max(minutes, cardioMinutesRange.lowerBound), cardioMinutesRange.upperBound)
        UserDefaults.standard.set(clamped, forKey: cardioLastMinutesKey)
    }
    static let heartRateDeviceTypeKey = "heartRateDeviceType"
    static let heartRateDeviceBrandKey = "heartRateDeviceBrand"

    // MARK: - Defaults

    /// Peso de barra Multipower por defecto (kg).
    static let defaultMultipowerBarWeight: Double = 15.0

    /// Peso de barra EZ por defecto (kg).
    static let defaultEZBarWeight: Double = 10.0

    /// Valor inicial editable de la barra estándar. No es una propiedad
    /// universal del tipo: el usuario puede cambiarlo en Ajustes.
    static let defaultStandardBarWeight: Double = 20.0

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

    /// Peso real configurado de la barra estándar. El valor inicial es 20 kg,
    /// pero no se considera universal: cada gimnasio puede tener otra barra.
    static var standardBarWeight: Double {
        guard UserDefaults.standard.object(forKey: standardBarWeightKey) != nil else {
            return defaultStandardBarWeight
        }
        return max(0.0, UserDefaults.standard.double(forKey: standardBarWeightKey))
    }

    /// Discos disponibles configurados, ordenados de mayor a menor.
    static var availablePlates: [Double] {
        guard let raw = UserDefaults.standard.string(forKey: availablePlatesKey) else {
            return plateOptions
        }
        return parsePlates(raw)
    }

    // MARK: - Heart rate

    /// Indica si el usuario quiere medir y registrar pulsaciones. Por defecto
    /// está activo para no romper las sesiones de quien ya usaba un sensor; al
    /// desactivarlo no se escanea Bluetooth, no se leen datos de HealthKit y la
    /// interfaz oculta los BPM.
    static var isHeartRateTrackingEnabled: Bool {
        guard UserDefaults.standard.object(forKey: isHeartRateTrackingEnabledKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: isHeartRateTrackingEnabledKey)
    }

    /// Tipo de dispositivo configurado para medir pulsaciones.
    static var heartRateDeviceType: HeartRateDeviceType {
        guard let raw = UserDefaults.standard.string(forKey: heartRateDeviceTypeKey) else {
            return .heartRateBand
        }
        return HeartRateDeviceType.fromStoredRawValue(raw)
    }

    /// Marca o modelo de la pulsera configurada (etiqueta de interfaz). Vacío
    /// cuando el usuario no ha escrito nada.
    static var heartRateDeviceBrand: String {
        let stored: String = UserDefaults.standard.string(forKey: heartRateDeviceBrandKey) ?? ""
        return stored.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

    // MARK: - Weekly goal

    /// Días de entrenamiento por semana que se persiguen por defecto.
    static let defaultWeeklyWorkoutGoal: Int = 4

    /// Rango configurable del objetivo semanal.
    static let weeklyWorkoutGoalRange: ClosedRange<Int> = 1...7

    /// Objetivo de días de entrenamiento por semana, acotado a `1...7`.
    static var weeklyWorkoutGoal: Int {
        guard UserDefaults.standard.object(forKey: weeklyWorkoutGoalKey) != nil else {
            return defaultWeeklyWorkoutGoal
        }
        let stored: Int = UserDefaults.standard.integer(forKey: weeklyWorkoutGoalKey)
        return min(max(stored, weeklyWorkoutGoalRange.lowerBound), weeklyWorkoutGoalRange.upperBound)
    }

    // MARK: - Onboarding

    /// Valor persistido con el nombre solicitado por el flujo de onboarding.
    static var didCompleteOnboarding_v1: Bool {
        return UserDefaults.standard.bool(forKey: didCompleteOnboardingKey)
    }

    /// Indica si el usuario ya ha terminado la configuración inicial.
    static var isOnboardingCompleted: Bool {
        return didCompleteOnboarding_v1
    }

    /// Marca el onboarding como completado. Solo se llama cuando el plan se ha
    /// guardado correctamente.
    static func markOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: didCompleteOnboardingKey)
    }

    // MARK: - Organización de rutinas

    /// Modalidad de organización configurada por el usuario, si existe.
    static var routineOrganizationMode: RoutineOrganizationMode? {
        guard let raw: String = UserDefaults.standard.string(forKey: routineOrganizationModeKey) else {
            return nil
        }
        return RoutineOrganizationMode.fromStoredRawValue(raw)
    }

    /// Número de rutinas propias configuradas. No hay límite superior: el
    /// usuario puede crear más rutinas que días tiene la semana.
    static var configuredOwnRoutineCount: Int {
        guard UserDefaults.standard.object(forKey: ownRoutineCountKey) != nil else {
            return RoutinePlanDraft.defaultRoutineCount
        }
        let stored: Int = UserDefaults.standard.integer(forKey: ownRoutineCountKey)
        return max(stored, RoutinePlanDraft.minimumRoutineCount)
    }

    // MARK: - Escritura agrupada (onboarding)

    /// Guarda el equipamiento elegido en el onboarding.
    static func storeEquipment(
        multipowerBarWeight: Double,
        ezBarWeight: Double,
        plates: Set<Double>,
        standardBarWeight: Double? = nil
    ) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.set(clampedBarWeight(multipowerBarWeight), forKey: multipowerBarWeightKey)
        defaults.set(clampedBarWeight(ezBarWeight), forKey: ezBarWeightKey)
        if let standardBarWeight {
            defaults.set(clampedBarWeight(standardBarWeight), forKey: standardBarWeightKey)
        }

        if !plates.isEmpty {
            defaults.set(serializePlates(plates), forKey: availablePlatesKey)
        }
    }

    /// Guarda la configuración de pulsaciones elegida en el onboarding.
    static func storeHeartRate(isEnabled: Bool, deviceType: HeartRateDeviceType, brand: String) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: isHeartRateTrackingEnabledKey)
        defaults.set(deviceType.rawValue, forKey: heartRateDeviceTypeKey)
        defaults.set(brand, forKey: heartRateDeviceBrandKey)
    }

    /// Acota el peso de una barra al rango admitido por la interfaz (0–100 kg).
    static func clampedBarWeight(_ value: Double) -> Double {
        return min(max(value, OnboardingPreferences.barWeightRange.lowerBound), OnboardingPreferences.barWeightRange.upperBound)
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
