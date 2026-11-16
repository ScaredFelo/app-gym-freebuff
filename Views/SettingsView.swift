import SwiftUI

struct SettingsView: View {
    @AppStorage(UserSettingsManager.multipowerBarWeightKey)
    private var multipowerBarWeight: Double = UserSettingsManager.defaultMultipowerBarWeight

    @AppStorage(UserSettingsManager.ezBarWeightKey)
    private var ezBarWeight: Double = UserSettingsManager.defaultEZBarWeight

    @AppStorage(UserSettingsManager.availablePlatesKey)
    private var availablePlatesRaw: String = UserSettingsManager.defaultAvailablePlates

    @AppStorage(UserSettingsManager.isBigPictureModeEnabledKey)
    private var isBigPictureModeEnabled: Bool = false

    private var availablePlates: [Double] {
        return UserSettingsManager.parsePlates(availablePlatesRaw)
    }

    var body: some View {
        Form {
            Section {
                barWeightRow(
                    title: "Peso barra Multipower",
                    value: $multipowerBarWeight
                )

                Stepper(
                    "Ajustar Multipower: \(UserSettingsManager.formatted(multipowerBarWeight)) kg",
                    value: $multipowerBarWeight,
                    in: 0...100,
                    step: 0.5
                )

                barWeightRow(
                    title: "Peso barra EZ",
                    value: $ezBarWeight
                )

                Stepper(
                    "Ajustar barra EZ: \(UserSettingsManager.formatted(ezBarWeight)) kg",
                    value: $ezBarWeight,
                    in: 0...100,
                    step: 0.5
                )
            } header: {
                Text("Equipamiento y Discos")
            } footer: {
                Text("Estos pesos se usan como base al calcular los discos de Multipower y de barra EZ.")
            }

            Section {
                ForEach(UserSettingsManager.plateOptions, id: \.self) { (plate: Double) in
                    Toggle(isOn: plateBinding(for: plate)) {
                        HStack(spacing: 10.0) {
                            Circle()
                                .fill(PlateCalculatorService.color(for: plate))
                                .frame(width: 14.0, height: 14.0)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.55), lineWidth: 0.8)
                                )

                            Text("\(UserSettingsManager.formatted(plate)) kg")
                        }
                    }
                    .tint(.green)
                }
            } header: {
                Text("Discos disponibles")
            } footer: {
                Text("Activa solo los discos de los que dispone tu gimnasio. El cálculo por lado usará únicamente estos pesos.")
            }

            Section {
                Toggle(isOn: $isBigPictureModeEnabled) {
                    Label("BIG PICTURE", systemImage: "textformat.size")
                }
                .tint(.green)
            } header: {
                Text("Modo visual")
            } footer: {
                Text("Aumenta la tipografía y el contraste durante el entrenamiento activo.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .tint(.green)
        .navigationTitle("Configuración")
        .withKeyboardDismiss()
    }

    private func barWeightRow(title: String, value: Binding<Double>) -> some View {
        return HStack {
            Text(title)

            Spacer()

            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72.0)

            Text("kg")
                .foregroundStyle(.secondary)
        }
    }

    private func plateBinding(for plate: Double) -> Binding<Bool> {
        return Binding(
            get: {
                return availablePlates.contains(plate)
            },
            set: { (isEnabled: Bool) in
                var plates: Set<Double> = Set(availablePlates)
                if isEnabled {
                    plates.insert(plate)
                } else {
                    plates.remove(plate)
                }
                availablePlatesRaw = UserSettingsManager.serializePlates(plates)
            }
        )
    }
}
