import XCTest

@testable import AppGym

final class SplitExpressionParserTests: XCTestCase {

    private func rawValues(_ expression: String) throws -> [String] {
        return try SplitExpressionParser.parse(expression).map { $0.rawValue }
    }

    func testSimpleBlockAndAliases() throws {
        XCTAssertEqual(try rawValues("Upper"), ["Upper"])
        XCTAssertEqual(try rawValues("Full body"), ["Full body"])
        XCTAssertEqual(try rawValues("hams"), ["Hamstrings"])
        XCTAssertEqual(try rawValues("Hamsting"), ["Hamstrings"])
        XCTAssertEqual(try rawValues("Lower/cames"), ["Lower"])
    }

    func testSlashSeparatedBlocks() throws {
        XCTAssertEqual(try rawValues("Push/Pull/Legs"), ["Push", "Pull", "Legs"])
        XCTAssertEqual(try rawValues("Chest+Back/Arms"), ["Chest+Back", "Arms"])
        XCTAssertEqual(try rawValues("chestback+arms"), ["Chest+Back", "Arms"])
    }

    func testGroupMultiplierKeepsOrder() throws {
        XCTAssertEqual(
            try rawValues("(Push/Pull) x2/Quads/Hamstrings/Legs"),
            ["Push", "Pull", "Push", "Pull", "Quads", "Hamstrings", "Legs"]
        )
    }

    func testBlockMultiplier() throws {
        XCTAssertEqual(try rawValues("Legs x3"), ["Legs", "Legs", "Legs"])
        XCTAssertEqual(try rawValues("fullbodyx2/upper"), ["Full body", "Full body", "Upper"])
    }

    func testUnknownBlockThrows() {
        XCTAssertThrowsError(try SplitExpressionParser.parse("Cardio"))
        XCTAssertThrowsError(try SplitExpressionParser.parse("Push/Mystery"))
    }

    func testTooManyRepetitionsThrows() {
        XCTAssertThrowsError(try SplitExpressionParser.parse("Legs x4"))
        XCTAssertThrowsError(try SplitExpressionParser.parse("(Push/Pull) x4"))
    }
}
