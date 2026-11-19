import SwiftUI
import SwiftData
import UIKit
import Charts

/// Pantalla de cardio: primero se elige modalidad y tiempo objetivo y, una vez
/// arranca, la misma pantalla muestra la cuenta atrás con pausa, ajuste de
/// tiempo y finalización. La sesión terminada se guarda en el historial con el
/// nombre "CARDIO · <TIPO>".
public struct CardioView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: CardioViewModel?
    @State private var abandonedSnapshot: CardioSessionSnapshot?

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
        .alert(
            "Sesión de cardio abandonada",
            isPresented: Binding(
                get: { abandonedSnapshot != nil },
                set: { (isPresented: Bool) in
                    if !isPresented {
                        abandonedSnapshot = nil
                    }
                }
            )
        ) {
            Button("Guardar sesión") {
                if let snapshot: CardioSessionSnapshot = abandonedSnapshot {
                    saveAbandonedSession(snapshot)
                }
            }

            Button("Descartar", role: .destructive) {
                CardioSessionStore.clear()
                abandonedSnapshot = nil
            }
        } message: {
            Text("Hay una sesión de cardio sin actividad desde hace más de 6 horas. Puedes guardarla con el tiempo registrado hasta el último dato o descartarla.")
        }
    }

    private func startSession(type: CardioType, minutes: Int, targetZone: Int) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let model = CardioViewModel(
            type: type,
            targetMinutes: minutes,
            targetZone: targetZone > 0 ? targetZone : nil
        )
        viewModel = model
        model.start()
    }

    /// Recupera la sesión que seguía activa cuando iOS suspendió o cerró la
    /// app, en lugar de volver a la pantalla de selección de tiempo.
    private func restoreSessionIfNeeded() {
        guard viewModel == nil else { return }
        guard let snapshot: CardioSessionSnapshot = CardioSessionStore.load() else { return }

        // Una sesión sin actualizaciones durante horas no se reanuda sola: se
        // ofrece guardarla o descartarla.
        let lastUpdate: Date = snapshot.savedAt ?? snapshot.startedAt
        guard Date().timeIntervalSince(lastUpdate) <= CardioSessionSnapshot.abandonmentThreshold else {
            abandonedSnapshot = snapshot
            return
        }

        guard let restored: CardioViewModel = CardioViewModel(snapshot: snapshot) else {
            CardioSessionStore.clear()
            return
        }

        viewModel = restored

        // Si el objetivo se cumplió mientras la app estaba cerrada, la sesión
        // se muestra ya terminada con su informe.
        if restored.phase == .running, restored.remaining(at: Date()) <= 0 {
            restored.finishEarly()
        } else if restored.phase == .paused {
            restored.resumeMonitoring()
        } else {
            restored.start()
        }
    }

    /// Guarda como sesión completada el tiempo que llegó a registrarse antes
    /// de que la app se cerrara.
    private func saveAbandonedSession(_ snapshot: CardioSessionSnapshot) {
        guard let type: CardioType = CardioType(rawValue: snapshot.typeRaw) else {
            CardioSessionStore.clear()
            abandonedSnapshot = nil
            return
        }

        let target: TimeInterval = max(60.0, snapshot.targetDuration)
        let registered: TimeInterval = snapshot.elapsedAtSave ?? Date().timeIntervalSince(snapshot.startedAt)
        let duration: TimeInterval = max(1.0, min(target, registered))

        let session = WorkoutSession(
            startDate: snapshot.startedAt,
            endDate: snapshot.startedAt.addingTimeInterval(duration),
            totalVolumeKg: 0.0,
            routineName: type.sessionName
        )
        session.bpmSamples = snapshot.bpmSamples

        modelContext.insert(session)
        try? modelContext.save()
        WidgetStreakStore.refresh(modelContext: modelContext)

        CardioSessionStore.clear()
        abandonedSnapshot = nil
    }
}

// MARK: - Configuración previa

private struct CardioSetupView: View {
    @Environment(\.dismiss) private var dismiss

