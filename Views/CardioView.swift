import SwiftUI
import SwiftData
import UIKit
import Charts

/// Pantalla de cardio: primero se elige modalidad y tiempo objetivo y, una vez
/// arranca, la misma pantalla muestra la cuenta atrás con pausa, ajuste de
/// tiempo y finalización. La sesión terminada se guarda en el historial con el
/// nombre "CARDIO · <TIPO>".
public struct CardioView: View {
    @State private var viewModel: CardioViewModel?

    public init() {}

    public var body: some View {
        ZStack {
            TechnicalGridBackground()

            if let viewModel: CardioViewModel = viewModel {
                CardioSessionView(viewModel: viewModel)
            } else {
                CardioSetupView(onStart: startSession)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(viewModel != nil)
        .onAppear {
            restoreSessionIfNeeded()
        }
    }

    private func startSession(type: CardioType, minutes: Int) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let model = CardioViewModel(type: type, targetMinutes: minutes)
        viewModel = model
        model.start()
    }

    /// Recupera la sesión que seguía activa cuando iOS suspendió o cerró la
    /// app, en lugar de volver a la pantalla de selección de tiempo.
    private func restoreSessionIfNeeded() {
        guard viewModel == nil else { return }
        guard let snapshot: CardioSessionSnapshot = CardioSessionStore.load() else { return }
        guard let restored: CardioViewModel = CardioViewModel(snapshot: snapshot) else {
            CardioSessionStore.clear()
            return
        }

        viewModel = restored

        // Si el objetivo se cumplió mientras la app estaba cerrada, la sesión
        // se muestra ya terminada con su informe.
        if restored.phase == .running, restored.remaining(at: Date()) <= 0 {
            restored.finishEarly()
        } else {
            restored.start()
        }
    }
}

// MARK: - Configuración previa

private struct CardioSetupView: View {
    @Environment(\.dismiss) private var dismiss

    let onStart: (CardioType, Int) -> Void

    @State private var selectedType: CardioType = .treadmill
    @State private var targetMinutes: Int = 20

    private let minutePresets: [Int] = [10, 15, 20, 30, 45, 60]
    private let minuteStep: Int = 5
    private let minimumMinutes: Int = 5
    private let maximumMinutes: Int = 180

