import SwiftUI

// MARK: - Gráfica horizontal de volumen semanal

/// Barras horizontales de series completadas por grupo muscular en los
/// últimos 7 días. Sustituye la gráfica de columnas anterior manteniendo la
/// estética táctica: barras finas, esquinas biseladas y contador monospaciado.
struct WeeklyMuscleVolumeBarChart: View {
    let sessions: [WorkoutSession]

    private static let labelWidth: CGFloat = 118.0
    private static let barHeight: CGFloat = 22.0
    private static let barSpacing: CGFloat = 4.0

    var body: some View {
        let items: [WeeklyMuscleVolumeItem] = computeItems()
        let scale: Int = maxScale(for: items)

        VStack(alignment: .leading, spacing: 8.0) {
            Text("VOLUMEN DE SERIES SEMANALES (ÚLTIMOS 7 DÍAS)")
                .font(EndfieldFont.label(9.0, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.accentYellow)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            VStack(spacing: Self.barSpacing) {
                ForEach(items) { (item: WeeklyMuscleVolumeItem) in
                    WeeklyMuscleVolumeRow(
                        item: item,
                        maxScale: scale,
                        labelWidth: Self.labelWidth,
                        barHeight: Self.barHeight
                    )
                }
            }
        }
    }

    // MARK: Cálculo

    /// Suma las series completadas de los últimos 7 días por grupo muscular
    /// principal. Devuelve siempre todos los grupos, incluidos los que van a 0.
    private func computeItems() -> [WeeklyMuscleVolumeItem] {
        let now: Date = Date()
        let windowStart: Date = now.addingTimeInterval(-7.0 * 86400.0)

        var totals: [MuscleGroup: Int] = [:]
        for group in MuscleGroup.allCases {
            totals[group] = 0
        }

        for session in sessions {
            guard let endDate: Date = session.endDate else { continue }
            guard endDate >= windowStart && endDate <= now else { continue }

            for log in session.setsCompleted {
                guard log.isCompleted else { continue }
                guard let exercise: Exercise = log.exercise else { continue }

                let groups: [MuscleGroup] = exercise.primaryMuscles.isEmpty
                    ? [exercise.muscleGroup]
                    : exercise.primaryMuscles

                for group in groups {
                    totals[group, default: 0] += 1
                }
            }
        }

        return MuscleGroup.allCases.map { (group: MuscleGroup) -> WeeklyMuscleVolumeItem in
            return WeeklyMuscleVolumeItem(
                group: group,
                setsCount: totals[group] ?? 0
            )
        }
    }

    /// Escala mínima de 12 series para que las barras no saturen el ancho con
    /// volúmenes pequeños.
    private func maxScale(for items: [WeeklyMuscleVolumeItem]) -> Int {
        let maximum: Int = items.reduce(0) { (result: Int, item: WeeklyMuscleVolumeItem) -> Int in
            return max(result, item.setsCount)
        }
        return max(12, maximum)
    }
}

// MARK: - Modelo de fila

struct WeeklyMuscleVolumeItem: Identifiable {
    let group: MuscleGroup
    let setsCount: Int

    var id: String {
        return group.rawValue
    }
}

// MARK: - Fila

struct WeeklyMuscleVolumeRow: View {
    let item: WeeklyMuscleVolumeItem
    let maxScale: Int
    let labelWidth: CGFloat
    let barHeight: CGFloat

    var body: some View {
        HStack(spacing: 8.0) {
            Text(item.group.shortName.uppercased())
                .font(EndfieldFont.label(11.0, weight: .semibold))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: labelWidth, alignment: .trailing)

            GeometryReader { (proxy: GeometryProxy) in
                let available: CGFloat = max(proxy.size.width, 0.0)
                let scale: CGFloat = CGFloat(max(maxScale, 1))
                let ratio: CGFloat = min(max(CGFloat(item.setsCount) / scale, 0.0), 1.0)
                let fillWidth: CGFloat = available * ratio

                ZStack(alignment: .leading) {
                    ChamferedRectangle(cut: 2.0)
                        .fill(EndfieldPalette.bgElevated)

                    if fillWidth > 0.0 {
                        ChamferedRectangle(cut: 2.0)
                            .fill(EndfieldPalette.accentYellow)
                            .frame(width: fillWidth)
                    }

                    ChamferedRectangle(cut: 2.0)
                        .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)

                    Text("\(item.setsCount)")
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(numberColor(fillWidth: fillWidth))
                        .padding(.leading, 8.0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
        }
    }

    /// Negro sobre el relleno amarillo cuando la barra cubre el número; blanco
    /// cuando no hay relleno suficiente (o el valor es 0).
    private func numberColor(fillWidth: CGFloat) -> Color {
        if item.setsCount <= 0 {
            return EndfieldPalette.textPrimary
        }
        return fillWidth >= 24.0 ? EndfieldPalette.bgPrimary : EndfieldPalette.textPrimary
    }
}
