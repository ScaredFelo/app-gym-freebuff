import SwiftUI

/// Confirmación previa a escribir en SwiftData.
///
/// Solo se presenta cuando `RoutineImportService` ya ha validado el archivo.
/// «No» no modifica ningún dato; «Sí» es la única vía que importa.
struct RoutineImportConfirmationView: View {
    let request: RoutineImportRequest
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            EndfieldPalette.bgPrimary.ignoresSafeArea()
            TechnicalGridBackground()

            VStack(alignment: .leading, spacing: 14.0) {
                HStack(spacing: 6.0) {
                    Text("IM.01")
                        .font(EndfieldFont.mono(9.0, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.accentCyan)
                        .padding(.horizontal, 4.0)
                        .padding(.vertical, 1.0)
                        .overlay {
                            ChamferedRectangle(cut: 3.0)
                                .stroke(EndfieldPalette.accentCyan.opacity(0.45), lineWidth: 1.0)
                        }

                    Rectangle()
                        .fill(EndfieldPalette.borderSubtle)
                        .frame(height: 1.0)

                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(EndfieldFont.mono(10.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize()
                }

                Text("¿Seguro que quieres importar esta rutina?")
                    .font(EndfieldFont.mono(15.0, weight: .heavy))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Vas a añadir la rutina \"\(request.routineName)\" a tu biblioteca de AppGym. ¿Quieres continuar?")
                    .font(EndfieldFont.mono(10.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(request.exerciseCount) EJERCICIOS · FORMATO .APPGYMROUTINE")
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                Spacer(minLength: 0.0)

                HStack(spacing: 8.0) {
                    Button(action: onCancel) {
                        Text("NO")
                            .font(EndfieldFont.mono(11.0, weight: .heavy))
                            .tracking(1.0)
                    }
                    .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.textPrimary))

                    Button(action: onConfirm) {
                        Text("SÍ")
                            .font(EndfieldFont.mono(11.0, weight: .heavy))
                            .tracking(1.0)
                    }
                    .buttonStyle(EndfieldPrimaryButtonStyle())
                }
            }
            .padding(18.0)
        }
        .presentationDetents([.height(300.0)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}
