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
        /// Copia validada pendiente de que el usuario revise los avisos.
        case reviewing
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
    /// Plan validado del archivo seleccionado. Solo existe mientras el usuario
    /// revisa los avisos; una selección nueva lo sustituye por completo.
    @Published private(set) var preparedBackupPlan: BackupImportPlan?

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

    /// `true` solo cuando el usuario ha importado una copia correctamente: la
    /// organización del entrenamiento procede del archivo, así que el flujo no
    /// pregunta por la modalidad ni genera un split adicional.
    var importedRoutinesReplaceOrganization: Bool {
        return context == .initialSetup && backupState == .imported
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

    /// Valida el archivo elegido sin modificar la base. El estado pasa a
    /// `.reviewing` con el plan preparado, que es el que la pantalla muestra y
    /// después aplica: nunca se prepara dos veces el mismo archivo.
    func prepareBackupImport(from url: URL, context modelContext: ModelContext) {
        // Cambiar de archivo invalida cualquier preparación anterior.
        preparedBackupPlan = nil
        backupState = .idle

        switch OnboardingService.prepareBackup(from: url, context: modelContext) {
        case .success(let plan):
            preparedBackupPlan = plan
            backupState = .reviewing
        case .failure(let error):
            backupState = .failed(message: error.localizedDescription)
        }
    }

    /// Descarta el plan pendiente sin tocar ningún dato.
    func cancelPreparedBackup() {
        preparedBackupPlan = nil
        if backupState == .reviewing {
            backupState = .idle
        }
    }

    /// Aplica el plan que el usuario acaba de revisar. Ignora cualquier segunda
    /// llamada mientras se importa o si ya no hay plan preparado, de modo que no
    /// pueden ejecutarse dos importaciones sobre la misma copia.
    @discardableResult
    func confirmPreparedBackup(
        context modelContext: ModelContext,
        safetyCopyDirectory: URL? = nil
    ) -> Result<BackupImportResult, Error> {
        guard backupState != .importing, let plan: BackupImportPlan = preparedBackupPlan else {
            return .failure(BackupError.restoreFailed)
        }

        guard plan.report.canImport else {
            preparedBackupPlan = nil
            backupState = .failed(message: plan.report.localizedMessage)
            return .failure(BackupError.validationFailed(plan.report))
        }

        backupState = .importing

        switch OnboardingService.confirmBackup(
            plan,
            context: modelContext,
            safetyCopyDirectory: safetyCopyDirectory
        ) {
        case .success(let result):
            // El archivo restaura ajustes en `UserDefaults`: el equipamiento y
            // las pulsaciones mostrados pasan a reflejar los importados.
            preparedBackupPlan = nil
            reloadPreferencesFromStorage()
            backupState = .imported
            return .success(result)
        case .failure(let error):
            preparedBackupPlan = nil
            backupState = .failed(message: error.localizedDescription)
            return .failure(error)
        }
    }

    func resetBackupState() {
        preparedBackupPlan = nil
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
