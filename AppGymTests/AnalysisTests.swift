import XCTest

@testable import AppGym

final class AnalysisTests: XCTestCase {

    func testRepeatedRoutineEmitsRecoveryNotice() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 2,
            l: 0,
            u: 2,
            expression: "Push x2",
            sessions: [.push, .push]
        )

        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)

        XCTAssertEqual(week.sessions.count, 2)
        XCTAssertFalse(week.recoveryNotices.isEmpty)

        let notice: RoutineNotice = try XCTUnwrap(week.recoveryNotices.first)
        XCTAssertEqual(notice.affectedRoutines, ["Push A", "Push B"])
        XCTAssertFalse(notice.muscleGroups.isEmpty)
        XCTAssertFalse(notice.reason.isEmpty)
    }

    func testSingleOverlapProducesDescriptiveNotice() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 2,
            l: 0,
            u: 2,
            expression: "Push x2",
            sessions: [.push, .push]
        )

        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)
        let reasons: [String] = week.fatigueNotices.map { $0.reason }

        XCTAssertFalse(reasons.isEmpty, "Un solo par solapado debe describirse sin exigir un umbral")
        XCTAssertTrue(reasons.contains(where: { $0.contains("Solapamiento") }))
        XCTAssertFalse(reasons.contains(where: { $0.lowercased().contains("fatiga real") }))
    }

    func testFrequencyNoticeIsDescriptiveAndThresholdFree() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 3,
            l: 3,
            u: 0,
            expression: "Legs x3",
            sessions: [.legs, .legs, .legs]
        )

        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)
        let reasons: [String] = week.fatigueNotices.map { $0.reason }

        XCTAssertFalse(reasons.isEmpty)
        XCTAssertTrue(reasons.contains(where: { $0.contains("Recuento de apariciones") }))
        XCTAssertTrue(reasons.contains(where: { $0.contains("no estiman fatiga") }))
        XCTAssertFalse(reasons.contains(where: { $0.contains("3 o más") }))
    }

    func testRepeatedPrimaryMuscleEmitsFatigueNotice() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 3,
            l: 3,
            u: 0,
            expression: "Legs x3",
            sessions: [.legs, .legs, .legs]
        )

        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)

        XCTAssertEqual(week.sessions.count, 3)
        XCTAssertFalse(week.fatigueNotices.isEmpty)
    }

    func testNoticesNeverBlockGeneration() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 3,
            l: 3,
            u: 0,
            expression: "Legs x3",
            sessions: [.legs, .legs, .legs]
        )

        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)

        XCTAssertFalse(week.notices.isEmpty, "Este caso debe producir avisos informativos")
        XCTAssertEqual(week.sessions.count, 3, "Los avisos no deben impedir generar la semana")
        XCTAssertEqual(week.totalExercises, week.sessions.reduce(0) { $0 + $1.exercises.count })
    }
}
