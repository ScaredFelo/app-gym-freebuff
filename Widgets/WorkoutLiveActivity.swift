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
            // Pantalla de bloqueo / banner del sistema.
            LockScreenLiveActivityView(
                state: context.state,
                workoutName: context.attributes.workoutName
            )
            .activityBackgroundTint(EndfieldPalette.bgPrimary)
            .activitySystemActionForegroundColor(EndfieldPalette.accentYellow)
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
                // Estado 2 · Compacta: marca táctica + cuenta atrás.
                CompactRestTimerView(state: context.state)
            } compactTrailing: {
                // Estado 2 · Compacta: cuadrado rojo + BPM.
                CompactBPMView(bpm: context.state.currentBPM)
            } minimal: {
                // Estado 3 · Minimizada: BPM y barra de descanso.
                MinimalBPMTimerView(state: context.state)
            }
            .keylineTint(EndfieldPalette.accentYellow)
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

    /// Etiqueta de serie compacta de consola: `S-01 · 60KG × 8`.
    static func setRow(_ set: LiveActivityCompletedSet) -> String {
        return String(
            format: "S-%02d · %@KG × %d",
            set.id,
            weightText(set.weight),
            set.reps
        )
    }
}

// MARK: - Formas y piezas de la identidad

/// Esquina cortada a 45° equivalente a `ChamferedRectangle` de la app.
private struct WidgetChamfer: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let limit: CGFloat = min(rect.width, rect.height) * 0.5
        let corner: CGFloat = min(cut, limit)

        var path: Path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - corner))
        path.closeSubpath()
        return path
    }
}

/// Etiqueta de código tipo `EX`.
private struct WidgetTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(EndfieldFont.label(8.0))
            .tracking(1.0)
            .foregroundStyle(tint)
            .padding(.horizontal, 4.0)
            .padding(.vertical, 1.5)
            .overlay {
                WidgetChamfer(cut: 2.5)
                    .stroke(tint.opacity(0.55), lineWidth: 1.0)
            }
    }
}

/// Barra de progreso nativa que se vacía sin refrescos de la app.
struct LiveActivityTimerBarView: View {
    let window: LiveActivityRestWindow
    let height: CGFloat
    let tint: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(EndfieldPalette.bgElevated)
                .frame(height: height)

            if window.isRunning {
                ProgressView(
                    timerInterval: window.range,
                    countsDown: true,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
                .progressViewStyle(.linear)
                .tint(tint)
                .frame(height: height)
                .clipped()
            } else {
                Rectangle()
                    .fill(tint.opacity(0.35))
                    .frame(height: height)
            }
        }
        .frame(height: height)
    }
}

/// Cuenta atrás digital nativa; "00:00" cuando no hay descanso corriendo.
struct LiveActivityTimerTextView: View {
    let window: LiveActivityRestWindow
    let font: Font
    let tint: Color

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
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Fila de serie registrada.
struct LiveActivitySetRowView: View {
    let set: LiveActivityCompletedSet
    let font: Font
    let tint: Color

