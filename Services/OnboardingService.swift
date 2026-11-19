import Foundation
import SwiftData

/// Servicio del onboarding.
///
/// Centraliza el estado de finalización, la importación de copias de seguridad
/// y la escritura de las preferencias que el flujo edita en memoria. La
/// importación reutiliza `BackupManager.restoreBackup` sin tocar el formato
/// JSON existente.
enum OnboardingService {

    // MARK: - Estado del onboarding

    static var isCompleted: Bool {
        return UserSettingsManager.isOnboardingCompleted
    }

    /// Marca el onboarding como completado. Solo debe llamarse cuando el
    /// guardado del plan haya terminado correctamente.
    static func completeOnboarding() {
        UserSettingsManager.markOnboardingCompleted()
    }

    // MARK: - Importación de copia de seguridad

    /// Importa una copia JSON. El resultado se devuelve en lugar de lanzarse
    /// para que la pantalla pueda mostrar éxito o error y ofrecer reintento.
    static func importBackup(from url: URL, context: ModelContext) -> Result<Void, Error> {
        do {
            try BackupManager.restoreBackup(from: url, context: context)
            WidgetStreakStore.refresh(modelContext: context)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Preferencias

    /// Escribe en `UserDefaults` el equipamiento y las pulsaciones elegidos.
    /// Se llama únicamente cuando el plan se ha guardado con éxito.
    static func applyPreferences(_ preferences: OnboardingPreferences) {
        UserSettingsManager.storeEquipment(
            multipowerBarWeight: preferences.clampedMultipowerBarWeight,
            ezBarWeight: preferences.clampedEZBarWeight,
            plates: preferences.availablePlates
        )

        UserSettingsManager.storeHeartRate(
            isEnabled: preferences.isHeartRateTrackingEnabled,
            deviceType: preferences.heartRateDeviceType,
            brand: preferences.normalizedHeartRateBrand
        )
    }
}
