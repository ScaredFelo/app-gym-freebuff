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
        let lowered: String = text.lowercased()
        return lowered.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
    }
}

// MARK: - Popup detallado

/// Hoja informativa que se abre al tocar un ejercicio: frecuencia de uso,
/// mapa muscular y análisis biomecánico.
struct ExerciseDetailSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.startDate, order: .reverse) private var sessions: [WorkoutSession]
    @State private var cachedStats: ExerciseUsageStats? = nil

    let exercise: Exercise

    init(exercise: Exercise) {
        self.exercise = exercise
    }

    private var primaryAccent: Color { MuscleHighlightRole.accent }
    private var cardBackground: Color { Color.white.opacity(0.04) }
    private var cardStroke: Color { Color.white.opacity(0.08) }

    private var info: ResolvedExerciseInfo {
        return ExerciseKnowledgeService.resolvedInfo(for: exercise)
    }

    private var stats: ExerciseUsageStats {
        return cachedStats ?? ExerciseUsageStats.empty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20.0) {
                        headerSection
                        badgesSection
                        frequencySection
                        muscleMapSection
                        notesSection
                        analysisSection
                    }
                    .padding(.horizontal, 20.0)
                    .padding(.top, 10.0)
                    .padding(.bottom, 36.0)
                }
            }
            .navigationTitle("Detalle del ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
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
        VStack(alignment: .leading, spacing: 10.0) {
            Text(exercise.name)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10.0) {
                EquipmentSimplifiedIconView(equipmentType: exercise.equipmentType)

                VStack(alignment: .leading, spacing: 2.0) {
                    Text(exercise.equipmentType.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(exercise.muscleGroup.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0.0)
            }
        }
    }

    // MARK: Badges

    private var badgesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8.0) {
                DetailBadge(text: "REPS: \(info.targetRepsText)", tint: .green)
                DetailBadge(text: info.isCompound ? "COMPLEJO" : "AISLAMIENTO", tint: .orange)
                DetailBadge(
                    text: info.requiresStraps ? "STRAPS: SÍ" : "STRAPS: NO",
                    tint: info.requiresStraps ? Color.yellow : Color.white.opacity(0.7)
                )
            }
        }
    }

    // MARK: Frecuencia

    private var frequencySection: some View {
        HStack(spacing: 12.0) {
            FrequencyCard(
                title: "Último mes",
                times: stats.lastMonthCount,
                icon: "calendar",
                tint: .green
            )

            FrequencyCard(
                title: "Total histórico",
                times: stats.totalCount,
                icon: "chart.bar.fill",
                tint: primaryAccent
            )
        }
    }

    // MARK: Mapa muscular

    private var muscleMapSection: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            DetailSectionTitle(title: "MAPA MUSCULAR")

            AnatomicalMuscleMapView(
                primaryMuscles: info.primaryMuscles,
                secondaryMuscles: info.secondaryMuscles
            )
            .padding(.vertical, 8.0)
        }
        .padding(16.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20.0, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20.0, style: .continuous)
                .stroke(cardStroke, lineWidth: 1.0)
        }
    }

    // MARK: Notas

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            DetailSectionTitle(title: "NOTAS APUNTADAS")

            let trimmedNotes: String = exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedNotes.isEmpty {
                Text("Sin notas apuntadas")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.35))
            } else {
                Text(trimmedNotes)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20.0, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20.0, style: .continuous)
                .stroke(cardStroke, lineWidth: 1.0)
        }
    }

    // MARK: Análisis biomecánico

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            DetailSectionTitle(title: "ANÁLISIS BIOMECÁNICO")

            BiomechanicalInfoCard(
                icon: "checkmark.seal.fill",
                title: "Por qué es un buen ejercicio",
                text: info.whyGoodExercise,
                tint: Color.green
            )

            BiomechanicalInfoCard(
                icon: "exclamationmark.triangle.fill",
                title: "Por qué no es un buen ejercicio",
                text: info.whyBadExercise,
                tint: Color.orange
            )

            BiomechanicalInfoCard(
                icon: "hand.thumbsup.fill",
                title: "Cuándo se recomienda usarlo",
                text: info.whenRecommended,
                tint: Color.green
            )

            BiomechanicalInfoCard(
                icon: "hand.raised.slash.fill",
                title: "Cuándo NO se recomienda",
                text: info.whenNotRecommended,
                tint: Color.red
            )
        }
    }
}

// MARK: - Componentes de la hoja

/// Chip compacto para los datos rápidos del ejercicio.
struct DetailBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.0, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10.0)
            .padding(.vertical, 6.0)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay {
                Capsule().stroke(tint.opacity(0.35), lineWidth: 1.0)
            }
    }
}

/// Tarjeta de frecuencia de uso.
struct FrequencyCard: View {
    let title: String
    let times: Int
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            HStack(spacing: 6.0) {
                Image(systemName: icon)
                    .font(.system(size: 11.0, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text("\(times) veces")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16.0, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16.0, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1.0)
        }
    }
}

/// Título de sección en mayúsculas y espaciado.
struct DetailSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11.0, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Color.white.opacity(0.45))
    }
}

/// Tarjeta de análisis biomecánico con icono semántico.
struct BiomechanicalInfoCard: View {
    let icon: String
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12.0) {
            Image(systemName: icon)
                .font(.system(size: 10.0, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26.0, height: 26.0)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4.0) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0.0)
        }
        .padding(14.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16.0, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16.0, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1.0)
        }
    }
}