    var body: some View {
        Text(LiveActivityFormat.setRow(set))
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
        VStack(alignment: .leading, spacing: 6.0) {
            headerRow

            Rectangle()
                .fill(EndfieldPalette.accentYellow.opacity(0.55))
                .frame(height: 1.0)

            HStack(alignment: .top, spacing: 10.0) {
                VStack(alignment: .leading, spacing: 3.0) {
                    if visibleSets.isEmpty {
                        Text("SIN SERIES REGISTRADAS")
                            .font(EndfieldFont.mono(11.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .lineLimit(1)
                    } else {
                        ForEach(visibleSets) { set in
                            LiveActivitySetRowView(
                                set: set,
                                font: EndfieldFont.mono(11.0, weight: .medium),
                                tint: EndfieldPalette.textPrimary.opacity(0.9)
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                RestDialView(state: state, width: 96.0)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6.0) {
            WidgetTag(text: "EX", tint: EndfieldPalette.accentYellow)

            Text(title.uppercased())
                .font(EndfieldFont.mono(14.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4.0)

            Rectangle()
                .fill(EndfieldPalette.accentRed)
                .frame(width: 5.0, height: 5.0)

            Text("LIVE")
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.accentRed)
        }
    }
}

/// Bloque de telemetría de descanso: cuenta atrás + barra + pulso.
struct RestDialView: View {
    let state: WorkoutActivityAttributes.ContentState
    var width: CGFloat = 104.0

    private var window: LiveActivityRestWindow {
        LiveActivityRestWindow(state: state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4.0) {
            Text("REST")
                .font(EndfieldFont.label(8.0))
                .tracking(1.2)
                .foregroundStyle(EndfieldPalette.textSecondary)

            LiveActivityTimerTextView(
                window: window,
                font: EndfieldFont.mono(19.0, weight: .heavy),
                tint: EndfieldPalette.accentYellow
            )

            LiveActivityTimerBarView(
                window: window,
                height: 3.0,
                tint: EndfieldPalette.accentYellow
            )

            HStack(spacing: 4.0) {
                Rectangle()
                    .fill(EndfieldPalette.accentRed)
                    .frame(width: 4.0, height: 4.0)

                Text(LiveActivityFormat.bpmWithUnit(state.currentBPM))
                    .font(EndfieldFont.label(9.0))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.accentRed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(7.0)
        .frame(width: width, alignment: .leading)
        .background(EndfieldPalette.bgPanel)
        .clipShape(WidgetChamfer(cut: 6.0))
        .overlay {
            WidgetChamfer(cut: 6.0)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }
}

// MARK: - Estado 2 · Normal / Compacta

struct CompactRestTimerView: View {
    let state: WorkoutActivityAttributes.ContentState

    private var window: LiveActivityRestWindow {
        LiveActivityRestWindow(state: state)
    }

    var body: some View {
        HStack(spacing: 4.0) {
            Rectangle()
                .fill(EndfieldPalette.accentYellow)
                .frame(width: 2.0, height: 13.0)

            LiveActivityTimerTextView(
                window: window,
                font: EndfieldFont.mono(12.0, weight: .heavy),
                tint: EndfieldPalette.accentYellow
            )
            .frame(minWidth: 30.0, maxWidth: 42.0, alignment: .leading)
        }
        .padding(.leading, 1.0)
    }
}

struct CompactBPMView: View {
    let bpm: Int

    var body: some View {
        HStack(spacing: 3.0) {
            Rectangle()
                .fill(EndfieldPalette.accentRed)
                .frame(width: 4.0, height: 4.0)

            Text(LiveActivityFormat.bpm(bpm))
                .font(EndfieldFont.mono(13.0, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("BPM")
                .font(EndfieldFont.label(8.0))
                .tracking(0.6)
                .foregroundStyle(EndfieldPalette.accentRed)
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
        VStack(alignment: .center, spacing: 3.0) {
            Text(LiveActivityFormat.bpm(state.currentBPM))
                .font(EndfieldFont.mono(12.0, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.accentRed)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            LiveActivityTimerBarView(
                window: window,
                height: 2.0,
                tint: EndfieldPalette.accentYellow
            )
            .frame(width: 18.0)
        }
        .frame(width: 22.0)
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
        VStack(alignment: .leading, spacing: 7.0) {
            HStack(spacing: 6.0) {
                WidgetTag(text: "EX", tint: EndfieldPalette.accentYellow)

                Text(title.uppercased())
                    .font(EndfieldFont.mono(17.0, weight: .heavy))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 6.0)

                Rectangle()
                    .fill(EndfieldPalette.accentRed)
                    .frame(width: 5.0, height: 5.0)

                Text("LIVE")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.accentRed)
            }

            Rectangle()
                .fill(EndfieldPalette.accentYellow.opacity(0.55))
                .frame(height: 1.0)

            HStack(alignment: .top, spacing: 12.0) {
                VStack(alignment: .leading, spacing: 3.0) {
                    if visibleSets.isEmpty {
                        Text("SIN SERIES REGISTRADAS")
                            .font(EndfieldFont.mono(11.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .lineLimit(1)
                    } else {
                        ForEach(visibleSets) { set in
                            LiveActivitySetRowView(
                                set: set,
                                font: EndfieldFont.mono(12.0, weight: .medium),
                                tint: EndfieldPalette.textPrimary.opacity(0.9)
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                RestDialView(state: state, width: 118.0)
            }
        }
        .padding(.horizontal, 14.0)
        .padding(.vertical, 11.0)
    }
}
