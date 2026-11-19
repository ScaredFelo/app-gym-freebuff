import SwiftUI

/// Configuración de la modalidad manual: número de rutinas vacías que se
/// crearán al confirmar. No añade ejercicios automáticamente.
struct CreateOwnRoutinesView: View {
    let chrome: OnboardingChrome
    @ObservedObject var viewModel: RoutineConfigurationViewModel
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "Crear mis propias rutinas",
            subtitle: "Define cuántas estructuras vacías quieres tener disponibles. Después las editas a tu ritmo.",
            footer: footer
        ) {
            TacticalPanel(code: "ORG.01", title: "Estructuras a crear", contentPadding: 12.0) {
                VStack(alignment: .leading, spacing: 10.0) {
                    HStack(spacing: 8.0) {
                        Text("NÚMERO DE RUTINAS")
                            .font(EndfieldFont.label(9.0))
                            .tracking(0.8)
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Spacer(minLength: 4.0)

                        Text("\(viewModel.plan.clampedRoutineCount)")
                            .font(EndfieldFont.mono(20.0, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(EndfieldPalette.accentYellow)
                            .fixedSize()
                    }

                    Stepper(
                        value: $viewModel.plan.ownRoutineCount,
                        in: RoutinePlanDraft.routineCountRange,
                        step: 1
                    ) {
                        Text("Ajustar número de rutinas: \(viewModel.plan.clampedRoutineCount)")
                            .font(EndfieldFont.mono(9.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .tint(EndfieldPalette.accentYellow)

                    Rectangle()
                        .fill(EndfieldPalette.borderSubtle)
                        .frame(height: 1.0)

                    VStack(spacing: 5.0) {
                        ForEach(0..<viewModel.plan.clampedRoutineCount, id: \.self) { (index: Int) in
                            HStack(spacing: 8.0) {
                                Text(viewModel.plan.routineCode(at: index))
                                    .font(EndfieldFont.label(8.0))
                                    .tracking(1.0)
                                    .foregroundStyle(EndfieldPalette.accentYellow)
                                    .fixedSize()

                                Text(viewModel.plan.routineName(at: index).uppercased())
                                    .font(EndfieldFont.mono(10.0, weight: .semibold))
                                    .foregroundStyle(EndfieldPalette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)

                                Spacer(minLength: 4.0)

                                Text("VACÍA")
                                    .font(EndfieldFont.label(7.0))
                                    .tracking(0.8)
                                    .foregroundStyle(EndfieldPalette.textSecondary)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 9.0)
                            .padding(.vertical, 7.0)
                            .background(
                                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                                    .fill(EndfieldPalette.bgElevated)
                            )
                        }
                    }
                }
            }

            OnboardingIntegrationPlaceholder(
                code: "EDIT.02",
                title: "Añadir ejercicios",
                message: "Las rutinas se crean vacías. Podrás añadir y ordenar ejercicios desde la pestaña Rutinas una vez confirmada la configuración.",
                symbolName: "list.bullet.rectangle"
            )
        }
    }

    private var footer: AnyView {
        return AnyView(
            OnboardingPrimaryFooter(title: "CONTINUAR AL RESUMEN") {
                onContinue()
            }
        )
    }
}
