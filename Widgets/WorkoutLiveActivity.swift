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
                // Estado 1 · Maximizada: ejercicio + series realizadas.
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedExerciseSummaryView(
                        state: context.state,
                        workoutName: context.attributes.workoutName
                    )
                }

                // Estado 1 · Maximizada: temporizador circular grande con BPM.
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedRestDialView(state: context.state)
                }
            } compactLeading: {
                // Estado 2 · Compacta: anillo pequeño + tiempo digital.
                CompactRestTimerView(state: context.state)
            } compactTrailing: {
                // Estado 2 · Compacta: ♥ BPM 103.
                CompactBPMView(bpm: context.state.currentBPM)
            } minimal: {
                // Estado 3 · Minimizada: anillo con los BPM dentro.
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

    static func setLabel(_ set: LiveActivityCompletedSet) -> String {
        return "Serie \(set.id): \(weightText(set.weight)) kg × \(set.reps)"
    }
}

private enum LiveActivityTheme {
    static let timer: Color = .green
    static let heart: Color = .red
}

// MARK: - Componentes compartidos

/// Anillo de progreso nativo. Se vacía segundo a segundo sin refrescos de app.
struct LiveActivityTimerRingView: View {
    let window: LiveActivityRestWindow
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            if window.isRunning {
                ProgressView(timerInterval: window.range, countsDown: true)
                    .progressViewStyle(.circular)
                    .tint(LiveActivityTheme.timer)
                    .labelsHidden()
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

    var body: some View {
        if window.isRunning {
            Text(timerInterval: window.range, countsDown: true, showsHours: false)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(LiveActivityTheme.timer)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Text("00:00")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(LiveActivityTheme.timer)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// Fila "Serie 1: 80 kg × 10".
struct LiveActivitySetRowView: View {
    let set: LiveActivityCompletedSet
    let font: Font

    var body: some View {
        Text(LiveActivityFormat.setLabel(set))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Estado 1 · Maximizada

struct ExpandedExerciseSummaryView: View {
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if visibleSets.isEmpty {
                Text("Sin series completadas")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.gray)
                    .lineLimit(1)
            } else {
                ForEach(visibleSets) { set in
                    LiveActivitySetRowView(
                        set: set,
                        font: .system(size: 11, weight: .semibold, design: .monospaced)
                    )
                }
            }
        }
        .frame(alignment: .leading)
    }
}

struct ExpandedRestDialView: View {
    let state: WorkoutActivityAttributes.ContentState

    private var window: LiveActivityRestWindow {
        LiveActivityRestWindow(state: state)
    }

    var body: some View {
        ZStack {
            LiveActivityTimerRingView(window: window, diameter: 68, lineWidth: 5)

            VStack(spacing: 1) {
                LiveActivityTimerTextView(
                    window: window,
                    font: .system(size: 15, weight: .bold, design: .monospaced)
                )

                Text("\(LiveActivityFormat.bpm(state.currentBPM)) BPM")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LiveActivityTheme.heart)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: 68, height: 68)
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

            LiveActivityTimerTextView(
                window: window,
                font: .system(size: 12, weight: .semibold, design: .monospaced)
            )
            .frame(minWidth: 28, maxWidth: 38, alignment: .leading)
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
            LiveActivityTimerRingView(window: window, diameter: 24, lineWidth: 3)

            Text(LiveActivityFormat.bpm(state.currentBPM))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LiveActivityTheme.heart)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Pantalla de bloqueo

struct LockScreenLiveActivityView: View {
    let state: WorkoutActivityAttributes.ContentState
    let workoutName: String

    private var window: LiveActivityRestWindow {
        LiveActivityRestWindow(state: state)
    }

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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if visibleSets.isEmpty {
                    Text("Sin series completadas")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.gray)
                        .lineLimit(1)
                } else {
                    ForEach(visibleSets) { set in
                        LiveActivitySetRowView(
                            set: set,
                            font: .system(size: 12, weight: .semibold, design: .monospaced)
                        )
                    }
                }
            }

            Spacer(minLength: 6)

            ZStack {
                LiveActivityTimerRingView(window: window, diameter: 68, lineWidth: 5)

                VStack(spacing: 1) {
                    LiveActivityTimerTextView(
                        window: window,
                        font: .system(size: 15, weight: .bold, design: .monospaced)
                    )

                    Text("\(LiveActivityFormat.bpm(state.currentBPM)) BPM")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LiveActivityTheme.heart)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 6)
            }
            .frame(width: 68, height: 68)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
