import Foundation
import SwiftData

// MARK: - Contexto del flujo

/// Indica desde dónde se abre el flujo de configuración de rutinas.
///
/// - `initialSetup`: primera apertura de la app. Recorre bienvenida,
///   importación de copia, personalización, modalidad y resumen.
/// - `changeRoutine`: Ajustes → Cambiar rutina. Reutiliza las pantallas de
///   modalidad y resumen, sin repetir las preguntas de configuración inicial.
enum RoutineFlowContext: String, Sendable {
    case initialSetup
    case changeRoutine

    /// Título técnico que se muestra en la barra de navegación.
    var navigationTitle: String {
        switch self {
        case .initialSetup:
            return "CONFIGURACIÓN INICIAL"
        case .changeRoutine:
            return "CAMBIAR RUTINA"
        }
    }

    /// Solo el contexto de cambio de rutina puede abandonarse sin guardar.
    var allowsCancellation: Bool {
        return self == .changeRoutine
    }
}

// MARK: - Modalidades de organización

/// Las formas de organizar el entrenamiento que ofrece AppGym.
///
/// En esta fase solo se persiste la elección y se prepara la navegación de
/// cada modalidad. Los generadores (automático y asistido) se integran en las
/// fases siguientes sin rehacer estas pantallas.
///
/// `later` no genera nada: cierra la configuración inicial con la lista de
/// rutinas vacía. Solo se ofrece en el onboarding; Ajustes → Cambiar rutina
/// siempre sustituye la organización actual por una nueva.
enum RoutineOrganizationMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case createOwn
    case templates
    case automatic
    case later

    var id: String { rawValue }

    /// Código técnico que encabeza la tarjeta.
    var code: String {
        switch self {
        case .createOwn:
            return "ORG.A"
        case .templates:
            return "ORG.B"
        case .automatic:
            return "ORG.C"
        case .later:
            return "ORG.D"
        }
    }

    var title: String {
        switch self {
        case .createOwn:
            return "Crear mis propias rutinas"
        case .templates:
            return "Utilizar plantillas"
        case .automatic:
            return "Generar mi split automáticamente"
        case .later:
            return "Crear mis rutinas más tarde"
        }
    }

    /// Descripción mostrada en la pantalla de selección.
    var summary: String {
        switch self {
        case .createOwn:
            return "Empieza desde cero y construye tus propias rutinas añadiendo los ejercicios que quieras."
        case .templates:
            return "Construye tu semana de entrenamiento utilizando las plantillas de ejercicios disponibles en AppGym."
        case .automatic:
            return "Indica cómo quieres entrenar y deja que AppGym construya una distribución semanal para ti."
        case .later:
            return "Puedes terminar la configuración ahora y crear tus rutinas cuando quieras desde la aplicación."
        }
    }

    var symbolName: String {
        switch self {
        case .createOwn:
            return "square.and.pencil"
        case .templates:
            return "square.grid.3x3"
        case .automatic:
            return "wand.and.stars"
        case .later:
            return "clock.arrow.circlepath"
        }
    }

    /// Título de la pantalla de configuración de la modalidad.
    var configurationTitle: String {
        switch self {
        case .createOwn:
            return "Crear mis propias rutinas"
        case .templates:
            return "Utilizar plantillas"
        case .automatic:
            return "Generar mi split automáticamente"
        case .later:
            return "Crear mis rutinas más tarde"
        }
    }

    static func fromStoredRawValue(_ rawValue: String) -> RoutineOrganizationMode? {
        return RoutineOrganizationMode(rawValue: rawValue)
    }
}

// MARK: - Plan en construcción

/// Borrador del plan que el usuario configura antes de confirmar el resumen.
///
/// No crea rutinas ni guarda nada: la selección de modalidad solo vive en
/// memoria hasta que se pulsa «Confirmar y empezar».
struct RoutinePlanDraft {
    /// Solo hay mínimo: un mismo día puede tener dos sesiones (mañana y tarde)
    /// y el número de rutinas manuales no depende de los siete días de la
    /// semana, así que no existe límite superior.
    static let minimumRoutineCount: Int = 1
    static let defaultRoutineCount: Int = 3

