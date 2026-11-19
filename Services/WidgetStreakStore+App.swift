import Foundation
import SwiftData
import WidgetKit

// MARK: - Integración con la app

/// Recálculo del snapshot de racha desde SwiftData. Vive en un archivo que solo
/// compila el target `AppGym`, para que `WidgetStreakStore` se pueda compartir
/// con la extensión de widgets sin arrastrar los modelos de datos de la app.
extension WidgetStreakStore {
    /// Recalcula el snapshot a partir de las sesiones de SwiftData, lo guarda y
    /// refresca los widgets. Se invoca al abrir la app, al finalizar o borrar
    /// una sesión, al importar una copia y al cambiar el objetivo semanal.
    public static func recalculateAndSave(sessions: [WorkoutSession], weeklyGoal: Int) {
        let workoutDates: [Date] = sessions.compactMap { (session: WorkoutSession) -> Date? in
            guard session.endDate != nil else { return nil }
            return session.startDate
        }

        let snapshot: WorkoutStreakSnapshot = makeSnapshot(
            workoutDates: workoutDates,
            weeklyGoal: weeklyGoal
        )

        saveWeeklyGoal(weeklyGoal)
        save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Atajo que lee todas las sesiones del contexto y aplica el objetivo
    /// guardado en `UserSettingsManager`.
    public static func refresh(modelContext: ModelContext) {
        let descriptor: FetchDescriptor<WorkoutSession> = FetchDescriptor<WorkoutSession>()
        let sessions: [WorkoutSession] = (try? modelContext.fetch(descriptor)) ?? []
        recalculateAndSave(sessions: sessions, weeklyGoal: UserSettingsManager.weeklyWorkoutGoal)
    }
}
