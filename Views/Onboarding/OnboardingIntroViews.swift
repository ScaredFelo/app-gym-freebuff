import SwiftUI

// MARK: - Bienvenida

struct OnboardingWelcomeView: View {
    let chrome: OnboardingChrome
    @ObservedObject var viewModel: OnboardingViewModel
    let onSelect: (Bool) -> Void

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "¿Has utilizado AppGym anteriormente?",
            subtitle: "Configura la app en unos pasos. Nada se guarda hasta que confirmes el resumen final."
        ) {
            VStack(spacing: 10.0) {
                OnboardingChoiceCard(
                    code: "SETUP.01-A",
                    title: "Sí",
                    caption: "Tengo una copia de seguridad exportada desde AppGym.",
                    symbolName: "arrow.down.doc",
                    isSelected: viewModel.hasUsedAppPreviously == true
                ) {
                    onSelect(true)
                }

                OnboardingChoiceCard(
                    code: "SETUP.01-B",
                    title: "No",
                    caption: "Es la primera vez que uso AppGym.",
                    symbolName: "sparkles",
                    isSelected: viewModel.hasUsedAppPreviously == false
                ) {
                    onSelect(false)
                }
            }

            OnboardingInfoNote(
                text: "La copia de seguridad es un archivo JSON con tus rutinas, ejercicios, sesiones y ajustes. Se importa sin modificar su formato."
            )
        }
    }
}

// MARK: - Personalización

struct OnboardingPersonalizationView: View {
    let chrome: OnboardingChrome
    @ObservedObject var viewModel: OnboardingViewModel
    let onSelect: (OnboardingViewModel.PersonalizationChoice) -> Void

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "¿Quieres personalizar AppGym?",
            subtitle: "El equipamiento, las pulsaciones y la organización del entrenamiento se configuran una sola vez."
        ) {
            VStack(spacing: 10.0) {
                OnboardingChoiceCard(
                    code: "CFG.02-A",
                    title: "Sí, personalizar",
                    caption: "Configura barras, discos, pulsaciones y cómo quieres organizar tus rutinas.",
                    symbolName: "slider.horizontal.3",
                    isSelected: viewModel.personalizationChoice == .customize
                ) {
                    onSelect(.customize)
                }

                OnboardingChoiceCard(
                    code: "CFG.02-B",
                    title: "No, continuar con la configuración predeterminada",
                    caption: "Se usan los valores actuales de equipamiento y pulsaciones.",
                    symbolName: "arrow.right.circle",
                    isSelected: viewModel.personalizationChoice == .useDefaults
                ) {
                    onSelect(.useDefaults)
                }
            }

            OnboardingInfoNote(
                text: "Puedes ajustar todo esto más adelante desde Configuración. La selección de rutinas personalizadas solo aparece si eliges personalizar."
            )
        }
    }
}
