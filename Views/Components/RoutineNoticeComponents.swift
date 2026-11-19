import SwiftUI

// MARK: - Modelo del aviso

/// Aviso informativo previo a la confirmación de una distribución semanal.
///
/// Los generadores de las fases 02 y 03 crearán estos avisos; esta fase solo
/// aporta el modelo y el componente visual reutilizable. No contienen umbrales
/// inventados ni bloquean la confirmación.
struct RoutineNotice: Identifiable {
    enum Kind {
        case muscleRecovery
        case fatigue

        var code: String {
            switch self {
            case .muscleRecovery:
                return "REC.01"
            case .fatigue:
                return "FRQ.01"
            }
        }

        var title: String {
            switch self {
            case .muscleRecovery:
                return "Recuperación muscular"
            case .fatigue:
                return "Frecuencia y solapamiento"
            }
        }

        var symbolName: String {
            switch self {
            case .muscleRecovery:
                return "clock.arrow.circlepath"
            case .fatigue:
                return "bolt.trianglebadge.exclamationmark"
            }
        }

        var tint: Color {
            switch self {
            case .muscleRecovery:
                return EndfieldPalette.accentCyan
            case .fatigue:
                return EndfieldPalette.accentRed
            }
        }
    }

    let id: UUID
    let kind: Kind
    /// Días implicados (por ejemplo, «LUNES», «MIÉRCOLES»).
    let involvedDays: [String]
    /// Rutinas afectadas por el aviso.
    let affectedRoutines: [String]
    /// Grupos musculares que podrían solaparse (vacío en la alerta de fatiga).
    let muscleGroups: [String]
    /// Motivo del aviso.
    let reason: String
    /// Recomendación adicional (solo en la alerta de fatiga).
    let recommendation: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        involvedDays: [String],
        affectedRoutines: [String],
        muscleGroups: [String] = [],
        reason: String,
        recommendation: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.involvedDays = involvedDays
        self.affectedRoutines = affectedRoutines
        self.muscleGroups = muscleGroups
        self.reason = reason
        self.recommendation = recommendation
    }

    /// Aviso de recuperación muscular: sesiones que trabajan el mismo grupo sin
    /// el descanso aproximado de 48 horas.
    static func muscleRecovery(
        involvedDays: [String],
        affectedRoutines: [String],
        muscleGroups: [String],
        reason: String
    ) -> RoutineNotice {
        return RoutineNotice(
            kind: .muscleRecovery,
            involvedDays: involvedDays,
            affectedRoutines: affectedRoutines,
            muscleGroups: muscleGroups,
            reason: reason
        )
    }

    /// Alerta de fatiga: distribución que puede acumular una carga elevada.
    static func fatigue(
        involvedDays: [String],
        affectedRoutines: [String],
        reason: String,
        recommendation: String
    ) -> RoutineNotice {
        return RoutineNotice(
            kind: .fatigue,
            involvedDays: involvedDays,
            affectedRoutines: affectedRoutines,
            reason: reason,
            recommendation: recommendation
        )
    }
}

// MARK: - Componente visual

/// Banner reutilizable para los avisos de recuperación y fatiga. Puede
/// insertarse tanto en el generador automático como en el constructor asistido
/// y en el resumen.
struct RoutineNoticeBanner: View {
    let notice: RoutineNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 9.0) {
            HStack(spacing: 7.0) {
                Image(systemName: notice.kind.symbolName)
                    .font(EndfieldFont.mono(12.0, weight: .bold))
                    .foregroundStyle(notice.kind.tint)
                    .fixedSize()

                Text(notice.kind.code)
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(notice.kind.tint)

                Text(notice.kind.title.uppercased())
                    .font(EndfieldFont.label(9.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4.0)
            }

            chipRow(label: "DÍAS", values: notice.involvedDays)
            chipRow(label: "RUTINAS", values: notice.affectedRoutines)

            if !notice.muscleGroups.isEmpty {
                chipRow(label: "GRUPOS", values: notice.muscleGroups)
            }

            labelBlock(label: "MOTIVO", text: notice.reason)

            if let recommendation = notice.recommendation {
                labelBlock(label: "RECOMENDACIÓN", text: recommendation)
            }

            Text("Aviso informativo: no bloquea la confirmación.")
                .font(EndfieldFont.label(7.0))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .fill(EndfieldPalette.bgPanel)
        )
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .stroke(notice.kind.tint.opacity(0.45), lineWidth: 1.0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notice.kind.title): \(notice.reason)")
    }

    private func chipRow(label: String, values: [String]) -> some View {
        HStack(alignment: .top, spacing: 8.0) {
            Text(label)
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .frame(width: 58.0, alignment: .leading)
                .fixedSize()

            if values.isEmpty {
                Text("—")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
            } else {
                FlowChipsView(values: values, tint: notice.kind.tint)
            }
        }
    }

    private func labelBlock(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3.0) {
            Text(label)
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary)

            Text(text)
                .font(EndfieldFont.mono(9.0))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Chips

/// Etiquetas técnicas en una fila con salto automático.
struct FlowChipsView: View {
    let values: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4.0) {
            ForEach(rows.indices, id: \.self) { (rowIndex: Int) in
                HStack(spacing: 4.0) {
                    ForEach(rows[rowIndex], id: \.self) { (value: String) in
                        TacticalTagBadge(text: value, tint: tint)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Reparte los valores en filas de tres para no desbordar pantallas
    /// pequeñas.
    private var rows: [[String]] {
        var result: [[String]] = []
        var current: [String] = []

        for value in values {
            current.append(value)
            if current.count == 3 {
                result.append(current)
                current = []
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }
}
