import SwiftUI
import SwiftData

/// Selector de split para Configuración → Compartir split.
///
/// Cada carpeta es un split completo: se selecciona la carpeta entera, nunca
/// rutinas sueltas ni varias carpetas. Solo se ofrecen carpetas con al menos
/// una rutina activa. No modifica nada: solo lee y genera el archivo.
struct SplitSharePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.name)])
    private var routines: [Routine]
    @Query(sort: [SortDescriptor(\RoutineFolder.sortOrder), SortDescriptor(\RoutineFolder.name)])
    private var folders: [RoutineFolder]

    @State private var shareFile: RoutineShareFile? = nil
    @State private var shareError: String? = nil

    private var exportableFolders: [RoutineFolder] {
        return RoutineSplitShareService.exportableFolders(folders, routines: routines)
    }

    var body: some View {
        ZStack {
            TechnicalGridBackground()

            VStack(spacing: 0.0) {
                header

                ScrollView {
                    Group {
                        if exportableFolders.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 4.0) {
                                ForEach(exportableFolders) { folder in
                                    folderRow(folder)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16.0)
                    .padding(.vertical, 10.0)
                }
                .scrollIndicators(.hidden)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .sheet(item: $shareFile, onDismiss: {
            shareFile = nil
            dismiss()
        }) { file in
            ActivityShareSheet(items: [file.url])
        }
        .alert(
            "Compartir split",
            isPresented: Binding(
                get: { shareError != nil },
                set: { isPresented in
                    if !isPresented { shareError = nil }
                }
            )
        ) {
            Button("Entendido", role: .cancel) {
                shareError = nil
            }
        } message: {
            Text(shareError ?? "")
        }
    }

    // MARK: - Cabecera

    private var header: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            HStack(spacing: 10.0) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 5.0) {
                        Image(systemName: "xmark")
                            .font(EndfieldFont.mono(10.0, weight: .bold))

                        Text("CERRAR")
                            .font(EndfieldFont.mono(10.0, weight: .heavy))
                            .tracking(0.9)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(
                    EndfieldSecondaryButtonStyle(
                        fullWidth: false,
                        compact: true,
                        tint: EndfieldPalette.textPrimary
                    )
                )
                .accessibilityLabel("Cerrar el selector de splits")

                Spacer(minLength: 6.0)

                Text("SP.01")
                    .font(EndfieldFont.mono(9.0, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.accentCyan)
                    .padding(.horizontal, 4.0)
                    .padding(.vertical, 1.0)
                    .overlay {
                        ChamferedRectangle(cut: 3.0)
                            .stroke(EndfieldPalette.accentCyan.opacity(0.45), lineWidth: 1.0)
                    }
            }

            VStack(alignment: .leading, spacing: 3.0) {
                Text("COMPARTIR SPLIT")
                    .font(EndfieldFont.mono(15.0, weight: .heavy))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text("SELECCIONA UNA CARPETA CON RUTINAS ACTIVAS")
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16.0)
        .padding(.top, 14.0)
        .padding(.bottom, 12.0)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EndfieldPalette.borderSubtle)
                .frame(height: 1.0)
        }
    }

    // MARK: - Filas

    private func folderRow(_ folder: RoutineFolder) -> some View {
        // Se numera con la lista completa de carpetas, como en la pestaña
        // Rutinas: el filtro de splits no cambia el código FL-xx.
        let index: Int = RoutineFolderService.sortedFolders(folders).firstIndex { $0.id == folder.id } ?? 0
        let count: Int = RoutineFolderService.activeRoutineCount(in: folder, routines: routines)

        return Button {
            select(folder)
        } label: {
            RoutineFolderCardContent(
                folder: folder,
                index: index,
                routineCount: count
            )
        }
        .buttonStyle(.plain)
        .background(EndfieldPalette.bgPanel)
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cornerCut))
        .accessibilityLabel("Compartir el split \(folder.name), \(count) rutinas")
    }

    // MARK: - Estado vacío

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            Text("SIN SPLITS PARA COMPARTIR")
                .font(EndfieldFont.mono(14.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Ninguna carpeta tiene rutinas activas. Crea una carpeta con rutinas en la pestaña Rutinas y vuelve aquí para compartirla como split.")
                .font(EndfieldFont.mono(10.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                dismiss()
            } label: {
                Text("CERRAR")
                    .font(EndfieldFont.mono(11.0, weight: .heavy))
                    .tracking(1.0)
            }
            .buttonStyle(EndfieldSecondaryButtonStyle(compact: true, tint: EndfieldPalette.accentYellow))
        }
        .padding(14.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .fill(EndfieldPalette.bgPanel)
        )
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }

    // MARK: - Acción

    private func select(_ folder: RoutineFolder) {
        do {
            shareFile = try RoutineSplitShareService.makeFile(for: folder, routines: routines)
        } catch {
            shareError = (error as? LocalizedError)?.errorDescription
                ?? "No se ha podido generar el archivo del split."
        }
    }
}
