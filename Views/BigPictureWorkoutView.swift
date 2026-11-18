import SwiftUI
import SwiftData
import Charts

/// Vista dedicada al modo Big Picture (entrenamiento con interfaz simplificada y
/// controles de gran tamaño). Extraída de `ActiveWorkoutView` para mantener la
/// separación de responsabilidades y el cuerpo de esa vista enfocado al modo normal.
public struct BigPictureWorkoutView: View {
    @ObservedObject private var viewModel: ActiveWorkoutViewModel
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @Environment(\.dismiss) private var dismiss

    let modelContext: ModelContext

    /// Callback invocado cuando el entrenamiento finaliza automáticamente
    /// (última serie del último ejercicio). El contenedor lo usa para hacer `dismiss()`.
    var onWorkoutFinished: (() -> Void)?

    @State private var weightInput = ""
    @FocusState private var isWeightFieldFocused: Bool
    @State private var showingCancelConfirmation = false

    public init(viewModel: ActiveWorkoutViewModel, modelContext: ModelContext, onWorkoutFinished: (() -> Void)? = nil) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.modelContext = modelContext
        self.onWorkoutFinished = onWorkoutFinished
    }

    public var body: some View {
        ZStack {
            TechnicalGridBackground()

            ScrollView {
                VStack(spacing: 12.0) {
                    // Barra superior: cancelar + nombre rutina
                    bigPictureTopBar

                    // MARK: - Ejercicio actual, índice y siguiente
                    exerciseHeaderPanel

                    // MARK: - Peso y repeticiones
                    BigPictureControlsView(
                        weightInput: $weightInput,
                        currentWeight: viewModel.bigPictureCurrentWeight,
                        currentReps: viewModel.bigPictureCurrentReps,
                        modelContext: modelContext,
                        onWeightChange: { value in
                            viewModel.bigPictureUpdateWeight(value, modelContext: modelContext)
                        },
                        onRepsChange: { delta in
                            viewModel.bigPictureAdjustReps(delta)
                        }
                    )
                    .padding(.horizontal, 16.0)

                    // MARK: - Temporizador integrado o botón registrar serie
                    restTimerProgressView

                    // MARK: - Gráfica BPM (visible durante todo el entrenamiento)
                    BPMChartView(samples: viewModel.bpmHistoryLast3Minutes)

                    // MARK: - Parrilla de series (historial vs nueva marca)
                    BigPictureSetsGridView(
                        currentExercise: viewModel.bigPictureCurrentExercise,
                        rows: viewModel.bigPictureSetRows(modelContext: modelContext)
                    )

                    // MARK: - Notas del ejercicio actual
                    exerciseNotesSection

                    // MARK: - Equipamiento y discos del ejercicio actual
                    equipmentVisualizerSection

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 16)
            }
        }
        .alert("¿Descartar entrenamiento?", isPresented: $showingCancelConfirmation) {
            Button("Sí, descartar", role: .destructive) {
                viewModel.cancelWorkout(modelContext: modelContext)
                dismiss()
            }
            Button("Seguir entrenando", role: .cancel) {}
        } message: {
            Text("Se perderán todos los registros de esta sesión.")
        }
        // El ViewModel activa `isShowingSummary` al finalizar el entrenamiento
        // (automáticamente en la última serie o desde el modo normal).
        // La pantalla completa no es interactiva: no hay gesto de arrastre ni
        // botón de cierre. La única salida es el botón "Terminar sesión".
        .fullScreenCover(isPresented: $viewModel.isShowingSummary) {
            WorkoutReviewView(
                session: viewModel.session,
                isPostWorkout: true,
                viewModel: viewModel,
                onFinish: {
                    dismiss() // Regresa al menú principal
                }
            )
            .interactiveDismissDisabled(true)
        }
    }

    // MARK: - Cabecera y barra superior

    /// Relleno superior (cerrar + nombre de rutina + telemetría de pulso).
    @ViewBuilder
    private var bigPictureTopBar: some View {
        HStack(spacing: 8.0) {
            Button {
                showingCancelConfirmation = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentRed, size: 28.0))
            .accessibilityLabel("Descartar entrenamiento")

            Text("BIG_PICTURE // TÁCTICO")
                .font(EndfieldFont.label(8.0))
                .tracking(1.2)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize()

            Text(viewModel.routine.name.uppercased())
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer(minLength: 4.0)

            HStack(spacing: 4.0) {
                EndfieldLiveDot(size: 5.0)

                Text(healthKitManager.currentBPM > 0 ? "\(healthKitManager.currentBPM)" : "--")
                    .font(EndfieldFont.mono(12.0, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(healthKitManager.currentBPM > 0 ? EndfieldPalette.accentRed : EndfieldPalette.textSecondary)

                Text("BPM")
                    .font(EndfieldFont.label(7.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }
            .fixedSize()
        }
        .padding(.horizontal, 16.0)
        .padding(.top, 8.0)
    }

    /// Bloque principal: número de ejercicio grande, nombre y objetivo.
    @ViewBuilder
    private var exerciseHeaderPanel: some View {
        TacticalPanel(accentBorder: true, contentPadding: 14.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                HStack(alignment: .firstTextBaseline, spacing: 7.0) {
                    Text(exerciseIndexText)
                        .font(EndfieldFont.mono(30.0, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(EndfieldPalette.accentYellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("// EJERCICIO")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.2)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize()

                    Spacer(minLength: 0.0)
                }

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                Text(viewModel.bigPictureCurrentExercise.uppercased())
                    .font(EndfieldFont.mono(21.0, weight: .heavy))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6.0) {
                    if let routineExercise: RoutineExercise = viewModel.bigPictureCurrentRoutineExercise {
                        TacticalTagBadge(
                            text: "REPS: \(routineExercise.targetRepsMin)-\(routineExercise.targetRepsMax)",
                            tint: EndfieldPalette.accentYellow
                        )
                    }

                    if !viewModel.bigPictureNextExercise.isEmpty {
                        Text(viewModel.bigPictureNextExercise.uppercased())
                            .font(EndfieldFont.label(8.0))
                            .tracking(1.0)
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    Spacer(minLength: 0.0)
                }
            }
        }
        .padding(.horizontal, 16.0)
    }

    private var exerciseIndexText: String {
        let sorted: [RoutineExercise] = viewModel.routine.exercises
            .sorted(by: { $0.sortOrder < $1.sortOrder })

        guard let current: RoutineExercise = viewModel.bigPictureCurrentRoutineExercise,
              let index: Int = sorted.firstIndex(where: { $0.id == current.id }) else {
            return "-- / --"
        }

        return String(format: "%02d / %02d", index + 1, sorted.count)
    }

    // MARK: - Temporizador

    /// Barra de descanso segmentada con controles angulares, o botón
    /// "Registrar serie" cuando no hay descanso activo.
    @ViewBuilder
    private var restTimerProgressView: some View {
        if viewModel.bigPictureIsTimerShowing {
            VStack(spacing: 8.0) {
                bigPictureTimerBar
                bigPictureTimerControls
            }
        } else {
            Button {
                viewModel.bigPictureRegisterSet(modelContext: modelContext)
            } label: {
                Text("REGISTRAR SERIE // CONFIRMAR")
            }
            .buttonStyle(EndfieldPrimaryButtonStyle())
            .padding(.horizontal, 16.0)
        }
    }

    private var bigPictureTimerBar: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            VStack(alignment: .leading, spacing: 7.0) {
                HStack(alignment: .firstTextBaseline, spacing: 6.0) {
                    Text(viewModel.isRestPaused ? "DESCANSO // PAUSA" : "DESCANSO // ACTIVO")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.2)
                        .foregroundStyle(viewModel.isRestPaused ? EndfieldPalette.accentRed : EndfieldPalette.textSecondary)

                    Spacer(minLength: 4.0)

                    Text(viewModel.bigPictureRemainingTimeFormatted)
                        .font(EndfieldFont.mono(22.0, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .contentTransition(.numericText())
                }

                SegmentedProgressBar(
                    progress: 1.0 - viewModel.bigPictureRestProgress,
                    segments: 30,
                    tint: viewModel.isRestPaused ? EndfieldPalette.accentRed : EndfieldPalette.accentYellow,
                    height: 6.0,
                    spacing: 2.0
                )
            }
            .padding(.horizontal, 12.0)
            .padding(.vertical, 10.0)
            .background(EndfieldPalette.bgPanel)
            .clipShape(ChamferedRectangle(cut: 8.0))
            .overlay {
                ChamferedRectangle(cut: 8.0)
                    .stroke(EndfieldPalette.borderActive, lineWidth: 1.0)
            }
            .padding(.horizontal, 16.0)
        }
    }

    private var bigPictureTimerControls: some View {
        HStack(spacing: 8.0) {
            Button {
                if viewModel.isRestPaused {
                    viewModel.resumeRest()
                } else {
                    viewModel.pauseRest()
                }
            } label: {
                HStack(spacing: 6.0) {
                    Image(systemName: viewModel.isRestPaused ? "play" : "pause")
                        .font(EndfieldFont.mono(11.0, weight: .bold))

                    Text(viewModel.isRestPaused ? "REANUDAR" : "PAUSAR")
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .tracking(1.0)
                }
            }
            .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.textPrimary))

            Button {
                viewModel.skipRest()
            } label: {
                HStack(spacing: 6.0) {
                    Image(systemName: "forward.end")
                        .font(EndfieldFont.mono(11.0, weight: .bold))

                    Text("SALTAR")
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .tracking(1.0)
                }
            }
            .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentRed))
        }
        .padding(.horizontal, 16.0)
    }

    // MARK: - Notas del ejercicio

    /// Campo editable de notas vinculado al ejercicio actual en tiempo real.
    @ViewBuilder
    private var exerciseNotesSection: some View {
        if let routineExercise = viewModel.bigPictureCurrentRoutineExercise {
            TacticalPanel(code: "OPS.NOTAS", title: "BITÁCORA", contentPadding: 10.0) {
                TextEditor(text: notesBinding(for: routineExercise))
                    .font(EndfieldFont.mono(12.0))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80.0, alignment: .topLeading)
                    .padding(8.0)
                    .background(EndfieldPalette.bgElevated)
                    .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
                    .overlay {
                        ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                            .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                    }
            }
            .padding(.horizontal, 16.0)
        }
    }

    private func notesBinding(for routineExercise: RoutineExercise) -> Binding<String> {
        Binding(
            get: { routineExercise.notes },
            set: {
                routineExercise.notes = $0
                try? modelContext.save()
            }
        )
    }

    // MARK: - Equipamiento

    /// Visualizador proporcional de discos para el ejercicio y la serie activa.
    @ViewBuilder
    private var equipmentVisualizerSection: some View {
        if let routineExercise = viewModel.bigPictureCurrentRoutineExercise,
           let exercise = routineExercise.exercise {
            TacticalPanel(code: "EQP.DISC", title: "DISCOS // BARRA", contentPadding: 10.0) {
                EquipmentVisualizerView(
                    equipmentType: exercise.equipmentType,
                    weight: viewModel.bigPictureCurrentWeight
                )
            }
            .padding(.horizontal, 16.0)
        }
    }
}

