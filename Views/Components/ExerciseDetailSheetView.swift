import SwiftUI
import SwiftData

// MARK: - Estadísticas de uso

/// Frecuencia de uso histórica de un ejercicio.
struct ExerciseUsageStats: Equatable {
    let lastMonthCount: Int
    let totalCount: Int

    static let empty: ExerciseUsageStats = ExerciseUsageStats(lastMonthCount: 0, totalCount: 0)

    static func compute(for exercise: Exercise, sessions: [WorkoutSession]) -> ExerciseUsageStats {
        let calendar: Calendar = Calendar.current
        let now: Date = Date()
        let monthLimit: Date = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let targetName: String = normalize(exercise.name)

        var monthly: Int = 0
        var total: Int = 0

        for session in sessions {
            guard session.endDate != nil else { continue }
            guard wasPerformed(exercise, targetName: targetName, in: session) else { continue }

            total += 1
            if session.startDate >= monthLimit {
                monthly += 1
            }
        }

        return ExerciseUsageStats(lastMonthCount: monthly, totalCount: total)
    }

    private static func wasPerformed(
        _ exercise: Exercise,
        targetName: String,
        in session: WorkoutSession
    ) -> Bool {
        let records: [WorkoutExerciseRecord] = session.exerciseRecords
        for record in records {
            if record.exerciseID == exercise.id {
                return true
            }
            if normalize(record.exerciseName) == targetName {
                return true
            }
        }

        for log in session.setsCompleted where log.isCompleted {
            if log.exercise?.id == exercise.id {
                return true
            }
            if let name: String = log.exercise?.name, normalize(name) == targetName {
                return true
            }
        }

        return false
    }

    private static func normalize(_ text: String) -> String {
        return ExerciseRules.comparisonKey(text)
    }
}

// MARK: - Popup detallado

