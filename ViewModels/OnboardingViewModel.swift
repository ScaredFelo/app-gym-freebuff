import Foundation
import SwiftData

/// Estado del onboarding: respuestas de bienvenida, personalización,
/// equipamiento, pulsaciones e importación de copia.
///
/// Las preferencias viven en memoria hasta que el resumen se confirma; así
/// abandonar el flujo no altera la configuración actual de la app.
@MainActor
final class OnboardingViewModel: ObservableObject {

    enum PersonalizationChoice: String {
        case undecided
        case customize
        case useDefaults
    }

    enum BackupState: Equatable {
        case idle
        case importing
        case imported
        case failed(message: String)
    }

    let context: RoutineFlowContext

    @Published var hasUsedAppPreviously: Bool?
    @Published var personalizationChoice: PersonalizationChoice = .undecided
    @Published var multipowerBarWeight: Double
    @Published var ezBarWeight: Double
    @Published var selectedPlates: Set<Double>
    @Published var isHeartRateTrackingEnabled: Bool
    @Published var heartRateDeviceType: HeartRateDeviceType
    @Published var heartRateDeviceBrand: String
    @Published private(set) var backupState: BackupState = .idle

    init(context: RoutineFlowContext) {
        self.context = context

        let preferences: OnboardingPreferences = OnboardingPreferences.defaults
        self.multipowerBarWeight = preferences.clampedMultipowerBarWeight
        self.ezBarWeight = preferences.clampedEZBarWeight
        self.selectedPlates = preferences.availablePlates
        self.isHeartRateTrackingEnabled = preferences.isHeartRateTrackingEnabled
        self.heartRateDeviceType = preferences.heartRateDeviceType
        self.heartRateDeviceBrand = preferences.heartRateDeviceBrand
    }

    // MARK: - Derivados

    /// La selección de modalidad de rutinas solo aparece si el usuario ha
    /// elegido personalizar la app.
    var shouldShowPersonalizationSteps: Bool {
        return personalizationChoice == .customize
    }

    var hasValidEquipment: Bool {
        return !selectedPlates.isEmpty
    }

    var preferences: OnboardingPreferences {
        return OnboardingPreferences(
            multipowerBarWeight: OnboardingPreferences.clampBarWeight(multipowerBarWeight),
            ezBarWeight: OnboardingPreferences.clampBarWeight(ezBarWeight),
            availablePlates: selectedPlates,
            isHeartRateTrackingEnabled: isHeartRateTrackingEnabled,
            heartRateDeviceType: heartRateDeviceType,
            heartRateDeviceBrand: heartRateDeviceBrand
        )
    }

    // MARK: - Respuestas

    func selectPreviousUse(_ hasUsed: Bool) {
        hasUsedAppPreviously = hasUsed
    }

    func selectPersonalization(_ choice: PersonalizationChoice) {
        personalizationChoice = choice
    }

    // MARK: - Equipamiento

    func isPlateSelected(_ plate: Double) -> Bool {
        return selectedPlates.contains(plate)
    }

    func togglePlate(_ plate: Double) {
        if selectedPlates.contains(plate) {
            selectedPlates.remove(plate)
        } else {
            selectedPlates.insert(plate)
        }
    }

    func adjustMultipowerBarWeight(by delta: Double) {
        multipowerBarWeight = Self.steppedWeight(multipowerBarWeight + delta)
    }

    func adjustEZBarWeight(by delta: Double) {
        ezBarWeight = Self.steppedWeight(ezBarWeight + delta)
    }

    private static func steppedWeight(_ value: Double) -> Double {
        let clamped: Double = OnboardingPreferences.clampBarWeight(value)
        let steps: Double = (clamped / OnboardingPreferences.barWeightStep).rounded()
        let stepped: Double = steps * OnboardingPreferences.barWeightStep
        return min(max(stepped, OnboardingPreferences.barWeightRange.lowerBound), OnboardingPreferences.barWeightRange.upperBound)
    }

    // MARK: - Pulsaciones

    func selectHeartRateDevice(_ device: HeartRateDeviceType) {
        heartRateDeviceType = device
    }

    // MARK: - Importación de copia

    func importBackup(from url: URL, context modelContext: ModelContext) {
        backupState = .importing

        switch OnboardingService.importBackup(from: url, context: modelContext) {
        case .success:
            // El archivo restaura ajustes en `UserDefaults`: el equipamiento y
            // las pulsaciones mostrados pasan a reflejar los importados.
            reloadPreferencesFromStorage()
            backupState = .imported
        case .failure(let error):
            backupState = .failed(message: error.localizedDescription)
        }
    }

    func resetBackupState() {
        backupState = .idle
    }

    // MARK: - Guardado final

    /// Refresca los valores en memoria con lo que hay en `UserDefaults`.
    func reloadPreferencesFromStorage() {
        let stored: OnboardingPreferences = OnboardingPreferences.defaults
        multipowerBarWeight = stored.clampedMultipowerBarWeight
        ezBarWeight = stored.clampedEZBarWeight
        selectedPlates = stored.availablePlates
        isHeartRateTrackingEnabled = stored.isHeartRateTrackingEnabled
        heartRateDeviceType = stored.heartRateDeviceType
        heartRateDeviceBrand = stored.heartRateDeviceBrand
    }

    /// Marca el onboarding como completado. Lo llama el flujo únicamente
    /// después de que el plan se haya guardado correctamente.
    func completeSetupIfNeeded() {
        guard context == .initialSetup else { return }
        OnboardingService.completeOnboarding()
    }
}