// MARK: - Big Picture Controls View (peso + repeticiones)

struct BigPictureControlsView: View {
    @Binding var weightInput: String
    @FocusState private var isWeightFocused: Bool
    var currentWeight: Double
    var currentReps: Int
    var modelContext: ModelContext
    var onWeightChange: (Double) -> Void
    var onRepsChange: (Int) -> Void

    private let weightStep: Double = 2.5

    var body: some View {
        VStack(spacing: 10.0) {
            weightRow

            Rectangle()
                .fill(EndfieldPalette.borderSubtle)
                .frame(height: 1.0)

            repsRow
        }
        .padding(.horizontal, 12.0)
        .padding(.vertical, 12.0)
        .background(EndfieldPalette.bgPanel)
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cornerCut))
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }

    // MARK: Peso

    private var weightRow: some View {
        HStack(spacing: 10.0) {
            stepButton(systemName: "minus", tint: EndfieldPalette.textPrimary) {
                onWeightChange(max(0.0, currentWeight - weightStep))
            }
            .accessibilityLabel("Restar peso")

            VStack(spacing: 0.0) {
                HStack(alignment: .firstTextBaseline, spacing: 4.0) {
                    TextField("0", text: $weightInput)
                        .textFieldStyle(.plain)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(EndfieldFont.mono(54.0, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .tint(EndfieldPalette.accentYellow)
                        .focused($isWeightFocused)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 90.0, alignment: .trailing)
                        .onChange(of: weightInput) { _, newValue in
                            guard isWeightFocused else { return }
                            let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                            guard let value = Double(normalized) else { return }
                            onWeightChange(value)
                        }
                        .onSubmit { isWeightFocused = false }
                        .accessibilityLabel("Peso actual. Toca para editar.")

                    Text("KG")
                        .font(EndfieldFont.mono(15.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize()
                }

                Text("CARGA // OBJETIVO")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .onChange(of: currentWeight) { _, newWeight in
                guard !isWeightFocused else { return }
                weightInput = formattedWeight(newWeight)
            }

            stepButton(systemName: "plus", tint: EndfieldPalette.accentYellow) {
                onWeightChange(currentWeight + weightStep)
            }
            .accessibilityLabel("Sumar peso")
        }
    }

    // MARK: Repeticiones

    private var repsRow: some View {
        HStack(spacing: 10.0) {
            stepButton(systemName: "minus", tint: EndfieldPalette.textPrimary) {
                onRepsChange(-1)
            }
            .accessibilityLabel("Restar repetición")

            VStack(spacing: 0.0) {
                Text("\(currentReps)")
                    .font(EndfieldFont.mono(54.0, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())

                Text("REPS // OBJETIVO")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }
            .frame(maxWidth: .infinity)

            stepButton(systemName: "plus", tint: EndfieldPalette.accentYellow) {
                onRepsChange(1)
            }
            .accessibilityLabel("Sumar repetición")
        }
    }

    private func stepButton(systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(EndfieldFont.mono(17.0, weight: .heavy))
        }
        .buttonStyle(EndfieldSquareButtonStyle(tint: tint, size: 46.0))
    }

    private func formattedWeight(_ weight: Double) -> String {
        guard weight > 0 else { return "" }
        if weight.rounded() == weight {
            return String(Int(weight))
        }
        return String(format: "%.1f", weight)
    }
}

// MARK: - BPM Chart View (ventana de 3 minutos)

struct BPMChartView: View {
    let samples: [ActiveWorkoutViewModel.BPMDataPoint]

    var body: some View {
        TacticalPanel(code: "HUD.BPM", title: "ÚLTIMOS 3 MIN", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 6.0) {
                TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                    if samples.isEmpty {
                        Text("ESPERANDO TELEMETRÍA CARDÍACA...")
                            .font(EndfieldFont.mono(10.0))
                            .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.7))
                            .frame(height: 100.0)
                            .frame(maxWidth: .infinity)
                    } else {
                        Chart(samples) { (sample: ActiveWorkoutViewModel.BPMDataPoint) in
                            LineMark(
                                x: .value("Tiempo", sample.timestamp),
                                y: .value("BPM", Double(sample.bpm))
                            )
                            .foregroundStyle(EndfieldPalette.accentRed)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Tiempo", sample.timestamp),
                                y: .value("BPM", Double(sample.bpm))
                            )
                            .foregroundStyle(EndfieldPalette.accentRed)
                        }
                        .chartXScale(domain: timeline.date.addingTimeInterval(-180)...timeline.date)
                        .chartYScale(domain: 40...200)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(values: .stride(by: 40.0)) { value in
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
                }
            }
        }
        .padding(.horizontal, 16.0)
        .padding(.bottom, 4.0)
    }
}

