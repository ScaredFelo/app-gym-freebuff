import Foundation
import SwiftUI
import SwiftData
import Charts

public struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("isBigPictureModeEnabled") private var isBigPictureModeEnabled = false

    @StateObject private var viewModel: ActiveWorkoutViewModel
    @State private var showingCancelConfirmation = false
    @State private var showingBigPictureCancelConfirmation = false
    @State private var showingRoutineChangeOptions = false
    @State private var showingNewRoutineNameAlert = false
    @State private var showingExercisePicker = false
    @State private var exercisePendingRemoval: RoutineExercise?
    @State private var pendingNewRoutinePromptID: UUID?
    @State private var newRoutineName = ""
    @Namespace private var timerAnimation
    @State private var timerOriginCardID: UUID?
    @State private var timerIsLaunching = false
    @State private var timerLaunchToken = UUID()
    @State private var timerDragOffset: CGFloat = 0

    private let horizontalPadding: CGFloat = 16

    public init(session: WorkoutSession, routine: Routine, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: ActiveWorkoutViewModel(session: session, routine: routine, modelContext: modelContext))
    }

    public var body: some View {
        Group {
            if isBigPictureModeEnabled {
                BigPictureWorkoutView(
                    viewModel: viewModel,
                    modelContext: modelContext,
                    onWorkoutFinished: {
                        dismiss()
                    }
                )
            } else {
                normalBody
                    .onChange(of: viewModel.session.endDate) { _, endDate in
                        if endDate != nil {
                            viewModel.isShowingSummary = true
                        }
                    }
                    .fullScreenCover(isPresented: $viewModel.isShowingSummary) {
                        WorkoutReviewView(
                            session: viewModel.session,
                            isPostWorkout: true,
                            viewModel: viewModel,
                            onFinish: {
                                dismiss()
                            }
                        )
                        .interactiveDismissDisabled(true)
                    }
            }
        }
        .onAppear {
            viewModel.startWorkoutActivityIfNeeded()
            viewModel.persistState()
        }
        // Cambio de ejercicio (modo normal y Big Picture): la Live Activity se
        // sincroniza al instante sin esperar al siguiente refresco.
        .onChange(of: viewModel.liveActivityExerciseName) { _, _ in
            viewModel.notifyLiveActivityExerciseChanged()
        }
        .onDisappear {
            // No se detiene el sensor cardíaco ni la grabación de muestras:
            // el entrenamiento sigue vivo en segundo plano hasta que el
            // usuario pulse "Terminar sesión" o cancele.
            pendingNewRoutinePromptID = nil
            PersistenceService.save(modelContext, operation: "guardar el estado del entrenamiento")
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                viewModel.handleScenePhaseActive()
            case .inactive:
                PersistenceService.save(modelContext, operation: "guardar el estado del entrenamiento")
            case .background:
                viewModel.handleScenePhaseBackground(modelContext: modelContext)
            @unknown default:
                break
            }
        }
        .navigationBarHidden(true)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                _ = viewModel.addExercise(exercise, modelContext: modelContext)
            }
        }
        .alert("¿Guardar cambios?", isPresented: $showingRoutineChangeOptions) {
            Button("Reemplazar rutina actual", role: .destructive) {
                _ = viewModel.finishWorkoutReplacingRoutine(modelContext: modelContext)
            }
            Button("Guardar como nueva rutina") {
                newRoutineName = "\(viewModel.routine.name) (modificada)"
                let promptID = UUID()
                pendingNewRoutinePromptID = promptID

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard pendingNewRoutinePromptID == promptID else { return }
                    showingNewRoutineNameAlert = true
                }
            }
            Button("Guardar solo el historial de hoy") {
                _ = viewModel.finishWorkoutHistoryOnly(modelContext: modelContext)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Has añadido, quitado o modificado datos respecto a la rutina original. ¿Qué quieres hacer con los cambios?")
        }
        .alert("Nueva rutina", isPresented: $showingNewRoutineNameAlert) {
            TextField("Nombre de la rutina", text: $newRoutineName)
            Button("Guardar") {
                _ = viewModel.finishWorkoutSavingAsNewRoutine(named: newRoutineName, modelContext: modelContext)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se guardará una copia con los cambios de hoy.")
        }
        .alert("¿Cancelar entrenamiento?", isPresented: $showingCancelConfirmation) {
            Button("Cancelar entrenamiento", role: .destructive) {
                pendingNewRoutinePromptID = nil
                showingRoutineChangeOptions = false
                showingNewRoutineNameAlert = false
                if viewModel.cancelWorkout(modelContext: modelContext) {
                    dismiss()
                }
            }
            Button("Seguir entrenando", role: .cancel) {}
        } message: {
            Text("Se descartará la sesión actual sin guardar el historial.")
        }
        .alert(
            "Eliminar ejercicio",
            isPresented: Binding(
                get: { exercisePendingRemoval != nil },
                set: { if !$0 { exercisePendingRemoval = nil } }
            )
        ) {
            Button("Eliminar", role: .destructive) {
                if let routineExercise = exercisePendingRemoval {
                    viewModel.removeExercise(routineExercise, modelContext: modelContext)
                }
                exercisePendingRemoval = nil
            }
            Button("Cancelar", role: .cancel) { exercisePendingRemoval = nil }
        } message: {
            Text("El ejercicio se quitará del entrenamiento actual.")
        }
        .alert(
            "¿Descartar entrenamiento?",
            isPresented: $showingBigPictureCancelConfirmation
        ) {
            Button("Sí, descartar", role: .destructive) {
                if viewModel.cancelWorkout(modelContext: modelContext) {
                    dismiss()
                }
            }
            Button("Seguir entrenando", role: .cancel) {}
        } message: {
            Text("Se descartará la sesión actual sin guardar el historial.")
        }
        .withKeyboardDismiss()
        .dismissKeyboardOnTap()
        .alert(
            "No se pudo guardar",
            isPresented: Binding(
                get: { viewModel.saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { viewModel.saveErrorMessage = nil }
                }
            )
        ) {
            Button("Entendido", role: .cancel) {
                viewModel.saveErrorMessage = nil
            }
        } message: {
            Text(viewModel.saveErrorMessage ?? "")
        }
    }

    private var normalBody: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                TechnicalGridBackground()

                // List of exercises on the main level
                ScrollView {
                    LazyVStack(spacing: 14) {
                        HUDStatusPanel(
                            routineName: viewModel.routine.name,
                            sessionStart: viewModel.session.startDate,
                            volumeKg: viewModel.session.totalVolumeKg,
                            isResting: viewModel.isResting,
                            isRestPaused: viewModel.isRestPaused,
                            totalRestSeconds: viewModel.totalRestSeconds,
                            restEndDate: viewModel.restTimerEndDate,
                            restRemainingFallback: viewModel.restTimeRemaining,
                            onCancel: { showingCancelConfirmation = true }
                        )

                        HealthDiagnosticBanner()

                        let _ = viewModel.structureVersion

                        let sortedExercises: [RoutineExercise] = viewModel.routine.exercises
                            .sorted(by: { $0.sortOrder < $1.sortOrder })

                        ForEach(Array(sortedExercises.enumerated()), id: \.element.id) { index, routineExercise in
                            if let exercise = routineExercise.exercise {
                                ExerciseCardView(
                                    index: index,
                                    routineExercise: routineExercise,
                                    exercise: exercise,
                                    sets: viewModel.activeSets[routineExercise.id] ?? [],
                                    isTimerOrigin: timerIsLaunching && timerOriginCardID == routineExercise.id,
                                    stopwatchSetIndex: viewModel.stopwatchRoutineExerciseID == routineExercise.id ? viewModel.stopwatchSetIndex : nil,
                                    stopwatchStartDate: viewModel.stopwatchRoutineExerciseID == routineExercise.id ? viewModel.stopwatchStartDate : nil,
                                    onToggleStopwatch: { setIndex in
                                        viewModel.toggleSetStopwatch(
                                            for: routineExercise.id,
                                            setIndex: setIndex,
                                            modelContext: modelContext
                                        )
                                    },
                                    onToggleSet: { setIndex in
                                        toggleSet(for: routineExercise, setIndex: setIndex)
                                    },
                                    onUpdateSet: { setIndex, weight, reps in
                                        viewModel.updateSetValues(
                                            for: routineExercise.id,
                                            setIndex: setIndex,
                                            weight: weight,
                                            reps: reps,
                                            modelContext: modelContext
                                        )
                                    },
                                    onAddSet: {
                                        _ = viewModel.addSet(for: routineExercise.id, modelContext: modelContext)
                                    },
                                    onRemove: {
                                        exercisePendingRemoval = routineExercise
                                    }
                                )
                            }
                        }

                        Button {
                            showingExercisePicker = true
                        } label: {
                            HStack(spacing: 8.0) {
                                Image(systemName: "plus")
                                    .font(EndfieldFont.mono(12.0, weight: .bold))

                                Text("AÑADIR EJERCICIO")
                                    .font(EndfieldFont.mono(12.0, weight: .bold))
                                    .tracking(1.2)
                            }
                        }
                        .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentCyan))

                        // Finish Workout Button
                        Button(action: {
                            // En un entreno libre no hay rutina que actualizar:
                            // la sesión se cierra directamente.
                            if viewModel.hasWorkoutChanges && !viewModel.isFreeWorkout {
                                showingRoutineChangeOptions = true
                            } else {
                                _ = viewModel.finishWorkout(modelContext: modelContext)
                            }
                        }) {
                            Text("EJECUTAR // FINALIZAR SESIÓN")
                        }
                        .buttonStyle(EndfieldPrimaryButtonStyle())
                        .padding(.top, 2.0)

                        Button(action: {
                            showingCancelConfirmation = true
                        }) {
                            HStack(spacing: 6.0) {
                                Image(systemName: "xmark")
                                    .font(EndfieldFont.mono(11.0, weight: .bold))

                                Text("ABORTAR // CANCELAR ENTRENAMIENTO")
                                    .font(EndfieldFont.mono(11.0, weight: .bold))
                                    .tracking(1.0)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentRed))

                        // Reserva el mismo espacio inferior exista o no temporizador flotante.
                        Color.clear
                            .frame(height: 88)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 16)
                    .frame(width: geometry.size.width)
                }
                .frame(width: geometry.size.width)

                // Temporizador maximizado
                if viewModel.isResting && (!viewModel.isTimerMinimized || (!viewModel.hasActiveRestTimer && !viewModel.isRestFinishing)) {
                    ZStack {
                        ZStack {
                            EndfieldPalette.bgPrimary
                                .ignoresSafeArea()

                            TechnicalGridOverlay(step: 28.0, lineColor: Color.white.opacity(0.05))
                        }
                        .opacity(viewModel.isRestFinishing ? 0 : 1)
                        .transition(.opacity)

                        VStack {
                            Spacer()
                            TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                                CircularTimerView(
                                    timeRemaining: displayedRestTime(at: timeline.date),
                                    totalSeconds: viewModel.totalRestSeconds,
                                    isPaused: viewModel.isRestPaused,
                                    onAdd10: { viewModel.add10Seconds() },
                                    onSub10: { viewModel.sub10Seconds() },
                                    onTogglePause: {
                                        if viewModel.isRestPaused {
                                            viewModel.resumeRest()
                                        } else {
                                            viewModel.pauseRest()
                                        }
                                    },
                                    onSkip: { skipRest() },
                                    onMinimize: { minimizeTimer() }
                                )
                            }
                            .matchedGeometryEffect(id: timerIsLaunching ? "timerContainer-inactive" : "timerContainer", in: timerAnimation, isSource: false)
                            .scaleEffect(viewModel.isRestFinishing ? 1.05 : 1)
                            .opacity(viewModel.isRestFinishing ? 0 : 1)
                            .offset(y: timerDragOffset)
                            .scaleEffect(timerDragOffset > 0 ? max(0.92, 1 - timerDragOffset / 1200) : 1)
                            .gesture(timerDragGesture)
                            .transition(.opacity)
                            Spacer()
                        }
                    }
                    .allowsHitTesting(!viewModel.isRestFinishing)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.isResting)
                    .animation(.easeIn(duration: 0.22), value: viewModel.isRestFinishing)
                    .zIndex(2)
                }

                // Temporizador minimizado flotando sobre la lista
                if viewModel.isResting && viewModel.isTimerMinimized && viewModel.hasActiveRestTimer {
                    TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                        MinimizedTimerView(
                            timeRemaining: displayedRestTime(at: timeline.date),
                            totalSeconds: viewModel.totalRestSeconds,
                            isPaused: viewModel.isRestPaused,
                            onExpand: { expandTimer() },
                            onTogglePause: {
                                if viewModel.isRestPaused {
                                    viewModel.resumeRest()
                                } else {
                                    viewModel.pauseRest()
                                }
                            },
                            onAdd10: { viewModel.add10Seconds() },
                            onSub10: { viewModel.sub10Seconds() },
                            onSkip: { skipRest() }
                        )
                    }
                    .matchedGeometryEffect(id: "timerContainer", in: timerAnimation, isSource: true)
                    .padding(.horizontal, horizontalPadding)
                    .frame(width: geometry.size.width)
                    .padding(.bottom, 8)
                    .offset(y: viewModel.isRestFinishing ? 44 : 0)
                    .opacity(viewModel.isRestFinishing ? 0 : 1)
                    .allowsHitTesting(!viewModel.isRestFinishing)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.isResting)
                    .zIndex(1)
                }
            }
            // Sin animaciones implícitas en el `ZStack` exterior: animar aquí
            // abarcaba también el `ScrollView` completo y hacía que activar o
            // cerrar el temporizador animase toda la lista (tirones).
        }
    }

    // MARK: - Barra de estado HUD del entrenamiento

    private struct HUDStatusPanel: View {
        @AppStorage(UserSettingsManager.isHeartRateTrackingEnabledKey)
        private var isHeartRateTrackingEnabled: Bool = true

        let routineName: String
        let sessionStart: Date
        let volumeKg: Double
        let isResting: Bool
        let isRestPaused: Bool
        let totalRestSeconds: Int
        let restEndDate: Date?
        let restRemainingFallback: Int
        let onCancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 9.0) {
                headerRow

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                    metricsBlock(now: timeline.date)
                }
            }
            .padding(.horizontal, 12.0)
            .padding(.vertical, 11.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChamferedRectangle(cut: EndfieldMetrics.cornerCut).fill(EndfieldPalette.bgPanel))
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                    .stroke(EndfieldPalette.borderActive, lineWidth: 1.0)
            }
            .overlay {
                TacticalCornerCrosses()
            }
        }

        // MARK: Cabecera

        private var headerRow: some View {
            HStack(spacing: 8.0) {
                Text("OP // ACTIVA")
                    .font(EndfieldFont.label(9.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .fixedSize()

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                Text("VOL // \(Int(volumeKg)) KG")
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.accentCyan)
                    .lineLimit(1)
                    .fixedSize()

                Text(routineName.uppercased())
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentRed, size: 26.0))
                .accessibilityLabel("Cancelar entrenamiento")
            }
        }

        // MARK: Telemetría

        @ViewBuilder
        private func metricsBlock(now: Date) -> some View {
            VStack(alignment: .leading, spacing: 7.0) {
                HStack(alignment: .top, spacing: 8.0) {
                    metricCell(
                        code: "T+ SESIÓN",
                        value: elapsedText(now: now),
                        unit: "",
                        tint: EndfieldPalette.textPrimary
                    )

                    if isHeartRateTrackingEnabled {
                        verticalSeparator

                        pulseCell

                        verticalSeparator
                    }

                    metricCell(
                        code: "DESCANSO",
                        value: restText(now: now),
                        unit: "",
                        tint: isResting ? EndfieldPalette.accentYellow : EndfieldPalette.textSecondary
                    )
                }

                if isResting {
                    SegmentedProgressBar(
                        progress: restProgress(now: now),
                        segments: 22,
                        tint: isRestPaused ? EndfieldPalette.accentRed : EndfieldPalette.accentYellow,
                        height: 4.0,
                        spacing: 2.0
                    )
                }
            }
        }

        private func metricCell(code: String, value: String, unit: String, tint: Color) -> some View {
            VStack(alignment: .leading, spacing: 2.0) {
                Text(code)
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(alignment: .firstTextBaseline, spacing: 3.0) {
                    Text(value)
                        .font(EndfieldFont.mono(19.0, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())

                    if !unit.isEmpty {
                        Text(unit)
                            .font(EndfieldFont.label(8.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var pulseCell: some View {
            PulseMetricCell()
        }

        private var verticalSeparator: some View {
            Rectangle()
                .fill(EndfieldPalette.borderSubtle)
                .frame(width: 1.0, height: 34.0)
        }

        // MARK: Cálculos de tiempo

        private func elapsedText(now: Date) -> String {
            let interval: TimeInterval = max(0.0, now.timeIntervalSince(sessionStart))
            let total: Int = Int(interval)
            let hours: Int = total / 3600
            let minutes: Int = (total % 3600) / 60
            let seconds: Int = total % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%02d:%02d", minutes, seconds)
        }

        private func remainingSeconds(now: Date) -> Int {
            if isRestPaused {
                return max(0, restRemainingFallback)
            }
            guard let deadline: Date = restEndDate else {
                return max(0, restRemainingFallback)
            }
            return max(0, Int(ceil(deadline.timeIntervalSince(now))))
        }

        private func restText(now: Date) -> String {
            guard isResting else { return "--:--" }
            let remaining: Int = remainingSeconds(now: now)
            return String(format: "%02d:%02d", remaining / 60, remaining % 60)
        }

        private func restProgress(now: Date) -> Double {
            guard totalRestSeconds > 0 else { return 0.0 }
            let remaining: Int = remainingSeconds(now: now)
            let consumed: Int = max(0, totalRestSeconds - remaining)
            return min(1.0, Double(consumed) / Double(totalRestSeconds))
        }
    }

    private var timerDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !viewModel.isRestFinishing else { return }
                timerDragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !viewModel.isRestFinishing else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        timerDragOffset = 0
                    }
                    return
                }

                if value.translation.height > 90 || value.predictedEndTranslation.height > 150 {
                    minimizeTimer()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        timerDragOffset = 0
                    }
                }
            }
    }

    private func toggleSet(for routineExercise: RoutineExercise, setIndex: Int) {
        guard let sets = viewModel.activeSets[routineExercise.id], sets.indices.contains(setIndex) else { return }
        let isCompleting = !sets[setIndex].isCompleted

        if isCompleting {
            beginTimerLaunch(from: routineExercise.id)
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            viewModel.toggleSetCompletion(for: routineExercise.id, setIndex: setIndex, modelContext: modelContext)
        }
    }

    private func beginTimerLaunch(from routineExerciseID: UUID) {
        let token = UUID()
        timerLaunchToken = token
        timerOriginCardID = routineExerciseID
        timerIsLaunching = true
        timerDragOffset = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard timerLaunchToken == token else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                timerIsLaunching = false
            }
        }
    }

    private func minimizeTimer() {
        guard !viewModel.isRestFinishing else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            timerDragOffset = 0
            viewModel.isTimerMinimized = true
        }
    }

    private func expandTimer() {
        guard !viewModel.isRestFinishing else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            timerDragOffset = 0
            viewModel.isTimerMinimized = false
        }
    }

    private func skipRest() {
        guard viewModel.isResting, !viewModel.isRestFinishing else { return }
        withAnimation(.easeIn(duration: 0.22)) {
            viewModel.skipRest()
        }
    }

    private func displayedRestTime(at date: Date) -> Int {
        if viewModel.isRestPaused {
            return viewModel.restTimeRemaining
        }

        guard let endDate = viewModel.restTimerEndDate else {
            return viewModel.restTimeRemaining
        }

        return max(0, Int(ceil(endDate.timeIntervalSince(date))))
    }

    /// Célula de pulso aislada: es la única vista del HUD que observa
    /// `BPMManager`. Las lecturas del sensor (hasta 4 Hz) solo redibujan
    /// este texto, no la lista completa de ejercicios.
    private struct PulseMetricCell: View {
        @ObservedObject private var bpmManager = BPMManager.shared
        @AppStorage(UserSettingsManager.isHeartRateTrackingEnabledKey)
        private var isHeartRateTrackingEnabled: Bool = true

        var body: some View {
            VStack(alignment: .leading, spacing: 2.0) {
                HStack(spacing: 4.0) {
                    EndfieldLiveDot(size: 5.0)

                    Text(isHeartRateTrackingEnabled ? "LIVE // 4HZ" : "BPM OFF")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.0)
                        .foregroundStyle(isHeartRateTrackingEnabled ? EndfieldPalette.accentRed.opacity(0.9) : EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3.0) {
                    Text(isHeartRateTrackingEnabled && bpmManager.currentBPM > 0 ? "\(bpmManager.currentBPM)" : "--")
                        .font(EndfieldFont.mono(19.0, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(isHeartRateTrackingEnabled && bpmManager.currentBPM > 0 ? EndfieldPalette.accentRed : EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())

                    Text("BPM")
                        .font(EndfieldFont.label(8.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Diagnóstico del sensor. Se oculta solo cuando ya hay pulso, de modo que
    /// la pantalla de entrenamiento no necesita observar `HealthKitManager` ni
    /// `LiveActivityManager`.
    private struct HealthDiagnosticBanner: View {
        @ObservedObject private var healthKitManager = HealthKitManager.shared
        @ObservedObject private var liveActivityManager = LiveActivityManager.shared
        @ObservedObject private var bpmManager = BPMManager.shared
        @AppStorage(UserSettingsManager.isHeartRateTrackingEnabledKey)
        private var isHeartRateTrackingEnabled: Bool = true

        var body: some View {
            if isHeartRateTrackingEnabled && bpmManager.currentBPM == 0 {
                TacticalPanel(code: "SYS.ERR", title: "SENSOR CARDÍACO", accentBorder: false, contentPadding: 12.0) {
                    VStack(alignment: .leading, spacing: 9.0) {
                        HStack(spacing: 7.0) {
                            Image(systemName: "heart.text.square")
                                .font(EndfieldFont.mono(11.0, weight: .bold))
                                .foregroundStyle(EndfieldPalette.accentRed)

                            Text("DIAGNÓSTICO")
                                .font(EndfieldFont.label(9.0))
                                .tracking(1.2)
                                .foregroundStyle(EndfieldPalette.accentRed)

                            Spacer(minLength: 0.0)
                        }

                        Text("ESTADO: \(bpmManager.statusText)")
                            .font(EndfieldFont.mono(10.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        if bpmManager.deviceType == .airPods {
                            Text("HEALTHKIT: \(healthKitManager.debugMessage)")
                                .font(EndfieldFont.mono(10.0))
                                .foregroundStyle(EndfieldPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }

                        Text("LIVE_ACTIVITY: \(liveActivityManager.debugMessage)")
                            .font(EndfieldFont.mono(10.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        Button {
                            bpmManager.reconnect()
                        } label: {
                            HStack(spacing: 6.0) {
                                Image(systemName: "heart")
                                    .font(EndfieldFont.mono(10.0, weight: .bold))

                                Text(bpmManager.deviceType == .airPods ? "RECONECTAR AIRPODS" : "RECONECTAR SENSOR BPM")
                                    .font(EndfieldFont.mono(10.0, weight: .bold))
                                    .tracking(0.8)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .buttonStyle(EndfieldSecondaryButtonStyle(compact: true, tint: EndfieldPalette.accentRed))
                        .accessibilityLabel(bpmManager.deviceType == .airPods ? "Reconectar AirPods" : "Reconectar sensor de pulso")
                    }
                }
            }
        }
    }
}

// MARK: - Exercise Card Component

struct ExerciseCardView: View {
    let index: Int
    let routineExercise: RoutineExercise
    let exercise: Exercise
    let sets: [ActiveWorkoutViewModel.SetInputState]
    let isTimerOrigin: Bool
    /// Serie cuyo cronómetro está en marcha, y su hora de inicio. Ambos llegan
    /// filtrados por tarjeta desde el ViewModel.
    let stopwatchSetIndex: Int?
    let stopwatchStartDate: Date?
    let onToggleStopwatch: (Int) -> Void
    let onToggleSet: (Int) -> Void
    let onUpdateSet: (Int, Double, Int) -> Void
    let onAddSet: () -> Void
    let onRemove: () -> Void

    @State private var notesExpanded = false
    @State private var showingEquipmentSheet = false

    private var notesBinding: Binding<String> {
        Binding(
            get: { routineExercise.notes },
            set: { routineExercise.notes = $0 }
        )
    }

    /// Peso de la serie activa (primera pendiente) o, si ya están hechas,
    /// el de la última serie configurada.
    private var activeWeight: Double {
        if let pending = sets.first(where: { (set: ActiveWorkoutViewModel.SetInputState) -> Bool in
            return !set.isCompleted
        }) {
            return pending.weight
        }
        if let last = sets.last {
            return last.weight
        }
        return routineExercise.defaultWeight
    }

    var body: some View {
        TacticalPanel(
            accentBorder: isTimerOrigin,
            contentPadding: 12.0
        ) {
            VStack(alignment: .leading, spacing: 10.0) {
                headerStrip

                Rectangle()
                    .fill(isTimerOrigin ? EndfieldPalette.borderActive : EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                titleBlock

                tableHeader

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                setRows

                addSetButton

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                notesBlock
            }
        }
        .sheet(isPresented: $showingEquipmentSheet) {
            ExerciseEquipmentSheet(
                equipmentType: exercise.equipmentType,
                weight: activeWeight
            )
            .presentationDetents([.height(300.0)])
            .presentationDragIndicator(.visible)
            .presentationBackground(EndfieldPalette.bgPrimary)
        }
    }

    // MARK: Cabecera técnica

    private var headerStrip: some View {
        HStack(spacing: 7.0) {
            Text("EX-\(String(format: "%02d", index + 1))")
                .font(EndfieldFont.mono(10.0, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.accentYellow)
                .padding(.horizontal, 5.0)
                .padding(.vertical, 2.0)
                .overlay {
                    ChamferedRectangle(cut: 3.0)
                        .stroke(EndfieldPalette.accentYellow.opacity(0.55), lineWidth: 1.0)
                }
                .fixedSize()

            Text(exercise.muscleGroup.shortName.uppercased())
                .font(EndfieldFont.label(8.0))
                .tracking(1.2)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .lineLimit(1)

            Rectangle()
                .fill(EndfieldPalette.borderSubtle)
                .frame(height: 1.0)

            Button(action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentRed, size: 28.0))
            .accessibilityLabel("Eliminar ejercicio")

            equipmentBox
        }
    }

    @ViewBuilder
    private var equipmentBox: some View {
        if exercise.equipmentType.usesPlates {
            Button {
                showingEquipmentSheet = true
            } label: {
                EquipmentSimplifiedIconView(equipmentType: exercise.equipmentType)
                    .frame(width: 28.0, height: 28.0)
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentCyan, size: 28.0))
            .accessibilityLabel("Ver discos de \(exercise.equipmentType.rawValue)")
        } else {
            EquipmentSimplifiedIconView(equipmentType: exercise.equipmentType)
                .frame(width: 28.0, height: 28.0)
                .background(ChamferedRectangle(cut: 3.0).fill(EndfieldPalette.bgElevated))
                .overlay {
                    ChamferedRectangle(cut: 3.0)
                        .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                }
                .accessibilityHidden(true)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            Text(exercise.name.uppercased())
                .font(EndfieldFont.mono(15.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            HStack(spacing: 5.0) {
                TacticalTagBadge(
                    text: "\(exercise.targetUnitLabel): \(routineExercise.targetRepsMin)-\(routineExercise.targetRepsMax)",
                    tint: EndfieldPalette.accentYellow
                )

                if exercise.isCompound {
                    TacticalTagBadge(text: "COMPLEJO", tint: EndfieldPalette.accentCyan)
                } else {
                    TacticalTagBadge(text: exercise.trackingMode == .reps ? "AISLAMIENTO" : "DURACIÓN", tint: EndfieldPalette.accentCyan)
                }

                if exercise.requiresStraps {
                    TacticalTagBadge(text: "STRAPS: SÍ", tint: EndfieldPalette.accentRed)
                }

                Spacer(minLength: 0.0)
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 6.0) {
            Text("Nº")
                .frame(width: 30.0, alignment: .leading)

            if exercise.trackingMode.isTimeBased {
                Text("CRONÓMETRO")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("")
                    .frame(width: 62.0, alignment: .center)

                Text(exercise.trackingMode.unitLabel)
                    .frame(width: 50.0, alignment: .center)
            } else {
                Text("GHOST")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("KG")
                    .frame(width: 62.0, alignment: .center)

                Text(exercise.trackingMode.unitLabel)
                    .frame(width: 50.0, alignment: .center)
            }

            Text("OK")
                .frame(width: 28.0, alignment: .center)
        }
        .font(EndfieldFont.label(8.0))
        .tracking(1.0)
        .foregroundStyle(EndfieldPalette.textSecondary)
    }

    private var setRows: some View {
        VStack(spacing: 5.0) {
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                if exercise.trackingMode.isTimeBased {
                    TimeSetRowView(
                        set: set,
                        trackingMode: exercise.trackingMode,
                        isRunning: stopwatchSetIndex == index && stopwatchStartDate != nil,
                        startDate: stopwatchSetIndex == index ? stopwatchStartDate : nil,
                        onToggleStopwatch: { onToggleStopwatch(index) },
                        onToggle: { onToggleSet(index) },
                        onUpdate: { reps in onUpdateSet(index, set.weight, reps) }
                    )
                } else {
                    SetRowView(
                        set: set,
                        targetRepsMin: routineExercise.targetRepsMin,
                        targetRepsMax: routineExercise.targetRepsMax,
                        onToggle: { onToggleSet(index) },
                        onUpdate: { w, r in onUpdateSet(index, w, r) }
                    )
                }
            }
        }
    }

    // MARK: Serie extra

    /// Permite añadir series al ejercicio en pleno entrenamiento, sin pasar
    /// por la edición de la rutina. El cardio es un único bloque cronometrado,
    /// así que no admite series extra.
    @ViewBuilder
    private var addSetButton: some View {
        if exercise.trackingMode != .minutes {
            Button(action: onAddSet) {
                HStack(spacing: 6.0) {
                    Image(systemName: "plus")
                        .font(EndfieldFont.mono(9.0, weight: .bold))

                    Text("AÑADIR SERIE")
                        .font(EndfieldFont.mono(9.0, weight: .bold))
                        .tracking(1.0)
                }
            }
            .buttonStyle(EndfieldSecondaryButtonStyle(compact: true, tint: EndfieldPalette.accentCyan))
            .accessibilityLabel("Añadir serie a \(exercise.name)")
        }
    }

    // MARK: Notas

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    notesExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6.0) {
                    Image(systemName: "note.text")
                        .font(EndfieldFont.mono(9.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.textSecondary)

                    Text("NOTAS_OP")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.2)
                        .foregroundStyle(EndfieldPalette.textSecondary)

                    Spacer(minLength: 0.0)

                    Text(notesExpanded ? "–" : "+")
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if notesExpanded {
                TextField("Poleas, agarre, altura...", text: notesBinding, axis: .vertical)
                    .font(EndfieldFont.mono(11.0))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(2...6)
                    .padding(9.0)
                    .background(ChamferedRectangle(cut: EndfieldMetrics.cellCut).fill(EndfieldPalette.bgElevated))
                    .overlay {
                        ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                            .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                    }
            }
        }
    }
}

// MARK: - Equipment Sheet

private struct ExerciseEquipmentSheet: View {
    let equipmentType: EquipmentType
    let weight: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            HazardStripeBar(height: 6.0)

            HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                Text(equipmentType.rawValue.uppercased())
                    .font(EndfieldFont.mono(13.0, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0.0)

                Text("\(UserSettingsManager.formatted(weight)) KG")
                    .font(EndfieldFont.mono(13.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .fixedSize()
            }

            EquipmentVisualizerView(
                equipmentType: equipmentType,
                weight: weight
            )

            Spacer(minLength: 0.0)
        }
        .padding(16.0)
        .background(EndfieldPalette.bgPrimary.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Set Row Component

struct SetRowView: View {
    let set: ActiveWorkoutViewModel.SetInputState
    let targetRepsMin: Int
    let targetRepsMax: Int
    let onToggle: () -> Void
    let onUpdate: (Double, Int) -> Void

    @State private var weightString: String
    @State private var repsString: String

    init(
        set: ActiveWorkoutViewModel.SetInputState,
        targetRepsMin: Int,
        targetRepsMax: Int,
        onToggle: @escaping () -> Void,
        onUpdate: @escaping (Double, Int) -> Void
    ) {
        self.set = set
        self.targetRepsMin = targetRepsMin
        self.targetRepsMax = targetRepsMax
        self.onToggle = onToggle
        self.onUpdate = onUpdate
        _weightString = State(initialValue: set.weight == 0 ? "" : String(format: "%.1f", set.weight))
        _repsString = State(initialValue: set.reps == 0 ? "" : "\(set.reps)")
    }

    var body: some View {
        HStack(spacing: 6.0) {
            // Set Number
            Text(String(format: "%02d", set.setNumber))
                .font(EndfieldFont.mono(11.0, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(set.isCompleted ? EndfieldPalette.accentYellow : EndfieldPalette.textSecondary)
                .frame(width: 30.0, alignment: .leading)

            // Ghost Reference
            Text(ghostText)
                .font(EndfieldFont.mono(10.0))
                .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Weight Input
            TextField("0", text: $weightString)
                .textFieldStyle(.plain)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(EndfieldFont.mono(16.0, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.textPrimary)
                .frame(width: 62.0, height: 36.0)
                .background(ChamferedRectangle(cut: EndfieldMetrics.cellCut).fill(EndfieldPalette.bgElevated))
                .overlay {
                    ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                        .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                }
                .onChange(of: weightString) { _, newValue in
                    if let w = Double(newValue) {
                        onUpdate(w, set.reps)
                    }
                }

            // Reps Input
            TextField(targetRepsMax > 0 ? "\(targetRepsMax)" : "0", text: $repsString)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(EndfieldFont.mono(16.0, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.textPrimary)
                .frame(width: 50.0, height: 36.0)
                .background(ChamferedRectangle(cut: EndfieldMetrics.cellCut).fill(EndfieldPalette.bgElevated))
                .overlay {
                    ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                        .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                }
                .onChange(of: repsString) { _, newValue in
                    if let r = Int(newValue) {
                        onUpdate(set.weight, r)
                    }
                }

            // Checkmark Button
            Button(action: onToggle) {
                Image(systemName: "checkmark")
                    .font(EndfieldFont.mono(13.0, weight: .heavy))
                    .opacity(set.isCompleted ? 1.0 : 0.0)
                    .frame(width: 28.0, height: 28.0)
            }
            .buttonStyle(SetCompletionButtonStyle(isCompleted: set.isCompleted))
            .accessibilityLabel(set.isCompleted ? "Serie completada" : "Marcar serie como completada")
        }
        .padding(.horizontal, 6.0)
        .padding(.vertical, 5.0)
        .background {
            if set.isCompleted {
                ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                    .fill(EndfieldPalette.accentYellow.opacity(0.06))
            }
        }
    }

    private var ghostText: String {
        guard let gw = set.ghostWeight, let gr = set.ghostReps else { return "—" }
        return "\(String(format: "%.0f", gw))kg × \(gr)"
    }
}

// MARK: - Time Set Row Component

/// Fila de una serie medida en tiempo (isométricos y cardio): cronómetro real
/// en marcha, sin columna de peso ni marca fantasma de kg.
struct TimeSetRowView: View {
    let set: ActiveWorkoutViewModel.SetInputState
    let trackingMode: ExerciseTrackingMode
    let isRunning: Bool
    let startDate: Date?
    let onToggleStopwatch: () -> Void
    let onToggle: () -> Void
    let onUpdate: (Int) -> Void

    @State private var valueString: String
    @FocusState private var isValueFocused: Bool

    init(
        set: ActiveWorkoutViewModel.SetInputState,
        trackingMode: ExerciseTrackingMode,
        isRunning: Bool,
        startDate: Date?,
        onToggleStopwatch: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onUpdate: @escaping (Int) -> Void
    ) {
        self.set = set
        self.trackingMode = trackingMode
        self.isRunning = isRunning
        self.startDate = startDate
        self.onToggleStopwatch = onToggleStopwatch
        self.onToggle = onToggle
        self.onUpdate = onUpdate
        _valueString = State(initialValue: set.reps == 0 ? "" : "\(set.reps)")
    }

    var body: some View {
        HStack(spacing: 6.0) {
            Text(String(format: "%02d", set.setNumber))
                .font(EndfieldFont.mono(11.0, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(set.isCompleted ? EndfieldPalette.accentYellow : EndfieldPalette.textSecondary)
                .frame(width: 30.0, alignment: .leading)

            elapsedView
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onToggleStopwatch) {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(EndfieldFont.mono(12.0, weight: .heavy))
            }
            .buttonStyle(EndfieldSquareButtonStyle(
                tint: isRunning ? EndfieldPalette.accentRed : EndfieldPalette.accentCyan,
                size: 30.0
            ))
            .frame(width: 62.0)
            .disabled(set.isCompleted)
            .opacity(set.isCompleted ? 0.4 : 1.0)
            .accessibilityLabel(isRunning ? "Detener cronómetro y registrar serie" : "Iniciar cronómetro de la serie")

            TextField(placeholder, text: $valueString)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(EndfieldFont.mono(15.0, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.textPrimary)
                .frame(width: 50.0, height: 36.0)
                .background(ChamferedRectangle(cut: EndfieldMetrics.cellCut).fill(EndfieldPalette.bgElevated))
                .overlay {
                    ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                        .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                }
                .focused($isValueFocused)
                .onChange(of: valueString) { _, newValue in
                    if let value = Int(newValue) {
                        onUpdate(value)
                    }
                }
                .onChange(of: set.reps) { _, newValue in
                    // El cronómetro escribe el tiempo real: el campo se
                    // sincroniza salvo que el usuario esté editándolo.
                    guard !isValueFocused else { return }
                    valueString = newValue == 0 ? "" : "\(newValue)"
                }

            Button(action: onToggle) {
                Image(systemName: "checkmark")
                    .font(EndfieldFont.mono(13.0, weight: .heavy))
                    .opacity(set.isCompleted ? 1.0 : 0.0)
                    .frame(width: 28.0, height: 28.0)
            }
            .buttonStyle(SetCompletionButtonStyle(isCompleted: set.isCompleted))
            .accessibilityLabel(set.isCompleted ? "Serie completada" : "Marcar serie como completada")
        }
        .padding(.horizontal, 6.0)
        .padding(.vertical, 5.0)
        .background {
            if set.isCompleted {
                ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                    .fill(EndfieldPalette.accentYellow.opacity(0.06))
            }
        }
    }

    /// Mientras corre muestra el tiempo real (mm:ss) actualizado por
    /// `TimelineView`; en reposo, la última marca registrada.
    @ViewBuilder
    private var elapsedView: some View {
        if isRunning, let startDate {
            TimelineView(.periodic(from: startDate, by: 1.0)) { timeline in
                Text(Self.formatted(elapsed: timeline.date.timeIntervalSince(startDate)))
                    .font(EndfieldFont.mono(18.0, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } else {
            Text(storedText)
                .font(EndfieldFont.mono(12.0, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var placeholder: String {
        return trackingMode == .minutes ? "min" : "seg"
    }

    private var storedText: String {
        guard set.reps > 0 else { return "—" }
        if trackingMode == .seconds {
            return Self.formatted(seconds: set.reps)
        }
        return "\(set.reps) min"
    }

    static func formatted(elapsed: TimeInterval) -> String {
        let total: Int = max(0, Int(elapsed))
        let hours: Int = total / 3600
        let minutes: Int = (total % 3600) / 60
        let seconds: Int = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func formatted(seconds: Int) -> String {
        let value: Int = max(0, seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

/// Botón cuadrado de 28x28 pt que se ilumina en amarillo al completar la serie.
private struct SetCompletionButtonStyle: ButtonStyle {
    let isCompleted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isCompleted ? EndfieldPalette.bgPrimary : EndfieldPalette.textSecondary)
            .frame(width: 28.0, height: 28.0)
            .background {
                if isCompleted {
                    ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                        .fill(EndfieldPalette.accentYellow)
                }
            }
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                    .stroke(
                        isCompleted ? EndfieldPalette.accentYellow : EndfieldPalette.borderSubtle,
                        lineWidth: 1.0
                    )
            }
            .opacity(configuration.isPressed ? 0.65 : 1.0)
    }
}
