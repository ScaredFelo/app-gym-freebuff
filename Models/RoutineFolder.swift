import Foundation
import SwiftData

/// Carpeta que agrupa rutinas en la pestaña Rutinas.
///
/// Decisión de persistencia (revisada en la auditoría 07.1):
///
/// La pertenencia se guarda **dentro de la carpeta**, como una lista ordenada
/// de UUID serializada, y `Routine` no gana ninguna propiedad nueva. Motivos:
///
/// - La migración V5 → V6 solo **añade una entidad**. No se altera la tabla de
///   rutinas de una instalación existente, así que no depende de que SwiftData
///   añada una columna nueva sobre un esquema histórico que en este proyecto se
///   declara con las clases actuales.
/// - Ninguna regla `deleteRule` relaciona carpetas con rutinas: borrar una
///   carpeta no puede arrastrar rutinas, series ni sesiones.
/// - Es el mismo criterio que ya usa `AssistedWeekPlan` (referencias por UUID
///   serializadas en lugar de relaciones entre modelos).
///
/// Una rutina pertenece como máximo a una carpeta (o a ninguna). La pertenencia
/// se resuelve siempre contra las rutinas que existen: un UUID obsoleto en una
/// carpeta no cuenta ni se muestra.
@Model
public final class RoutineFolder {
    public var id: UUID
    public var name: String
    /// Orden estable de las carpetas en la lista principal.
    public var sortOrder: Int
    /// UUID de las rutinas contenidas, en orden de incorporación.
    ///
    /// La lectura de datos ilegibles devuelve una lista vacía para no romper la
    /// interfaz, y la escritura es **no destructiva**: si la codificación falla
    /// se conserva el valor anterior en lugar de vaciar la pertenencia.
    public var routineIDsData: Data = Data()

    @Transient
    public var routineIDs: [UUID] {
        get {
            guard !routineIDsData.isEmpty else { return [] }
            do {
                return try JSONDecoder().decode([UUID].self, from: routineIDsData)
            } catch {
                print("[Persistence] Pertenencia de carpeta ilegible: \(error)")
                return []
            }
        }
        set {
            do {
                routineIDsData = try JSONEncoder().encode(newValue)
            } catch {
                print("[Persistence] No se pudo codificar la pertenencia de la carpeta; se conserva la anterior: \(error)")
            }
        }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        routineIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.routineIDsData = (try? JSONEncoder().encode(routineIDs)) ?? Data()
    }

    // MARK: - Pertenencia

    public func contains(routineID: UUID) -> Bool {
        return routineIDs.contains(routineID)
    }

    /// Añade la rutina si no estaba. No duplica identificadores.
    @discardableResult
    public func add(routineID: UUID) -> Bool {
        var current: [UUID] = routineIDs
        guard !current.contains(routineID) else { return false }
        current.append(routineID)
        routineIDs = current
        return true
    }

    @discardableResult
    public func remove(routineID: UUID) -> Bool {
        var current: [UUID] = routineIDs
        guard current.contains(routineID) else { return false }
        current.removeAll { $0 == routineID }
        routineIDs = current
        return true
    }
}
