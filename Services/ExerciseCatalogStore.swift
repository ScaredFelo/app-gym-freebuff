import Foundation

/// Carga el catálogo de rutinas, variantes y ejercicios empaquetado desde
/// `Catálogo de Rutinas y Ejercicios Gym - Modificado.xlsx`.
///
/// Las variantes se indexan por hoja:
/// - `single`: rutina base.
/// - `double`: sufijos `A` y `B`.
/// - `triple`: sufijos `A`, `B` y `C`.
struct ExerciseCatalogStore {
    let file: ExerciseCatalogFile
    private let variantsByLevel: [Int: [String: CatalogRoutineVariant]]

    static let shared: ExerciseCatalogStore? = {
        do {
            return try ExerciseCatalogStore(bundle: Bundle.main)
        } catch {
            print("[ExerciseCatalog] No se pudo cargar el catálogo: \(error)")
            return nil
        }
    }()

    init(bundle: Bundle) throws {
        guard let url: URL = bundle.url(forResource: "ExerciseCatalog", withExtension: "json")
            ?? bundle.url(forResource: "ExerciseCatalog", withExtension: "json", subdirectory: "Resources") else {
            throw SplitGenerationError.catalogUnavailable
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SplitGenerationError.catalogUnavailable
        }

        try self.init(data: data)
    }

    init(data: Data) throws {
        let decoded: ExerciseCatalogFile
        do {
            decoded = try JSONDecoder().decode(ExerciseCatalogFile.self, from: data)
        } catch {
            throw SplitGenerationError.catalogDecodingFailed
        }

        try ExerciseCatalogStore.validate(decoded)

        file = decoded

        var levels: [Int: [String: CatalogRoutineVariant]] = [:]
        levels[1] = try ExerciseCatalogStore.index(decoded.levels.single)
        levels[2] = try ExerciseCatalogStore.index(decoded.levels.double)
        levels[3] = try ExerciseCatalogStore.index(decoded.levels.triple)
        variantsByLevel = levels
    }

    // MARK: - Consulta

    /// Variante concreta para una aparición de la rutina en la semana.
    func variant(for routine: CatalogRoutine, occurrences: Int, suffix: String) -> CatalogRoutineVariant? {
        guard let level: [String: CatalogRoutineVariant] = variantsByLevel[occurrences] else {
            return nil
        }
        return level[ExerciseCatalogStore.key(routine: routine, suffix: suffix)]
    }

    /// Número de variantes distintas disponibles para una rutina.
    func availableVariants(for routine: CatalogRoutine) -> Int {
        var count: Int = 0
        for level in 1...3 {
            guard let variants: [String: CatalogRoutineVariant] = variantsByLevel[level] else { continue }
            for suffix in suffixes(for: level) {
                if variants[ExerciseCatalogStore.key(routine: routine, suffix: suffix)] != nil {
                    count += 1
                }
            }
        }
        return count
    }

    static func suffixes(for occurrences: Int) -> [String] {
        switch occurrences {
        case 1:
            return [""]
        case 2:
            return ["A", "B"]
        case 3:
            return ["A", "B", "C"]
        default:
            return []
        }
    }

    static func key(routine: CatalogRoutine, suffix: String) -> String {
        return suffix.isEmpty ? routine.rawValue : "\(routine.rawValue) \(suffix)"
    }

    // MARK: - Carga e integridad

    private static func index(_ variants: [CatalogRoutineVariant]) throws -> [String: CatalogRoutineVariant] {
        var map: [String: CatalogRoutineVariant] = [:]
        for variant in variants {
            guard map[variant.routineRaw] == nil else {
                throw SplitGenerationError.integrity("la variante «\(variant.routineRaw)» está duplicada en el catálogo")
            }
            guard !variant.exercises.isEmpty else {
                throw SplitGenerationError.integrity("la variante «\(variant.routineRaw)» no tiene ejercicios")
            }
            map[variant.routineRaw] = variant
        }
        return map
    }

    private static func validate(_ file: ExerciseCatalogFile) throws {
        guard file.levels.single.count == 10,
              file.levels.double.count == 20,
              file.levels.triple.count == 9 else {
            throw SplitGenerationError.integrity(
                "se esperaban 10/20/9 variantes y hay \(file.levels.single.count)/\(file.levels.double.count)/\(file.levels.triple.count)"
            )
        }

        guard file.uniqueExercises.count == 47 else {
            throw SplitGenerationError.integrity("se esperaban 47 ejercicios únicos y hay \(file.uniqueExercises.count)")
        }
    }
}
