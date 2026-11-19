import Foundation
import SwiftData

// MARK: - Guardado con errores visibles

/// Punto único de guardado de la app.
///
/// Antes cada vista usaba `try? modelContext.save()`: si SwiftData fallaba
/// (disco lleno, store bloqueado, migración a medias) la interfaz mostraba la
/// acción como realizada aunque nada se hubiese escrito. Este helper devuelve
/// el resultado y deja el error en el log con la operación que lo provocó.
enum PersistenceService {
    /// Intenta guardar y devuelve si se ha escrito de verdad.
    @discardableResult
    static func save(_ context: ModelContext, operation: String) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            print("[Persistence] No se pudo guardar «\(operation)»: \(error)")
            return false
        }
    }

    /// Guarda y, si falla, deshace los cambios pendientes para que la interfaz
    /// no muestre datos que no están en disco.
    @discardableResult
    static func saveOrRollback(_ context: ModelContext, operation: String) -> Bool {
        if save(context, operation: operation) {
            return true
        }
        context.rollback()
        return false
    }
}

// MARK: - Sesiones que quedaron abiertas

/// Cierra las sesiones sin `endDate` que ya no tienen forma de reanudarse.
///
/// El entrenamiento crea la sesión en SwiftData al arrancar, antes de abrir la
/// pantalla. Si el usuario mata la app, descarta el entrenamiento o el estado
/// recuperable se pierde, esa sesión queda abierta para siempre y aparece en el
/// historial y en el backup como un entrenamiento sin final.
enum WorkoutSessionCleanup {
    static func closeStaleSessions(context: ModelContext, keeping activeID: UUID?) {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                session.endDate == nil
            }
        )

        guard let sessions = try? context.fetch(descriptor), !sessions.isEmpty else { return }

        var didChange = false

        for session in sessions {
            if let activeID, session.id == activeID {
                // Es el entrenamiento que la app va a reanudar.
                continue
            }

            if session.setsCompleted.isEmpty {
                // No llegó a registrar ninguna serie: no aporta historial.
                context.delete(session)
            } else {
                // Tenía series registradas: se cierra en la última marca real
                // para conservar el volumen ya conseguido.
                let lastSetDate = session.setsCompleted.map { $0.date }.max() ?? session.startDate
                session.endDate = max(lastSetDate, session.startDate)
                session.exerciseRecords = WorkoutMetricsCalculator.buildExerciseRecords(for: session)
            }

            didChange = true
        }

        guard didChange else { return }
        PersistenceService.save(context, operation: "cerrar sesiones sin finalizar")
    }
}
