import SwiftUI

/// Flujo de importación de un split recibido.
///
/// Todas las decisiones viven en una sola hoja con fases: confirmación,
/// elección de modo, nombre de carpeta y aviso de sustitución. Ninguna fase
/// escribe en SwiftData; solo la confirmación final ejecuta la importación.
struct SplitImportFlowView: View {
    let request: SplitImportRequest
    let onCancel: () -> Void
    let onImportAsNewFolder: (String) -> Void
    let onReplaceOrganization: () -> Void

    private enum Phase {
        case confirmation
        case options
        case folderName
        case replaceWarning
    }

    @State private var phase: Phase = .confirmation
    @State private var folderName: String = SplitImportService.defaultFolderName

    var body: some View {
        ZStack {
            EndfieldPalette.bgPrimary.ignoresSafeArea()
            TechnicalGridBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14.0) {
                    codeRow

                    switch phase {
                    case .confirmation:
                        confirmationContent

                    case .options:
                        optionsContent

                    case .folderName:
                        folderNameContent

                    case .replaceWarning:
                        replaceWarningContent
                    }
                }
                .padding(18.0)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Piezas comunes

    private var codeRow: some View {
        HStack(spacing: 6.0) {
            Text("SP.02")
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

            Text("\(request.routineCount) RUTINAS")
                .font(EndfieldFont.label(8.0))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.textSecondary)

            Image(systemName: "square.and.arrow.down.on.square")
                .font(EndfieldFont.mono(10.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize()
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(EndfieldFont.mono(15.0, weight: .heavy))
            .foregroundStyle(EndfieldPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(EndfieldFont.mono(10.0))
            .foregroundStyle(EndfieldPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Fases

    private var confirmationContent: some View {
        VStack(alignment: .leading, spacing: 14.0) {
            title("¿Seguro que quieres importar este split?")

            message("Vas a importar el split \"\(request.splitName)\", que contiene \(request.routineCount) rutinas. ¿Quieres continuar?")

            HStack(spacing: 8.0) {
                Button(action: onCancel) {
                    Text("NO")
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(1.0)
                }
                .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.textPrimary))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        phase = .options
                    }
                } label: {
                    Text("SÍ")
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(1.0)
                }
                .buttonStyle(EndfieldPrimaryButtonStyle())
            }
        }
    }

    private var optionsContent: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            title("¿Cómo quieres importar este split?")

            optionButton(
                title: "CREAR UNA CARPETA CON EL SPLIT COMPARTIDO",
                detail: "Se añade junto a tus rutinas actuales. Nada se archiva ni se borra.",
                tint: EndfieldPalette.accentYellow,
                isPrimary: true
            ) {
                folderName = SplitImportService.defaultFolderName
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = .folderName
                }
            }

            optionButton(
                title: "SUSTITUIR MI ORGANIZACIÓN ACTUAL",
                detail: "Tus rutinas activas dejan de aparecer y el historial se conserva.",
                tint: EndfieldPalette.accentRed,
                isPrimary: false
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = .replaceWarning
                }
            }

            HStack(spacing: 8.0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        phase = .confirmation
                    }
                } label: {
                    Text("VOLVER")
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(1.0)
                }
                .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.textPrimary))

                Button(action: onCancel) {
                    Text("CANCELAR")
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(1.0)
                }
                .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.textSecondary))
            }
            .padding(.top, 2.0)
        }
    }

    private var folderNameContent: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            title("Carpeta del split")

            message("La carpeta se crea con este nombre. Si ya existe, se añadirá un número al final.")

            VStack(alignment: .leading, spacing: 6.0) {
                Text("NOMBRE DE LA CARPETA")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                TextField(
                    "",
                    text: $folderName,
                    prompt: Text(SplitImportService.defaultFolderName)
                        .foregroundColor(EndfieldPalette.textSecondary.opacity(0.6))
                )
                .textFieldStyle(.plain)
                .font(EndfieldFont.mono(12.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .tint(EndfieldPalette.accentYellow)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .padding(.vertical, 8.0)
                .padding(.horizontal, 8.0)
                .background(EndfieldPalette.bgElevated)
                .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
                .overlay {
                    ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                        .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                }
            }

            HStack(spacing: 8.0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        phase = .options
                    }
                } label: {
                    Text("VOLVER")
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(1.0)
                }
                .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.textPrimary))

                Button {
                    onImportAsNewFolder(folderName)
                } label: {
                    Text("IMPORTAR SPLIT")
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(1.0)
                }
                .buttonStyle(EndfieldPrimaryButtonStyle())
                .disabled(trimmedFolderName.isEmpty)
                .opacity(trimmedFolderName.isEmpty ? 0.5 : 1.0)
            }
        }
    }

    private var replaceWarningContent: some View {
        VStack(alignment: .leading, spacing: 14.0) {
            title("Sustituir organización actual")

            message("Las rutinas activas actuales serán sustituidas por el split recibido. Las rutinas anteriores dejarán de aparecer en tu lista activa, pero el historial de tus entrenamientos se conservará.")

            HStack(spacing: 8.0) {
                // Cancelar aquí abandona la importación completa: la advertencia
                // ya es el último paso antes de archivar la organización.
                Button(action: onCancel) {
                    Text("CANCELAR")
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(1.0)
                }
                .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.textSecondary))

                Button(action: onReplaceOrganization) {
                    Text("SUSTITUIR ORGANIZACIÓN")
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(1.0)
                }
                .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentRed))
            }
        }
    }

    private var trimmedFolderName: String {
        return folderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Botón de opción

    private func optionButton(
        title: String,
        detail: String,
        tint: Color,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6.0) {
                HStack(spacing: 6.0) {
                    Text(title)
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(isPrimary ? EndfieldPalette.bgPrimary : tint)
                        .fixedSize(horizontal: false, vertical: true)

                    if isPrimary {
                        Text("RECOMENDADO")
                            .font(EndfieldFont.label(7.0))
                            .tracking(0.8)
                            .foregroundStyle(EndfieldPalette.bgPrimary.opacity(0.7))
                    }
                }

                Text(detail)
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(isPrimary ? EndfieldPalette.bgPrimary.opacity(0.7) : EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12.0)
            .background(isPrimary ? EndfieldPalette.accentYellow : EndfieldPalette.bgPanel)
            .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cornerCut))
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                    .stroke(isPrimary ? EndfieldPalette.accentYellow : EndfieldPalette.borderSubtle, lineWidth: 1.0)
            }
        }
        .buttonStyle(.plain)
    }
}
