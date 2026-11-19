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

    /// Devuelve la rutina contenedora vacía y lista para recibir ejercicios, o
    /// `nil` si no se pudo leer la base de datos.
    ///
    /// Antes el fallo de lectura se convertía en un array vacío: la app no
    /// encontraba la contenedora y creaba una segunda "ENTRENO LIBRE", con los
    /// ejercicios repartidos entre las dos. Ahora el fallo se trata como tal.
    static func prepare(modelContext: ModelContext) -> Routine? {
        let allRoutines: [Routine]
        do {
            allRoutines = try modelContext.fetch(FetchDescriptor<Routine>())
        } catch {
            print("[Persistence] No se pudieron leer las rutinas para el entreno libre: \(error)")
            return nil
        }
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
