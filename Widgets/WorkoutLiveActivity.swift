import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct AppGymWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}

// MARK: - Configuración

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenLiveActivityView(
                state: context.state,
                workoutName: context.attributes.workoutName
            )
            .activityBackgroundTint(Color(red: 0.04, green: 0.04, blue: 0.05))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Estado 1 · Maximizada: todo el contenido vive en `.bottom`
                // para usar el ancho completo por debajo de las cámaras y no
                // recortar el título con la curva superior izquierda.
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedWorkoutView(
                        state: context.state,
                        workoutName: context.attributes.workoutName
                    )
                }
            } compactLeading: {
                // Estado 2 · Compacta: anillo limpio + tiempo digital al lado.
                CompactRestTimerView(state: context.state)
            } compactTrailing: {
                // Estado 2 · Compacta: ♥ BPM 103.
                CompactBPMView(bpm: context.state.currentBPM)
            } minimal: {
                // Estado 3 · Minimizada: solo los BPM dentro del anillo.
                MinimalBPMTimerView(state: context.state)
            }
            .keylineTint(.red)
        }
    }
}

// MARK: - Ventana de descanso

/// Normaliza las fechas del `ContentState` para que los temporizadores nativos
/// (`ProgressView(timerInterval:)` y `Text(timerInterval:)`) siempre reciban un
/// rango válido y no decreciente.
struct LiveActivityRestWindow {
    let range: ClosedRange<Date>
    let isRunning: Bool

    init(state: WorkoutActivityAttributes.ContentState, now: Date = Date()) {
        let startDate: Date = state.restStartDate
        let endDate: Date = state.restEndDate > state.restStartDate ? state.restEndDate : state.restStartDate
        self.range = startDate...endDate
        self.isRunning = state.isResting && endDate > now
    }
}

// MARK: - Formato

enum LiveActivityFormat {
    static func weightText(_ weight: Double) -> String {
        let rounded: Double = weight.rounded()
        if abs(weight - rounded) < 0.001 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", weight)
    }

    static func bpm(_ bpm: Int) -> String {
        return bpm > 0 ? "\(bpm)" : "--"
    }

    static func bpmWithUnit(_ bpm: Int) -> String {
        return bpm > 0 ? "\(bpm) BPM" : "-- BPM"
    }

    static func setLabel(_ set: LiveActivityCompletedSet) -> String {
        return "Serie \(set.id): \(weightText(set.weight)) kg × \(set.reps)"
    }
}

private enum LiveActivityTheme {
    static let timer: Color = .green
    static let heart: Color = .red
    static let body: Color = Color.white.opacity(0.9)
    static let muted: Color = Color.white.opacity(0.45)
}

// MARK: - Componentes compartidos

