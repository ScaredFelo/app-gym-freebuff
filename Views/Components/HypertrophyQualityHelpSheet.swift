import SwiftUI

// MARK: - Modelo de ayuda

/// Contenido explicativo de una métrica de calidad de hipertrofia.
struct HypertrophyMetricHelp: Identifiable {
    let id: String
    let icon: String
    let title: String
    let summary: String
    let units: String
    let target: String
    let importance: String
}

// MARK: - Hoja de ayuda

/// Hoja modal con la explicación detallada de las métricas de la sección
/// "Calidad de hipertrofia" del review.
struct HypertrophyQualityHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private static let metrics: [HypertrophyMetricHelp] = [
        HypertrophyMetricHelp(
            id: "edwards",
            icon: "flame.fill",
            title: "Carga de Entrenamiento de Edwards",
            summary: "Suma los minutos pasados en cada zona de frecuencia cardíaca (del 50% al 100% de tu FC máxima) multiplicados por un factor de intensidad (×1 a ×5). Sirve para cuantificar el esfuerzo cardiovascular total acumulado en la sesión.",
            units: "UA (Unidades Arbitrarias / puntos de carga).",
            target: "60 – 150 UA en una sesión estándar de pesas de 45–75 min. Menos de 40 UA indica baja densidad o descansos muy largos; más de 180 UA de forma frecuente indica alta fatiga sistémica.",
            importance: "Permite comparar el desgaste interno real entre entrenamientos distintos y controlar la fatiga acumulada de la semana."
        ),
        HypertrophyMetricHelp(
            id: "trimp",
            icon: "waveform.path.ecg",
            title: "TRIMP (Training Impulse de Banister)",
            summary: "Calcula el impulso fisiológico total combinando la duración de la sesión con tu reserva cardíaca relativa (FC media respecto a FC reposo y FC máxima) mediante una curva exponencial que penaliza más los esfuerzos cerca del límite.",
            units: "Puntos TRIMP (UA).",
            target: "40 – 110 puntos TRIMP en rutinas de hipertrofia. En sesiones pesadas de pierna o espalda puede subir a 100 – 140.",
            importance: "Mide el estrés metabólico y autonómico real que soporta el cuerpo más allá de los kilos levantados."
        ),
        HypertrophyMetricHelp(
            id: "recovery",
            icon: "arrow.down.heart.fill",
            title: "Eficiencia de Recuperación entre Series",
            summary: "Mide la velocidad a la que bajan tus pulsaciones durante los descansos, comparando el pico al acabar una serie con el mínimo alcanzado antes de empezar la siguiente (HR Recovery / Drop Rate).",
            units: "BPM/min (latidos por minuto recuperados por cada minuto de descanso).",
            target: "≥ 20 – 35 BPM/min indica excelente recuperación y capacidad aeróbica; 12 – 20 BPM/min es habitual en series pesadas al fallo; menos de 12 BPM/min alerta de fatiga acumulada, estrés o descanso insuficiente.",
            importance: "Recuperar rápido el pulso entre series permite mantener la fuerza y el rendimiento mecánico en las siguientes series sin que la fatiga cardiovascular limite el estímulo muscular."
        ),
        HypertrophyMetricHelp(
            id: "density",
            icon: "scalemass.fill",
            title: "Densidad Cardiovascular Efectiva",
            summary: "Divide el tonelaje total levantado entre el impulso cardiovascular generado (kg levantados / TRIMP), mostrando cuánta carga mecánica útil produces por cada punto de estrés cardíaco.",
            units: "kg / TRIMP.",
            target: "≥ 80 – 150+ kg/TRIMP en sesiones con básicos multiarticulares pesados; 30 – 80 kg/TRIMP en rutinas de aislamiento o grupos pequeños. El objetivo clave es ver una tendencia ascendente en rutinas similares con el paso de las semanas.",
            importance: "Diferencia si una sesión fue dura porque moviste mucha carga mecánica efectiva (estímulo real de hipertrofia) o simplemente porque tu pulso estuvo elevado por fatiga, calor o falta de acondicionamiento."
        )
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        header

                        ForEach(Self.metrics) { (metric: HypertrophyMetricHelp) in
                            HypertrophyMetricHelpCard(metric: metric)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Calidad de hipertrofia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        Text("Cómo interpretar tus métricas cardiovasculares y de carga durante la sesión.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Tarjeta de métrica

/// Tarjeta independiente con los cinco puntos explicativos de una métrica.
struct HypertrophyMetricHelpCard: View {
    let metric: HypertrophyMetricHelp

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: metric.icon)
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .frame(width: 24, alignment: .center)

                Text(metric.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HypertrophyMetricHelpBlock(
                label: "Qué es",
                text: metric.summary
            )

            HypertrophyMetricHelpBlock(
                label: "Para qué sirve",
                text: paraQueSirve
            )

            HypertrophyMetricHelpBlock(
                label: "Unidades",
                text: metric.units
            )

            HypertrophyMetricHelpBlock(
                label: "Valores objetivo en hipertrofia",
                text: metric.target
            )

            HypertrophyMetricHelpBlock(
                label: "Por qué es importante",
                text: metric.importance
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var paraQueSirve: String {
        switch metric.id {
        case "edwards":
            return "Cuantificar el esfuerzo cardiovascular total acumulado en la sesión."
        case "trimp":
            return "Estimar el impulso fisiológico global de la sesión a partir de la duración y la intensidad cardíaca relativa."
        case "recovery":
            return "Valorar la velocidad de recuperación del pulso durante los descansos entre series."
        default:
            return "Relacionar la carga mecánica levantada con el coste cardiovascular que ha supuesto."
        }
    }
}

// MARK: - Bloque de texto

struct HypertrophyMetricHelpBlock: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.green)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
