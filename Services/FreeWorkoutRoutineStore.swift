import Foundation
import SwiftData

/// Rutina contenedora de los entrenamientos "sobre la marcha".
///
/// El entrenamiento libre necesita una `Routine` real en SwiftData para poder
/// añadir ejercicios y series durante la sesión, pero no debe aparecer en la
/// lista de rutinas ni generar copias nuevas en cada entrenamiento. Se usa una
/// única rutina marcada con `isTemplate == false`, que la lista ignora y que se
/// vacía al empezar cada sesión libre.
enum FreeWorkoutRoutineStore {
    static let routineName = "ENTRENO LIBRE"

    static func isFree(_ routine: Routine) -> Bool {
        return !routine.isTemplate
    }

    /// Devuelve la rutina contenedora vacía y lista para recibir ejercicios.
    static func prepare(modelContext: ModelContext) -> Routine {
        let allRoutines: [Routine] = (try? modelContext.fetch(FetchDescriptor<Routine>())) ?? []
        let existing: Routine? = allRoutines.first { (routine: Routine) -> Bool in
            return !routine.isTemplate
        }

        let routine: Routine
        if let existing {
            routine = existing
        } else {
            let created = Routine(name: routineName, isTemplate: false, exercises: [])
            modelContext.insert(created)
            routine = created
        }

        let leftovers: [RoutineExercise] = routine.exercises
        routine.exercises.removeAll()
        for routineExercise in leftovers {
            modelContext.delete(routineExercise)
        }

        routine.name = routineName
        return routine
    }
}
