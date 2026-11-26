import XCTest
import Foundation
import SwiftData

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

// MARK: - Calendario de Progreso: criterio único de día

/// Pruebas del criterio compartido por los marcadores del calendario y la
/// selección de un día en Progreso (`WorkoutDayCatalog`).
///
/// La presentación de SwiftUI (la hoja y el cambio a la pantalla de
/// estadísticas) no se puede ejercitar desde XCTest con las herramientas
/// actuales: eso requiere Xcode o un iPhone. Lo que sí se fija aquí es el
/// contrato del que depende esa presentación: qué días llevan marcador, qué
/// sesiones se ofrecen, en qué orden, con qué identidad y que abrir
/// estadísticas no modifica SwiftData.
final class ProgressDaySelectionTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema: Schema = Schema(versionedSchema: AppSchemaV6.self)
        let configuration: ModelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Utilidades

    private func moment(day: Int, hour: Int, minute: Int) -> Date {
        let calendar: Calendar = WorkoutDayCalendar.calendar
        var components: DateComponents = DateComponents()
        components.year = 2025
        components.month = 3
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    @discardableResult
    private func storeSession(
        start: Date,
        end: Date?,
        routineName: String = "PUSH"
    ) throws -> WorkoutSession {
        let session: WorkoutSession = WorkoutSession(
            startDate: start,
            endDate: end,
            totalVolumeKg: 0.0,
            routineName: routineName
        )
        context.insert(session)
        try context.save()
        return session
    }

    // MARK: - Selección de un día

    func testSelectingADayWithOneFinishedSessionOpensItsStatistics() throws {
        let start: Date = moment(day: 10, hour: 18, minute: 0)
        let session: WorkoutSession = try storeSession(start: start, end: start.addingTimeInterval(3_600))

        let selection: WorkoutDaySelection = try XCTUnwrap(
            WorkoutDayCatalog.selection(on: WorkoutDayCalendar.dayKey(for: start), from: [session])
        )

        XCTAssertEqual(selection.sessions.count, 1)
        XCTAssertTrue(selection.singleSession === session, "Debe abrirse el mismo modelo, sin copiarlo")
        XCTAssertEqual(selection.day, WorkoutDayCalendar.dayKey(for: start))
    }

    func testTheFirstSelectionWorksWithoutTouchingAnotherDay() throws {
        let start: Date = moment(day: 11, hour: 8, minute: 30)
        let session: WorkoutSession = try storeSession(start: start, end: start.addingTimeInterval(2_400))
        let sessions: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())

        // Primera llamada de la vista, sin ninguna selección previa.
        let first: WorkoutDaySelection = try XCTUnwrap(
            WorkoutDayCatalog.selection(on: WorkoutDayCalendar.dayKey(for: start), from: sessions)
        )

        XCTAssertEqual(first.sessions.map(\.id), [session.id])
        XCTAssertNotNil(first.singleSession)
    }

    func testSelectingTwoConsecutiveDaysUpdatesTheSessions() throws {
        let firstDay: Date = moment(day: 12, hour: 9, minute: 0)
        let secondDay: Date = moment(day: 13, hour: 9, minute: 0)
        let firstSession: WorkoutSession = try storeSession(
            start: firstDay,
            end: firstDay.addingTimeInterval(1_800),
            routineName: "PUSH"
        )
        let secondSession: WorkoutSession = try storeSession(
            start: secondDay,
            end: secondDay.addingTimeInterval(1_800),
            routineName: "PULL"
        )
        let sessions: [WorkoutSession] = [firstSession, secondSession]

        let first: WorkoutDaySelection = try XCTUnwrap(WorkoutDayCatalog.selection(on: firstDay, from: sessions))
        let second: WorkoutDaySelection = try XCTUnwrap(WorkoutDayCatalog.selection(on: secondDay, from: sessions))

        XCTAssertEqual(first.sessions.map(\.id), [firstSession.id])
        XCTAssertEqual(second.sessions.map(\.id), [secondSession.id])
        XCTAssertFalse(
            second.sessions.contains { $0.id == firstSession.id },
            "No deben sobrevivir las sesiones del día anterior"
        )
    }

    func testSelectingTheSameDayTwiceKeepsTheSessionsAndRenewsThePresentation() throws {
        let start: Date = moment(day: 14, hour: 19, minute: 0)
        let session: WorkoutSession = try storeSession(start: start, end: start.addingTimeInterval(2_700))
        let day: Date = WorkoutDayCalendar.dayKey(for: start)

        let first: WorkoutDaySelection = try XCTUnwrap(WorkoutDayCatalog.selection(on: day, from: [session]))
        let second: WorkoutDaySelection = try XCTUnwrap(WorkoutDayCatalog.selection(on: day, from: [session]))

        XCTAssertEqual(first.sessions.map(\.id), second.sessions.map(\.id))
        XCTAssertNotEqual(
            first.id,
            second.id,
            "Cada pulsación debe producir una presentación nueva, no reutilizar la hoja anterior"
        )
    }

    func testADayWithoutWorkoutsDoesNotReuseOldSessions() throws {
        let start: Date = moment(day: 15, hour: 17, minute: 0)
        let session: WorkoutSession = try storeSession(start: start, end: start.addingTimeInterval(1_500))
        let sessions: [WorkoutSession] = [session]
        let emptyDay: Date = moment(day: 20, hour: 12, minute: 0)

        XCTAssertNotNil(WorkoutDayCatalog.selection(on: start, from: sessions))
        XCTAssertNil(WorkoutDayCatalog.selection(on: emptyDay, from: sessions))
        XCTAssertFalse(
            WorkoutDayCatalog.markedDays(from: sessions).contains(WorkoutDayCalendar.dayKey(for: emptyDay))
        )
    }

    func testMultipleSessionsOnTheSameDayAreAllSelectableAndOrdered() throws {
        let morning: Date = moment(day: 16, hour: 9, minute: 0)
        let evening: Date = moment(day: 16, hour: 19, minute: 0)
        let eveningSession: WorkoutSession = try storeSession(
            start: evening,
            end: evening.addingTimeInterval(2_000),
            routineName: "PULL"
        )
        let morningSession: WorkoutSession = try storeSession(
            start: morning,
            end: morning.addingTimeInterval(2_000),
            routineName: "PUSH"
        )

        let selection: WorkoutDaySelection = try XCTUnwrap(
            WorkoutDayCatalog.selection(on: morning, from: [eveningSession, morningSession])
        )

        XCTAssertEqual(selection.sessions.map(\.id), [morningSession.id, eveningSession.id])
        XCTAssertNil(selection.singleSession)
        XCTAssertTrue(
            selection.sessions.contains { $0 === eveningSession },
            "Elegir una sesión concreta debe devolver ese mismo modelo"
        )
    }

    func testAnActiveSessionIsNotTreatedAsFinishedStatistics() throws {
        let start: Date = moment(day: 17, hour: 18, minute: 0)
        let active: WorkoutSession = try storeSession(start: start, end: nil)
        let day: Date = WorkoutDayCalendar.dayKey(for: start)

        XCTAssertFalse(active.isFinishedWorkout)
        XCTAssertTrue(WorkoutDayCatalog.markedDays(from: [active]).isEmpty)
        XCTAssertNil(WorkoutDayCatalog.selection(on: day, from: [active]))
        XCTAssertTrue(WorkoutDayCatalog.finishedSessions(on: day, from: [active]).isEmpty)
    }

    func testMarkingAndSelectingShareTheSameCalendarAndTimeZone() throws {
        let late: Date = moment(day: 18, hour: 23, minute: 50)
        let early: Date = moment(day: 19, hour: 0, minute: 10)
        let lateSession: WorkoutSession = try storeSession(start: late, end: late.addingTimeInterval(600))
        let earlySession: WorkoutSession = try storeSession(start: early, end: early.addingTimeInterval(600))
        let sessions: [WorkoutSession] = [lateSession, earlySession]

        XCTAssertEqual(WorkoutDayCalendar.calendar.timeZone, Calendar.current.timeZone)
        XCTAssertEqual(WorkoutDayCalendar.calendar.firstWeekday, 2)
        XCTAssertEqual(WorkoutDayCalendar.dayKey(for: late), WorkoutDayCalendar.calendar.startOfDay(for: late))

        let marked: Set<Date> = WorkoutDayCatalog.markedDays(from: sessions)
        XCTAssertEqual(marked.count, 2, "23:50 y 00:10 pertenecen a días distintos")
        XCTAssertNotEqual(WorkoutDayCalendar.dayKey(for: late), WorkoutDayCalendar.dayKey(for: early))

        for day in marked {
            XCTAssertNotNil(
                WorkoutDayCatalog.selection(on: day, from: sessions),
                "Todo día marcado debe abrir exactamente las sesiones que lo marcaron"
            )
        }

        XCTAssertEqual(
            WorkoutDayCatalog.selection(on: late, from: sessions)?.sessions.map(\.id),
            [lateSession.id]
        )
        XCTAssertEqual(
            WorkoutDayCatalog.selection(on: early, from: sessions)?.sessions.map(\.id),
            [earlySession.id]
        )
    }

    func testDismissingTheStatisticsKeepsTheCalendarSelectable() throws {
        let firstDay: Date = moment(day: 21, hour: 9, minute: 0)
        let secondDay: Date = moment(day: 22, hour: 9, minute: 0)
        let firstSession: WorkoutSession = try storeSession(
            start: firstDay,
            end: firstDay.addingTimeInterval(1_200),
            routineName: "PUSH"
        )
        let secondSession: WorkoutSession = try storeSession(
            start: secondDay,
            end: secondDay.addingTimeInterval(1_200),
            routineName: "LEGS"
        )
        let sessions: [WorkoutSession] = [firstSession, secondSession]

        // Estado de la vista al abrir el informe del primer día.
        var presented: WorkoutDaySelection? = WorkoutDayCatalog.selection(on: firstDay, from: sessions)
        XCTAssertNotNil(presented)

        // Cerrar el informe devuelve la vista a `nil`.
        presented = nil
        XCTAssertNil(presented)

        presented = WorkoutDayCatalog.selection(on: secondDay, from: sessions)
        XCTAssertEqual(try XCTUnwrap(presented).sessions.map(\.id), [secondSession.id])

        // Y el primero sigue siendo seleccionable tras el cierre.
        XCTAssertEqual(
            WorkoutDayCatalog.selection(on: firstDay, from: sessions)?.sessions.map(\.id),
            [firstSession.id]
        )
    }

    func testOpeningStatisticsDoesNotModifyOrDeleteStoredRecords() throws {
        let start: Date = moment(day: 23, hour: 18, minute: 0)
        let exercise: Exercise = Exercise(name: "Press banca", muscleGroup: .chest, equipmentType: .olympicBar)
        context.insert(exercise)

        let session: WorkoutSession = WorkoutSession(
            startDate: start,
            endDate: start.addingTimeInterval(3_000),
            totalVolumeKg: 800.0,
            routineName: "PUSH"
        )
        context.insert(session)

        let log: WorkoutSetLog = WorkoutSetLog(
            date: start.addingTimeInterval(120),
            weight: 80.0,
            reps: 5,
            isCompleted: true,
            exercise: exercise,
            session: session
        )
        context.insert(log)
        try context.save()

        let sessionsBefore: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        let logsBefore: [WorkoutSetLog] = try context.fetch(FetchDescriptor<WorkoutSetLog>())
        let endDateBefore: Date? = session.endDate
        let volumeBefore: Double = session.totalVolumeKg

        let selection: WorkoutDaySelection = try XCTUnwrap(
            WorkoutDayCatalog.selection(on: WorkoutDayCalendar.dayKey(for: start), from: sessionsBefore)
        )
        XCTAssertTrue(selection.singleSession === session)

        let sessionsAfter: [WorkoutSession] = try context.fetch(FetchDescriptor<WorkoutSession>())
        let logsAfter: [WorkoutSetLog] = try context.fetch(FetchDescriptor<WorkoutSetLog>())

        XCTAssertEqual(sessionsAfter.count, sessionsBefore.count)
        XCTAssertEqual(logsAfter.count, logsBefore.count)
        XCTAssertTrue(sessionsAfter.first === session, "La identidad del modelo debe conservarse")
        XCTAssertTrue(logsAfter.first === log)
        XCTAssertEqual(session.endDate, endDateBefore)
        XCTAssertEqual(session.totalVolumeKg, volumeBefore)
        XCTAssertEqual(log.session?.id, session.id)
        XCTAssertFalse(context.hasChanges, "Abrir estadísticas es una operación de lectura")
    }

    func testEveryMarkedDayOpensACoherentSelection() throws {
        let finishedDay: Date = moment(day: 24, hour: 9, minute: 0)
        let activeDay: Date = moment(day: 25, hour: 9, minute: 0)
        let finished: WorkoutSession = try storeSession(start: finishedDay, end: finishedDay.addingTimeInterval(1_800))
        let active: WorkoutSession = try storeSession(start: activeDay, end: nil)
        let sessions: [WorkoutSession] = [finished, active]

        let marked: Set<Date> = WorkoutDayCatalog.markedDays(from: sessions)

        XCTAssertEqual(marked, [WorkoutDayCalendar.dayKey(for: finishedDay)])
        for day in marked {
            XCTAssertNotNil(WorkoutDayCatalog.selection(on: day, from: sessions))
        }
        XCTAssertNil(WorkoutDayCatalog.selection(on: activeDay, from: sessions))
    }
}
