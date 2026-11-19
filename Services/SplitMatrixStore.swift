import Foundation

/// Carga y valida la matriz oficial W/L/U empaquetada desde el Excel
/// `logica_rutines_gym_complet.xlsx`.
///
/// La validación de integridad se ejecuta al construir el store: 118
/// combinaciones únicas, el duplicado 7/5/6, y el reparto efectivo 83 avisos /
/// 35 válidas aplicando la prioridad absoluta de W = 7.
struct SplitMatrixStore {
    let file: SplitMatrixFile
    private let entriesByKey: [String: SplitMatrixEntry]

    static let shared: SplitMatrixStore? = {
        do {
            return try SplitMatrixStore(bundle: Bundle.main)
        } catch {
            print("[SplitMatrix] No se pudo cargar la matriz: \(error)")
            return nil
        }
    }()

    init(bundle: Bundle) throws {
        guard let url: URL = bundle.url(forResource: "SplitMatrix", withExtension: "json")
            ?? bundle.url(forResource: "SplitMatrix", withExtension: "json", subdirectory: "Resources") else {
            throw SplitGenerationError.matrixUnavailable
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SplitGenerationError.matrixUnavailable
        }

        try self.init(data: data)
    }

    init(data: Data) throws {
        let decoded: SplitMatrixFile
        do {
            decoded = try JSONDecoder().decode(SplitMatrixFile.self, from: data)
        } catch {
            throw SplitGenerationError.decodingFailed
        }

        try SplitMatrixStore.validate(decoded)

        file = decoded
        var map: [String: SplitMatrixEntry] = [:]
        for entry in decoded.entries {
            map[SplitMatrixStore.key(w: entry.w, l: entry.l, u: entry.u)] = entry
        }
        entriesByKey = map
    }

    // MARK: - Consulta

    func entry(w: Int, l: Int, u: Int) -> SplitMatrixEntry? {
        return entriesByKey[SplitMatrixStore.key(w: w, l: l, u: u)]
    }

    static func key(w: Int, l: Int, u: Int) -> String {
        return "\(w)/\(l)/\(u)"
    }

    // MARK: - Integridad

    private static func validate(_ file: SplitMatrixFile) throws {
        guard file.entries.count == 118 else {
            throw SplitGenerationError.integrity("se esperaban 118 combinaciones y hay \(file.entries.count)")
        }

        let uniqueKeys: Set<String> = Set(file.entries.map { (entry: SplitMatrixEntry) -> String in
            return key(w: entry.w, l: entry.l, u: entry.u)
        })

        guard uniqueKeys.count == 118 else {
            throw SplitGenerationError.integrity("solo hay \(uniqueKeys.count) combinaciones únicas")
        }

        guard file.entries.contains(where: { (entry: SplitMatrixEntry) -> Bool in
            return entry.w == 7 && entry.l == 5 && entry.u == 6
        }) else {
            throw SplitGenerationError.integrity("falta el duplicado 7/5/6")
        }

        let effectiveWarnings: Int = file.entries.filter { (entry: SplitMatrixEntry) -> Bool in
            return entry.w == 7 || entry.isWarningRow
        }.count

        let effectiveValid: Int = file.entries.filter { (entry: SplitMatrixEntry) -> Bool in
            return entry.w != 7 && !entry.isWarningRow
        }.count

        guard effectiveWarnings == 83, effectiveValid == 35 else {
            throw SplitGenerationError.integrity(
                "el reparto efectivo es \(effectiveWarnings) avisos / \(effectiveValid) válidas en lugar de 83 / 35"
            )
        }

        guard file.entries.filter({ (entry: SplitMatrixEntry) -> Bool in
            return entry.w != 7 && !entry.isWarningRow
        }).allSatisfy({ (entry: SplitMatrixEntry) -> Bool in
            return !entry.splits.isEmpty
        }) else {
            throw SplitGenerationError.integrity("hay combinaciones válidas sin propuesta de split")
        }
    }
}
