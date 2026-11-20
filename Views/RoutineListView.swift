import Foundation
import SwiftUI
import SwiftData
import UIKit

public struct RoutineListView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            RoutineCollectionScreen(scope: .mainList)
        }
    }
}

// MARK: - Ámbito de la pantalla

/// La misma pantalla se usa para la lista principal y para el interior de una
/// carpeta. Solo cambia el conjunto de rutinas que muestra y la navegación.
enum RoutineListScope: Equatable {
    case mainList
    case folder(UUID)
}

/// Hojas de la pantalla. Se presentan con un único `.sheet(item:)` para que
/// crear una carpeta, renombrarla y mover una rutina nunca compitan entre sí.
private enum RoutineListSheet: Identifiable {
    case createFolder
    case renameFolder(RoutineFolder)
    case moveRoutine(Routine)

    var id: String {
        switch self {
        case .createFolder:
            return "create-folder"
        case .renameFolder(let folder):
            return "rename-\(folder.id.uuidString)"
        case .moveRoutine(let routine):
            return "move-\(routine.id.uuidString)"
        }
    }
}

// MARK: - Pantalla

private struct RoutineCollectionScreen: View {
    let scope: RoutineListScope

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.name)])
    private var routines: [Routine]
    @Query(sort: [SortDescriptor(\RoutineFolder.sortOrder), SortDescriptor(\RoutineFolder.name)])
    private var folders: [RoutineFolder]

    @State private var activeSession: WorkoutSession? = nil
    @State private var selectedRoutineForWorkout: Routine? = nil
    @State private var routineToEdit: Routine? = nil
    @State private var isCreatingNewRoutine = false
    @State private var isEditing = false
    @State private var routinePendingDeletion: Routine? = nil
    @State private var pendingDeletionArchives = false
    @State private var activeSheet: RoutineListSheet? = nil
    @State private var pendingSheetNotice: String?
    @State private var folderPendingDeletion: RoutineFolder? = nil
    @State private var folderDeletionRoutineCount: Int = 0
    @State private var folderToOpenID: UUID? = nil
    @State private var routineNotice: String?
    @State private var isShowingCardio = false
    @State private var saveErrorMessage: String?

    /// Tras importar un split, su carpeta se abre automáticamente.
    @StateObject private var importCoordinator = RoutineImportCoordinator.shared

    /// El entreno libre se ejecuta siempre en modo normal: con Big Picture
    /// activo se avisa y se ofrece desactivarlo antes de arrancar.
    @AppStorage(UserSettingsManager.isBigPictureModeEnabledKey)
    private var isBigPictureModeEnabled: Bool = false
    @State private var showingFreeWorkoutBigPictureAlert = false

    // MARK: - Datos derivados

    /// Las rutinas temporales de los entrenos libres viven en el mismo
    /// contexto, pero nunca se listan ni se editan desde aquí.
    private var activeRoutines: [Routine] {
        return routines.filter { $0.isActivePlanRoutine }
    }

    private var isMainList: Bool {
        return scope == .mainList
    }

    private var currentFolder: RoutineFolder? {
        guard case .folder(let folderID) = scope else { return nil }
        return folders.first { $0.id == folderID }
    }

    private var sortedFolders: [RoutineFolder] {
        return RoutineFolderService.sortedFolders(folders)
    }

    private var rows: [RoutineListRow] {
        switch scope {
        case .mainList:
            return RoutineFolderService.mainRows(
                folders: folders,
                activeRoutines: activeRoutines
            )
        case .folder:
            guard let folder = currentFolder else { return [] }
            return RoutineFolderService.rows(in: folder, activeRoutines: activeRoutines)
        }
    }

    /// Rutinas del ámbito actual: las sueltas en la lista principal o las de la
    /// carpeta abierta. El reordenado y la eliminación trabajan solo sobre ellas.
    private var scopeRoutines: [Routine] {
        if let folder = currentFolder {
            return RoutineFolderService.routines(in: folder, from: activeRoutines)
        }
        return RoutineFolderService.looseRoutines(from: activeRoutines, folders: folders)
    }

    private var isCompletelyEmpty: Bool {
        return isMainList && scopeRoutines.isEmpty && sortedFolders.isEmpty
    }

    private var isFolderEmpty: Bool {
        return !isMainList && scopeRoutines.isEmpty
    }

    private var navigationTitleText: String {
        if isEditing {
            return "EDITAR RUTINAS"
        }
        if isMainList {
            return "RUTINAS"
        }
        return (currentFolder?.name ?? "CARPETA").uppercased()
    }

    private var folderDeletionMessage: String {
        let count: Int = folderDeletionRoutineCount
        let noun: String = count == 1 ? "rutina" : "rutinas"
        return "Esta carpeta contiene \(count) \(noun). Si continúas, se eliminará la carpeta y también todas las rutinas que contiene. Esta acción no se puede deshacer."
    }

    // MARK: - Cuerpo

    var body: some View {
        Group {
            if isMainList {
                screenContent
                    .navigationDestination(item: $folderToOpenID) { folderID in
                        RoutineCollectionScreen(scope: .folder(folderID))
                    }
            } else {
                screenContent
            }
        }
        .onAppear {
            consumeRevealedFolder()
        }
        .onChange(of: importCoordinator.folderToReveal) { (_: UUID?, _: UUID?) in
            consumeRevealedFolder()
        }
    }

    /// Abre la carpeta del split recién importado una sola vez.
    private func consumeRevealedFolder() {
        // Solo la lista principal navega a carpetas: una pantalla de carpeta
        // abierta no debe consumir el aviso.
        guard isMainList else { return }
        guard let folderID: UUID = importCoordinator.folderToReveal else { return }
        importCoordinator.folderToReveal = nil
        folderToOpenID = folderID
    }

    private var listContent: some View {
        ZStack {
            TechnicalGridBackground()

            List {
                if isMainList && !isEditing {
                    quickActionsRow
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8.0, leading: 16.0, bottom: 6.0, trailing: 16.0))
                }

                if !isEditing && isCompletelyEmpty {
                    emptyStateRow
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10.0, leading: 16.0, bottom: 10.0, trailing: 16.0))
                }

                if !isEditing && isFolderEmpty {
                    folderEmptyStateRow
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10.0, leading: 16.0, bottom: 10.0, trailing: 16.0))
                }

                ForEach(rows) { row in
                    rowView(row)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Barra de herramientas, entrenamiento y hojas de edición. La cadena de
    /// modificadores se reparte en varias propiedades para que el compilador no
    /// tenga que resolver una única expresión de doscientas líneas.
    private var editableContent: some View {
        listContent
        .alert(
            "No se pudo guardar",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { saveErrorMessage = nil }
                }
            )
        ) {
            Button("Entendido", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isMainList && !isEditing {
                    Button(action: createFolder) {
                        Image(systemName: "folder.badge.plus")
                            .font(EndfieldFont.mono(12.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.accentCyan)
                    }
                    .accessibilityLabel("Nueva carpeta")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button(action: confirmEditMode) {
                        Image(systemName: "checkmark")
                            .font(EndfieldFont.mono(12.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.accentYellow)
                    }
                    .accessibilityLabel("Confirmar cambios")
                } else if isMainList {
                    Button(action: createRoutine) {
                        Image(systemName: "plus")
                            .font(EndfieldFont.mono(12.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.accentYellow)
                    }
                    .accessibilityLabel("Nueva rutina")
                }
            }
        }
        .fullScreenCover(item: $activeSession, onDismiss: {
            selectedRoutineForWorkout = nil
            routineToEdit = nil
        }) { session in
            if let routine = selectedRoutineForWorkout {
                NavigationStack {
                    ActiveWorkoutView(session: session, routine: routine, modelContext: modelContext)
                }
                .interactiveDismissDisabled(true)
            }
        }
        .fullScreenCover(isPresented: $isShowingCardio) {
            CardioView()
        }
        .sheet(item: $routineToEdit, onDismiss: {
            routineToEdit = nil
            isCreatingNewRoutine = false
        }) { routine in
            NavigationStack {
                EditRoutineView(routine: routine, isNewRoutine: isCreatingNewRoutine)
            }
        }
        .sheet(item: $activeSheet, onDismiss: {
            activeSheet = nil
            if let notice = pendingSheetNotice {
                routineNotice = notice
                pendingSheetNotice = nil
            }
        }) { route in
            switch route {
            case .createFolder:
                FolderNameSheet(mode: .create) { notice in
                    pendingSheetNotice = notice
                }
            case .renameFolder(let folder):
                FolderNameSheet(mode: .rename(folder)) { notice in
                    pendingSheetNotice = notice
                }
            case .moveRoutine(let routine):
                MoveRoutineSheet(routine: routine) { notice in
                    pendingSheetNotice = notice
                }
            }
        }
    }

    /// Confirmaciones de eliminación o archivado de rutinas y carpetas.
    private var deletionContent: some View {
        editableContent
        .alert(
            pendingDeletionArchives ? "Archivar rutina" : "Eliminar rutina",
            isPresented: Binding(
                get: { routinePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        routinePendingDeletion = nil
                        pendingDeletionArchives = false
                    }
                }
            )
        ) {
            if pendingDeletionArchives {
                Button("Archivar") {
                    if let routine = routinePendingDeletion {
                        archiveReferencedRoutine(routine)
                    }
                }
            } else {
                Button("Eliminar", role: .destructive) {
                    if let routine = routinePendingDeletion {
                        deleteRoutine(routine)
                    }
                }
            }
            Button("Cancelar", role: .cancel) {
                routinePendingDeletion = nil
                pendingDeletionArchives = false
            }
        } message: {
            Text(
                pendingDeletionArchives
                    ? "\"\(routinePendingDeletion?.name ?? "")\" está referenciada por un plan asistido. Se archivará para conservar el historial y no se borrará."
                    : "Se eliminará \"\(routinePendingDeletion?.name ?? "")\". Esta acción no se puede deshacer."
            )
        }
    }

    /// Avisos informativos de la pantalla.
    private var screenContent: some View {
        deletionContent
        .alert(
            "¿Eliminar carpeta?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        folderPendingDeletion = nil
                        folderDeletionRoutineCount = 0
                    }
                }
            )
        ) {
            Button("Cancelar", role: .cancel) {
                folderPendingDeletion = nil
                folderDeletionRoutineCount = 0
            }
            Button("Eliminar carpeta y rutinas", role: .destructive) {
                if let folder = folderPendingDeletion {
                    deleteFolder(folder)
                }
            }
        } message: {
            Text(folderDeletionMessage)
        }
        .alert(
            "Aviso de rutina",
            isPresented: Binding(
                get: { routineNotice != nil },
                set: { isPresented in
                    if !isPresented { routineNotice = nil }
                }
            )
        ) {
            Button("Entendido", role: .cancel) {
                routineNotice = nil
            }
        } message: {
            Text(routineNotice ?? "")
        }
        .alert("Modo Big Picture activo", isPresented: $showingFreeWorkoutBigPictureAlert) {
            Button("Cancelar", role: .cancel) {}

            Button("Desactivar y continuar") {
                isBigPictureModeEnabled = false
                beginFreeWorkout()
            }
        } message: {
            Text("No es posible entrenar libremente con el modo Big Picture activo. ¿Quieres desactivarlo para continuar?")
        }
    }

    // MARK: - Filas

    @ViewBuilder
    private func rowView(_ row: RoutineListRow) -> some View {
        switch row {
        case .folder(let folder):
            folderRowView(folder)

        case .routine(let routine, let position):
            RoutineRowView(
                routine: routine,
                displayIndex: position,
                isEditing: isEditing,
                onStart: { startWorkout(with: routine) },
                onEdit: {
                    guard !isEditing else { return }
                    isCreatingNewRoutine = false
                    routineToEdit = routine
                },
                onLongPress: { enterEditMode() },
                canMoveUp: canMoveUp(routine),
                canMoveDown: canMoveDown(routine),
                onMoveUp: { moveRoutine(routine, offset: -1) },
                onMoveDown: { moveRoutine(routine, offset: 1) },
                onRequestDelete: { requestDeletion(of: routine) },
                onRequestMove: { activeSheet = .moveRoutine(routine) }
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4.0, leading: 16.0, bottom: 4.0, trailing: 16.0))
        }
    }

    private func folderRowView(_ folder: RoutineFolder) -> some View {
        let index: Int = sortedFolders.firstIndex { $0.id == folder.id } ?? 0
        // Misma fuente de verdad que la alerta de eliminación: solo rutinas
        // activas y visibles; las archivadas no cuentan.
        let count: Int = RoutineFolderService.activeRoutineCount(in: folder, routines: routines)

        return HStack(spacing: 0.0) {
            Button {
                guard !isEditing else { return }
                folderToOpenID = folder.id
            } label: {
                RoutineFolderCardContent(
                    folder: folder,
                    index: index,
                    routineCount: count
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir la carpeta \(folder.name), \(count) rutinas")

            Menu {
                Button {
                    activeSheet = .renameFolder(folder)
                } label: {
                    Label("Renombrar carpeta", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    requestFolderDeletion(folder)
                } label: {
                    Label("Eliminar carpeta", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .frame(width: 28.0, height: 28.0)
                    .background(ChamferedRectangle(cut: 4.0).fill(EndfieldPalette.bgElevated))
                    .overlay {
                        ChamferedRectangle(cut: 4.0)
                            .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                    }
                    .padding(.trailing, 12.0)
            }
            .accessibilityLabel("Opciones de la carpeta \(folder.name)")
        }
        .background(EndfieldPalette.bgPanel)
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cornerCut))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4.0, leading: 16.0, bottom: 4.0, trailing: 16.0))
    }

    // MARK: - Acciones rápidas

    private var quickActionsRow: some View {
        HStack(spacing: 8.0) {
            quickActionButton(
                icon: "bolt.fill",
                title: "ENTRENO LIBRE",
                caption: "AÑADIR AL VUELO",
                tint: EndfieldPalette.accentCyan,
                action: startFreeWorkout
            )

            quickActionButton(
                icon: "figure.run",
                title: "CARDIO",
                caption: "TIEMPO + TIPO",
                tint: EndfieldPalette.accentYellow,
                action: { isShowingCardio = true }
            )
        }
    }

    private func quickActionButton(
        icon: String,
        title: String,
        caption: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9.0) {
                Image(systemName: icon)
                    .font(.system(size: 14.0, weight: .semibold))
                    .frame(width: 26.0, height: 26.0)
                    .background(ChamferedRectangle(cut: 3.0).fill(tint.opacity(0.12)))
                    .overlay {
                        ChamferedRectangle(cut: 3.0)
                            .stroke(tint.opacity(0.5), lineWidth: 1.0)
                    }

                VStack(alignment: .leading, spacing: 2.0) {
                    Text(title)
                        .font(EndfieldFont.mono(10.0, weight: .heavy))
                        .tracking(0.9)
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(caption)
                        .font(EndfieldFont.label(7.0, weight: .regular))
                        .tracking(0.4)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Spacer(minLength: 0.0)
            }
            .padding(.horizontal, 9.0)
            .padding(.vertical, 8.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChamferedRectangle(cut: 5.0).fill(EndfieldPalette.bgPanel))
            .overlay {
                ChamferedRectangle(cut: 5.0)
                    .stroke(tint.opacity(0.35), lineWidth: 1.0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(caption)")
    }

    /// Arranca un entrenamiento sin rutina: el usuario añade los ejercicios y
    /// las series que quiera desde la propia pantalla de entrenamiento.
    private func startFreeWorkout() {
        guard !isEditing else { return }

        guard !isBigPictureModeEnabled else {
            showingFreeWorkoutBigPictureAlert = true
            return
        }

        beginFreeWorkout()
    }

    private func beginFreeWorkout() {
        guard !ActiveWorkoutStateStore.hasActiveWorkout else {
            saveErrorMessage = "Ya hay un entrenamiento activo. Termínalo o descártalo antes de empezar otro."
            return
        }

        routineToEdit = nil
        guard let routine = FreeWorkoutRoutineStore.prepare(modelContext: modelContext) else {
            saveErrorMessage = "No se ha podido preparar el entreno libre. Vuelve a intentarlo."
            return
        }

        let session = WorkoutSession(startDate: Date(), totalVolumeKg: 0.0, routineName: routine.name)
        modelContext.insert(session)

        guard PersistenceService.saveOrRollback(modelContext, operation: "iniciar el entreno libre") else {
            saveErrorMessage = "No se ha podido iniciar el entreno libre. Comprueba el espacio libre del dispositivo."
            return
        }

        selectedRoutineForWorkout = routine
        activeSession = session
    }

    private func startWorkout(with routine: Routine) {
        guard !isEditing else { return }
        guard !ActiveWorkoutStateStore.hasActiveWorkout else {
            saveErrorMessage = "Ya hay un entrenamiento activo. Termínalo o descártalo antes de empezar otro."
            return
        }

        routineToEdit = nil
        let session = WorkoutSession(startDate: Date(), totalVolumeKg: 0.0, routineName: routine.name)
        modelContext.insert(session)

        guard PersistenceService.saveOrRollback(modelContext, operation: "iniciar el entrenamiento") else {
            saveErrorMessage = "No se ha podido iniciar el entrenamiento. Comprueba el espacio libre del dispositivo."
            return
        }

        selectedRoutineForWorkout = routine
        activeSession = session
    }

    private func createRoutine() {
        guard !isEditing else { return }

        // Las rutinas nuevas no se asignan automáticamente a ninguna carpeta.
        let routine = RoutineService.makeManualDraftRoutine(after: activeRoutines)
        isCreatingNewRoutine = true
        routineToEdit = routine
    }

    // MARK: - Carpetas

    private func createFolder() {
        guard !isEditing else { return }
        pendingSheetNotice = nil
        activeSheet = .createFolder
    }

    private func requestFolderDeletion(_ folder: RoutineFolder) {
        guard RoutineFolderService.requiresDeletionConfirmation(for: folder, routines: routines) else {
            // Carpeta vacía: se elimina directamente, sin confirmación.
            deleteFolder(folder)
            return
        }

        folderDeletionRoutineCount = RoutineFolderService.activeRoutineCount(
            in: folder,
            routines: routines
        )
        folderPendingDeletion = folder
    }

    private func deleteFolder(_ folder: RoutineFolder) {
        do {
            let summary: RoutineFolderService.DeletionSummary = try RoutineFolderService.deleteFolder(
                folder,
                containedRoutines: routines,
                context: modelContext
            )

            folderPendingDeletion = nil
            folderDeletionRoutineCount = 0

            if summary.archivedRoutineCount > 0 {
                routineNotice = "Se han archivado \(summary.archivedRoutineCount) rutina(s) referenciadas por un plan asistido para conservar el historial y las sesiones."
            }
        } catch {
            folderPendingDeletion = nil
            folderDeletionRoutineCount = 0
            saveErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "No se ha podido eliminar la carpeta."
        }
    }

    // MARK: - Estado vacío

    /// Instalación sin rutinas ni carpetas (por ejemplo, tras terminar la
    /// configuración inicial con «Crear mis rutinas más tarde»).
    private var emptyStateRow: some View {
        VStack(alignment: .leading, spacing: 12.0) {
            HStack(spacing: 6.0) {
                Text("RT-00")
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

                Text("0 EX")
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }

            Text("SIN RUTINAS TODAVÍA")
                .font(EndfieldFont.mono(15.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Todavía no hay ninguna rutina creada. Crea la primera y añade los ejercicios que quieras para empezar a registrar entrenamientos.")
                .font(EndfieldFont.mono(10.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: createRoutine) {
                HStack(spacing: 6.0) {
                    Image(systemName: "plus")
                        .font(EndfieldFont.mono(10.0, weight: .bold))

                    Text("CREAR MI PRIMERA RUTINA")
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .tracking(1.0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(EndfieldPalette.bgPrimary)
                .padding(.horizontal, 12.0)
                .padding(.vertical, 10.0)
                .frame(maxWidth: .infinity)
                .background(EndfieldPalette.accentYellow)
                .clipShape(ChamferedRectangle(cut: 4.0))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Crear mi primera rutina")
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

    /// Carpeta abierta sin rutinas: explica cómo meter rutinas sin crear una
    /// nueva automáticamente dentro de la carpeta.
    private var folderEmptyStateRow: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            Text("CARPETA VACÍA")
                .font(EndfieldFont.mono(13.0, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.textPrimary)

            Text("No hay ninguna rutina dentro de esta carpeta. Mueve una desde la lista principal manteniéndola pulsada y deslizándola hacia la izquierda.")
                .font(EndfieldFont.mono(10.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Orden y edición

    private func canMoveUp(_ routine: Routine) -> Bool {
        guard let index = scopeRoutines.firstIndex(where: { $0.id == routine.id }) else { return false }
        return index > 0
    }

    private func canMoveDown(_ routine: Routine) -> Bool {
        guard let index = scopeRoutines.firstIndex(where: { $0.id == routine.id }) else { return false }
        return index < scopeRoutines.count - 1
    }

    private func moveRoutine(_ routine: Routine, offset: Int) {
        var ordered = scopeRoutines
        guard let index = ordered.firstIndex(where: { $0.id == routine.id }) else { return }

        let targetIndex = index + offset
        guard ordered.indices.contains(targetIndex) else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            ordered.swapAt(index, targetIndex)
            for (position, item) in ordered.enumerated() {
                item.sortOrder = position
            }
        }
        PersistenceService.save(modelContext, operation: "reordenar las rutinas")
    }

    private func enterEditMode() {
        guard !isEditing else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
    }

    private func exitEditMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
        routinePendingDeletion = nil
        pendingDeletionArchives = false
        routineNotice = nil
    }

    private func confirmEditMode() {
        PersistenceService.save(modelContext, operation: "guardar la edición de rutinas")
        exitEditMode()
    }

    private func requestDeletion(of routine: Routine) {
        switch RoutineService.deletionPolicy(for: routine, context: modelContext) {
        case .archiveReferenced:
            pendingDeletionArchives = true
            routinePendingDeletion = routine

        case .delete:
            pendingDeletionArchives = false
            routinePendingDeletion = routine
        }
    }

    private func archiveReferencedRoutine(_ routine: Routine) {
        let remaining = scopeRoutines.filter { $0.id != routine.id }
        routine.isArchived = true
        for (index, item) in remaining.enumerated() {
            item.sortOrder = index
        }

        guard PersistenceService.saveOrRollback(modelContext, operation: "archivar la rutina referenciada") else {
            saveErrorMessage = "No se ha podido archivar la rutina. Vuelve a intentarlo."
            return
        }

        routinePendingDeletion = nil
        pendingDeletionArchives = false
        routineNotice = "«\(routine.name)» está referenciada por un plan asistido. Se ha archivado para conservar el historial, sin borrar la rutina ni sus sesiones."
    }

    private func deleteRoutine(_ routine: Routine) {
        switch RoutineService.deletionPolicy(for: routine, context: modelContext) {
        case .archiveReferenced:
            archiveReferencedRoutine(routine)
            return

        case .delete:
            break
        }

        modelContext.delete(routine)

        let remaining = scopeRoutines.filter { $0.id != routine.id }
        for (index, item) in remaining.enumerated() {
            item.sortOrder = index
        }

        guard PersistenceService.saveOrRollback(modelContext, operation: "eliminar la rutina") else {
            saveErrorMessage = "No se ha podido eliminar la rutina. Vuelve a intentarlo."
            return
        }

        routinePendingDeletion = nil
        pendingDeletionArchives = false
    }
}

// MARK: - Tarjeta de carpeta

/// Tarjeta de carpeta compartida con la pestaña Rutinas y el selector de
/// Configuración → Compartir rutina, para no duplicar su diseño.
struct RoutineFolderCardContent: View {
    let folder: RoutineFolder
    let index: Int
    let routineCount: Int

    var body: some View {
        HStack(spacing: 10.0) {
            Image(systemName: routineCount == 0 ? "folder" : "folder.fill")
                .font(.system(size: 13.0, weight: .semibold))
                .foregroundStyle(EndfieldPalette.accentCyan)
                .frame(width: 30.0, height: 30.0)
                .background(ChamferedRectangle(cut: 3.0).fill(EndfieldPalette.accentCyan.opacity(0.12)))
                .overlay {
                    ChamferedRectangle(cut: 3.0)
                        .stroke(EndfieldPalette.accentCyan.opacity(0.45), lineWidth: 1.0)
                }
                .fixedSize()

            VStack(alignment: .leading, spacing: 5.0) {
                HStack(spacing: 6.0) {
                    Text(String(format: "FL-%02d", index + 1))
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

                    Text("\(routineCount) RT")
                        .font(EndfieldFont.label(8.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                }

                Text(folder.name.uppercased())
                    .font(EndfieldFont.mono(15.0, weight: .heavy))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(routineCount == 1 ? "1 rutina en la carpeta" : "\(routineCount) rutinas en la carpeta")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6.0)

            Image(systemName: "chevron.right")
                .font(EndfieldFont.mono(10.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize()
        }
        .padding(.leading, 12.0)
        .padding(.vertical, 12.0)
        .padding(.trailing, 10.0)
        .contentShape(Rectangle())
    }
}

// MARK: - Tarjeta de rutina

struct RoutineRowView: View {
    let routine: Routine
    /// Posición dentro del ámbito actual (lista principal o carpeta). Se usa
    /// para el código técnico sin depender del `sortOrder` global.
    let displayIndex: Int
    let isEditing: Bool
    let onStart: () -> Void
    let onEdit: () -> Void
    let onLongPress: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRequestDelete: () -> Void
    let onRequestMove: () -> Void

    @State private var suppressNextTap = false
    @State private var dragOffset: CGFloat = 0
    @State private var thresholdHapticTriggered = false

    private let deleteThreshold: CGFloat = RoutineFolderService.swipeThreshold

    var body: some View {
        ZStack {
            if isEditing && abs(dragOffset) > 24 {
                if dragOffset > 0 {
                    deleteBackground
                        .opacity(min(1, abs(dragOffset) / deleteThreshold))
                } else {
                    moveBackground
                        .opacity(min(1, abs(dragOffset) / deleteThreshold))
                }
            }

            cardSurface
        }
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cornerCut))
        .id(routine.id)
        .onChange(of: isEditing) { _, editing in
            if !editing {
                dragOffset = 0
                thresholdHapticTriggered = false
            }
        }
    }

    private var cardSurface: some View {
        HStack(spacing: 8.0) {
            routineContent
            trailingControls
        }
        .background(EndfieldPalette.bgPanel)
        .overlay(
            ChamferedRectangle(cut: EndfieldMetrics.cornerCut)
                .stroke(isEditing ? EndfieldPalette.borderActive : EndfieldPalette.borderSubtle, lineWidth: 1.0)
        )
        .offset(x: dragOffset)
    }

    private var routineContent: some View {
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

            if !isEditing {
                HStack(spacing: 5.0) {
                    Image(systemName: "play.fill")
                        .font(EndfieldFont.mono(9.0, weight: .bold))

                    Text("INICIAR")
                        .font(EndfieldFont.mono(10.0, weight: .heavy))
                        .tracking(1.0)
                }
                .foregroundStyle(EndfieldPalette.bgPrimary)
                .padding(.horizontal, 10.0)
                .padding(.vertical, 7.0)
                .background(EndfieldPalette.accentYellow)
                .clipShape(ChamferedRectangle(cut: 4.0))
                .fixedSize()
            }
        }
        .padding(12.0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditing, !suppressNextTap else { return }
            onStart()
        }
        .onLongPressGesture(
            minimumDuration: 0.5,
            maximumDistance: 20,
            perform: {
                suppressNextTap = true
                onLongPress()
            },
            onPressingChanged: { isPressing in
                guard !isPressing, suppressNextTap else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    suppressNextTap = false
                }
            }
        )
        .simultaneousGesture(swipeGesture, including: isEditing ? .all : .none)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            isEditing
                ? "Editar \(routine.name)"
                : "Iniciar entrenamiento con \(routine.name)"
        )
        .accessibilityAction(named: "Mover a una carpeta") {
            guard isEditing else { return }
            onRequestMove()
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isEditing {
            if canMoveUp || canMoveDown {
                VStack(spacing: 5.0) {
                    if canMoveUp {
                        moveButton(
                            icon: "chevron.up",
                            action: onMoveUp,
                            accessibilityLabel: "Subir \(routine.name)"
                        )
                    }

                    if canMoveDown {
                        moveButton(
                            icon: "chevron.down",
                            action: onMoveDown,
                            accessibilityLabel: "Bajar \(routine.name)"
                        )
                    }
                }
                .padding(.trailing, 10.0)
            }
        } else {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(EndfieldFont.mono(10.0, weight: .bold))
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.textSecondary, size: 28.0))
            .padding(.trailing, 12.0)
            .accessibilityLabel("Editar rutina \(routine.name)")
        }
    }

    private var deleteBackground: some View {
        ZStack {
            EndfieldPalette.accentRed

            HStack(spacing: 8.0) {
                Image(systemName: "trash.fill")
                    .font(EndfieldFont.mono(11.0, weight: .bold))

                Text("ELIMINAR")
                    .font(EndfieldFont.mono(11.0, weight: .heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(EndfieldPalette.bgPrimary)
            .padding(.horizontal, 20.0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Fondo del gesto hacia la izquierda: mover a una carpeta.
    private var moveBackground: some View {
        ZStack {
            EndfieldPalette.accentCyan

            HStack(spacing: 8.0) {
                Image(systemName: "folder.fill.badge.plus")
                    .font(EndfieldFont.mono(11.0, weight: .bold))

                Text("MOVER")
                    .font(EndfieldFont.mono(11.0, weight: .heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(EndfieldPalette.bgPrimary)
            .padding(.horizontal, 20.0)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard isEditing else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                dragOffset = value.translation.width

                if abs(value.translation.width) >= deleteThreshold, !thresholdHapticTriggered {
                    thresholdHapticTriggered = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .onEnded { value in
                guard isEditing else { return }

                let action: RoutineSwipeAction = RoutineFolderService.swipeAction(
                    horizontal: value.translation.width,
                    vertical: value.translation.height,
                    threshold: deleteThreshold
                )

                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    dragOffset = 0
                }
                thresholdHapticTriggered = false

                switch action {
                case .none:
                    break
                case .deleteRoutine:
                    onRequestDelete()
                case .moveToFolder:
                    onRequestMove()
                }
            }
    }

    private func moveButton(
        icon: String,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(EndfieldFont.mono(9.0, weight: .bold))
        }
        .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.textSecondary, size: 26.0))
        .accessibilityLabel(accessibilityLabel)
    }
}
