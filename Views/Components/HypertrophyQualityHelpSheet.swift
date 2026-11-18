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
                TechnicalGridBackground()

                ScrollView {
                    VStack(spacing: 10.0) {
                        HazardStripeBar(height: 6.0)
                            .padding(.horizontal, -16.0)

                        header

                        ForEach(Array(Self.metrics.enumerated()), id: \.element.id) { index, metric in
                            HypertrophyMetricHelpCard(
                                metric: metric,
                                code: String(format: "HYP.%02d", index + 1)
                            )
                        }
                    }
                    .padding(.horizontal, 16.0)
                    .padding(.top, 8.0)
                    .padding(.bottom, 24.0)
                }
            }
            .navigationTitle("HYP // TELEMETRÍA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.accentYellow)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5.0) {
            Text("MANUAL DE INTERPRETACIÓN // MÉTRICAS CARDIOVASCULARES Y DE CARGA")
                .font(EndfieldFont.label(9.0))
                .tracking(1.2)
                .foregroundStyle(EndfieldPalette.accentYellow)
                .fixedSize(horizontal: false, vertical: true)

            Text("Cómo interpretar tus métricas cardiovasculares y de carga durante la sesión.")
                .font(EndfieldFont.mono(10.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Tarjeta de métrica

/// Tarjeta independiente con los cinco puntos explicativos de una métrica.
struct HypertrophyMetricHelpCard: View {
    let metric: HypertrophyMetricHelp
    let code: String

    var body: some View {
        TacticalPanel(code: code, title: metric.title, contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 9.0) {
                HStack(spacing: 6.0) {
                    Image(systemName: metric.icon)
                        .font(EndfieldFont.mono(10.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.accentYellow)

                    Text(metric.units.uppercased())
                        .font(EndfieldFont.label(8.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textSecondary)
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
        }
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
        VStack(alignment: .leading, spacing: 2.0) {
            HStack(spacing: 5.0) {
                Rectangle()
                    .fill(EndfieldPalette.accentYellow.opacity(0.7))
                    .frame(width: 3.0, height: 3.0)

                Text(label.uppercased())
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.accentYellow.opacity(0.9))
            }

            Text(text)
                .font(EndfieldFont.mono(10.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
