import SwiftUI
import SwiftData
import Charts

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
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Weekly Volume Chart
                        weeklyVolumeChartSection

                        // Monthly Workout Calendar
                        monthlyCalendarSection

                        // Personal Records (PRs) - desplegable
                        DisclosureGroup("Récords Personales (PRs)", isExpanded: $showingPersonalRecords) {
                            personalRecordsSectionContent
                        }

                        // Workout History & Total Volume - desplegable
                        DisclosureGroup("Historial de Sesiones", isExpanded: $showingWorkoutHistory) {
                            workoutHistorySectionContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Estadísticas")
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
                .presentationBackground(Color.black)
            }
            .fullScreenCover(item: $reviewSession) { (session: WorkoutSession) in
                WorkoutReviewView(session: session, isPostWorkout: false)
            }
        }
    }

    // MARK: - Weekly Volume Chart
    private var weeklyVolumeChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volumen de Series (Últimos 7 días)")
                .font(.headline)
                .foregroundStyle(.white)

            let weeklyData = computeWeeklyMuscleVolume()

            if weeklyData.isEmpty {
                Text("No hay suficientes datos esta semana.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Chart(weeklyData) { item in
                    BarMark(
                        x: .value("Grupo", item.muscleGroup),
                        y: .value("Series", item.setsCount)
                    )
                    .foregroundStyle(by: .value("Grupo", item.muscleGroup))
                    .cornerRadius(8)
                }
                .chartXAxis(.hidden)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
                .chartYAxis {
                    AxisMarks(values: .stride(by: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)
            }
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(16)
    }

    struct MuscleVolumeItem: Identifiable {
        let id = UUID()
        let muscleGroup: String
        let setsCount: Int
    }

    private func computeWeeklyMuscleVolume() -> [MuscleVolumeItem] {
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        // La serie computa en la fecha en la que empezó la rutina, no en la
        // fecha/hora exacta en la que se marcó (puede ser pasada la medianoche).
        let recentSets = sets.filter { setLog in
            guard setLog.isCompleted else { return false }
            let logDate = setLog.workoutStartDate ?? setLog.session?.startDate ?? setLog.date
            return logDate >= oneWeekAgo
        }
        var counts: [String: Int] = [:]

        for setLog in recentSets {
            if let muscle = setLog.exercise?.muscleGroup.rawValue {
                counts[muscle, default: 0] += 1
            }
        }

        return counts.map { MuscleVolumeItem(muscleGroup: $0.key, setsCount: $0.value) }
            .sorted { $0.setsCount > $1.setsCount }
    }

    // MARK: - Monthly Workout Calendar

    /// Calendario mensual paginado horizontalmente. Las sesiones se pasan al
    /// componente para resaltar los días con entrenamiento y abrir el popup
    /// diario existente al pulsar cualquier fecha.
    private var monthlyCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendario de Entrenamientos")
                .font(.headline)
                .foregroundStyle(.white)

            MonthlyCalendarPagerView(
                sessions: sessions,
                onSelectDate: { (date: Date) in
                    selectDay(date)
                }
            )
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(16)
    }

    // MARK: - Personal Records (PRs) - contenido (sin título, va dentro del DisclosureGroup)
    private var personalRecordsSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if exercises.isEmpty {
                Text("Sin ejercicios registrados.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(exercises) { exercise in
                        let pr = computePR(for: exercise)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text(exercise.muscleGroup.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(pr != nil ? "\(String(format: "%.1f", pr!.weight)) kg" : "—")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.green)
                                Text(pr != nil ? "\(pr!.reps) reps" : "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(.systemGray6).opacity(0.1))
                        .cornerRadius(12)
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
        VStack(alignment: .leading, spacing: 12) {
            let sortedSessions = sessions.sorted(by: { (lhs: WorkoutSession, rhs: WorkoutSession) -> Bool in
                return lhs.startDate > rhs.startDate
            })

            if sortedSessions.isEmpty {
                Text("No hay sesiones registradas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedSessions) { (session: WorkoutSession) in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.startDate, style: .date)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("\(session.setsCompleted.count) series completadas")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(session.totalVolumeKg)) kg vol.")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)

                            Button(role: .destructive) {
                                sessionPendingDeletion = session
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                                    .foregroundStyle(.red.opacity(0.9))
                                    .frame(width: 32, height: 32)
                                    .background(Color.red.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Eliminar entrenamiento")
                        }
                        .padding(12)
                        .background(Color(.systemGray6).opacity(0.1))
                        .cornerRadius(12)
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
    }
}

// MARK: - Selector de entrenamientos de un día

struct DaySessionsSheet: View {
    let date: Date
    let sessions: [WorkoutSession]
    let onSelect: (WorkoutSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateText)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(sessions) { session in
                        Button {
                            onSelect(session)
                        } label: {
                            DaySessionRowView(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(routineName)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 10) {
                    Label(startTimeText, systemImage: "clock")
                    Label(durationText, systemImage: "timer")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(volumeText)
                .font(.subheadline.bold())
                .foregroundStyle(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.12))
        .cornerRadius(12)
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
        return String(format: "%.0f kg", resolvedVolume())
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

