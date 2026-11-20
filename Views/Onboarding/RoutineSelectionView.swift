import SwiftUI

/// Selección de la modalidad de organización del entrenamiento.
///
/// Elegir una tarjeta no crea rutinas ni guarda un plan: solo cambia el estado
/// en memoria. El guardado real ocurre en el resumen.
struct RoutineSelectionView: View {
    let chrome: OnboardingChrome
    @ObservedObject var viewModel: RoutineConfigurationViewModel
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "¿Cómo quieres organizar tu entrenamiento?",
            subtitle: "Elige una modalidad. Podrás volver atrás y cambiarla antes de continuar.",
            footer: footer
        ) {
            VStack(spacing: 10.0) {
                ForEach(viewModel.availableModes) { (mode: RoutineOrganizationMode) in
                    OnboardingChoiceCard(
                        code: mode.code,
                        title: mode.title,
                        caption: mode.summary,
                        symbolName: mode.symbolName,
                        isSelected: viewModel.plan.mode == mode,
                        tint: EndfieldPalette.accentYellow
                    ) {
                        OnboardingHaptics.selection()
                        viewModel.selectMode(mode)
                    }
                }
            }

            OnboardingInfoNote(text: noteText)
        }
    }

    private var noteText: String {
        let base: String = "Las modalidades son excluyentes. «Utilizar plantillas» abre el constructor de siete días; la generación automática usa la matriz W/L/U."

        if viewModel.availableModes.contains(.later) {
            return base + " «Crear mis rutinas más tarde» termina la configuración sin generar ninguna rutina. Las rutinas personales nunca se borran."
        }

        return base + " Las rutinas personales nunca se borran."
    }

    private var footer: AnyView {
        return AnyView(
            OnboardingPrimaryFooter(
                title: "CONTINUAR",
                isEnabled: viewModel.canContinueFromOrganization
            ) {
                onContinue()
            }
        )
    }
}