    /// Zona de pulso elegida para el aviso opcional de salida (0 = sin aviso).
    @AppStorage(UserSettingsManager.cardioAlertZoneKey) private var alertZone: Int = 0

    let onStart: (CardioType, Int, Int) -> Void

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

                    TacticalPanel(code: "AUD.03", title: "Avisos de pulso", contentPadding: 12.0) {
                        VStack(alignment: .leading, spacing: 8.0) {
                            HStack(spacing: 8.0) {
                                alertZoneOption(title: "OFF", value: 0)
                                alertZoneOption(title: "Z2", value: 2)
                                alertZoneOption(title: "Z3", value: 3)
                                alertZoneOption(title: "Z4", value: 4)
                            }

                            Text("Z2 60–70% · Z3 70–80% · Z4 80–90% FC MÁX. MITAD, ÚLTIMO MINUTO Y OBJETIVO SUENAN SIEMPRE.")
                                .font(EndfieldFont.label(7.0, weight: .regular))
                                .tracking(0.5)
                                .foregroundStyle(EndfieldPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button {
                        onStart(selectedType, targetMinutes, alertZone)
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

    private func alertZoneOption(title: String, value: Int) -> some View {
        let isSelected: Bool = alertZone == value

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            alertZone = value
        } label: {
            Text(title)
                .font(EndfieldFont.mono(11.0, weight: .bold))
                .tracking(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9.0)
                .foregroundStyle(isSelected ? EndfieldPalette.bgPrimary : EndfieldPalette.textPrimary)
                .background(
                    ChamferedRectangle(cut: 4.0)
                        .fill(isSelected ? EndfieldPalette.accentCyan : EndfieldPalette.bgElevated)
                )
                .overlay(
                    ChamferedRectangle(cut: 4.0)
                        .stroke(isSelected ? EndfieldPalette.accentCyan : EndfieldPalette.borderSubtle, lineWidth: 1.0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == 0 ? "Sin aviso de zona" : "Avisar al salir de la zona Z\(value)")
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
                            CardioSensorStatusView()
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

// MARK: - Estado del sensor de pulso

/// Aviso de enlace del pulsómetro durante el cardio. Se mantiene aislado para
/// que las lecturas del sensor no redibujen la pantalla completa.
private struct CardioSensorStatusView: View {
    @ObservedObject private var bpmManager = BPMManager.shared

    /// Solo se avisa en rojo si antes hubo enlace: al empezar la sesión la
    /// banda todavía se está buscando y eso no es un fallo.
    @State private var hasBeenConnected = false
    @State private var didWarnDisconnect = false

    private var isLost: Bool {
        return hasBeenConnected && !bpmManager.isConnected
    }

    private var dotTint: Color {
        if bpmManager.isConnected { return EndfieldPalette.accentCyan }
        return isLost ? EndfieldPalette.accentRed : EndfieldPalette.textSecondary.opacity(0.7)
    }

    private var title: String {
        if bpmManager.isConnected { return "SENSOR DE PULSO ENLAZADO" }
        return isLost ? "SENSOR DE PULSO DESCONECTADO" : "BUSCANDO SENSOR DE PULSO"
    }

    private var titleTint: Color {
        return isLost ? EndfieldPalette.accentRed : EndfieldPalette.textSecondary
    }

    private var searchText: String {
        let raw: String = bpmManager.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "BUSCANDO..." : raw.uppercased()
    }

    var body: some View {
        HStack(spacing: 8.0) {
            Rectangle()
                .fill(dotTint)
                .frame(width: 5.0, height: 5.0)

            Text(title)
                .font(EndfieldFont.label(8.0))
                .tracking(0.9)
                .foregroundStyle(titleTint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer(minLength: 6.0)

            if bpmManager.isConnected {
                Text(bpmManager.currentBPM > 0 ? "\(bpmManager.currentBPM) BPM" : "-- BPM")
                    .font(EndfieldFont.mono(10.0, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.accentRed)
                    .fixedSize()
            } else if isLost {
                Button {
                    bpmManager.reconnect()
                } label: {
                    Text("RECONECTAR")
                        .font(EndfieldFont.mono(9.0, weight: .bold))
                        .tracking(0.6)
                }
                .buttonStyle(
                    EndfieldSecondaryButtonStyle(
                        fullWidth: false,
                        compact: true,
                        tint: EndfieldPalette.accentCyan
                    )
                )
            } else {
                Text(searchText)
                    .font(EndfieldFont.label(7.5))
                    .tracking(0.6)
                    .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .padding(.horizontal, 9.0)
        .padding(.vertical, 6.0)
        .background(EndfieldPalette.bgElevated)
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                .stroke(
                    isLost ? EndfieldPalette.accentRed.opacity(0.55) : EndfieldPalette.borderSubtle,
                    lineWidth: 1.0
                )
        }
        .onAppear {
            if bpmManager.isConnected {
                hasBeenConnected = true
                didWarnDisconnect = false
            }
        }
        .onChange(of: bpmManager.isConnected) { _, isConnected in
            if isConnected {
                hasBeenConnected = true
                didWarnDisconnect = false
                return
            }

            // Un único aviso por caída: las reconexiones no encadenan hápticos.
            guard hasBeenConnected, !didWarnDisconnect else { return }
            didWarnDisconnect = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
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

    /// FC máxima del usuario. El informe guardado la pasa para sombrear las
    /// zonas Z1–Z5 detrás de la curva; la telemetría en vivo no las dibuja.
    var hrMax: Double? = nil

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

    /// Bandas de zona calculadas sobre la FC máxima. Vacías en la telemetría
    /// en vivo, que no dibuja zonas.
    private var zoneBands: [CardioZoneStyle.Band] {
        guard let hrMax: Double = hrMax, hrMax > 0 else { return [] }
        return CardioZoneStyle.bands(hrMax: hrMax)
    }

    private var chart: some View {
        Chart {
            ForEach(zoneBands) { (band: CardioZoneStyle.Band) in
                RectangleMark(
                    xStart: .value("Inicio", xDomain.lowerBound),
                    xEnd: .value("Fin", xDomain.upperBound),
                    yStart: .value("Zona", band.lowerBPM),
                    yEnd: .value("Zona", band.upperBPM)
                )
                .foregroundStyle(CardioZoneStyle.bandTint(for: band.id))
            }

            ForEach(samples) { (sample: BPMSample) in
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

// MARK: - Estilo de zonas de FC

/// Colores y cortes de las zonas de frecuencia cardíaca. Se comparten entre la
/// gráfica (bandas sombreadas) y las filas del informe.
enum CardioZoneStyle {
    struct Band: Identifiable {
        let id: Int
        let lowerBPM: Double
        let upperBPM: Double
    }

    /// Cortes sobre la FC máxima, alineados con los pesos de la carga de
    /// Edwards: 50–60–70–80–90 %.
    static func bands(hrMax: Double) -> [Band] {
        return [
            Band(id: 1, lowerBPM: hrMax * 0.50, upperBPM: hrMax * 0.60),
            Band(id: 2, lowerBPM: hrMax * 0.60, upperBPM: hrMax * 0.70),
            Band(id: 3, lowerBPM: hrMax * 0.70, upperBPM: hrMax * 0.80),
            Band(id: 4, lowerBPM: hrMax * 0.80, upperBPM: hrMax * 0.90),
            Band(id: 5, lowerBPM: hrMax * 0.90, upperBPM: hrMax * 1.10)
        ]
    }

    static func tint(for zone: Int) -> Color {
        switch zone {
        case 1:
            return EndfieldPalette.accentCyan.opacity(0.55)
        case 2:
            return EndfieldPalette.accentCyan
        case 3:
            return EndfieldPalette.accentYellow.opacity(0.7)
        case 4:
            return EndfieldPalette.accentYellow
        case 5:
            return EndfieldPalette.accentRed
        default:
            return EndfieldPalette.textSecondary
        }
    }

    static func bandTint(for zone: Int) -> Color {
        switch zone {
        case 1:
            return EndfieldPalette.accentCyan.opacity(0.05)
        case 2:
            return EndfieldPalette.accentCyan.opacity(0.09)
        case 3:
            return EndfieldPalette.accentYellow.opacity(0.05)
        case 4:
            return EndfieldPalette.accentYellow.opacity(0.09)
        case 5:
            return EndfieldPalette.accentRed.opacity(0.08)
        default:
            return Color.clear
        }
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
                            showsTimeAxis: true,
                            hrMax: report.hrMax
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

                    if hasZoneData {
                        zoneSection
                    }
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

    // MARK: Zonas de FC

    private var hasZoneData: Bool {
        return report.zones.contains { (zone: CardioZoneMetrics) -> Bool in
            return zone.seconds > 0
        }
    }

    private var totalZoneSeconds: TimeInterval {
        return report.zones.reduce(0.0) { (sum: TimeInterval, zone: CardioZoneMetrics) -> TimeInterval in
            return sum + zone.seconds
        }
    }

    private var zoneSection: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(spacing: 6.0) {
                Text("ZONAS DE FC // % FC MÁX")
                    .font(EndfieldFont.label(7.5))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                Spacer(minLength: 4.0)

                Text("\(zoneTime(totalZoneSeconds)) EN ZONA")
                    .font(EndfieldFont.label(7.0))
                    .tracking(0.6)
                    .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.8))
                    .fixedSize()
            }
            .padding(.top, 2.0)

            GeometryReader { (proxy: GeometryProxy) in
                HStack(spacing: 0.0) {
                    ForEach(report.zones) { (zone: CardioZoneMetrics) in
                        Rectangle()
                            .fill(CardioZoneStyle.tint(for: zone.id).opacity(zone.seconds > 0 ? 0.85 : 0.18))
                            .frame(width: CGFloat(max(0.0, zone.fraction)) * proxy.size.width)
                    }
                }
                .frame(width: proxy.size.width, height: 6.0, alignment: .leading)
            }
            .frame(height: 6.0)
            .clipShape(ChamferedRectangle(cut: 2.0))

            VStack(spacing: 4.0) {
                ForEach(report.zones) { (zone: CardioZoneMetrics) in
                    zoneRow(zone)
                }
            }
        }
    }

    private func zoneRow(_ zone: CardioZoneMetrics) -> some View {
        HStack(spacing: 6.0) {
            Rectangle()
                .fill(CardioZoneStyle.tint(for: zone.id))
                .frame(width: 5.0, height: 5.0)

            Text("Z\(zone.id)")
                .font(EndfieldFont.mono(9.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .frame(width: 16.0, alignment: .leading)

            Text(zoneRangeLabel(zone))
                .font(EndfieldFont.label(7.5))
                .tracking(0.4)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(zoneTime(zone.seconds))
                .font(EndfieldFont.mono(10.0, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(zone.seconds > 0 ? EndfieldPalette.textPrimary : EndfieldPalette.textSecondary)
                .fixedSize()

            Text("\(zone.percent)%")
                .font(EndfieldFont.mono(10.0, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.textSecondary)
                .frame(width: 38.0, alignment: .trailing)
                .fixedSize()
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

    private func zoneRangeLabel(_ zone: CardioZoneMetrics) -> String {
        let lower: Int = Int((zone.lowerFraction * 100.0).rounded())
        if zone.id == 5 {
            return "\(lower)% +"
        }
        let upper: Int = Int((zone.upperFraction * 100.0).rounded())
        return "\(lower)–\(upper)%"
    }

    private func zoneTime(_ seconds: TimeInterval) -> String {
        let total: Int = max(0, Int(seconds.rounded()))
        let minutes: Int = total / 60
        let remainder: Int = total % 60
        return String(format: "%02d:%02d", minutes, remainder)
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

