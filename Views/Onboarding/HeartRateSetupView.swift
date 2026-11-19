import SwiftUI

/// Medición de pulsaciones durante el entrenamiento. Guarda los mismos campos
/// que Configuración (`isHeartRateTrackingEnabled`, `heartRateDeviceType`,
/// `heartRateDeviceBrand`) y no solicita Bluetooth en este punto.
struct HeartRateSetupView: View {
    let chrome: OnboardingChrome
    @ObservedObject var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "Pulsaciones",
            subtitle: "¿Quieres medir tus pulsaciones durante el entrenamiento?",
            footer: footer
        ) {
            VStack(spacing: 10.0) {
                OnboardingChoiceCard(
                    code: "BPM.03-A",
                    title: "Sí",
                    caption: "Muestra los BPM en el entrenamiento y en las estadísticas.",
                    symbolName: "heart.fill",
                    isSelected: viewModel.isHeartRateTrackingEnabled
                ) {
                    OnboardingHaptics.selection()
                    viewModel.isHeartRateTrackingEnabled = true
                }

                OnboardingChoiceCard(
                    code: "BPM.03-B",
                    title: "No",
                    caption: "El entrenamiento funciona igual, sin datos de frecuencia cardíaca.",
                    symbolName: "heart.slash",
                    isSelected: !viewModel.isHeartRateTrackingEnabled
                ) {
                    OnboardingHaptics.selection()
                    viewModel.isHeartRateTrackingEnabled = false
                }
            }

            if viewModel.isHeartRateTrackingEnabled {
                TacticalPanel(code: "BPM.04", title: "Dispositivo de medición", contentPadding: 12.0) {
                    VStack(spacing: 9.0) {
                        ForEach(HeartRateDeviceType.allCases) { (type: HeartRateDeviceType) in
                            OnboardingChoiceCard(
                                code: type == .heartRateBand ? "BPM-B1" : "BPM-B2",
                                title: type.title,
                                caption: type.subtitle,
                                symbolName: type.symbolName,
                                isSelected: viewModel.heartRateDeviceType == type
                            ) {
                                OnboardingHaptics.selection()
                                viewModel.selectHeartRateDevice(type)
                            }
                        }

                        if viewModel.heartRateDeviceType == .heartRateBand {
                            VStack(alignment: .leading, spacing: 6.0) {
                                Text("MARCA / MODELO (OPCIONAL)")
                                    .font(EndfieldFont.label(8.0))
                                    .tracking(1.0)
                                    .foregroundStyle(EndfieldPalette.textSecondary)

                                TextField(
                                    "",
                                    text: $viewModel.heartRateDeviceBrand,
                                    prompt: Text("Amazfit, Polar, Garmin...")
                                        .foregroundColor(EndfieldPalette.textSecondary.opacity(0.6))
                                )
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .tacticalField()
                                .accessibilityLabel("Marca o modelo de la pulsera")
                            }
                        }

                        Text("La conexión Bluetooth se solicita al empezar un entrenamiento, no durante la configuración.")
                            .font(EndfieldFont.mono(9.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .withKeyboardDismiss()
    }

    private var footer: AnyView {
        return AnyView(
            OnboardingPrimaryFooter(title: "CONTINUAR") {
                onContinue()
            }
        )
    }
}
