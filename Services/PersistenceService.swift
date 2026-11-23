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

// MARK: - Borrado de ejercicios

/// Borrado seguro de un ejercicio del catálogo.
///
/// `Exercise.logs` usa `deleteRule: .cascade` y los análisis históricos
/// (volumen semanal, series por sesión, récords y ficha del ejercicio) se
/// calculan a partir de esas series. Borrar un ejercicio en uso eliminaría el
/// historial de entrenamientos pasados, así que el borrado solo se permite
/// cuando no hay nada que perder:
///
/// - si el ejercicio pertenece a alguna rutina, no se borra: la rutina se
///   quedaría con un enlace sin ejercicio;
/// - si tiene series registradas, no se borra: el historial cambiaría;
/// - si no está referenciado por nada, se borra y se guarda.
///
/// Ninguna de las comprobaciones modifica datos: cuando se bloquea, la base
/// queda exactamente como estaba.
enum ExerciseDeletionService {
    enum Outcome: Equatable {
        case deleted
        /// Está en uso por una o varias rutinas (se listan sus nombres).
        case blockedByRoutines([String])
        /// Tiene series registradas en el historial.
        case blockedByHistory(Int)
        /// No se pudo comprobar si está en uso: se conserva por seguridad.
        case blockedUnknown
        case saveFailed

        /// Mensaje para la alerta de la interfaz. `nil` cuando se ha borrado.
        func message(for exercise: Exercise) -> String? {
            switch self {
            case .deleted:
                return nil
            case .blockedByRoutines(let names):
                let list: String = names.joined(separator: ", ")
                let isSingle: Bool = names.count == 1
                let usedIn: String = isSingle ? "la rutina" : "las rutinas"
                let removeFrom: String = isSingle ? "esa rutina" : "esas rutinas"
                return "«\(exercise.name)» se usa en \(usedIn) \(list). Elimínalo primero de \(removeFrom) para poder borrarlo. No se ha modificado ningún dato."
            case .blockedByHistory(let count):
                let series: String = count == 1 ? "1 serie registrada" : "\(count) series registradas"
                return "«\(exercise.name)» tiene \(series) en el historial. Borrarlo eliminaría esos datos y cambiaría el volumen y las estadísticas de entrenamientos pasados, así que no se ha borrado. Puedes renombrarlo si no quieres usarlo."
            case .blockedUnknown:
                return "No se ha podido comprobar si «\(exercise.name)» está en uso, así que no se ha borrado."
            case .saveFailed:
                return "No se ha podido eliminar «\(exercise.name)». Vuelve a intentarlo."
            }
        }
    }

    static func delete(_ exercise: Exercise, context: ModelContext) -> Outcome {
        switch referencingRoutineNames(of: exercise, context: context) {
        case .failure:
            return .blockedUnknown
        case .success(let names):
            if !names.isEmpty {
                return .blockedByRoutines(names)
            }
        }

        let historyCount: Int = exercise.logs.count
        guard historyCount == 0 else { return .blockedByHistory(historyCount) }

        context.delete(exercise)
        guard PersistenceService.saveOrRollback(context, operation: "eliminar el ejercicio") else {
            return .saveFailed
        }
        return .deleted
    }

    /// Rutinas cuyos enlaces apuntan al ejercicio. Se leen las rutinas
    /// completas porque `RoutineExercise` no tiene referencia inversa a su
    /// rutina; el catálogo de rutinas es pequeño y el borrado es una acción
    /// puntual. Ante un error de lectura se devuelve `failure` para no borrar
    /// sobre una comprobación incompleta.
    private static func referencingRoutineNames(
        of exercise: Exercise,
        context: ModelContext
    ) -> Result<[String], Error> {
        do {
            let routines: [Routine] = try context.fetch(FetchDescriptor<Routine>())
            let names: [String] = routines
                .filter { (routine: Routine) -> Bool in
                    return routine.exercises.contains { (link: RoutineExercise) -> Bool in
                        return link.exercise?.id == exercise.id
                    }
                }
                .map(\.name)
            return .success(names)
        } catch {
            print("[Persistence] No se pudieron comprobar las rutinas del ejercicio: \(error)")
            return .failure(error)
        }
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
