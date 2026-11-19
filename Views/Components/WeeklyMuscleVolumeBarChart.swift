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

        VStack(alignment: .leading, spacing: 8.0) {
            Text("VOLUMEN SEMANAL // SERIES Y MINUTOS DE CARDIO")
                .font(EndfieldFont.label(9.0, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.accentYellow)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            VStack(spacing: Self.barSpacing) {
                ForEach(items) { (item: WeeklyMuscleVolumeItem) in
                    WeeklyMuscleVolumeRow(
                        item: item,
                        labelWidth: Self.labelWidth,
                        barHeight: Self.barHeight
                    )
                }
            }
        }
    }

    // MARK: Cálculo

    /// Suma las series completadas de los últimos 7 días por grupo muscular
    /// principal y los minutos de cardio por separado. Devuelve siempre todos
    /// los grupos, incluidos los que van a 0.
    private func computeItems() -> [WeeklyMuscleVolumeItem] {
        let now: Date = Date()
        let windowStart: Date = now.addingTimeInterval(-7.0 * 86400.0)

        var totals: [MuscleGroup: Int] = [:]
        var cardioMinutes: Int = 0
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

                // El cardio no se mide en series: se suman los minutos
                // registrados por el cronómetro de cada bloque.
                if exercise.trackingMode == .minutes || groups.contains(.cardio) {
                    cardioMinutes += max(0, log.reps)
                    continue
                }

                for group in groups {
                    totals[group, default: 0] += 1
                }
            }
        }

        // Series y minutos viven en escalas distintas: cada unidad se compara
        // con su propio máximo para que la fila de cardio siga siendo legible.
        let setsScale: Int = max(12, totals.values.max() ?? 0)
        let minutesScale: Int = max(60, cardioMinutes)

        return MuscleGroup.allCases.map { (group: MuscleGroup) -> WeeklyMuscleVolumeItem in
            if group == .cardio {
                return WeeklyMuscleVolumeItem(
                    group: group,
                    value: cardioMinutes,
                    unitSuffix: " min",
                    scale: minutesScale
                )
            }

            return WeeklyMuscleVolumeItem(
                group: group,
                value: totals[group] ?? 0,
                unitSuffix: "",
                scale: setsScale
            )
        }
    }
}

// MARK: - Modelo de fila

struct WeeklyMuscleVolumeItem: Identifiable {
    let group: MuscleGroup
    /// Series completadas o, en cardio, minutos acumulados.
    let value: Int
    /// Sufijo de la unidad cuando el valor no son series (` min`).
    let unitSuffix: String
    /// Escala propia de la unidad de la fila.
    let scale: Int

    var id: String {
        return group.rawValue
    }
}

// MARK: - Fila

struct WeeklyMuscleVolumeRow: View {
    let item: WeeklyMuscleVolumeItem
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
                let scale: CGFloat = CGFloat(max(item.scale, 1))
                let ratio: CGFloat = min(max(CGFloat(item.value) / scale, 0.0), 1.0)
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

                    Text("\(item.value)\(item.unitSuffix)")
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
        if item.value <= 0 {
            return EndfieldPalette.textPrimary
        }
        return fillWidth >= 24.0 ? EndfieldPalette.bgPrimary : EndfieldPalette.textPrimary
    }
}
