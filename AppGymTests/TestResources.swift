import Foundation
import XCTest

@testable import AppGym

/// Acceso a los recursos empaquetados de la app desde el bundle de pruebas.
enum TestResources {
    private final class BundleToken {}

    enum ResourceError: Error {
        case missing(String)
    }

    static var bundle: Bundle {
        return Bundle(for: BundleToken.self)
    }

    static func data(named name: String) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
            throw ResourceError.missing("\(name).json")
        }
        return try Data(contentsOf: url)
    }

    static func matrixStore() throws -> SplitMatrixStore {
        return try SplitMatrixStore(data: data(named: "SplitMatrix"))
    }

    static func catalogStore() throws -> ExerciseCatalogStore {
        return try ExerciseCatalogStore(data: data(named: "ExerciseCatalog"))
    }
}
