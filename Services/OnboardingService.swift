import Foundation
import SwiftData

/// Servicio del onboarding.
///
/// Centraliza el estado de finalización, la importación de copias de seguridad
/// y la escritura de las preferencias que el flujo edita en memoria. La
/// importación reutiliza `BackupManager` sin tocar el formato JSON existente.
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

    /// Valida la copia sin modificar SwiftData.
    ///
    /// El plan devuelto es el mismo que después se entrega a `confirmBackup`,
    /// de modo que los avisos mostrados y los datos aplicados no pueden
    /// divergir.
    static func prepareBackup(from url: URL, context: ModelContext) -> Result<BackupImportPlan, Error> {
        do {
            return .success(try BackupManager.prepareImport(from: url, context: context))
        } catch {
            return .failure(error)
        }
    }

    /// Aplica un plan ya preparado y refresca los widgets. El resultado se
    /// devuelve en lugar de lanzarse para que la pantalla pueda mostrar éxito o
    /// error y ofrecer reintento.
    static func confirmBackup(
        _ plan: BackupImportPlan,
        context: ModelContext,
        safetyCopyDirectory: URL? = nil
    ) -> Result<BackupImportResult, Error> {
        do {
            let result: BackupImportResult = try BackupManager.restoreBackup(
                using: plan,
                context: context,
                safetyCopyDirectory: safetyCopyDirectory
            )
            WidgetStreakStore.refresh(modelContext: context)
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    /// Importa una copia JSON en un solo paso. Se mantiene para las llamadas que
    /// no necesitan revisar los avisos antes de aplicar el archivo.
    static func importBackup(from url: URL, context: ModelContext) -> Result<Void, Error> {
        switch prepareBackup(from: url, context: context) {
        case .success(let plan):
            switch confirmBackup(plan, context: context) {
            case .success:
                return .success(())
            case .failure(let error):
                return .failure(error)
            }
        case .failure(let error):
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
