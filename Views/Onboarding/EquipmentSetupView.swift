import SwiftUI

/// Configuración del equipamiento del gimnasio: pesos de barra Multipower y EZ
/// y discos disponibles (los once del catálogo actual).
struct EquipmentSetupView: View {
    let chrome: OnboardingChrome
    @ObservedObject var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "Equipamiento disponible",
            subtitle: "Indica los pesos de tus barras y los discos de los que dispones. Se usan para calcular los discos de cada serie.",
            footer: footer
        ) {
            TacticalPanel(code: "EQP.01", title: "Barras", contentPadding: 12.0) {
                VStack(alignment: .leading, spacing: 12.0) {
                    barWeightRow(
                        title: "Barra Multipower",
                        value: $viewModel.multipowerBarWeight,
                        onDecrease: { viewModel.adjustMultipowerBarWeight(by: -OnboardingPreferences.barWeightStep) },
                        onIncrease: { viewModel.adjustMultipowerBarWeight(by: OnboardingPreferences.barWeightStep) }
                    )

                    Rectangle()
                        .fill(EndfieldPalette.borderSubtle)
                        .frame(height: 1.0)

                    barWeightRow(
                        title: "Barra EZ",
                        value: $viewModel.ezBarWeight,
                        onDecrease: { viewModel.adjustEZBarWeight(by: -OnboardingPreferences.barWeightStep) },
                        onIncrease: { viewModel.adjustEZBarWeight(by: OnboardingPreferences.barWeightStep) }
                    )

                    Text("Rango de 0 a 100 kg con incrementos de 0,5 kg. El peso de la barra se suma al de los discos al calcular la carga.")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TacticalPanel(code: "PLT.02", title: "Discos disponibles", contentPadding: 12.0) {
                VStack(alignment: .leading, spacing: 6.0) {
                    ForEach(UserSettingsManager.plateOptions, id: \.self) { (plate: Double) in
                        TacticalToggleRow(
                            code: "PLT",
                            title: "\(UserSettingsManager.formatted(plate)) KG",
                            isOn: plateBinding(for: plate)
                        ) {
                            Rectangle()
                                .fill(PlateCalculatorService.color(for: plate))
                                .frame(width: 10.0, height: 10.0)
                                .overlay {
                                    Rectangle()
                                        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                                }
                        }
                    }

                    Text(viewModel.hasValidEquipment
                         ? "\(viewModel.selectedPlates.count) discos activos."
                         : "Activa al menos un disco para poder calcular los pesos.")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(viewModel.hasValidEquipment
                                         ? EndfieldPalette.textSecondary
                                         : EndfieldPalette.accentRed)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2.0)
                }
            }
        }
        .withKeyboardDismiss()
    }

    // MARK: - Fila de peso

    private func barWeightRow(
        title: String,
        value: Binding<Double>,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6.0) {
            Text(title.uppercased())
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary)

            HStack(spacing: 7.0) {
                Button(action: onDecrease) {
                    Image(systemName: "minus")
                        .font(EndfieldFont.mono(12.0, weight: .heavy))
                }
                .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentYellow, size: 32.0))
                .accessibilityLabel("Restar 0,5 kg a \(title)")

                TextField("0", value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .tacticalField(alignment: .center)
                    .accessibilityLabel("Peso de \(title) en kilogramos")

                Text("KG")
                    .font(EndfieldFont.label(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize()

                Button(action: onIncrease) {
                    Image(systemName: "plus")
                        .font(EndfieldFont.mono(12.0, weight: .heavy))
                }
                .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentYellow, size: 32.0))
                .accessibilityLabel("Sumar 0,5 kg a \(title)")
            }

            Stepper(
                value: value,
                in: OnboardingPreferences.barWeightRange,
                step: OnboardingPreferences.barWeightStep
            ) {
                Text("Ajustar \(title): \(UserSettingsManager.formatted(value.wrappedValue)) kg")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .tint(EndfieldPalette.accentYellow)
        }
    }

    private func plateBinding(for plate: Double) -> Binding<Bool> {
        return Binding(
            get: {
                return viewModel.isPlateSelected(plate)
            },
            set: { (isEnabled: Bool) in
                guard isEnabled != viewModel.isPlateSelected(plate) else { return }
                viewModel.togglePlate(plate)
            }
        )
    }

    // MARK: - Footer

    private var footer: AnyView {
        return AnyView(
            VStack(spacing: 6.0) {
                OnboardingPrimaryFooter(title: "CONTINUAR", isEnabled: viewModel.hasValidEquipment) {
                    onContinue()
                }

                if !viewModel.hasValidEquipment {
                    Text("ACTIVA AL MENOS UN DISCO")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.accentRed)
                }
            }
        )
    }
}