/// Anillo de progreso nativo. Se vacía segundo a segundo sin refrescos de app.
/// Las etiquetas van vacías para que SwiftUI dibuje solo el anillo y no
/// superponga números blancos dentro del círculo.
struct LiveActivityTimerRingView: View {
    let window: LiveActivityRestWindow
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            if window.isRunning {
                ProgressView(
                    timerInterval: window.range,
                    countsDown: true,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
                .progressViewStyle(.circular)
                .tint(LiveActivityTheme.timer)
            } else {
                ZStack {
                    Circle()
                        .stroke(LiveActivityTheme.timer.opacity(0.25), lineWidth: lineWidth)

                    Circle()
                        .stroke(
                            LiveActivityTheme.timer,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                }
                .padding(lineWidth / 2)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Cuenta atrás digital nativa; "00:00" cuando no hay descanso corriendo.
struct LiveActivityTimerTextView: View {
    let window: LiveActivityRestWindow
    let font: Font
    let tint: Color
    /// Centra la cuenta atrás en el ancho disponible. El dial circular lo deja
    /// activo para que el reloj quede centrado en el anillo; la vista compacta
    /// lo desactiva para conservar su alineación a la izquierda.
    var centersText: Bool = true

    private var textAlignment: Alignment {
        return centersText ? Alignment.center : Alignment.leading
    }

    /// `Text(timerInterval:)` se expande al ancho propuesto por defecto: en el
    /// dial lo limitamos y centramos explícitamente; en la compacta dejamos que
    /// el texto mida su ancho natural.
    private var textMaxWidth: CGFloat? {
        return centersText ? CGFloat.infinity : nil
    }

    var body: some View {
        Group {
            if window.isRunning {
                Text(timerInterval: window.range, countsDown: true, showsHours: false)
            } else {
                Text("00:00")
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .multilineTextAlignment(centersText ? TextAlignment.center : TextAlignment.leading)
        .frame(maxWidth: textMaxWidth, alignment: textAlignment)
    }
}

/// Fila "Serie 1: 60 kg × 8".
struct LiveActivitySetRowView: View {
    let set: LiveActivityCompletedSet
    let font: Font
    let tint: Color

    var body: some View {
        Text(LiveActivityFormat.setLabel(set))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Estado 1 · Maximizada

struct ExpandedWorkoutView: View {
    let state: WorkoutActivityAttributes.ContentState
    let workoutName: String

    private var title: String {
        let name: String = state.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? workoutName : name
    }

    /// Nunca más de 4 filas para que la isla expandida no desborde.
    private var visibleSets: [LiveActivityCompletedSet] {
        Array(state.completedSets.suffix(4))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                if visibleSets.isEmpty {
                    Text("Sin series completadas")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(LiveActivityTheme.muted)
                        .lineLimit(1)
                } else {
                    ForEach(visibleSets) { set in
                        LiveActivitySetRowView(
                            set: set,
                            font: .system(size: 13, weight: .medium, design: .monospaced),
                            tint: LiveActivityTheme.body
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            RestDialView(state: state)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }
}

/// Dial circular compartido de 82×82 (anillo de 80 con tiempo y BPM dentro).
/// Lo usan la isla maximizada y la pantalla de bloqueo.
struct RestDialView: View {
    let state: WorkoutActivityAttributes.ContentState

    private var window: LiveActivityRestWindow {
        LiveActivityRestWindow(state: state)
    }

    var body: some View {
        ZStack(alignment: .center) {
            LiveActivityTimerRingView(window: window, diameter: 80, lineWidth: 5)

            // Columna interior de ancho fijo y centrado exacto: así el reloj
            // digital y los BPM quedan alineados respecto al anillo verde.
            VStack(alignment: .center, spacing: 2) {
                LiveActivityTimerTextView(
                    window: window,
                    font: .system(size: 17, weight: .bold, design: .rounded),
                    tint: .white
                )
                .frame(maxWidth: .infinity, alignment: .center)

                Text(LiveActivityFormat.bpmWithUnit(state.currentBPM))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LiveActivityTheme.heart)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: 64, alignment: .center)
        }
        .frame(width: 82, height: 82)
    }
}

// MARK: - Estado 2 · Normal / Compacta

struct CompactRestTimerView: View {
    let state: WorkoutActivityAttributes.ContentState

    private var window: LiveActivityRestWindow {
        LiveActivityRestWindow(state: state)
    }

    var body: some View {
        HStack(spacing: 4) {
            LiveActivityTimerRingView(window: window, diameter: 18, lineWidth: 2.5)

            // Compacta: el reloj no se centra, mantiene su ancho natural
            // pegado a la izquierda junto al anillo pequeño.
            LiveActivityTimerTextView(
                window: window,
                font: .system(size: 12, weight: .semibold, design: .monospaced),
                tint: LiveActivityTheme.timer,
                centersText: false
            )
            .frame(minWidth: 28, maxWidth: 40, alignment: .leading)
        }
        .padding(.leading, 1)
    }
}

struct CompactBPMView: View {
    let bpm: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(LiveActivityTheme.heart)

            Text("BPM")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(LiveActivityTheme.heart)

            Text(LiveActivityFormat.bpm(bpm))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Estado 3 · Minimizada

struct MinimalBPMTimerView: View {
    let state: WorkoutActivityAttributes.ContentState

    private var window: LiveActivityRestWindow {
        LiveActivityRestWindow(state: state)
    }

    var body: some View {
        ZStack {
            LiveActivityTimerRingView(window: window, diameter: 22, lineWidth: 3)

            Text(LiveActivityFormat.bpm(state.currentBPM))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LiveActivityTheme.heart)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Pantalla de bloqueo

struct LockScreenLiveActivityView: View {
    let state: WorkoutActivityAttributes.ContentState
    let workoutName: String

    private var title: String {
        let name: String = state.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? workoutName : name
    }

    private var visibleSets: [LiveActivityCompletedSet] {
        Array(state.completedSets.suffix(4))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                if visibleSets.isEmpty {
                    Text("Sin series completadas")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(LiveActivityTheme.muted)
                        .lineLimit(1)
                } else {
                    ForEach(visibleSets) { set in
                        LiveActivitySetRowView(
                            set: set,
                            font: .system(size: 12, weight: .medium, design: .monospaced),
                            tint: LiveActivityTheme.body
                        )
                    }
                }
            }

            Spacer(minLength: 6)

            RestDialView(state: state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
