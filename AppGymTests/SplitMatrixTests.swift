import XCTest

@testable import AppGym

final class SplitMatrixTests: XCTestCase {

    func testMatrixIntegrityAndDuplicate() throws {
        let store: SplitMatrixStore = try TestResources.matrixStore()

        XCTAssertEqual(store.file.entries.count, 118)
        XCTAssertEqual(store.file.entries.count, Set(store.file.entries.map { "\($0.w)/\($0.l)/\($0.u)" }).count)
        XCTAssertEqual(store.file.duplicateWarnings.count, 1)
        XCTAssertEqual(store.file.duplicateWarnings.first?.w, 7)
        XCTAssertEqual(store.file.duplicateWarnings.first?.l, 5)
        XCTAssertEqual(store.file.duplicateWarnings.first?.u, 6)
        XCTAssertEqual(store.file.duplicateWarnings.first?.rows, [100, 105])
    }

    func testEffectiveWarningAndValidCounts() throws {
        let store: SplitMatrixStore = try TestResources.matrixStore()

        let warnings: Int = store.file.entries.filter { $0.w == 7 || $0.isWarningRow }.count
        let valid: Int = store.file.entries.filter { $0.w != 7 && !$0.isWarningRow }.count

        XCTAssertEqual(warnings, 83)
        XCTAssertEqual(valid, 35)
        XCTAssertEqual(warnings + valid, 118)
    }

    func testWeekSevenAlwaysBlocksGeneration() throws {
        let store: SplitMatrixStore = try TestResources.matrixStore()

        for pair in [(3, 4), (4, 3)] {
            let result: SplitGenerationResult = SplitGenerator.generate(w: 7, l: pair.0, u: pair.1, store: store)

            guard case .warning(let warning) = result else {
                XCTFail("W=7 debe devolver un aviso y nunca propuestas")
                continue
            }

            if case .weeklyRest = warning.kind {
                // Correcto.
            } else {
                XCTFail("El aviso de W=7 debe ser de descanso semanal")
            }
        }

        // Incluso con valores distintos de la matriz, W=7 se bloquea.
        guard case .warning = SplitGenerator.generate(w: 7, l: 2, u: 2, store: store) else {
            return XCTFail("W=7 debe bloquearse siempre")
        }
    }

    func testEveryValidCombinationProducesInterpretableProposals() throws {
        let store: SplitMatrixStore = try TestResources.matrixStore()
        var checked: Int = 0

        for entry in store.file.entries where entry.w != 7 && !entry.isWarningRow {
            let result: SplitGenerationResult = SplitGenerator.generate(
                w: entry.w,
                l: entry.l,
                u: entry.u,
                store: store
            )

            guard case .proposals(let proposals, _) = result else {
                XCTFail("La combinación \(entry.w)/\(entry.l)/\(entry.u) debería tener propuestas")
                continue
            }

            XCTAssertFalse(proposals.isEmpty)
            XCTAssertTrue(proposals.allSatisfy { $0.sessions.count == entry.w })
            XCTAssertTrue(proposals.allSatisfy { $0.w == entry.w && $0.l == entry.l && $0.u == entry.u })
            checked += 1
        }

        XCTAssertEqual(checked, 35)
    }

    func testWarningRowReturnsInsufficientRestWarning() throws {
        let store: SplitMatrixStore = try TestResources.matrixStore()

        guard let entry = store.file.entries.first(where: { $0.w != 7 && $0.isWarningRow }) else {
            return XCTFail("La matriz debe contener combinaciones con aviso distintas de W=7")
        }

        let result: SplitGenerationResult = SplitGenerator.generate(
            w: entry.w,
            l: entry.l,
            u: entry.u,
            store: store
        )

        guard case .warning(let warning) = result else {
            return XCTFail("Una fila con aviso no debe generar propuestas")
        }

        if case .insufficientRest = warning.kind {
            // Correcto.
        } else {
            XCTFail("El aviso debe ser de descanso insuficiente")
        }
    }

    func testMissingCombinationIsNotApproximated() throws {
        let store: SplitMatrixStore = try TestResources.matrixStore()
        let existing: Set<String> = Set(store.file.entries.map { "\($0.w)/\($0.l)/\($0.u)" })

        var candidate: (w: Int, l: Int, u: Int)? = nil

        search: for w in 1...6 {
            for l in 0...w {
                for u in 0...w where !existing.contains("\(w)/\(l)/\(u)") {
                    candidate = (w, l, u)
                    break search
                }
            }
        }

        guard let candidate else {
            return XCTFail("No se encontró una combinación ausente para probar la búsqueda exacta")
        }

        switch SplitGenerator.generate(w: candidate.w, l: candidate.l, u: candidate.u, store: store) {
        case .failure:
            break
        default:
            XCTFail("Una combinación ausente no debe generar propuestas")
        }
    }

    func testInputValidationRanges() {
        if case .invalidInput = SplitGenerator.generate(w: 0, l: 0, u: 0) {
            // Correcto.
        } else {
            XCTFail("W=0 debe ser una entrada no válida")
        }

        if case .invalidInput = SplitGenerator.generate(w: 3, l: 4, u: 0) {
            // Correcto.
        } else {
            XCTFail("L mayor que W debe ser una entrada no válida")
        }
    }
}