    private let typeColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 8.0),
        GridItem(.flexible(), spacing: 8.0)
    ]
    private let presetColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 8.0),
        GridItem(.flexible(), spacing: 8.0),
        GridItem(.flexible(), spacing: 8.0)
    ]

    var body: some View {
        VStack(spacing: 10.0) {
            header

            ScrollView {
                VStack(spacing: 14.0) {
                    HazardStripeBar(height: 7.0)

                    TacticalPanel(code: "MOD.01", title: "Tipo de cardio", contentPadding: 12.0) {
                        LazyVGrid(columns: typeColumns, spacing: 8.0) {
                            ForEach(CardioType.allCases) { type in
                                cardioTypeTile(type)
                            }
                        }
                    }

                    TacticalPanel(code: "TMR.02", title: "Tiempo objetivo", contentPadding: 12.0) {
                        VStack(spacing: 12.0) {
                            durationValue
                            durationPresets
                            durationFineAdjust
                        }
                    }

                    Button {
                        onStart(selectedType, targetMinutes)
                    } label: {
                        HStack(spacing: 8.0) {
                            Image(systemName: "play.fill")

                            Text("INICIAR // SESIÓN DE CARDIO")
                        }
                    }
                    .buttonStyle(EndfieldPrimaryButtonStyle())
                }
                .padding(.horizontal, 16.0)
                .padding(.bottom, 28.0)
            }
        }
        .padding(.top, 8.0)
    }

    private var header: some View {
        HStack(spacing: 10.0) {
            VStack(alignment: .leading, spacing: 3.0) {
                Text("MOD // CARDIO")
                    .font(EndfieldFont.label(9.0))
                    .tracking(1.3)
                    .foregroundStyle(EndfieldPalette.accentYellow)

                Text("SELECCIÓN DE PROTOCOLO")
                    .font(EndfieldFont.mono(16.0, weight: .heavy))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6.0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.textSecondary, size: 30.0))
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 16.0)
    }

    private func cardioTypeTile(_ type: CardioType) -> some View {
        let isSelected: Bool = selectedType == type

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedType = type
        } label: {
            VStack(alignment: .leading, spacing: 8.0) {
                HStack(spacing: 6.0) {
                    Image(systemName: type.symbolName)
                        .font(.system(size: 17.0, weight: .semibold))
                        .frame(height: 20.0)

                    Spacer(minLength: 0.0)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(EndfieldFont.mono(9.0, weight: .bold))
                    }
                }

                VStack(alignment: .leading, spacing: 2.0) {
                    Text(type.title)
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(type.subtitle.uppercased())
                        .font(EndfieldFont.label(7.0, weight: .regular))
                        .tracking(0.4)
                        .foregroundStyle(isSelected ? EndfieldPalette.accentYellow.opacity(0.75) : EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.textPrimary)
            .padding(10.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ChamferedRectangle(cut: 4.0)
                    .fill(isSelected ? EndfieldPalette.accentYellow.opacity(0.10) : EndfieldPalette.bgElevated)
            )
            .overlay(
                ChamferedRectangle(cut: 4.0)
                    .stroke(isSelected ? EndfieldPalette.accentYellow.opacity(0.7) : EndfieldPalette.borderSubtle, lineWidth: 1.0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.title), \(type.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var durationValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6.0) {
            Text("\(targetMinutes)")
                .font(EndfieldFont.mono(38.0, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.accentYellow)
                .contentTransition(.numericText())

            Text("MIN")
                .font(EndfieldFont.label(10.0))
                .tracking(1.2)
                .foregroundStyle(EndfieldPalette.textSecondary)

            Spacer(minLength: 4.0)

            Text(clockString(TimeInterval(targetMinutes) * 60.0))
                .font(EndfieldFont.mono(12.0, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.textSecondary)
        }
    }

    private var durationPresets: some View {
        LazyVGrid(columns: presetColumns, spacing: 8.0) {
            ForEach(minutePresets, id: \.self) { minutes in
                presetButton(minutes)
            }
        }
    }

    private func presetButton(_ minutes: Int) -> some View {
        let isSelected: Bool = targetMinutes == minutes

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            targetMinutes = minutes
        } label: {
            Text("\(minutes)")
                .font(EndfieldFont.mono(12.0, weight: .bold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9.0)
                .foregroundStyle(isSelected ? EndfieldPalette.bgPrimary : EndfieldPalette.textPrimary)
                .background(
                    ChamferedRectangle(cut: 4.0)
                        .fill(isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.bgElevated)
                )
                .overlay(
                    ChamferedRectangle(cut: 4.0)
                        .stroke(isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.borderSubtle, lineWidth: 1.0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(minutes) minutos")
    }

    private var durationFineAdjust: some View {
        HStack(spacing: 8.0) {
            adjustButton(symbol: "minus", enabled: targetMinutes > minimumMinutes) {
                targetMinutes = max(minimumMinutes, targetMinutes - minuteStep)
            }

            Text("AJUSTE \(minuteStep) MIN")
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .frame(maxWidth: .infinity)

            adjustButton(symbol: "plus", enabled: targetMinutes < maximumMinutes) {
                targetMinutes = min(maximumMinutes, targetMinutes + minuteStep)
            }
        }
    }

    private func adjustButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: symbol)
                .font(EndfieldFont.mono(11.0, weight: .bold))
        }
        .buttonStyle(
            EndfieldSquareButtonStyle(
                tint: enabled ? EndfieldPalette.accentCyan : EndfieldPalette.textSecondary.opacity(0.4),
                size: 32.0
            )
        )
        .disabled(!enabled)
    }

    private func clockString(_ seconds: TimeInterval) -> String {
        let total: Int = max(0, Int(seconds))
        let minutes: Int = total / 60
        let secs: Int = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Sesión en curso

private struct CardioSessionView: View {
    @ObservedObject var viewModel: CardioViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UserSettingsManager.isHeartRateTrackingEnabledKey)
    private var isHeartRateTrackingEnabled: Bool = true

    @State private var showingAbortConfirmation = false
    @State private var didPersistSession = false

    private let minuteStep: Int = 5

    var body: some View {
        VStack(spacing: 10.0) {
            header

            ScrollView {
                VStack(spacing: 14.0) {
                    HazardStripeBar(height: 7.0)
                    sessionPanel

                    if viewModel.phase == .finished {
                        cardioReport
                        finishedActions
                    } else {
                        if isHeartRateTrackingEnabled {
                            bpmChartPanel
                        }
                        runningActions
                    }
                }
                .padding(.horizontal, 16.0)
                .padding(.bottom, 28.0)
            }
        }
        .padding(.top, 8.0)
        .onChange(of: viewModel.phase) { _, newPhase in
            guard newPhase == .finished else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            persistSession()
        }
        .onAppear {
            // Sesión restaurada que ya había cumplido su objetivo.
            if viewModel.phase == .finished {
                persistSession()
            }
        }
        .alert("¿Abortar sesión de cardio?", isPresented: $showingAbortConfirmation) {
            Button("Descartar", role: .destructive) {
                didPersistSession = true
                viewModel.cancelSession()
                dismiss()
            }
            Button("Continuar", role: .cancel) {}
        } message: {
            Text("Se descartará el tiempo realizado sin guardarlo en el historial.")
        }
    }

    private var header: some View {
        HStack(spacing: 10.0) {
            VStack(alignment: .leading, spacing: 3.0) {
                Text("MOD // CARDIO")
                    .font(EndfieldFont.label(9.0))
                    .tracking(1.3)
                    .foregroundStyle(EndfieldPalette.accentYellow)

                Text(viewModel.phase == .finished ? "SESIÓN COMPLETADA" : viewModel.type.title)
                    .font(EndfieldFont.mono(16.0, weight: .heavy))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6.0)

            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.textSecondary, size: 30.0))
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 16.0)
    }

    private func close() {
        if viewModel.phase == .finished {
            dismiss()
        } else {
            showingAbortConfirmation = true
        }
    }

    private var sessionPanel: some View {
        TacticalPanel(code: "OP.LIVE", title: viewModel.type.title, accentBorder: true, contentPadding: 16.0) {
            VStack(spacing: 14.0) {
                HStack(spacing: 6.0) {
                    EndfieldLiveDot(size: 6.0)

                    Text(statusText)
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.1)
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4.0)

                    Text("OBJ // \(clockString(viewModel.targetDuration))")
                        .font(EndfieldFont.label(8.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize()
                }

                TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                    timerBlock(at: timeline.date)
                }
            }
        }
    }

    private func timerBlock(at date: Date) -> some View {
        let isFinished: Bool = viewModel.phase == .finished
        let progress: Double = isFinished ? 1.0 : viewModel.progress(at: date)

        return VStack(spacing: 12.0) {
            Text(clockString(isFinished ? viewModel.elapsed(at: date) : viewModel.remaining(at: date)))
                .font(EndfieldFont.mono(52.0, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(isFinished ? EndfieldPalette.accentCyan : EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .contentTransition(.numericText())

            Text(isFinished ? "TIEMPO TOTAL" : "TIEMPO RESTANTE")
                .font(EndfieldFont.label(8.0))
                .tracking(1.4)
                .foregroundStyle(EndfieldPalette.textSecondary)

            SegmentedProgressBar(
                progress: progress,
                segments: 26,
                tint: viewModel.phase == .paused ? EndfieldPalette.accentRed : EndfieldPalette.accentYellow,
                height: 6.0,
                spacing: 2.0
            )

            HStack(spacing: 8.0) {
                Text("T+ \(clockString(viewModel.elapsed(at: date)))")

                Spacer(minLength: 4.0)

                Text("\(Int(progress * 100.0))%")
            }
            .font(EndfieldFont.label(8.0))
            .tracking(0.8)
            .foregroundStyle(EndfieldPalette.textSecondary)
        }
    }

    private var statusText: String {
        switch viewModel.phase {
        case .running:
            return "EN CURSO // TIEMPO REAL"
        case .paused:
            return "PAUSADO"
        case .finished:
            return viewModel.reachedTarget ? "OBJETIVO COMPLETADO" : "SESIÓN FINALIZADA"
        }
    }

    private var statusTint: Color {
        switch viewModel.phase {
        case .running, .finished:
            return EndfieldPalette.accentCyan
        case .paused:
            return EndfieldPalette.accentRed
        }
    }

    private var runningActions: some View {
        VStack(spacing: 10.0) {
            HStack(spacing: 8.0) {
                Button {
                    togglePause()
                } label: {
                    HStack(spacing: 6.0) {
                        Image(systemName: viewModel.phase == .paused ? "play.fill" : "pause.fill")

                        Text(viewModel.phase == .paused ? "REANUDAR" : "PAUSAR")
                    }
                }
                .buttonStyle(
                    EndfieldSecondaryButtonStyle(
                        tint: viewModel.phase == .paused ? EndfieldPalette.accentYellow : EndfieldPalette.accentCyan
                    )
                )

                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    viewModel.adjustTarget(byMinutes: minuteStep)
                } label: {
                    Text("+\(minuteStep) MIN")
                }
                .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentYellow))
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.finishEarly()
            } label: {
                Text("FINALIZAR // GUARDAR SESIÓN")
            }
            .buttonStyle(EndfieldPrimaryButtonStyle())

            Text("EL TIEMPO SE CALCULA CON EL RELOJ: PUEDES BLOQUEAR EL MÓVIL O CAMBIAR DE APP.")
                .font(EndfieldFont.label(7.5, weight: .regular))
                .tracking(0.5)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4.0)
        }
    }

    private var finishedActions: some View {
        VStack(spacing: 10.0) {
            HStack(spacing: 7.0) {
                Image(systemName: "checkmark.seal.fill")
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.accentCyan)

                Text("SESIÓN GUARDADA EN EL HISTORIAL")
                    .font(EndfieldFont.label(8.5))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.accentCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0.0)
            }
            .padding(.horizontal, 4.0)

            Button {
                persistSession()
                dismiss()
            } label: {
                Text("CERRAR // VOLVER A RUTINAS")
            }
            .buttonStyle(EndfieldPrimaryButtonStyle())
        }
    }

    // MARK: - Gráfica de pulsaciones (últimos 3 minutos)

    private var bpmChartPanel: some View {
        TacticalPanel(code: "HUD.BPM", title: "Últimos 3 min", contentPadding: 12.0) {
            TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                chartContent(at: timeline.date)
            }
        }
    }

    @ViewBuilder
    private func chartContent(at date: Date) -> some View {
        let samples: [BPMSample] = viewModel.bpmPoints(within: 180.0, relativeTo: date)

        if samples.isEmpty {
            Text("ESPERANDO TELEMETRÍA CARDÍACA...")
                .font(EndfieldFont.mono(10.0))
                .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.7))
                .frame(height: 100.0)
                .frame(maxWidth: .infinity)
        } else {
            CardioBPMChart(
                samples: samples,
                xDomain: date.addingTimeInterval(-180.0)...date
            )
        }
    }

    // MARK: - Informe de sesión

    private var cardioReport: some View {
        CardioReportPanel(report: viewModel.report())
    }

    private func togglePause() {
        if viewModel.phase == .paused {
            viewModel.resume()
        } else {
            viewModel.pause()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func persistSession() {
        guard !didPersistSession else { return }
        didPersistSession = true

        // Se registra el tiempo efectivo del cronómetro (sin las pausas ni los
        // huecos en los que la app quedó suspendida), no la hora del reloj.
        let duration: TimeInterval = viewModel.elapsed(at: viewModel.finishedAt ?? Date())

        let session = WorkoutSession(
            startDate: viewModel.startedAt,
            endDate: viewModel.startedAt.addingTimeInterval(max(1.0, duration)),
            totalVolumeKg: 0.0,
            routineName: viewModel.type.sessionName
        )
        // La telemetría de la sesión queda guardada con ella para que el
        // historial pueda analizarla igual que las sesiones de fuerza.
        session.bpmSamples = viewModel.bpmHistory

        modelContext.insert(session)
        try? modelContext.save()
        WidgetStreakStore.refresh(modelContext: modelContext)
    }

    private func clockString(_ seconds: TimeInterval) -> String {
        let total: Int = max(0, Int(seconds))
        let hours: Int = total / 3600
        let minutes: Int = (total % 3600) / 60
        let secs: Int = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Gráfica de BPM (reutilizable)

/// Gráfica de línea de BPM con el estilo de la telemetría en vivo. Se usa con
/// la ventana de 3 minutos durante la sesión y con la sesión completa en el
/// informe guardado.
struct CardioBPMChart: View {
    let samples: [BPMSample]
    let xDomain: ClosedRange<Date>

    /// El informe guardado dibuja referencias temporales en el eje X. La
    /// telemetría en vivo las mantiene ocultas porque su ventana es fija de
    /// 3 minutos y el cronómetro ya marca el tiempo.
    var showsTimeAxis: Bool = false

    var body: some View {
        if showsTimeAxis {
            chart
                .chartXAxis {
                    AxisMarks(values: timeTicks()) { (value: AxisValue) in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2.0, 2.0]))
                            .foregroundStyle(Color.white.opacity(0.08))

                        AxisTick(length: 3.0)
                            .foregroundStyle(EndfieldPalette.textSecondary)

                        AxisValueLabel {
                            if let date: Date = value.as(Date.self) {
                                Text(elapsedLabel(for: date))
                                    .font(EndfieldFont.label(7.5))
                                    .tracking(0.6)
                                    .foregroundStyle(EndfieldPalette.textSecondary)
                            }
                        }
                    }
                }
        } else {
            chart
                .chartXAxis(.hidden)
        }
    }

    private var chart: some View {
        Chart(samples) { (sample: BPMSample) in
            LineMark(
                x: .value("Tiempo", sample.timestamp),
                y: .value("BPM", sample.bpm)
            )
            .foregroundStyle(EndfieldPalette.accentRed)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Tiempo", sample.timestamp),
                y: .value("BPM", sample.bpm)
            )
            .foregroundStyle(EndfieldPalette.accentRed)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 40...200)
        .chartYAxis {
            AxisMarks(values: .stride(by: 40.0)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2.0, 2.0]))
                    .foregroundStyle(Color.white.opacity(0.10))
                AxisValueLabel()
                    .font(EndfieldFont.label(8.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }
        }
        .frame(height: 100.0)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Referencias de tiempo

    /// Marcas de inicio, fin e intervalos regulares de 5, 10 o 15 minutos
    /// según la duración de la sesión.
    private func timeTicks() -> [Date] {
        let start: Date = xDomain.lowerBound
        let total: TimeInterval = max(0.0, xDomain.upperBound.timeIntervalSince(start))
        guard total > 0 else { return [start] }

        let minimumStep: TimeInterval = 300.0
        let rawStep: TimeInterval = total / 5.0
        let step: TimeInterval = max(minimumStep, (rawStep / minimumStep).rounded(.up) * minimumStep)

        var ticks: [Date] = [start]
        var offset: TimeInterval = step
        while offset < total - 1.0 {
            ticks.append(start.addingTimeInterval(offset))
            offset += step
        }
        ticks.append(xDomain.upperBound)
        return ticks
    }

    /// Tiempo transcurrido desde el inicio de la sesión en formato `mm:ss`.
    private func elapsedLabel(for date: Date) -> String {
        let elapsed: TimeInterval = max(0.0, date.timeIntervalSince(xDomain.lowerBound))
        let totalSeconds: Int = Int(elapsed.rounded())
        let minutes: Int = totalSeconds / 60
        let seconds: Int = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Informe de sesión de cardio (reutilizable)

/// Panel del informe de una sesión de cardio. Se usa al terminar la sesión y
/// al abrir una sesión de cardio desde el calendario o el historial.
struct CardioReportPanel: View {
    let report: CardioMetrics

    /// Muestras de toda la sesión para la gráfica del informe guardado. `nil`
    /// en el informe en vivo, que ya muestra la telemetría de los 3 últimos
    /// minutos encima del cronómetro.
    var chartSamples: [BPMSample]? = nil

    /// Inicio y fin reales de la sesión para que el eje temporal cubra toda la
    /// duración del informe aunque el sensor conectara tarde o perdiera
    /// lecturas.
    var chartStart: Date? = nil
    var chartEnd: Date? = nil

    var body: some View {
        TacticalPanel(
            code: "RPT.01",
            title: "Informe de sesión",
            accentBorder: true,
            contentPadding: 12.0
        ) {
            VStack(alignment: .leading, spacing: 8.0) {
                HStack(spacing: 8.0) {
                    reportBox(
                        code: "T+",
                        label: "TIEMPO",
                        value: report.durationFormatted,
                        tint: EndfieldPalette.textPrimary
                    )

                    if report.hasHeartRateData {
                        reportBox(
                            code: "MEDIA",
                            label: "BPM",
                            value: "\(Int(report.averageBPM.rounded()))",
                            tint: EndfieldPalette.accentRed
                        )

                        reportBox(
                            code: "PICO",
                            label: "BPM MÁX",
                            value: "\(report.maxBPM)",
                            tint: EndfieldPalette.accentRed
                        )
                    }
                }

                if let chartSamples: [BPMSample] = chartSamples,
                   !chartSamples.isEmpty,
                   let domain: ClosedRange<Date> = sessionChartDomain(for: chartSamples) {
                    VStack(alignment: .leading, spacing: 4.0) {
                        Text("BPM // SESIÓN COMPLETA")
                            .font(EndfieldFont.label(8.0))
                            .tracking(1.0)
                            .foregroundStyle(EndfieldPalette.textSecondary)

                        CardioBPMChart(
                            samples: chartSamples,
                            xDomain: domain,
                            showsTimeAxis: true
                        )
                    }
                    .padding(.top, 2.0)
                }

                if report.hasHeartRateData {
                    reportRow(
                        code: "MIN",
                        title: "BPM mínimos",
                        value: "\(report.minBPM)",
                        unit: "BPM",
                        tint: EndfieldPalette.accentCyan
                    )

                    reportRow(
                        code: "EDW",
                        title: "Carga de Edwards",
                        value: String(format: "%.0f", report.edwardsTrainingLoad),
                        unit: "UA",
                        tint: EndfieldPalette.accentYellow
                    )

                    reportRow(
                        code: "TRIMP",
                        title: "TRIMP de Banister",
                        value: String(format: "%.1f", report.trimp),
                        unit: "TRIMP",
                        tint: EndfieldPalette.accentCyan
                    )
                } else {
                    Text("SIN TELEMETRÍA CARDÍACA: SOLO SE REGISTRA EL TIEMPO DE LA SESIÓN.")
                        .font(EndfieldFont.label(7.5, weight: .regular))
                        .tracking(0.5)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Dominio temporal de la gráfica del informe: de la primera a la última
    /// muestra guardada, con un mínimo de un minuto si solo hay una lectura.
    private func sessionChartDomain(for samples: [BPMSample]) -> ClosedRange<Date>? {
        let timestamps: [Date] = samples.map { (sample: BPMSample) -> Date in
            return sample.timestamp
        }
        guard let firstSample: Date = timestamps.min(),
              let lastSample: Date = timestamps.max() else { return nil }

        let start: Date = chartStart ?? firstSample
        let end: Date = chartEnd ?? lastSample

        if end <= start {
            return firstSample...(firstSample.addingTimeInterval(60.0))
        }

        // Si alguna muestra cae fuera del rango nominal, se amplía el eje para
        // no recortarla.
        return min(start, firstSample)...max(end, lastSample)
    }

    private func reportBox(code: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4.0) {
            Text(code)
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(tint)

            Text(value)
                .font(EndfieldFont.mono(18.0, weight: .heavy))
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

    private func reportRow(
        code: String,
        title: String,
        value: String,
        unit: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 8.0) {
            Text(code)
                .font(EndfieldFont.label(7.5))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .frame(width: 38.0, alignment: .leading)

            Text(title)
                .font(EndfieldFont.mono(10.0, weight: .semibold))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 6.0)

            Text(value)
                .font(EndfieldFont.mono(15.0, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
                .fixedSize()

            Text(unit)
                .font(EndfieldFont.label(7.5))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize()
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

