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
    /// Referencia semanal de cardio aerobio. La barra de cardio se mide contra
    /// este valor fijo (y no contra su propio total) para que cada sesión
    /// alargue la barra en lugar de quedar siempre llena.
    private static let cardioReferenceMinutes: Int = 150

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

            // Minutos de cardio registrados en los bloques cronometrados de la
            // sesión (máquina de cardio dentro de una rutina).
            var loggedCardioMinutes: Int = 0
            // Series de fuerza completadas: una sesión con carga no puede
            // aportar su duración completa como minutos de cardio.
            var completedStrengthSets: Int = 0

            for log in session.setsCompleted {
                guard log.isCompleted else { continue }
                guard let exercise: Exercise = log.exercise else { continue }

                let groups: [MuscleGroup] = exercise.primaryMuscles.isEmpty
                    ? [exercise.muscleGroup]
                    : exercise.primaryMuscles

                // El cardio no se mide en series: se suman los minutos
                // registrados por el cronómetro de cada bloque.
                if exercise.trackingMode == .minutes || groups.contains(.cardio) {
                    loggedCardioMinutes += max(0, log.reps)
                    continue
                }

                completedStrengthSets += 1
                for group in groups {
                    totals[group, default: 0] += 1
                }
            }

            // La pantalla de cardio guarda la sesión como un único bloque de
            // tiempo, sin series ni ejercicios asociados: sus minutos salen de
            // la duración del cronómetro.
            if loggedCardioMinutes > 0 {
                cardioMinutes += loggedCardioMinutes
            } else if completedStrengthSets == 0 && session.isCardioSession {
                let duration: TimeInterval = max(0.0, endDate.timeIntervalSince(session.startDate))
                cardioMinutes += max(0, Int((duration / 60.0).rounded()))
            }
        }

        // Las series se comparan con su propio máximo; el cardio, con la
        // referencia semanal fija, para que sumar minutos siempre se note.
        let setsScale: Int = max(12, totals.values.max() ?? 0)
        let minutesScale: Int = max(Self.cardioReferenceMinutes, cardioMinutes)

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