    var mode: RoutineOrganizationMode?
    var ownRoutineCount: Int = RoutinePlanDraft.defaultRoutineCount

    var clampedRoutineCount: Int {
        return max(ownRoutineCount, Self.minimumRoutineCount)
    }

    var isReadyToSave: Bool {
        return mode != nil
    }

    /// Nombre por defecto de las rutinas vacías creadas en modo manual.
    func routineName(at index: Int) -> String {
        return String(format: "Rutina %02d", index + 1)
    }

    /// Código técnico corto de cada rutina, usado en el resumen.
    func routineCode(at index: Int) -> String {
        return String(format: "RT-%02d", index + 1)
    }
}

// MARK: - Preferencias de configuración inicial

/// Valores de equipamiento y pulsaciones que el onboarding edita en memoria y
/// que solo se escriben en `UserDefaults` al confirmar el resumen.
struct OnboardingPreferences {
    static let barWeightRange: ClosedRange<Double> = 0...100
    static let barWeightStep: Double = 0.5

    var multipowerBarWeight: Double
    var ezBarWeight: Double
    var availablePlates: Set<Double>
    var isHeartRateTrackingEnabled: Bool
    var heartRateDeviceType: HeartRateDeviceType
    var heartRateDeviceBrand: String

    /// Valores actuales de la app, que son los predeterminados del onboarding.
    static var defaults: OnboardingPreferences {
        return OnboardingPreferences(
            multipowerBarWeight: UserSettingsManager.multipowerBarWeight,
            ezBarWeight: UserSettingsManager.ezBarWeight,
            availablePlates: Set(UserSettingsManager.availablePlates),
            isHeartRateTrackingEnabled: UserSettingsManager.isHeartRateTrackingEnabled,
            heartRateDeviceType: UserSettingsManager.heartRateDeviceType,
            heartRateDeviceBrand: UserSettingsManager.heartRateDeviceBrand
        )
    }

    var hasValidEquipment: Bool {
        return !availablePlates.isEmpty
    }

    var clampedMultipowerBarWeight: Double {
        return Self.clampBarWeight(multipowerBarWeight)
    }

    var clampedEZBarWeight: Double {
        return Self.clampBarWeight(ezBarWeight)
    }

    var normalizedHeartRateBrand: String {
        return heartRateDeviceBrand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clampBarWeight(_ value: Double) -> Double {
        return min(max(value, barWeightRange.lowerBound), barWeightRange.upperBound)
    }
}

// MARK: - Resumen

/// Fila del resumen: etiqueta a la izquierda, valor técnico a la derecha.
struct RoutineSummaryItem: Identifiable {
    let id: String
    let label: String
    let value: String

    init(code: String, label: String, value: String) {
        self.id = code
        self.label = label
        self.value = value
    }
}

/// Bloque del resumen con su propio código técnico.
struct RoutineSummarySection: Identifiable {
    let id: String
    let code: String
    let title: String
    let items: [RoutineSummaryItem]
    let note: String?

    init(code: String, title: String, items: [RoutineSummaryItem], note: String? = nil) {
        self.id = code
        self.code = code
        self.title = title
        self.items = items
        self.note = note
    }
}

// MARK: - Resultado y errores

struct RoutineApplicationResult {
    let mode: RoutineOrganizationMode
    let archivedRoutineCount: Int
    let createdRoutineCount: Int
}

enum RoutineConfigurationError: LocalizedError {
    case missingOrganizationMode
    case emptyPlateSelection
    case missingGeneratedPlan
    case missingAssistedWeek
    case generationFailed(String)
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .missingOrganizationMode:
            return "Selecciona cómo quieres organizar tu entrenamiento antes de confirmar."
        case .emptyPlateSelection:
            return "Activa al menos un disco disponible para poder calcular los pesos."
        case .missingGeneratedPlan:
            return "Genera y selecciona una propuesta de split antes de confirmar."
        case .missingAssistedWeek:
            return "Completa los siete días y genera la semana asistida antes de confirmar."
        case .generationFailed(let detail):
            return detail
        case .persistenceFailed:
            return "No se ha podido guardar la configuración. Tus datos actuales se han conservado; vuelve a intentarlo."
        }
    }
}

// MARK: - Constructor asistido de siete días

