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
    @State private var saveErrorMessage: String?

    /// Única fuente de presentación del calendario. La hoja muestra la lista de
    /// sesiones del día o, si solo hay una, sus estadísticas directamente.
    @State private var daySelection: WorkoutDaySelection?

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
                "No se pudo guardar",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented { saveErrorMessage = nil }
                    }
                )
            ) {
                Button("Entendido", role: .cancel) {
                    saveErrorMessage = nil
                }
            } message: {
                Text(saveErrorMessage ?? "")
            }
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
            // Una sola presentación: la lista del día y las estadísticas viven
            // en la misma hoja, así que no hay un segundo modal encadenado al
            // cierre del primero.
            .sheet(item: $daySelection) { (selection: WorkoutDaySelection) in
                ProgressDaySheet(selection: selection)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(EndfieldPalette.bgPrimary)
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

    /// Abre las sesiones del día pulsado con el criterio compartido del
    /// calendario (`WorkoutDayCatalog`). Un día sin sesiones finalizadas no
    /// abre nada y tampoco lleva marcador, así que no queda una acción
    /// incoherente. La selección se reemplaza siempre: nunca sobreviven las
    /// sesiones del día anterior.
    private func selectDay(_ date: Date) {
        daySelection = WorkoutDayCatalog.selection(on: date, from: sessions)
    }

    // MARK: - Eliminación de sesiones

    /// Elimina la sesión seleccionada y sus series asociadas. Al borrar de
    /// SwiftData, los `@Query` de sesiones, series y ejercicios invalidan la
    /// vista y recalculan calendario, volumen semanal y récords personales.
    private func deletePendingSession() {
        guard let session: WorkoutSession = sessionPendingDeletion else { return }
        sessionPendingDeletion = nil

        let sessionLogs: [WorkoutSetLog] = session.setsCompleted
        for log in sessionLogs {
            modelContext.delete(log)
        }
        modelContext.delete(session)

        guard PersistenceService.saveOrRollback(modelContext, operation: "eliminar la sesión") else {
            saveErrorMessage = "No se ha podido eliminar la sesión. Vuelve a intentarlo."
            return
        }

        // La sesión borrada deja de contar para la racha semanal.
        WidgetStreakStore.refresh(modelContext: modelContext)
    }
}

// MARK: - Contenedor único de la selección de un día

/// Único propietario de la presentación del calendario.
///
/// Evita encadenar una hoja y un `fullScreenCover`: la lista del día y las
/// estadísticas comparten jerarquía, así que elegir una sesión es un cambio de
/// estado dentro de la hoja ya presentada y cerrar el informe vuelve directo al
/// calendario. No se duplica ni se recrea ninguna `WorkoutSession`.
private struct ProgressDaySheet: View {
    let selection: WorkoutDaySelection

    /// Sesión elegida dentro de la hoja. `nil` mientras se muestra la lista.
    /// Con una sola sesión no se usa: se abre directamente su informe.
    @State private var reviewedSession: WorkoutSession?

    var body: some View {
        Group {
            if let session: WorkoutSession = reviewedSession ?? selection.singleSession {
                WorkoutReviewView(session: session, isPostWorkout: false)
            } else {
                DaySessionsSheet(
                    date: selection.day,
                    sessions: selection.sessions,
                    onSelect: { (session: WorkoutSession) in
                        reviewedSession = session
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
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
