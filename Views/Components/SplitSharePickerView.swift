import SwiftUI
import SwiftData

/// Selector de split para Configuración → Compartir split.
///
/// Construye el split en el momento de compartirlo: reproduce la jerarquía de
/// la pestaña Rutinas con las carpetas (contraídas al abrirse) y las rutinas
/// independientes, y permite marcar rutinas de orígenes distintos sin mover
/// nada ni crear carpetas en el dispositivo del emisor.
///
/// Solo lee el modelo: no inserta, modifica ni mueve rutinas. La selección y el
/// despliegue de carpetas son estado temporal de la interfaz, y el archivo se
/// genera con `RoutineSplitShareService` en el orden visual de la pestaña.
struct SplitSharePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.name)])
    private var routines: [Routine]
    @Query(sort: [SortDescriptor(\RoutineFolder.sortOrder), SortDescriptor(\RoutineFolder.name)])
    private var folders: [RoutineFolder]

    @State private var selection: SplitShareSelectorState = SplitShareSelectorState()
    @State private var shareFile: RoutineShareFile? = nil
    @State private var shareError: String? = nil

    // MARK: - Datos derivados

    /// Carpetas con al menos una rutina activa. Las vacías o con solo rutinas
    /// archivadas no se ofrecen.
    private var selectableFolders: [RoutineFolder] {
        return RoutineSplitShareService.exportableFolders(folders, routines: routines)
    }

    private var looseRoutines: [Routine] {
        return RoutineSplitShareService.looseActiveRoutines(folders: folders, routines: routines)
    }

    private var selectedRoutines: [Routine] {
        return RoutineSplitShareService.selectedRoutines(selection, folders: folders, routines: routines)
    }

    private var isCompletelyEmpty: Bool {
        return selectableFolders.isEmpty && looseRoutines.isEmpty
    }

    // MARK: - Cuerpo

    var body: some View {
        ZStack {
            TechnicalGridBackground()

            VStack(spacing: 0.0) {
                header

                ScrollView {
                    screenContent
                        .padding(.horizontal, 16.0)
                        .padding(.vertical, 10.0)
                }
                .scrollIndicators(.hidden)

                footer
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

    @ViewBuilder
    private var screenContent: some View {
        if isCompletelyEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 4.0) {
                ForEach(selectableFolders) { folder in
                    folderSection(folder)
                }

                if !looseRoutines.isEmpty {
                    looseSection
                }
            }
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

                Text("MARCA LAS RUTINAS QUE FORMAN EL SPLIT")
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
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

    // MARK: - Carpetas

    private func folderSection(_ folder: RoutineFolder) -> some View {
        VStack(spacing: 4.0) {
            folderRow(folder)

            if selection.isExpanded(folder.id) {
                folderRoutines(folder)
            }
        }
    }

    private func folderRoutines(_ folder: RoutineFolder) -> some View {
        let contained: [Routine] = RoutineSplitShareService.activeRoutines(in: folder, routines: routines)

        return ForEach(Array(contained.enumerated()), id: \.element.id) { index, routine in
            routineRow(routine, displayIndex: index)
                .padding(.leading, 12.0)
        }
    }

    private func folderRow(_ folder: RoutineFolder) -> some View {
        // Se numera con la lista completa de carpetas, como en la pestaña
        // Rutinas: la selección no cambia el código FL-xx.
        let index: Int = RoutineFolderService.sortedFolders(folders).firstIndex { $0.id == folder.id } ?? 0
        let count: Int = RoutineFolderService.activeRoutineCount(in: folder, routines: routines)
        let isExpanded: Bool = selection.isExpanded(folder.id)
        let state: SplitFolderSelectionState = selection.folderState(folder, routines: routines)

        return HStack(spacing: 0.0) {
            Button {
                toggleExpansion(folder)
            } label: {
                RoutineFolderCardContent(
                    folder: folder,
                    index: index,
                    routineCount: count,
                    disclosure: isExpanded ? .expanded : .collapsed
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isExpanded
                    ? "Contraer la carpeta \(folder.name), \(count) rutinas"
                    : "Desplegar la carpeta \(folder.name), \(count) rutinas"
            )

            Button {
                toggleFolder(folder)
            } label: {
                SplitSelectionCheckbox(state: state)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12.0)
            .accessibilityLabel(
                state == .all
                    ? "Quitar la selección de la carpeta \(folder.name)"
                    : "Seleccionar todas las rutinas de la carpeta \(folder.name)"
            )
            .accessibilityAddTraits(state == .all ? .isSelected : [])
        }
        .background(EndfieldPalette.bgPanel)
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cornerCut))
    }

    // MARK: - Rutinas independientes

    private var looseSection: some View {
        VStack(spacing: 4.0) {
            HStack(spacing: 6.0) {
                Text("RUTINAS INDEPENDIENTES")
                    .font(EndfieldFont.mono(9.0, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.accentCyan)

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                Text("\(looseRoutines.count) RT")
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }
            .padding(.horizontal, 2.0)
            .padding(.top, 6.0)

            ForEach(Array(looseRoutines.enumerated()), id: \.element.id) { index, routine in
                routineRow(routine, displayIndex: index)
            }
        }
    }

    private func routineRow(_ routine: Routine, displayIndex: Int) -> some View {
        SplitShareRoutineRow(
            routine: routine,
            displayIndex: displayIndex,
            isSelected: selection.contains(routine.id),
            onToggle: { toggleRoutine(routine) }
        )
    }

    // MARK: - Barra inferior

    private var footer: some View {
        VStack(spacing: 8.0) {
            HStack(spacing: 8.0) {
                Text(selectionSummary)
                    .font(EndfieldFont.mono(10.0, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(
                        selection.isEmpty ? EndfieldPalette.textSecondary : EndfieldPalette.textPrimary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Spacer(minLength: 6.0)

                Button {
                    deselectAll()
                } label: {
                    Text("DESELECCIONAR TODO")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(
                    EndfieldSecondaryButtonStyle(
                        fullWidth: false,
                        compact: true,
                        tint: EndfieldPalette.textSecondary
                    )
                )
                .disabled(selection.isEmpty)
                .opacity(selection.isEmpty ? 0.45 : 1.0)
                .accessibilityLabel("Deseleccionar todas las rutinas")
            }

            Button(action: share) {
                HStack(spacing: 6.0) {
                    Image(systemName: "square.and.arrow.up")
                        .font(EndfieldFont.mono(10.0, weight: .bold))

                    Text("COMPARTIR SPLIT")
                        .font(EndfieldFont.mono(12.0, weight: .heavy))
                        .tracking(1.0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .buttonStyle(EndfieldPrimaryButtonStyle())
            .disabled(!selection.canShare)
            .opacity(selection.canShare ? 1.0 : 0.4)
            .accessibilityLabel("Compartir split con \(selection.selectedCount) rutinas")
        }
        .padding(.horizontal, 16.0)
        .padding(.top, 10.0)
        .padding(.bottom, 14.0)
        .background(EndfieldPalette.bgPrimary)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EndfieldPalette.borderSubtle)
                .frame(height: 1.0)
        }
    }

    private var selectionSummary: String {
        let count: Int = selection.selectedCount
        if count == 0 {
            return "NINGUNA RUTINA SELECCIONADA"
        }
        if count == 1 {
            return "1 RUTINA SELECCIONADA"
        }
        return "\(count) RUTINAS SELECCIONADAS"
    }

    // MARK: - Estado vacío

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            Text("SIN RUTINAS PARA COMPARTIR")
                .font(EndfieldFont.mono(14.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("No hay ninguna rutina activa. Crea rutinas en la pestaña Rutinas y vuelve aquí para construir un split con las que quieras compartir.")
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

    // MARK: - Acciones

    private func toggleExpansion(_ folder: RoutineFolder) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selection.toggleExpansion(folder.id)
        }
    }

    private func toggleFolder(_ folder: RoutineFolder) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selection.toggleFolder(folder, routines: routines)
        }
    }

    private func toggleRoutine(_ routine: Routine) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selection.toggleRoutine(routine)
        }
    }

    private func deselectAll() {
        withAnimation(.easeInOut(duration: 0.15)) {
            selection.deselectAll()
        }
    }

    private func share() {
        do {
            shareFile = try RoutineSplitShareService.makeFile(for: selectedRoutines)
        } catch {
            shareError = (error as? LocalizedError)?.errorDescription
                ?? "No se ha podido generar el archivo del split."
        }
    }
}

// MARK: - Casilla de selección

/// Casilla con los tres estados de una carpeta: vacía, intermedia y completa.
/// Las rutinas usan solo vacía o completa.
private struct SplitSelectionCheckbox: View {
    let state: SplitFolderSelectionState

    var body: some View {
        Image(systemName: symbol)
            .font(EndfieldFont.mono(12.0, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 30.0, height: 30.0)
            .background(ChamferedRectangle(cut: 4.0).fill(background))
            .overlay {
                ChamferedRectangle(cut: 4.0)
                    .stroke(strokeColor, lineWidth: 1.0)
            }
            .fixedSize()
    }

    private var symbol: String {
        switch state {
        case .none:
            return "square"
        case .partial:
            return "minus.square.fill"
        case .all:
            return "checkmark.square.fill"
        }
    }

    private var tint: Color {
        return state == .none
            ? EndfieldPalette.textSecondary.opacity(0.7)
            : EndfieldPalette.accentYellow
    }

    private var background: Color {
        return state == .none
            ? EndfieldPalette.bgElevated
            : EndfieldPalette.accentYellow.opacity(0.12)
    }

    private var strokeColor: Color {
        return state == .none
            ? EndfieldPalette.borderSubtle
            : EndfieldPalette.accentYellow.opacity(0.75)
    }
}

// MARK: - Fila de rutina

/// Fila de selección con el mismo lenguaje visual que `RoutineRowView`, sin
/// gestos ni arranque de entrenamiento: aquí una pulsación marca o desmarca.
private struct SplitShareRoutineRow: View {
    let routine: Routine
    let displayIndex: Int
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 0.0) {
                routineContent

                Spacer(minLength: 6.0)

                SplitSelectionCheckbox(state: isSelected ? .all : .none)
                    .padding(.trailing, 12.0)
            }
            .background(EndfieldPalette.bgPanel)
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                    .stroke(
                        isSelected ? EndfieldPalette.accentYellow.opacity(0.55) : EndfieldPalette.borderSubtle,
                        lineWidth: 1.0
                    )
            }
            .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cornerCut))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isSelected
                ? "Deseleccionar la rutina \(routine.name)"
                : "Seleccionar la rutina \(routine.name)"
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var routineContent: some View {
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
        .padding(.leading, 12.0)
        .padding(.vertical, 12.0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