/// Días de la semana del constructor asistido. El índice 0 es lunes para que
/// el orden coincida con el orden cronológico que ve el usuario.
enum AssistedWeekday: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case monday = 0
    case tuesday = 1
    case wednesday = 2
    case thursday = 3
    case friday = 4
    case saturday = 5
    case sunday = 6

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .monday: return "LUNES"
        case .tuesday: return "MARTES"
        case .wednesday: return "MIÉRCOLES"
        case .thursday: return "JUEVES"
        case .friday: return "VIERNES"
        case .saturday: return "SÁBADO"
        case .sunday: return "DOMINGO"
        }
    }

    var shortCode: String {
        switch self {
        case .monday: return "L"
        case .tuesday: return "M"
        case .wednesday: return "X"
        case .thursday: return "J"
        case .friday: return "V"
        case .saturday: return "S"
        case .sunday: return "D"
        }
    }

    static func from(index: Int) -> AssistedWeekday? {
        return AssistedWeekday(rawValue: index)
    }
}

/// Estado de una casilla. Un día vacío no es un día de descanso: son estados
/// distintos y solo `.rest` cuenta como configuración válida de descanso.
enum AssistedDaySelection: Equatable, Sendable {
    case unassigned
    case rest
    case routine(CatalogRoutine)

    var routine: CatalogRoutine? {
        if case .routine(let routine) = self { return routine }
        return nil
    }

    var isRest: Bool {
        return self == .rest
    }

    var isConfigured: Bool {
        switch self {
        case .unassigned: return false
        case .rest, .routine: return true
        }
    }

    var label: String {
        switch self {
        case .unassigned:
            return "SIN CONFIGURAR"
        case .rest:
            return "DESCANSO"
        case .routine(let routine):
            return routine.displayName
        }
    }
}

struct AssistedDaySlot: Identifiable, Equatable, Sendable {
    let weekday: AssistedWeekday
    var selection: AssistedDaySelection = .unassigned
    /// Sufijo asignado por el recálculo de variantes (`""` = base). `nil`
    /// significa que la variante no se ha podido asignar.
    var assignedSuffix: String? = nil
    var variantProblem: String? = nil

    var id: Int { weekday.rawValue }

    var variantLabel: String? {
        guard let assignedSuffix else { return nil }
        return assignedSuffix.isEmpty ? "BASE" : "VAR \(assignedSuffix)"
    }
}

/// Día que se entrega a la persistencia. `sessionIndex` apunta a la sesión
/// generada correspondiente; los días de descanso lo dejan en `nil`.
struct AssistedDayDraft: Sendable {
    let weekday: AssistedWeekday
    let isRest: Bool
    let routineRaw: String?
    let variantSuffix: String
    let sessionIndex: Int?
}

struct AssistedWeekDraft {
    let days: [AssistedDayDraft]
    let week: GeneratedWeek
}

/// Registro serializado de un día. Se guarda en `AssistedWeekPlan.daysData`
/// para no añadir una segunda tabla ni relaciones que puedan borrar rutinas
/// personales al aplicar una semana.
struct AssistedWeekDayRecord: Codable, Equatable, Sendable {
    let weekdayIndex: Int
    let isRest: Bool
    let routineID: UUID?
    let routineName: String
    let variantSuffix: String
    let sessionIndex: Int?
}

/// Plan semanal guardado por el constructor asistido. Los planes anteriores se
/// marcan inactivos, nunca se borran. Las rutinas personales no se enlazan
/// aquí y no se archivan al confirmar.
@Model
final class AssistedWeekPlan {
    var id: UUID
    var createdAt: Date
    var isActivePlan: Bool
    var daysData: Data

    @Transient
    var days: [AssistedWeekDayRecord] {
        guard !daysData.isEmpty else { return [] }
        do {
            return try JSONDecoder().decode([AssistedWeekDayRecord].self, from: daysData)
        } catch {
            print("[Persistence] Semana asistida ilegible: \(error)")
            return []
        }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        isActivePlan: Bool = true,
        days: [AssistedWeekDayRecord]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.isActivePlan = isActivePlan
        self.daysData = (try? JSONEncoder().encode(days)) ?? Data()
    }
}