// MARK: - Big Picture Sets Grid View (3 columnas)

struct BigPictureSetsGridView: View {
    var currentExercise: String
    var rows: [ActiveWorkoutViewModel.BigPictureSetRow]

    var body: some View {
        TacticalPanel(code: "SET.LOG", title: "ÚLTIMA SESIÓN", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                Text(currentExercise.uppercased())
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if rows.isEmpty {
                    Text("SIN SERIES REGISTRADAS")
                        .font(EndfieldFont.mono(10.0))
                        .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.7))
                } else {
                    let columns: [GridItem] = [
                        GridItem(.flexible(), spacing: 8.0),
                        GridItem(.flexible(), spacing: 8.0),
                        GridItem(.flexible(), spacing: 8.0)
                    ]

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8.0) {
                        Text("SERIE")
                            .gridColumnHeader()
                        Text("ÚLTIMA")
                            .gridColumnHeader()
                        Text("NUEVA")
                            .gridColumnHeader()

                        ForEach(rows) { row in
                            BigPictureSetRowView(row: row)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16.0)
    }
}

private extension Text {
    func gridColumnHeader() -> some View {
        self
            .font(EndfieldFont.label(8.0))
            .tracking(1.0)
            .foregroundStyle(EndfieldPalette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BigPictureSetRowView: View {
    var row: ActiveWorkoutViewModel.BigPictureSetRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3.0) {
            Text(String(format: "S-%02d", row.setNumber))
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary)

            Text(row.previousText ?? "—")
                .font(EndfieldFont.mono(11.0))
                .foregroundStyle(EndfieldPalette.textPrimary.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(row.currentText ?? "—")
                .font(EndfieldFont.mono(11.0, weight: .bold))
                .foregroundStyle(row.currentText == nil ? EndfieldPalette.textSecondary.opacity(0.45) : EndfieldPalette.accentYellow)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7.0)
        .background(EndfieldPalette.bgElevated)
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }
}
