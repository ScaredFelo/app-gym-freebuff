import SwiftUI
import SwiftData

/// Ventana de selección de la rutina que se va a compartir desde
/// Configuración → Compartir rutina.
///
/// Reproduce la estructura de la pestaña Rutinas con `RoutineFolderService` y
/// la tarjeta de carpeta existente: carpetas primero, después las rutinas sin
/// carpeta, y el interior de una carpeta muestra solo sus rutinas.
///
/// Solo se puede seleccionar una rutina individual: pulsar una carpeta navega,
/// nunca la selecciona, y no hay selección múltiple. El flujo no escribe en
/// SwiftData ni mueve nada.
struct RoutineSharePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.name)])
    private var routines: [Routine]
    @Query(sort: [SortDescriptor(\RoutineFolder.sortOrder), SortDescriptor(\RoutineFolder.name)])
    private var folders: [RoutineFolder]

    @State private var openFolderID: UUID? = nil
    @State private var shareFile: RoutineShareFile? = nil
    @State private var shareError: String? = nil

    // MARK: - Datos derivados

    private var activeRoutines: [Routine] {
        return routines.filter { $0.isActivePlanRoutine }
    }

    private var sortedFolders: [RoutineFolder] {
        return RoutineFolderService.sortedFolders(folders)
    }

    private var openFolder: RoutineFolder? {
        guard let openFolderID else { return nil }
        return folders.first { $0.id == openFolderID }
    }

    private var rows: [RoutineListRow] {
        if let folder = openFolder {
            return RoutineFolderService.rows(in: folder, activeRoutines: activeRoutines)
        }
        return RoutineFolderService.mainRows(folders: folders, activeRoutines: activeRoutines)
    }

    // MARK: - Cuerpo

    var body: some View {
        ZStack {
            TechnicalGridBackground()

            VStack(spacing: 0.0) {
                header

                ScrollView {
                    Group {
                        if openFolder == nil && activeRoutines.isEmpty {
                            noRoutinesState
                        } else if let folder = openFolder, rows.isEmpty {
                            emptyFolderState(folder)
                        } else {
                            LazyVStack(spacing: 4.0) {
                                ForEach(rows) { row in
                                    rowView(row)
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
            // Al cerrar la hoja de compartir se vuelve a Configuración.
            shareFile = nil
            dismiss()
        }) { file in
            ActivityShareSheet(items: [file.url])
        }
        .alert(
            "Compartir rutina",
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
                Button(action: goBack) {
                    HStack(spacing: 5.0) {
                        Image(systemName: openFolder == nil ? "xmark" : "chevron.left")
                            .font(EndfieldFont.mono(10.0, weight: .bold))

                        Text(openFolder == nil ? "CERRAR" : "VOLVER")
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
                .accessibilityLabel(openFolder == nil ? "Cerrar el selector" : "Volver a la lista de carpetas")

                Spacer(minLength: 6.0)

                Text("SH.01")
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
                Text(openFolder?.name.uppercased() ?? "COMPARTIR RUTINA")
                    .font(EndfieldFont.mono(15.0, weight: .heavy))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(subtitle)
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

    private var subtitle: String {
        if let folder = openFolder {
            let count: Int = RoutineFolderService.activeRoutineCount(in: folder, routines: routines)
            return count == 1 ? "1 RUTINA EN LA CARPETA" : "\(count) RUTINAS EN LA CARPETA"
        }
        return "SELECCIONA UNA RUTINA PARA COMPARTIR"
    }

    // MARK: - Filas

    @ViewBuilder
    private func rowView(_ row: RoutineListRow) -> some View {
        switch row {
        case .folder(let folder):
            folderRow(folder)

        case .routine(let routine, let position):
            RoutineShareRowView(
                routine: routine,
                displayIndex: position,
                onSelect: { select(routine) }
            )
        }
    }

    private func folderRow(_ folder: RoutineFolder) -> some View {
        let index: Int = sortedFolders.firstIndex { $0.id == folder.id } ?? 0
        let count: Int = RoutineFolderService.activeRoutineCount(in: folder, routines: routines)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                openFolderID = folder.id
            }
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
        .accessibilityLabel("Abrir la carpeta \(folder.name), \(count) rutinas")
    }

    // MARK: - Estados vacíos

    private var noRoutinesState: some View {
        panel(
            title: "SIN RUTINAS PARA COMPARTIR",
            message: "Todavía no hay ninguna rutina activa. Crea una rutina en la pestaña Rutinas y vuelve aquí para compartirla.",
            actionTitle: "CERRAR",
            action: goBack
        )
    }

    private func emptyFolderState(_ folder: RoutineFolder) -> some View {
        panel(
            title: "CARPETA VACÍA",
            message: "La carpeta «\(folder.name)» no contiene ninguna rutina activa que se pueda compartir ahora mismo.",
            actionTitle: "VOLVER",
            action: goBack
        )
    }

    private func panel(
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12.0) {
            Text(title)
                .font(EndfieldFont.mono(14.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(EndfieldFont.mono(10.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                Text(actionTitle)
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

    // MARK: - Acciones

    /// Dentro de una carpeta vuelve al nivel anterior; en la lista principal
    /// cierra el selector y regresa a Configuración. Sin escribir nada.
    private func goBack() {
        if openFolder != nil {
            withAnimation(.easeInOut(duration: 0.2)) {
                openFolderID = nil
            }
            return
        }
        dismiss()
    }

    private func select(_ routine: Routine) {
        do {
            shareFile = try RoutineShareService.makeFile(for: routine)
        } catch {
            shareError = (error as? LocalizedError)?.errorDescription
                ?? "No se ha podido generar el archivo de la rutina."
        }
    }
}

// MARK: - Fila de rutina para compartir

/// Fila de selección con el mismo lenguaje visual que `RoutineRowView`, pero
/// sin gestos ni arranque de entrenamiento: aquí una pulsación selecciona.
private struct RoutineShareRowView: View {
    let routine: Routine
    let displayIndex: Int
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10.0) {
                VStack(alignment: .leading, spacing: 5.0) {
                    HStack(spacing: 6.0) {
                        Text(String(format: "RT-%02d", displayIndex + 1))
                            .font(EndfieldFont.mono(9.0, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(EndfieldPalette.accentYellow)
                            .padding(.horizontal, 4.0)
                            .padding(.vertical, 1.0)
                            .overlay {
                                ChamferedRectangle(cut: 3.0)
                                    .stroke(EndfieldPalette.accentYellow.opacity(0.45), lineWidth: 1.0)
                            }

                        Rectangle()
                            .fill(EndfieldPalette.borderSubtle)
                            .frame(height: 1.0)

                        Text("\(routine.exercises.count) EX")
                            .font(EndfieldFont.label(8.0))
                            .tracking(0.8)
                            .foregroundStyle(EndfieldPalette.textSecondary)
                    }

                    Text(routine.name.uppercased())
                        .font(EndfieldFont.mono(15.0, weight: .heavy))
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text("\(routine.exercises.count) ejercicios configurados".uppercased())
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 6.0)

                HStack(spacing: 5.0) {
                    Image(systemName: "square.and.arrow.up")
                        .font(EndfieldFont.mono(9.0, weight: .bold))

                    Text("COMPARTIR")
                        .font(EndfieldFont.mono(10.0, weight: .heavy))
                        .tracking(0.8)
                }
                .foregroundStyle(EndfieldPalette.bgPrimary)
                .padding(.horizontal, 10.0)
                .padding(.vertical, 7.0)
                .background(EndfieldPalette.accentYellow)
                .clipShape(ChamferedRectangle(cut: 4.0))
                .fixedSize()
            }
            .padding(12.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(EndfieldPalette.bgPanel)
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cornerCut))
        .accessibilityLabel("Compartir la rutina \(routine.name)")
    }
}
