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
    @State private var cardioComparison: CardioComparison?
    @State private var didLoadComparison: Bool = false
    @AppStorage(UserSettingsManager.isHeartRateTrackingEnabledKey)
    private var isHeartRateTrackingEnabled: Bool = true

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
            TechnicalGridBackground()

            ScrollView {
                VStack(spacing: 14.0) {
                    HazardStripeBar(height: 7.0)
                        .padding(.horizontal, -16.0)

                    WorkoutReviewHeaderView(
                        title: reviewTitle,
                        routineName: routineName,
                        sessionDate: session.startDate
                    )

                    if session.isCardioSession {
                        // El cardio no tiene series ni kg: reutiliza el mismo
                        // informe que se muestra al terminar la sesión.
                        CardioReportPanel(
                            report: cardioReport,
                            chartSamples: session.bpmSamples,
                            chartStart: session.startDate,
                            chartEnd: session.endDate
                        )

                        // Comparativa con la última sesión de la misma
                        // modalidad, una vez resuelta contra el historial.
                        if didLoadComparison {
                            CardioComparisonView(
                                comparison: cardioComparison,
                                typeTitle: session.cardioType?.title
                            )
                        }
                    } else {
                        WorkoutReviewMainMetricsView(metrics: metrics)

                        if isHeartRateTrackingEnabled {
                            WorkoutReviewHeartRateSectionView(metrics: metrics)
                        }

                        WorkoutReviewQualitySectionView(metrics: metrics)
                    }
                }
                .padding(.horizontal, 16.0)
                .padding(.top, 8.0)
                .padding(.bottom, 24.0)
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .interactiveDismissDisabled(isPostWorkout)
        .preferredColorScheme(.dark)
        .onAppear {
            loadCardioComparisonIfNeeded()
        }
    }

    private var routineName: String {
        let trimmed: String = session.routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Entrenamiento" : trimmed
    }

    private var reviewTitle: String {
        if session.isCardioSession {
            return "INFORME DE CARDIO"
        }
        return isPostWorkout ? "OPERACIÓN COMPLETADA" : "REVIEW DE MISIÓN"
    }

    /// Busca la última sesión de cardio del mismo tipo anterior a la revisada
    /// y compara sus estadísticas con las de esta.
    private func loadCardioComparisonIfNeeded() {
        guard session.isCardioSession, !didLoadComparison else { return }

        let routineName: String = session.routineName
        let startedAt: Date = session.startDate

        var descriptor: FetchDescriptor<WorkoutSession> = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { (candidate: WorkoutSession) -> Bool in
                return candidate.routineName == routineName &&
                    candidate.startDate < startedAt
            },
            sortBy: [SortDescriptor(\WorkoutSession.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        defer { didLoadComparison = true }

        guard let previous: WorkoutSession = try? modelContext.fetch(descriptor).first else {
            cardioComparison = nil
            return
        }

        let previousEnd: Date = previous.endDate ?? previous.startDate
        let previousDuration: TimeInterval = max(0.0, previousEnd.timeIntervalSince(previous.startDate))
        let previousMetrics: CardioMetrics = WorkoutMetricsCalculator.calculateCardio(
            duration: previousDuration,
            samples: previous.bpmSamples
        )

        cardioComparison = WorkoutMetricsCalculator.compareCardio(
            current: cardioReport,
            previous: previousMetrics,
            previousDate: previous.startDate
        )
    }

    /// Métricas calculables de una sesión de cardio guardada: tiempo y
    /// pulsaciones registradas (sin volumen, densidad ni recuperación).
    private var cardioReport: CardioMetrics {
        let endDate: Date = session.endDate ?? Date()
        let duration: TimeInterval = max(0, endDate.timeIntervalSince(session.startDate))
        return WorkoutMetricsCalculator.calculateCardio(
            duration: duration,
            samples: session.bpmSamples
        )
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0.0) {
            Button {
                finish()
            } label: {
                Text(isPostWorkout ? "TERMINAR // CERRAR SESIÓN" : "CERRAR // INFORME")
            }
            .buttonStyle(EndfieldPrimaryButtonStyle())
            .padding(.horizontal, 16.0)
            .padding(.top, 12.0)
            .padding(.bottom, 12.0)
        }
        .background(EndfieldPalette.bgPrimary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EndfieldPalette.borderSubtle)
                .frame(height: 1.0)
        }
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
        VStack(alignment: .leading, spacing: 6.0) {
            Text("INFORME DE MISIÓN // DEBRIEFING")
                .font(EndfieldFont.label(9.0))
                .tracking(1.4)
                .foregroundStyle(EndfieldPalette.accentYellow)

            Text(title.uppercased())
                .font(EndfieldFont.mono(19.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(EndfieldPalette.borderSubtle)
                .frame(height: 1.0)
                .padding(.vertical, 2.0)

            HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                Text(routineName.uppercased())
                    .font(EndfieldFont.mono(12.0, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.accentCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4.0)

                Text(sessionDate.formatted(date: .numeric, time: .shortened))
                    .font(EndfieldFont.label(8.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Métricas principales

struct WorkoutReviewMainMetricsView: View {
    let metrics: WorkoutMetrics

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 8.0),
        GridItem(.flexible(), spacing: 8.0),
        GridItem(.flexible(), spacing: 8.0)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8.0) {
            telemetryBox(
                code: "T+",
                label: "TIEMPO",
                value: metrics.durationFormatted,
                tint: EndfieldPalette.textPrimary
            )

            telemetryBox(
                code: "VOL",
                label: "KG TOTAL",
                value: String(format: "%.0f", metrics.totalVolumeKg),
                tint: EndfieldPalette.accentYellow
            )

            telemetryBox(
                code: "MEDIA",
                label: "ENTRE SERIES",
                value: metrics.averageTimeBetweenSetsFormatted,
                tint: EndfieldPalette.accentCyan
            )
        }
    }

    private func telemetryBox(code: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4.0) {
            Text(code)
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(tint)

            Text(value)
                .font(EndfieldFont.mono(17.0, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(label)
                .font(EndfieldFont.label(7.0))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9.0)
        .background(EndfieldPalette.bgElevated)
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }
}

// MARK: - Frecuencia cardíaca

struct WorkoutReviewHeartRateSectionView: View {
    let metrics: WorkoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            EndfieldSectionHeader(code: "HUD.BPM", title: "Frecuencia cardíaca")

            HStack(spacing: 8.0) {
                WorkoutReviewHeartRateSummaryCard(
                    title: "BPM MÁXIMOS",
                    icon: "heart.fill",
                    tint: EndfieldPalette.accentRed,
                    primaryValue: metrics.maxBPMAbsolute > 0 ? "\(metrics.maxBPMAbsolute)" : "—",
                    secondaryValue: metrics.maxBPMAverage > 0
                        ? "Media \(Int(metrics.maxBPMAverage.rounded())) BPM"
                        : "Sin datos"
                )

                WorkoutReviewHeartRateSummaryCard(
                    title: "BPM MÍNIMOS",
                    icon: "heart",
                    tint: EndfieldPalette.accentCyan,
                    primaryValue: metrics.minBPMAbsolute > 0 ? "\(metrics.minBPMAbsolute)" : "—",
                    secondaryValue: metrics.minBPMAverage > 0
                        ? "Media \(Int(metrics.minBPMAverage.rounded())) BPM"
                        : "Sin datos"
                )
            }

            if metrics.exerciseHeartRateRows.isEmpty {
                Text("SIN MUESTRAS SUFICIENTES PARA DESGLOSAR POR EJERCICIO")
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 5.0) {
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
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(spacing: 5.0) {
                Image(systemName: icon)
                    .font(EndfieldFont.mono(9.0, weight: .bold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Text(primaryValue)
                .font(EndfieldFont.mono(26.0, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(secondaryValue.uppercased())
                .font(EndfieldFont.label(7.0))
                .tracking(0.6)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10.0)
        .background(EndfieldPalette.bgPanel)
        .clipShape(ChamferedRectangle(cut: 8.0))
        .overlay {
            ChamferedRectangle(cut: 8.0)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }
}

struct WorkoutReviewExerciseHeartRateRowView: View {
    let row: ExerciseHeartRateRow

    var body: some View {
        HStack(spacing: 8.0) {
            Text(row.exerciseName.uppercased())
                .font(EndfieldFont.label(8.0))
                .tracking(0.6)
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer(minLength: 6.0)

            Text(row.peakBPM > 0 ? "PICO \(row.peakBPM)" : "PICO —")
                .font(EndfieldFont.mono(9.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.accentRed)

            Text(row.previousLowBPM > 0 ? "PREV \(row.previousLowBPM)" : "PREV —")
                .font(EndfieldFont.mono(9.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.accentCyan)
        }
        .padding(.horizontal, 9.0)
        .padding(.vertical, 7.0)
        .background(EndfieldPalette.bgElevated)
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }
}

// MARK: - Calidad de hipertrofia

struct WorkoutReviewQualitySectionView: View {
    let metrics: WorkoutMetrics

    @State private var isHelpPresented: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            header

            WorkoutReviewQualityCardView(
                code: "HYP.01",
                icon: "flame",
                title: "Carga de Edwards",
                value: String(format: "%.0f", metrics.edwardsTrainingLoad),
                unit: "UA",
                description: "Minutos en cada zona cardíaca ponderados de Z1×1 a Z5×5.",
                level: level(value: metrics.edwardsTrainingLoad, reference: 200.0),
                tint: EndfieldPalette.accentYellow
            )

            WorkoutReviewQualityCardView(
                code: "HYP.02",
                icon: "waveform.path.ecg",
                title: "TRIMP de Banister",
                value: String(format: "%.1f", metrics.trimp),
                unit: "TRIMP",
                description: "Duración × delta de FC × 0,64 × e^(1,92 × delta).",
                level: level(value: metrics.trimp, reference: 150.0),
                tint: EndfieldPalette.accentCyan
            )

            WorkoutReviewQualityCardView(
                code: "HYP.03",
                icon: "arrow.down.heart",
                title: "Eficiencia de recuperación",
                value: String(format: "%.1f", metrics.recoveryRate),
                unit: "BPM/MIN",
                description: "Descenso medio de pulsaciones por minuto entre series.",
                level: level(value: metrics.recoveryRate, reference: 40.0),
                tint: EndfieldPalette.accentYellow
            )

            WorkoutReviewQualityCardView(
                code: "HYP.04",
                icon: "scalemass",
                title: "Densidad cardiovascular",
                value: String(format: "%.1f", metrics.cardiovascularDensity),
                unit: "KG/TRIMP",
                description: "Kg movidos por unidad de impulso cardiovascular.",
                level: level(value: metrics.cardiovascularDensity, reference: 150.0),
                tint: EndfieldPalette.accentRed
            )
        }
        .sheet(isPresented: $isHelpPresented) {
            HypertrophyQualityHelpSheet()
        }
    }

    private var header: some View {
        HStack(spacing: 8.0) {
            EndfieldSectionHeader(code: "HYP", title: "Calidad de hipertrofia")

            Button {
                isHelpPresented = true
            } label: {
                Image(systemName: "questionmark")
                    .font(EndfieldFont.mono(10.0, weight: .bold))
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentYellow, size: 26.0))
            .accessibilityLabel("Explicación de las métricas de calidad de hipertrofia")
        }
    }

    private func level(value: Double, reference: Double) -> Double {
        guard reference > 0.0 else { return 0.0 }
        let ratio: Double = value / reference
        return min(max(ratio, 0.0), 1.0)
    }
}

struct WorkoutReviewQualityCardView: View {
    let code: String
    let icon: String
    let title: String
    let value: String
    let unit: String
    let description: String
    let level: Double
    let tint: Color

    var body: some View {
        TacticalPanel(code: code, title: title, contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 7.0) {
                HStack(alignment: .firstTextBaseline, spacing: 5.0) {
                    Image(systemName: icon)
                        .font(EndfieldFont.mono(10.0, weight: .bold))
                        .foregroundStyle(tint)

                    Text(value)
                        .font(EndfieldFont.mono(20.0, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(unit)
                        .font(EndfieldFont.label(8.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize()

                    Spacer(minLength: 0.0)
                }

                SegmentedProgressBar(
                    progress: level,
                    segments: 16,
                    tint: tint,
                    height: 4.0,
                    spacing: 2.0
                )

                Text(description)
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Comparativa con la última sesión de cardio

/// Panel que enfrenta las estadísticas de la sesión revisada con las de la
/// última sesión de la misma modalidad. Si no hay sesión anterior, lo indica
/// en lugar de mostrar una comparativa vacía.
struct CardioComparisonView: View {
    let comparison: CardioComparison?
    let typeTitle: String?

    private var modalityName: String {
        let trimmed: String = (typeTitle ?? "CARDIO").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "CARDIO" : trimmed
    }

    var body: some View {
        TacticalPanel(code: "CMP.01", title: "VS última sesión", contentPadding: 12.0) {
            if let comparison: CardioComparison = comparison {
                content(comparison)
            } else {
                Text("SIN SESIÓN ANTERIOR DE \(modalityName) PARA COMPARAR.")
                    .font(EndfieldFont.label(7.5, weight: .regular))
                    .tracking(0.5)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func content(_ comparison: CardioComparison) -> some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(spacing: 6.0) {
                Text("\(modalityName) // \(comparison.previousDate.formatted(date: .abbreviated, time: .omitted).uppercased())")
                    .font(EndfieldFont.label(7.5))
                    .tracking(0.9)
                    .foregroundStyle(EndfieldPalette.accentCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Spacer(minLength: 4.0)

                Text("\u{394} ACTUAL VS ANTERIOR")
                    .font(EndfieldFont.label(7.0))
                    .tracking(0.6)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize()
            }

            VStack(spacing: 5.0) {
                ForEach(comparison.rows) { (row: CardioComparisonRow) in
                    CardioComparisonRowView(row: row)
                }
            }
        }
    }
}

struct CardioComparisonRowView: View {
    let row: CardioComparisonRow

    private var deltaTint: Color {
        switch row.direction {
        case 1:
            return EndfieldPalette.accentCyan
        case -1:
            return EndfieldPalette.accentRed
        default:
            return EndfieldPalette.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 8.0) {
            VStack(alignment: .leading, spacing: 3.0) {
                HStack(spacing: 5.0) {
                    Text(row.code)
                        .font(EndfieldFont.label(7.0))
                        .tracking(0.9)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize()

                    Text(row.title)
                        .font(EndfieldFont.mono(10.0, weight: .semibold))
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Text("ANT \(row.previousValue.uppercased())")
                    .font(EndfieldFont.label(7.0))
                    .tracking(0.5)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6.0)

            VStack(alignment: .trailing, spacing: 3.0) {
                Text(row.currentValue.uppercased())
                    .font(EndfieldFont.mono(14.0, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(row.deltaText)
                    .font(EndfieldFont.mono(9.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(deltaTint)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 9.0)
        .padding(.vertical, 6.0)
        .background(EndfieldPalette.bgElevated)
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }
}

