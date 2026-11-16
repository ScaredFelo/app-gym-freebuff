import Foundation
import SwiftUI
import SwiftData

/// Review unificado de una sesión. Se usa a pantalla completa al terminar el
/// entrenamiento y también desde el calendario para revisar sesiones pasadas.
public struct WorkoutReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let session: WorkoutSession
    private let isPostWorkout: Bool
    private let viewModel: ActiveWorkoutViewModel?
    private let onFinish: (() -> Void)?

    @State private var metrics: WorkoutMetrics

    public init(
        session: WorkoutSession,
        isPostWorkout: Bool = false,
        viewModel: ActiveWorkoutViewModel? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        self.session = session
        self.isPostWorkout = isPostWorkout
        self.viewModel = viewModel
        self.onFinish = onFinish
        _metrics = State(initialValue: WorkoutMetricsCalculator.calculate(for: session))
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    WorkoutReviewHeaderView(
                        title: isPostWorkout ? "Entrenamiento completado" : "Review de rutina",
                        routineName: routineName,
                        sessionDate: session.startDate
                    )

                    WorkoutReviewMainMetricsView(metrics: metrics)

                    WorkoutReviewHeartRateSectionView(metrics: metrics)

                    WorkoutReviewQualitySectionView(metrics: metrics)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .interactiveDismissDisabled(isPostWorkout)
        .preferredColorScheme(.dark)
    }

    private var routineName: String {
        let trimmed: String = session.routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Entrenamiento" : trimmed
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            Button {
                finish()
            } label: {
                Text(isPostWorkout ? "Terminar sesión" : "Cerrar")
                    .font(.headline.bold())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func finish() {
        if isPostWorkout {
            if let viewModel: ActiveWorkoutViewModel = viewModel {
                viewModel.confirmWorkoutSummary(modelContext: modelContext)
            }
            onFinish?()
        } else {
            dismiss()
        }
    }
}

// MARK: - Cabecera

struct WorkoutReviewHeaderView: View {
    let title: String
    let routineName: String
    let sessionDate: Date

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(routineName)
                .font(.headline)
                .foregroundStyle(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(sessionDate, format: .dateTime.day().month().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Métricas principales

struct WorkoutReviewMainMetricsView: View {
    let metrics: WorkoutMetrics

    var body: some View {
        VStack(spacing: 0) {
            WorkoutReviewMetricRow(
                icon: "clock.fill",
                title: "Tiempo de sesión",
                value: metrics.durationFormatted
            )

            divider

            WorkoutReviewMetricRow(
                icon: "scalemass.fill",
                title: "Kg levantados",
                value: String(format: "%.0f kg", metrics.totalVolumeKg)
            )

            divider

            WorkoutReviewMetricRow(
                icon: "timeline.selection",
                title: "Media entre series",
                value: metrics.averageTimeBetweenSetsFormatted,
                subtitle: "Tiempo medio entre series"
            )
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var divider: some View {
        Divider()
            .background(Color.white.opacity(0.08))
            .padding(.vertical, 10)
    }
}

struct WorkoutReviewMetricRow: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String?

    init(icon: String, title: String, value: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.value = value
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.green)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let subtitle: String = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

// MARK: - Frecuencia cardíaca

struct WorkoutReviewHeartRateSectionView: View {
    let metrics: WorkoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Frecuencia cardíaca por ejercicio")

            HStack(spacing: 12) {
                WorkoutReviewHeartRateSummaryCard(
                    title: "BPM máximos",
                    icon: "heart.fill",
                    tint: .red,
                    primaryValue: metrics.maxBPMAbsolute > 0 ? "\(metrics.maxBPMAbsolute)" : "—",
                    secondaryValue: metrics.maxBPMAverage > 0
                        ? "Media \(Int(metrics.maxBPMAverage.rounded())) BPM"
                        : "Sin datos"
                )

                WorkoutReviewHeartRateSummaryCard(
                    title: "BPM más bajos",
                    icon: "heart.slash.fill",
                    tint: .orange,
                    primaryValue: metrics.minBPMAbsolute > 0 ? "\(metrics.minBPMAbsolute)" : "—",
                    secondaryValue: metrics.minBPMAverage > 0
                        ? "Media \(Int(metrics.minBPMAverage.rounded())) BPM"
                        : "Sin datos"
                )
            }

            if metrics.exerciseHeartRateRows.isEmpty {
                Text("Sin muestras de pulso suficientes para desglosar por ejercicio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(metrics.exerciseHeartRateRows) { (row: ExerciseHeartRateRow) in
                        WorkoutReviewExerciseHeartRateRowView(row: row)
                    }
                }
            }
        }
    }
}

struct WorkoutReviewHeartRateSummaryCard: View {
    let title: String
    let icon: String
    let tint: Color
    let primaryValue: String
    let secondaryValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(tint)

                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text(primaryValue)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(secondaryValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct WorkoutReviewExerciseHeartRateRowView: View {
    let row: ExerciseHeartRateRow

    var body: some View {
        HStack(spacing: 10) {
            Text(row.exerciseName)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Text(row.peakBPM > 0 ? "Pico \(row.peakBPM)" : "Pico —")
                .font(.caption2.bold())
                .foregroundStyle(.red)

            Text(row.previousLowBPM > 0 ? "Previo \(row.previousLowBPM)" : "Previo —")
                .font(.caption2.bold())
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6).opacity(0.08))
        .cornerRadius(10)
    }
}

// MARK: - Calidad de hipertrofia

struct WorkoutReviewQualitySectionView: View {
    let metrics: WorkoutMetrics

    @State private var isHelpPresented: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            WorkoutReviewQualityCardView(
                icon: "flame.fill",
                title: "Carga de Edwards",
                value: String(format: "%.0f", metrics.edwardsTrainingLoad),
                unit: "u.a.",
                description: "Minutos en cada zona cardíaca ponderados de Z1×1 a Z5×5."
            )

            WorkoutReviewQualityCardView(
                icon: "waveform.path.ecg",
                title: "TRIMP de Banister",
                value: String(format: "%.1f", metrics.trimp),
                unit: "TRIMP",
                description: "Duración × delta de FC × 0,64 × e^(1,92 × delta)."
            )

            WorkoutReviewQualityCardView(
                icon: "arrow.down.heart.fill",
                title: "Eficiencia de recuperación",
                value: String(format: "%.1f", metrics.recoveryRate),
                unit: "BPM/min",
                description: "Descenso medio de pulsaciones por minuto entre series."
            )

            WorkoutReviewQualityCardView(
                icon: "scalemass.fill",
                title: "Densidad cardiovascular",
                value: String(format: "%.1f", metrics.cardiovascularDensity),
                unit: "kg/TRIMP",
                description: "Kg movidos por unidad de impulso cardiovascular."
            )
        }
        .sheet(isPresented: $isHelpPresented) {
            HypertrophyQualityHelpSheet()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("CALIDAD DE HIPERTROFIA")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            Button {
                isHelpPresented = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Explicación de las métricas de calidad de hipertrofia")

            Spacer(minLength: 0)
        }
    }
}

struct WorkoutReviewQualityCardView: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.green)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(14)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Utilidades de sección

@ViewBuilder
func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
}
