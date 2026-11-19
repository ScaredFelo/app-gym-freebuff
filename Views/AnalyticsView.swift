import SwiftUI
import SwiftData

public struct AnalyticsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var sets: [WorkoutSetLog]
    @Query private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]

    @State private var showingPersonalRecords = false
    @State private var showingWorkoutHistory = false
    @State private var sessionPendingDeletion: WorkoutSession?

    // Selección de un día del calendario y review de una sesión histórica.
    @State private var selectedDayDate: Date?
    @State private var selectedDaySessions: [WorkoutSession] = []
    @State private var showingDaySessions = false
    @State private var sessionToReviewAfterSheet: WorkoutSession?
    @State private var reviewSession: WorkoutSession?

    public var body: some View {
        NavigationStack {
            ZStack {
                TechnicalGridBackground()

                ScrollView {
                    VStack(spacing: 12.0) {
                        // Weekly Volume Chart
                        weeklyVolumeChartSection

                        // Monthly Workout Calendar
                        monthlyCalendarSection

                        // Personal Records (PRs) - desplegable
                        EndfieldDisclosure(
                            code: "PR.01",
                            title: "Récords personales",
                            isExpanded: $showingPersonalRecords
                        ) {
                            personalRecordsSectionContent
                        }

                        // Workout History & Total Volume - desplegable
                        EndfieldDisclosure(
                            code: "LOG.02",
                            title: "Historial de sesiones",
                            isExpanded: $showingWorkoutHistory
                        ) {
                            workoutHistorySectionContent
                        }
                    }
                    .padding(.horizontal, 16.0)
                    .padding(.vertical, 16.0)
                }
            }
            .navigationTitle("PROGRESO")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "¿Eliminar entrenamiento?",
                isPresented: Binding(
                    get: { sessionPendingDeletion != nil },
                    set: { if !$0 { sessionPendingDeletion = nil } }
                )
            ) {
                Button("Eliminar", role: .destructive) {
                    deletePendingSession()
                }
                Button("Cancelar", role: .cancel) {
                    sessionPendingDeletion = nil
                }
            } message: {
                Text("Esta acción no se puede deshacer.")
            }
            .sheet(isPresented: $showingDaySessions, onDismiss: openPendingReviewSession) {
                DaySessionsSheet(
                    date: selectedDayDate ?? Date(),
                    sessions: selectedDaySessions,
                    onSelect: { (session: WorkoutSession) in
                        sessionToReviewAfterSheet = session
                        showingDaySessions = false
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(EndfieldPalette.bgPrimary)
            }
            .fullScreenCover(item: $reviewSession) { (session: WorkoutSession) in
                WorkoutReviewView(session: session, isPostWorkout: false)
            }
        }
    }

    // MARK: - Weekly Volume Chart

    /// Barras horizontales de series completadas por grupo muscular en los
    /// últimos 7 días, dentro del panel táctico de telemetría.
    private var weeklyVolumeChartSection: some View {
        TacticalPanel(code: "TEL.07", title: "Volumen de series", contentPadding: 12.0) {
            WeeklyMuscleVolumeBarChart(sessions: sessions)
        }
    }

    // MARK: - Monthly Workout Calendar

    /// Calendario mensual paginado horizontalmente. Las sesiones se pasan al
    /// componente para resaltar los días con entrenamiento y abrir el popup
    /// diario existente al pulsar cualquier fecha.
    private var monthlyCalendarSection: some View {
        TacticalPanel(code: "CAL.01", title: "Calendario de entrenamientos", contentPadding: 12.0) {
            MonthlyCalendarPagerView(
                sessions: sessions,
                onSelectDate: { (date: Date) in
                    selectDay(date)
                }
            )
        }
    }

    // MARK: - Personal Records (PRs) - contenido (sin título, va dentro del DisclosureGroup)

    private var personalRecordsSectionContent: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            if exercises.isEmpty {
                Text("SIN EJERCICIOS REGISTRADOS")
                    .font(EndfieldFont.mono(10.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
            } else {
                ForEach(exercises) { exercise in
                    let pr = computePR(for: exercise)

                    HStack(spacing: 8.0) {
                        VStack(alignment: .leading, spacing: 2.0) {
                            Text(exercise.name.uppercased())
                                .font(EndfieldFont.label(9.0))
                                .tracking(0.6)
                                .foregroundStyle(EndfieldPalette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Text(exercise.muscleGroup.shortName.uppercased())
                                .font(EndfieldFont.label(7.0))
                                .foregroundStyle(EndfieldPalette.textSecondary)
                        }

                        Spacer(minLength: 6.0)

                        Text(pr != nil ? "\(String(format: "%.1f", pr!.weight)) KG" : "—")
                            .font(EndfieldFont.mono(11.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.accentYellow)

                        Text(pr != nil ? "× \(pr!.reps)" : "")
                            .font(EndfieldFont.mono(9.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                    }
                    .padding(.vertical, 6.0)
                    .padding(.horizontal, 8.0)
                    .background(EndfieldPalette.bgElevated)
                    .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
                    .overlay {
                        ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                            .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                    }
                }
            }
        }
    }

    struct PersonalRecord {
        let weight: Double
        let reps: Int
    }

    private func computePR(for exercise: Exercise) -> PersonalRecord? {
        let exerciseLogs = sets.filter { $0.exercise?.id == exercise.id && $0.isCompleted }
        guard let bestLog = exerciseLogs.max(by: { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }) else {
            return nil
        }
        return PersonalRecord(weight: bestLog.weight, reps: bestLog.reps)
    }

    // MARK: - Workout History & Total Volume - contenido (sin título, va dentro del DisclosureGroup)

    private var workoutHistorySectionContent: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            let sortedSessions = sessions.sorted(by: { (lhs: WorkoutSession, rhs: WorkoutSession) -> Bool in
                return lhs.startDate > rhs.startDate
            })

            if sortedSessions.isEmpty {
                Text("NO HAY SESIONES REGISTRADAS")
                    .font(EndfieldFont.mono(10.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
            } else {
                ForEach(sortedSessions) { (session: WorkoutSession) in
                    HStack(spacing: 8.0) {
                        VStack(alignment: .leading, spacing: 2.0) {
                            Text(session.startDate.formatted(date: .numeric, time: .omitted))
                                .font(EndfieldFont.mono(10.0, weight: .bold))
                                .foregroundStyle(EndfieldPalette.textPrimary)

                            Text(sessionDetailText(session))
                                .font(EndfieldFont.label(7.0))
                                .tracking(0.8)
                                .foregroundStyle(EndfieldPalette.textSecondary)
                        }

                        Spacer(minLength: 6.0)

                        Text(sessionMetricText(session))
                            .font(EndfieldFont.mono(10.0, weight: .bold))
                            .foregroundStyle(sessionMetricTint(session))

                        Button(role: .destructive) {
                            sessionPendingDeletion = session
                        } label: {
                            Image(systemName: "trash")
                                .font(EndfieldFont.mono(9.0, weight: .bold))
                        }
                        .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentRed, size: 26.0))
                        .accessibilityLabel("Eliminar entrenamiento")
                    }
                    .padding(.vertical, 6.0)
                    .padding(.horizontal, 8.0)
                    .background(EndfieldPalette.bgElevated)
                    .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
                    .overlay {
                        ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                            .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            sessionPendingDeletion = session
                        } label: {
                            Label("Eliminar entrenamiento", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Descripción de una sesión

    /// Las sesiones de cardio no tienen series ni volumen: se describen por
    /// modalidad y duración.
    private func sessionDetailText(_ session: WorkoutSession) -> String {
        if let cardioType: CardioType = session.cardioType {
            return "CARDIO // \(cardioType.title)"
        }
        return "\(session.setsCompleted.count) SERIES"
    }

    private func sessionMetricText(_ session: WorkoutSession) -> String {
        if session.isCardioSession {
            return sessionDurationText(session)
        }
        return "\(Int(session.totalVolumeKg)) KG"
    }

    private func sessionMetricTint(_ session: WorkoutSession) -> Color {
        return session.isCardioSession ? EndfieldPalette.accentCyan : EndfieldPalette.accentYellow
    }

    private func sessionDurationText(_ session: WorkoutSession) -> String {
        let endDate: Date = session.endDate ?? Date()
        let duration: TimeInterval = max(0, endDate.timeIntervalSince(session.startDate))
        return WorkoutMetricsCalculator.formatDuration(duration).uppercased()
    }

    // MARK: - Selección de día y review histórico

    /// Filtra las sesiones iniciadas en el día pulsado y abre el selector.
    /// Si no hay entrenamientos ese día no se presenta nada.
    private func selectDay(_ date: Date) {
        let calendar: Calendar = Calendar.current
        let daySessions: [WorkoutSession] = sessions
            .filter { (session: WorkoutSession) -> Bool in
                return session.endDate != nil && calendar.isDate(session.startDate, inSameDayAs: date)
            }
            .sorted { (lhs: WorkoutSession, rhs: WorkoutSession) -> Bool in
                return lhs.startDate < rhs.startDate
            }

        guard !daySessions.isEmpty else { return }

        selectedDayDate = date
        selectedDaySessions = daySessions
        showingDaySessions = true
    }

    /// Se ejecuta al cerrarse el sheet del día. Solo abre el review cuando el
    /// cierre se ha producido por seleccionar una rutina concreta.
    private func openPendingReviewSession() {
        guard let session: WorkoutSession = sessionToReviewAfterSheet else { return }
        sessionToReviewAfterSheet = nil
        reviewSession = session
    }

    // MARK: - Eliminación de sesiones

    /// Elimina la sesión seleccionada y sus series asociadas. Al borrar de
    /// SwiftData, los `@Query` de sesiones, series y ejercicios invalidan la
    /// vista y recalculan calendario, volumen semanal y récords personales.
    private func deletePendingSession() {
        guard let session: WorkoutSession = sessionPendingDeletion else { return }
        sessionPendingDeletion = nil

        if reviewSession?.id == session.id {
            reviewSession = nil
        }
        if sessionToReviewAfterSheet?.id == session.id {
            sessionToReviewAfterSheet = nil
        }

        let sessionLogs: [WorkoutSetLog] = session.setsCompleted
        for log in sessionLogs {
            modelContext.delete(log)
        }
        modelContext.delete(session)
        try? modelContext.save()
        // La sesión borrada deja de contar para la racha semanal.
        WidgetStreakStore.refresh(modelContext: modelContext)
    }
}

// MARK: - Selector de entrenamientos de un día

struct DaySessionsSheet: View {
    let date: Date
    let sessions: [WorkoutSession]
    let onSelect: (WorkoutSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            HazardStripeBar(height: 6.0)

            VStack(alignment: .leading, spacing: 4.0) {
                Text("OP.LOG // \(dateText.uppercased())")
                    .font(EndfieldFont.label(9.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summaryText.uppercased())
                    .font(EndfieldFont.mono(10.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }
            .padding(.top, 2.0)

            ScrollView {
                VStack(spacing: 8.0) {
                    ForEach(sessions) { session in
                        Button {
                            onSelect(session)
                        } label: {
                            DaySessionRowView(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8.0)
            }
        }
        .padding(.horizontal, 16.0)
        .padding(.top, 8.0)
        .padding(.bottom, 16.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EndfieldPalette.bgPrimary)
        .preferredColorScheme(.dark)
    }

    private var dateText: String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var summaryText: String {
        sessions.count == 1 ? "1 entrenamiento" : "\(sessions.count) entrenamientos"
    }
}

// MARK: - Fila de sesión dentro del selector de día

struct DaySessionRowView: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 8.0) {
            VStack(alignment: .leading, spacing: 4.0) {
                Text(routineName.uppercased())
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 8.0) {
                    Text(startTimeText)
                    Text("//")
                        .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.5))
                    Text(durationText)
                }
                .font(EndfieldFont.label(8.0))
                .tracking(0.6)
                .foregroundStyle(EndfieldPalette.textSecondary)
            }

            Spacer(minLength: 6.0)

            if let cardioType: CardioType = session.cardioType {
                HStack(spacing: 4.0) {
                    Image(systemName: cardioType.symbolName)
                        .font(.system(size: 10.0, weight: .semibold))

                    Text(cardioType.title)
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(EndfieldPalette.accentCyan)
            } else {
                Text(volumeText)
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Image(systemName: "chevron.right")
                .font(EndfieldFont.mono(9.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textSecondary)
        }
        .padding(10.0)
        .background(EndfieldPalette.bgElevated)
        .clipShape(ChamferedRectangle(cut: 6.0))
        .overlay {
            ChamferedRectangle(cut: 6.0)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
        .contentShape(Rectangle())
    }

    private var routineName: String {
        let trimmed: String = session.routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Entrenamiento" : trimmed
    }

    private var startTimeText: String {
        session.startDate.formatted(date: .omitted, time: .shortened)
    }

    private var durationText: String {
        let endDate: Date = session.endDate ?? Date()
        let duration: TimeInterval = max(0, endDate.timeIntervalSince(session.startDate))
        return WorkoutMetricsCalculator.formatDuration(duration)
    }

    private var volumeText: String {
        return String(format: "%.0f KG", resolvedVolume())
    }

    private func resolvedVolume() -> Double {
        if session.totalVolumeKg > 0 {
            return session.totalVolumeKg
        }

        let completedLogs: [WorkoutSetLog] = session.setsCompleted.filter { (log: WorkoutSetLog) -> Bool in
            return log.isCompleted
        }
        return completedLogs.reduce(0.0) { (total: Double, log: WorkoutSetLog) -> Double in
            return total + log.weight * Double(log.reps)
        }
    }
}
