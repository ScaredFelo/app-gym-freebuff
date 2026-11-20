import Foundation

// MARK: - Documento compartido

/// Configuración de un ejercicio dentro de una rutina compartida.
///
/// Incluye solo lo necesario para reconstruir la rutina: no hay series
/// realizadas, pesos levantados, fechas ni pulsaciones.
struct RoutineShareExercise: Codable, Equatable {
    var name: String
    var muscleGroupRaw: String
    var equipmentTypeRaw: String
    var requiresStraps: Bool
    var trackingModeRaw: String
    var targetRepsMin: Int
    var targetRepsMax: Int
    /// Descanso por defecto del ejercicio en el catálogo (`nil` si es por BPM).
    var defaultRestSeconds: Int?
    /// Descanso por caída de pulsaciones (`nil` si es por tiempo).
    var defaultRestTargetBPM: Int?
    var sets: Int
    var repsMin: Int
    var repsMax: Int
    var restSeconds: Int
    var targetWeight: Double
    var notes: String
    var sortOrder: Int
}

/// Rutina compartida: nombre, procedencia y ejercicios configurados.
/// No contiene historial de entrenamientos.
struct RoutineShareRoutine: Codable, Equatable {
    var id: UUID
    var name: String
    var source: String
    var exercises: [RoutineShareExercise]
}

/// Raíz del archivo `.appgymroutine`.
struct RoutineSharePayload: Codable, Equatable {
    static let formatIdentifier: String = "appgym.routine"
    static let currentVersion: Int = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var routine: RoutineShareRoutine
}

/// Archivo listo para compartir.
struct RoutineShareFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let routineName: String

    init(id: UUID = UUID(), url: URL, routineName: String) {
        self.id = id
        self.url = url
        self.routineName = routineName
    }
}

enum RoutineShareError: LocalizedError {
    case encodingFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "No se ha podido preparar la rutina para compartirla."
        case .writeFailed:
            return "No se ha podido generar el archivo de la rutina. Comprueba el espacio libre del dispositivo."
        }
    }
}

// MARK: - Servicio

/// Genera el archivo `.appgymroutine` de una rutina individual.
///
/// Solo lee el modelo: no inserta, modifica ni mueve nada, y el archivo no
/// incluye sesiones, series registradas, pesos levantados, fechas ni
/// pulsaciones. La exportación de la copia de seguridad completa sigue siendo
/// responsabilidad de `BackupManager`.
enum RoutineShareService {
    static let fileExtension: String = "appgymroutine"

    // MARK: Contenido

    static func payload(for routine: Routine, exportedAt: Date = Date()) -> RoutineSharePayload {
        return RoutineSharePayload(
            format: RoutineSharePayload.formatIdentifier,
            version: RoutineSharePayload.currentVersion,
            exportedAt: exportedAt,
            routine: sharedRoutine(for: routine)
        )
    }

    /// Bloque de rutina reutilizado por `.appgymroutine` y `.appgymsplit`.
    ///
    /// Contiene solo la configuración de la rutina: nunca sesiones, series
    /// registradas, fechas ni pulsaciones.
    static func sharedRoutine(for routine: Routine) -> RoutineShareRoutine {
        let exercises: [RoutineShareExercise] = routine.exercises
            .sorted { lhs, rhs in lhs.sortOrder < rhs.sortOrder }
            .map { link -> RoutineShareExercise in
                var defaultRestSeconds: Int? = nil
                var defaultRestTargetBPM: Int? = nil

                if let exercise = link.exercise {
                    switch exercise.defaultRestCondition {
                    case .timer(let seconds):
                        defaultRestSeconds = seconds
                    case .bpmDrop(let targetBpm):
                        defaultRestTargetBPM = targetBpm
                    }
                }

                let exercise: Exercise? = link.exercise
                return RoutineShareExercise(
                    name: exercise?.name ?? "Ejercicio sin nombre",
                    muscleGroupRaw: exercise?.muscleGroupRaw ?? "",
                    equipmentTypeRaw: exercise?.equipmentTypeRaw ?? "",
                    requiresStraps: exercise?.requiresStraps ?? false,
                    trackingModeRaw: exercise?.trackingModeRaw ?? "reps",
                    targetRepsMin: exercise?.targetRepsMin ?? link.targetRepsMin,
                    targetRepsMax: exercise?.targetRepsMax ?? link.targetRepsMax,
                    defaultRestSeconds: defaultRestSeconds,
                    defaultRestTargetBPM: defaultRestTargetBPM,
                    sets: link.defaultSets,
                    repsMin: link.targetRepsMin,
                    repsMax: link.targetRepsMax,
                    restSeconds: link.restSeconds,
                    targetWeight: link.defaultWeight,
                    notes: link.notes,
                    sortOrder: link.sortOrder
                )
            }

        return RoutineShareRoutine(
            id: routine.id,
            name: routine.name,
            source: routine.source.rawValue,
            exercises: exercises
        )
    }

    static func encodedData(for routine: Routine, exportedAt: Date = Date()) throws -> Data {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            return try encoder.encode(payload(for: routine, exportedAt: exportedAt))
        } catch {
            throw RoutineShareError.encodingFailed
        }
    }

    // MARK: Archivo

    static func fileName(for routine: Routine, date: Date = Date()) -> String {
        return "AppGym_Rutina_\(safeName(routine.name))_\(dateStamp(for: date)).\(fileExtension)"
    }

    /// Marca de fecha común a los nombres de archivo compartidos.
    static func dateStamp(for date: Date) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func makeFile(
        for routine: Routine,
        directory: URL? = nil,
        exportedAt: Date = Date()
    ) throws -> RoutineShareFile {
        let data: Data = try encodedData(for: routine, exportedAt: exportedAt)
        let folder: URL = directory ?? FileManager.default.temporaryDirectory
        let url: URL = folder.appendingPathComponent(fileName(for: routine, date: exportedAt))

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RoutineShareError.writeFailed
        }

        return RoutineShareFile(url: url, routineName: routine.name)
    }

    /// Nombre apto para un archivo: sin acentos, sin separadores y acotado.
    static func safeName(_ name: String) -> String {
        let allowed: CharacterSet = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_"))
        let folded: String = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let mapped: String = folded.unicodeScalars
            .map { scalar in allowed.contains(scalar) ? String(scalar) : "_" }
            .joined()
        let collapsed: String = mapped.replacingOccurrences(
            of: "_+",
            with: "_",
            options: .regularExpression
        )
        let trimmed: String = collapsed.trimmingCharacters(
            in: CharacterSet(charactersIn: "_-")
        )

        return trimmed.isEmpty ? "rutina" : String(trimmed.prefix(40))
    }
}