/// Hoja informativa que se abre al tocar un ejercicio: frecuencia de uso,
/// mapa muscular y análisis biomecánico, presentada como ficha técnica.
struct ExerciseDetailSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @State private var cachedStats: ExerciseUsageStats? = nil

    let exercise: Exercise

    init(exercise: Exercise) {
        self.exercise = exercise
    }

    private var primaryAccent: Color { MuscleHighlightRole.accent }

    private var info: ResolvedExerciseInfo {
        return ExerciseKnowledgeService.resolvedInfo(for: exercise)
    }

    private var stats: ExerciseUsageStats {
        return cachedStats ?? ExerciseUsageStats.empty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TechnicalGridBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14.0) {
                        headerSection
                        badgesSection
                        frequencySection
                        muscleMapSection
                        notesSection
                        analysisSection
                    }
                    .padding(.horizontal, 16.0)
                    .padding(.top, 10.0)
                    .padding(.bottom, 32.0)
                }
            }
            .navigationTitle("FICHA TÉCNICA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.accentYellow)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            guard cachedStats == nil else { return }
            cachedStats = ExerciseUsageStats.compute(for: exercise, sessions: sessions)
        }
    }

    // MARK: Cabecera

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            HStack(spacing: 6.0) {
                Text("EX.DB")
                    .font(EndfieldFont.mono(9.0, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .padding(.horizontal, 5.0)
                    .padding(.vertical, 2.0)
                    .overlay {
                        ChamferedRectangle(cut: 3.0)
                            .stroke(EndfieldPalette.accentYellow.opacity(0.55), lineWidth: 1.0)
                    }

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                Text(exercise.muscleGroup.shortName.uppercased())
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }

            Text(exercise.name.uppercased())
                .font(EndfieldFont.mono(19.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8.0) {
                EquipmentSimplifiedIconView(equipmentType: exercise.equipmentType)
                    .frame(width: 30.0, height: 30.0)
                    .background(EndfieldPalette.bgElevated)
                    .clipShape(ChamferedRectangle(cut: 3.0))
                    .overlay {
                        ChamferedRectangle(cut: 3.0)
                            .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                    }

                VStack(alignment: .leading, spacing: 2.0) {
                    Text(exercise.equipmentType.rawValue.uppercased())
                        .font(EndfieldFont.label(9.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(exercise.muscleGroup.rawValue.uppercased())
                        .font(EndfieldFont.label(8.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0.0)
            }
        }
    }

    // MARK: Badges

    private var badgesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6.0) {
                DetailBadge(text: "\(exercise.targetUnitLabel): \(info.targetRepsText)", tint: EndfieldPalette.accentYellow)
                DetailBadge(
                    text: info.isCompound ? "COMPLEJO" : (exercise.trackingMode == .reps ? "AISLAMIENTO" : "DURACIÓN"),
                    tint: EndfieldPalette.accentCyan
                )
                DetailBadge(
                    text: info.requiresStraps ? "STRAPS: SÍ" : "STRAPS: NO",
                    tint: info.requiresStraps ? EndfieldPalette.accentRed : EndfieldPalette.textSecondary
                )
            }
        }
    }

    // MARK: Frecuencia

    private var frequencySection: some View {
        HStack(spacing: 8.0) {
            FrequencyCard(
                title: "Último mes",
                times: stats.lastMonthCount,
                icon: "calendar",
                tint: EndfieldPalette.accentCyan
            )

            FrequencyCard(
                title: "Total histórico",
                times: stats.totalCount,
                icon: "chart.bar",
                tint: primaryAccent
            )
        }
    }

    // MARK: Mapa muscular

    private var muscleMapSection: some View {
        TacticalPanel(code: "BIO.01", title: "Mapa muscular", contentPadding: 12.0) {
            AnatomicalMuscleMapView(
                primaryMuscles: info.primaryMuscles,
                secondaryMuscles: info.secondaryMuscles
            )
            .padding(.vertical, 2.0)
        }
    }

    // MARK: Notas

    private var notesSection: some View {
        TacticalPanel(code: "OPS.NOTAS", title: "Notas apuntadas", contentPadding: 12.0) {
            let trimmedNotes: String = exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedNotes.isEmpty {
                Text("SIN NOTAS APUNTADAS")
                    .font(EndfieldFont.mono(10.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
            } else {
                Text(trimmedNotes)
                    .font(EndfieldFont.mono(11.0))
                    .foregroundStyle(EndfieldPalette.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Análisis biomecánico

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            EndfieldSectionHeader(code: "BIO.02", title: "Análisis biomecánico")

            BiomechanicalInfoCard(
                icon: "checkmark.seal",
                title: "Por qué es un buen ejercicio",
                text: info.whyGoodExercise,
                tint: EndfieldPalette.accentYellow
            )

            BiomechanicalInfoCard(
                icon: "exclamationmark.triangle",
                title: "Por qué no es un buen ejercicio",
                text: info.whyBadExercise,
                tint: EndfieldPalette.accentRed
            )

            BiomechanicalInfoCard(
                icon: "hand.thumbsup",
                title: "Cuándo se recomienda usarlo",
                text: info.whenRecommended,
                tint: EndfieldPalette.accentCyan
            )

            BiomechanicalInfoCard(
                icon: "hand.raised.slash",
                title: "Cuándo NO se recomienda",
                text: info.whenNotRecommended,
                tint: EndfieldPalette.accentRed
            )
        }
    }
}

// MARK: - Componentes de la hoja

/// Chip compacto angular para los datos rápidos del ejercicio.
struct DetailBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(EndfieldFont.label(8.0))
            .tracking(1.2)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 7.0)
            .padding(.vertical, 4.0)
            .background(tint.opacity(0.10))
            .clipShape(ChamferedRectangle(cut: 4.0))
            .overlay {
                ChamferedRectangle(cut: 4.0)
                    .stroke(tint.opacity(0.45), lineWidth: 1.0)
            }
    }
}

/// Caja de telemetría de frecuencia de uso.
struct FrequencyCard: View {
    let title: String
    let times: Int
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(spacing: 5.0) {
                Image(systemName: icon)
                    .font(EndfieldFont.mono(9.0, weight: .bold))
                    .foregroundStyle(tint)

                Text(title.uppercased())
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4.0) {
                Text("\(times)")
                    .font(EndfieldFont.mono(22.0, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.textPrimary)

                Text("×")
                    .font(EndfieldFont.label(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }
        }
        .padding(10.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EndfieldPalette.bgPanel)
        .clipShape(ChamferedRectangle(cut: 6.0))
        .overlay {
            ChamferedRectangle(cut: 6.0)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }
}

/// Título de sección técnico.
struct DetailSectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(EndfieldFont.label(9.0))
            .tracking(1.2)
            .foregroundStyle(EndfieldPalette.textSecondary)
    }
}

/// Ficha de análisis biomecánico con barra de acento lateral.
struct BiomechanicalInfoCard: View {
    let icon: String
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9.0) {
            Rectangle()
                .fill(tint.opacity(0.75))
                .frame(width: 2.0)

            VStack(alignment: .leading, spacing: 4.0) {
                HStack(spacing: 5.0) {
                    Image(systemName: icon)
                        .font(EndfieldFont.mono(9.0, weight: .bold))
                        .foregroundStyle(tint)

                    Text(title.uppercased())
                        .font(EndfieldFont.label(9.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(text)
                    .font(EndfieldFont.mono(10.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0.0)
        }
        .padding(10.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EndfieldPalette.bgElevated)
        .clipShape(ChamferedRectangle(cut: 2.0))
        .overlay {
            ChamferedRectangle(cut: 2.0)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }
}
