import SwiftUI
import SwiftData

// MARK: - Nombre de carpeta

/// Para qué se usa el diálogo de nombre. Renombrar reutiliza la misma pantalla
/// para no duplicar validación ni mensajes.
enum FolderNameSheetMode {
    case create
    case rename(RoutineFolder)
}

/// Diálogo para crear o renombrar una carpeta.
///
/// La validación (nombre vacío, solo espacios o duplicado) se hace en
/// `RoutineFolderService`; aquí solo se muestra el error sin cerrar la hoja.
struct FolderNameSheet: View {
    let mode: FolderNameSheetMode
    var onFinished: (String) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\RoutineFolder.sortOrder), SortDescriptor(\RoutineFolder.name)])
    private var folders: [RoutineFolder]

    @State private var name: String = ""
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    private var title: String {
        switch mode {
        case .create:
            return "NUEVA CARPETA"
        case .rename:
            return "RENOMBRAR CARPETA"
        }
    }

    private var confirmTitle: String {
        switch mode {
        case .create:
            return "CREAR CARPETA"
        case .rename:
            return "GUARDAR NOMBRE"
        }
    }

    private var trimmedName: String {
        return RoutineFolderService.normalizedName(name)
    }

    var body: some View {
        ZStack {
            EndfieldPalette.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14.0) {
                    Text(title)
                        .font(EndfieldFont.mono(13.0, weight: .heavy))
                        .tracking(1.1)
                        .foregroundStyle(EndfieldPalette.textPrimary)

                    Text("El nombre solo organiza la lista de rutinas. No modifica ninguna rutina ni su historial.")
                        .font(EndfieldFont.mono(10.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Nombre de la carpeta", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .onSubmit(commit)
                        .font(EndfieldFont.mono(12.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .padding(11.0)
                        .background(ChamferedRectangle(cut: 4.0).fill(EndfieldPalette.bgPanel))
                        .overlay {
                            ChamferedRectangle(cut: 4.0)
                                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                        }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(EndfieldFont.mono(9.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.accentRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8.0) {
                        Button("CANCELAR") {
                            dismiss()
                        }
                        .font(EndfieldFont.mono(10.0, weight: .heavy))
                        .tracking(0.9)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11.0)
                        .background(ChamferedRectangle(cut: 4.0).fill(EndfieldPalette.bgPanel))
                        .overlay {
                            ChamferedRectangle(cut: 4.0)
                                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                        }

                        Button(confirmTitle) {
                            commit()
                        }
                        .font(EndfieldFont.mono(10.0, weight: .heavy))
                        .tracking(0.9)
                        .foregroundStyle(EndfieldPalette.bgPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11.0)
                        .background(EndfieldPalette.accentYellow)
                        .clipShape(ChamferedRectangle(cut: 4.0))
                        .disabled(trimmedName.isEmpty)
                        .opacity(trimmedName.isEmpty ? 0.5 : 1.0)
                    }
                }
                .padding(16.0)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.height(300.0)])
        .presentationDragIndicator(.visible)
        .onAppear {
            if case .rename(let folder) = mode {
                name = folder.name
            }
        }
        .task {
            // El teclado aún no está montado cuando la hoja aparece.
            try? await Task.sleep(nanoseconds: 300_000_000)
            isNameFocused = true
        }
    }

    private func commit() {
        do {
            switch mode {
            case .create:
                let folder: RoutineFolder = try RoutineFolderService.createFolder(
                    named: name,
                    existingFolders: folders,
                    context: modelContext
                )
                onFinished("Carpeta «\(folder.name)» creada.")

            case .rename(let folder):
                try RoutineFolderService.renameFolder(
                    folder,
                    to: name,
                    existingFolders: folders,
                    context: modelContext
                )
                onFinished("Carpeta renombrada a «\(RoutineFolderService.normalizedName(name))».")
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "No se han podido guardar los cambios."
        }
    }
}

// MARK: - Mover rutina

/// Flujo abierto al deslizar una rutina hacia la izquierda.
///
/// Reproduce el mensaje pedido y ofrece las tres opciones (carpeta nueva,
/// carpeta existente, cancelar). Dentro de una carpeta añade la opción de sacar
/// la rutina a la lista principal, necesario para que una rutina pueda volver.
struct MoveRoutineSheet: View {
    let routine: Routine
    var onFinished: (String) -> Void = { _ in }

    private enum Step {
        case options
        case newFolder
        case existingFolders
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\RoutineFolder.sortOrder), SortDescriptor(\RoutineFolder.name)])
    private var folders: [RoutineFolder]

    @State private var step: Step = .options
    @State private var folderName: String = ""
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    private var sortedFolders: [RoutineFolder] {
        return RoutineFolderService.sortedFolders(folders)
    }

    private var currentFolder: RoutineFolder? {
        return RoutineFolderService.folder(containing: routine, from: folders)
    }

    private var trimmedName: String {
        return RoutineFolderService.normalizedName(folderName)
    }

    var body: some View {
        ZStack {
            EndfieldPalette.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14.0) {
                    header

                    switch step {
                    case .options:
                        optionsContent

                    case .newFolder:
                        newFolderContent

                    case .existingFolders:
                        existingFoldersContent
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(EndfieldFont.mono(9.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.accentRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("CANCELAR") {
                        dismiss()
                    }
                    .font(EndfieldFont.mono(10.0, weight: .heavy))
                    .tracking(0.9)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11.0)
                    .background(ChamferedRectangle(cut: 4.0).fill(EndfieldPalette.bgPanel))
                    .overlay {
                        ChamferedRectangle(cut: 4.0)
                            .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                    }
                }
                .padding(16.0)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Cabecera

    private var header: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            HStack(spacing: 6.0) {
                Text("MV-01")
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

                if let currentFolder {
                    Text(currentFolder.name.uppercased())
                        .font(EndfieldFont.label(8.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("LISTA PRINCIPAL")
                        .font(EndfieldFont.label(8.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                }
            }

            Text("¿QUIERES MOVER ESTA RUTINA?")
                .font(EndfieldFont.mono(15.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Puedes moverla a una carpeta nueva, a una carpeta existente o cancelar esta acción.")
                .font(EndfieldFont.mono(10.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(routine.name.uppercased())
                .font(EndfieldFont.mono(11.0, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.accentYellow)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8.0)
                .padding(.vertical, 6.0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ChamferedRectangle(cut: 4.0).fill(EndfieldPalette.bgPanel))
                .overlay {
                    ChamferedRectangle(cut: 4.0)
                        .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                }
        }
    }

    // MARK: Opciones

    private var optionsContent: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            optionButton(
                icon: "folder.badge.plus",
                title: "Crear una carpeta nueva",
                caption: "ESCRIBE UN NOMBRE",
                tint: EndfieldPalette.accentCyan
            ) {
                errorMessage = nil
                step = .newFolder
            }

            optionButton(
                icon: "folder",
                title: "Mover a una carpeta existente",
                caption: sortedFolders.isEmpty ? "TODAVÍA NO HAY CARPETAS" : "\(sortedFolders.count) DISPONIBLES",
                tint: EndfieldPalette.textSecondary
            ) {
                errorMessage = nil
                step = .existingFolders
            }
            .disabled(sortedFolders.isEmpty)
            .opacity(sortedFolders.isEmpty ? 0.55 : 1.0)

            if currentFolder != nil {
                optionButton(
                    icon: "tray.and.arrow.up",
                    title: "Sacar de la carpeta",
                    caption: "VUELVE A LA LISTA PRINCIPAL",
                    tint: EndfieldPalette.accentYellow
                ) {
                    move(to: nil)
                }
            }
        }
    }

    // MARK: Carpeta nueva

    private var newFolderContent: some View {
        VStack(alignment: .leading, spacing: 10.0) {
            Text("NOMBRE DE LA CARPETA")
                .font(EndfieldFont.label(8.0))
                .tracking(0.9)
                .foregroundStyle(EndfieldPalette.textSecondary)

            TextField("Nombre de la carpeta", text: $folderName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .focused($isNameFocused)
                .font(EndfieldFont.mono(12.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .padding(11.0)
                .background(ChamferedRectangle(cut: 4.0).fill(EndfieldPalette.bgPanel))
                .overlay {
                    ChamferedRectangle(cut: 4.0)
                        .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                }

            Button("CREAR Y MOVER") {
                createFolderAndMove()
            }
            .font(EndfieldFont.mono(10.0, weight: .heavy))
            .tracking(0.9)
            .foregroundStyle(EndfieldPalette.bgPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11.0)
            .background(EndfieldPalette.accentYellow)
            .clipShape(ChamferedRectangle(cut: 4.0))
            .disabled(trimmedName.isEmpty)
            .opacity(trimmedName.isEmpty ? 0.5 : 1.0)

            backButton
        }
        .onAppear {
            isNameFocused = true
        }
    }

    // MARK: Carpetas existentes

    private var existingFoldersContent: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            if sortedFolders.isEmpty {
                Text("Todavía no hay ninguna carpeta. Crea una nueva para mover esta rutina.")
                    .font(EndfieldFont.mono(10.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(sortedFolders) { folder in
                    let isCurrent: Bool = folder.id == currentFolder?.id
                    Button {
                        guard !isCurrent else { return }
                        move(to: folder)
                    } label: {
                        HStack(spacing: 9.0) {
                            Image(systemName: isCurrent ? "folder.fill" : "folder")
                                .font(.system(size: 12.0, weight: .semibold))
                                .foregroundStyle(EndfieldPalette.accentCyan)

                            VStack(alignment: .leading, spacing: 2.0) {
                                Text(folder.name.uppercased())
                                    .font(EndfieldFont.mono(11.0, weight: .heavy))
                                    .foregroundStyle(EndfieldPalette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                Text(isCurrent ? "CARPETA ACTUAL" : "\(RoutineFolderService.activeRoutineCount(in: folder, routines: allRoutines)) RUTINAS")
                                    .font(EndfieldFont.label(8.0))
                                    .tracking(0.6)
                                    .foregroundStyle(EndfieldPalette.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0.0)
                        }
                        .padding(.horizontal, 10.0)
                        .padding(.vertical, 9.0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ChamferedRectangle(cut: 4.0).fill(EndfieldPalette.bgPanel))
                        .overlay {
                            ChamferedRectangle(cut: 4.0)
                                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCurrent)
                    .opacity(isCurrent ? 0.55 : 1.0)
                }
            }

            backButton
        }
    }

    private var backButton: some View {
        Button("VOLVER A OPCIONES") {
            errorMessage = nil
            step = .options
        }
        .font(EndfieldFont.mono(9.0, weight: .heavy))
        .tracking(0.8)
        .foregroundStyle(EndfieldPalette.textSecondary)
    }

    // MARK: Acciones

    private var allRoutines: [Routine] {
        return (try? modelContext.fetch(FetchDescriptor<Routine>())) ?? []
    }

    private func move(to folder: RoutineFolder?) {
        do {
            try RoutineFolderService.moveRoutine(routine, to: folder, context: modelContext)

            if let folder {
                onFinished("«\(routine.name)» se ha movido a la carpeta «\(folder.name)».")
            } else {
                onFinished("«\(routine.name)» vuelve a la lista principal.")
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "No se ha podido mover la rutina."
        }
    }

    private func createFolderAndMove() {
        do {
            let folder: RoutineFolder = try RoutineFolderService.createFolder(
                named: folderName,
                moving: routine,
                existingFolders: folders,
                context: modelContext
            )
            onFinished("«\(routine.name)» se ha movido a la nueva carpeta «\(folder.name)».")
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "No se ha podido mover la rutina."
        }
    }

    private func optionButton(
        icon: String,
        title: String,
        caption: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9.0) {
                Image(systemName: icon)
                    .font(.system(size: 13.0, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28.0, height: 28.0)
                    .background(ChamferedRectangle(cut: 3.0).fill(tint.opacity(0.12)))
                    .overlay {
                        ChamferedRectangle(cut: 3.0)
                            .stroke(tint.opacity(0.45), lineWidth: 1.0)
                    }

                VStack(alignment: .leading, spacing: 2.0) {
                    Text(title.uppercased())
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(caption)
                        .font(EndfieldFont.label(8.0))
                        .tracking(0.6)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0.0)
            }
            .padding(.horizontal, 10.0)
            .padding(.vertical, 9.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChamferedRectangle(cut: 4.0).fill(EndfieldPalette.bgPanel))
            .overlay {
                ChamferedRectangle(cut: 4.0)
                    .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(caption)")
    }
}
