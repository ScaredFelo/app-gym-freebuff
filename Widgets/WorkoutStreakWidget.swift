import SwiftUI
import WidgetKit

// MARK: - Entrada de timeline

struct WorkoutStreakEntry: TimelineEntry {
    let date: Date
    let snapshot: WorkoutStreakSnapshot
}

// MARK: - Provider

struct WorkoutStreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutStreakEntry {
        return WorkoutStreakEntry(date: Date(), snapshot: WorkoutStreakSnapshot.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutStreakEntry) -> Void) {
        let entry: WorkoutStreakEntry = WorkoutStreakEntry(
            date: Date(),
            snapshot: WidgetStreakStore.currentSnapshot()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutStreakEntry>) -> Void) {
        let now: Date = Date()
        let weekChange: Date = WidgetStreakStore.nextWeekStart(after: now)
        // Dos entradas: ahora y el lunes a las 00:00 exactas. Con `.atEnd` el
        // cambio de semana no depende del cupo de recargas de WidgetKit, que
        // recorta la política de una hora.
        let entries: [WorkoutStreakEntry] = [
            WorkoutStreakEntry(date: now, snapshot: WidgetStreakStore.currentSnapshot(now: now)),
            WorkoutStreakEntry(date: weekChange, snapshot: WidgetStreakStore.currentSnapshot(now: weekChange))
        ]
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Widget

struct WorkoutStreakWidget: Widget {
    let kind: String = "WorkoutStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutStreakProvider()) { (entry: WorkoutStreakEntry) in
            WorkoutStreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Racha y objetivo")
        .description("Semanas consecutivas cumpliendo el objetivo y días entrenados.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Contenedor

struct WorkoutStreakWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    let entry: WorkoutStreakEntry

    var body: some View {
        Group {
            switch widgetFamily {
            case .systemMedium:
                WorkoutStreakMediumView(snapshot: entry.snapshot)
            default:
                WorkoutStreakSmallView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(EndfieldPalette.bgPrimary, for: .widget)
    }
}

// MARK: - Tamaño pequeño

struct WorkoutStreakSmallView: View {
    let snapshot: WorkoutStreakSnapshot

    private var goal: Int {
        return max(snapshot.weeklyGoal, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5.0) {
            headerRow

            Spacer(minLength: 0.0)

            HStack(alignment: .firstTextBaseline, spacing: 5.0) {
                Text("\(snapshot.weekStreak)")
                    .font(EndfieldFont.mono(38.0, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                VStack(alignment: .leading, spacing: 0.0) {
                    Text("SEMANAS")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("EN RACHA")
                        .font(EndfieldFont.label(7.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 0.0)

            VStack(alignment: .leading, spacing: 4.0) {
                Text("ESTA SEMANA: \(snapshot.currentWeekWorkouts)/\(goal)")
                    .font(EndfieldFont.mono(9.0, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                WorkoutStreakProgressBar(
                    progress: snapshot.goalProgress,
                    height: 5.0,
                    segments: 0
                )
            }
        }
        .padding(9.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StreakPanelChrome(cut: 8.0))
    }

    private var headerRow: some View {
        HStack(spacing: 4.0) {
            Rectangle()
                .fill(EndfieldPalette.accentYellow)
                .frame(width: 4.0, height: 8.0)

            Text("STREAK // GOAL")
                .font(EndfieldFont.label(8.0))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if !WidgetStreakStore.isSharedStorageAvailable {
                Text("SIN SYNC")
                    .font(EndfieldFont.label(7.0))
                    .tracking(0.6)
                    .foregroundStyle(EndfieldPalette.accentRed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer(minLength: 0.0)
        }
    }
}

// MARK: - Tamaño mediano

struct WorkoutStreakMediumView: View {
    let snapshot: WorkoutStreakSnapshot

    private var goal: Int {
        return max(snapshot.weeklyGoal, 1)
    }

    private var weekdays: [Bool] {
        return snapshot.weekdays
    }

    /// Sin App Group el widget no puede leer nada de la app: se avisa en vez
    /// de pintar ceros como si fueran datos reales.
    private var goalTitle: String {
        if WidgetStreakStore.isSharedStorageAvailable {
            return "OBJETIVO SEMANAL // \(snapshot.currentWeekWorkouts) DE \(goal) DÍAS"
        }
        return "SIN SYNC // ABRE LA APP"
    }

    var body: some View {
        HStack(spacing: 10.0) {
            streakBox

            VStack(alignment: .leading, spacing: 7.0) {
                Text(goalTitle)
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.7)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                weekdayRow

                Spacer(minLength: 0.0)

                VStack(alignment: .leading, spacing: 4.0) {
                    WorkoutStreakProgressBar(
                        progress: snapshot.goalProgress,
                        height: 8.0,
                        segments: goal
                    )

                    Text("\(snapshot.currentWeekWorkouts)/\(goal) DÍAS COMPLETADOS")
                        .font(EndfieldFont.label(7.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(StreakPanelChrome(cut: 8.0))
    }

    private var streakBox: some View {
        VStack(alignment: .center, spacing: 2.0) {
            Text("\(snapshot.weekStreak)")
                .font(EndfieldFont.mono(40.0, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.accentYellow)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("SEMANAS EN RACHA")
                .font(EndfieldFont.label(7.0))
                .tracking(0.6)
                .multilineTextAlignment(.center)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
        }
        .padding(8.0)
        .frame(width: 82.0)
        .frame(maxHeight: .infinity)
        .background(EndfieldPalette.bgPanel)
        .clipShape(StreakChamfer(cut: 5.0))
        .overlay {
            StreakChamfer(cut: 5.0)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 3.0) {
            ForEach(0..<7, id: \.self) { (index: Int) in
                weekdayCell(index: index)
            }
        }
    }

    private func weekdayCell(index: Int) -> some View {
        let isTrained: Bool = index >= 0 && index < weekdays.count ? weekdays[index] : false
        let symbol: String = WorkoutStreakSnapshot.weekdaySymbols[index]

        return Text(symbol)
            .font(EndfieldFont.label(8.0, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(isTrained ? EndfieldPalette.bgPrimary : EndfieldPalette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 22.0, height: 22.0)
            .background(isTrained ? EndfieldPalette.accentYellow : EndfieldPalette.bgElevated)
            .clipShape(StreakChamfer(cut: 2.0))
            .overlay {
                StreakChamfer(cut: 2.0)
                    .stroke(
                        isTrained ? EndfieldPalette.accentYellow : EndfieldPalette.borderSubtle,
                        lineWidth: 1.0
                    )
            }
    }
}

// MARK: - Barra de progreso

struct WorkoutStreakProgressBar: View {
    let progress: Double
    var height: CGFloat = 6.0
    /// `0` o `1` dibujan una barra continua; más de 1, una barra segmentada.
    var segments: Int = 0

    var body: some View {
        let clamped: Double = min(max(progress, 0.0), 1.0)
        let barHeight: CGFloat = max(height, 1.0)
        let segmentCount: Int = segments
        let tint: Color = EndfieldPalette.accentYellow
        let track: Color = EndfieldPalette.bgElevated

        Canvas { context, size in
            let drawnHeight: CGFloat = min(barHeight, size.height)

            if segmentCount > 1 {
                let spacing: CGFloat = 2.0
                let totalSpacing: CGFloat = spacing * CGFloat(segmentCount - 1)
                let segmentWidth: CGFloat = max(0.0, (size.width - totalSpacing) / CGFloat(segmentCount))
                let litCount: Int = Int((clamped * Double(segmentCount)).rounded())

                var index: Int = 0
                while index < segmentCount {
                    let x: CGFloat = CGFloat(index) * (segmentWidth + spacing)
                    let rect: CGRect = CGRect(x: x, y: 0.0, width: segmentWidth, height: drawnHeight)
                    context.fill(Path(rect), with: .color(index < litCount ? tint : track))
                    index += 1
                }
            } else {
                let fullRect: CGRect = CGRect(x: 0.0, y: 0.0, width: size.width, height: drawnHeight)
                context.fill(Path(fullRect), with: .color(track))

                let fillWidth: CGFloat = size.width * CGFloat(clamped)
                if fillWidth > 0.0 {
                    let fillRect: CGRect = CGRect(x: 0.0, y: 0.0, width: fillWidth, height: drawnHeight)
                    context.fill(Path(fillRect), with: .color(tint))
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Piezas de la identidad táctica

/// Esquina cortada a 45° equivalente a `ChamferedRectangle` de la app.
struct StreakChamfer: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let limit: CGFloat = min(rect.width, rect.height) * 0.5
        let corner: CGFloat = min(max(cut, 0.0), limit)

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

/// Fondo mate, borde fino de 1 px y cruces `+` en las cuatro esquinas.
struct StreakPanelChrome: View {
    let cut: CGFloat

    var body: some View {
        let cornerCut: CGFloat = cut
        let fill: Color = EndfieldPalette.bgPrimary
        let stroke: Color = EndfieldPalette.borderSubtle
        let crossTint: Color = EndfieldPalette.accentYellow.opacity(0.55)
        let arm: CGFloat = 6.0
        let inset: CGFloat = 4.0

        Canvas { context, size in
            let bounds: CGRect = CGRect(origin: .zero, size: size)
            let limit: CGFloat = min(bounds.width, bounds.height) * 0.5
            let corner: CGFloat = min(cornerCut, limit)

            var panel: Path = Path()
            panel.move(to: CGPoint(x: bounds.minX, y: bounds.minY))
            panel.addLine(to: CGPoint(x: bounds.maxX - corner, y: bounds.minY))
            panel.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY + corner))
            panel.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
            panel.addLine(to: CGPoint(x: bounds.minX + corner, y: bounds.maxY))
            panel.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY - corner))
            panel.closeSubpath()

            context.fill(panel, with: .color(fill))
            context.stroke(panel, with: .color(stroke), lineWidth: 1.0)

            let thickness: CGFloat = 1.0
            let centers: [CGPoint] = [
                CGPoint(x: inset + arm / 2.0, y: inset + arm / 2.0),
                CGPoint(x: size.width - inset - arm / 2.0, y: inset + arm / 2.0),
                CGPoint(x: inset + arm / 2.0, y: size.height - inset - arm / 2.0),
                CGPoint(x: size.width - inset - arm / 2.0, y: size.height - inset - arm / 2.0)
            ]

            var crosses: Path = Path()
            for center in centers {
                crosses.addRect(
                    CGRect(
                        x: center.x - arm / 2.0,
                        y: center.y - thickness / 2.0,
                        width: arm,
                        height: thickness
                    )
                )
                crosses.addRect(
                    CGRect(
                        x: center.x - thickness / 2.0,
                        y: center.y - arm / 2.0,
                        width: thickness,
                        height: arm
                    )
                )
            }

            context.fill(crosses, with: .color(crossTint))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
