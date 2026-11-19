import Foundation
import SwiftUI
import SwiftData
import UIKit

public struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.name)])
    private var routines: [Routine]

    @State private var activeSession: WorkoutSession? = nil
    @State private var selectedRoutineForWorkout: Routine? = nil
    @State private var routineToEdit: Routine? = nil
    @State private var isCreatingNewRoutine = false
    @State private var isEditing = false
    @State private var routinePendingDeletion: Routine? = nil
    @State private var isShowingCardio = false
    @State private var saveErrorMessage: String?

    /// El entreno libre se ejecuta siempre en modo normal: con Big Picture
    /// activo se avisa y se ofrece desactivarlo antes de arrancar.
    @AppStorage(UserSettingsManager.isBigPictureModeEnabledKey)
    private var isBigPictureModeEnabled: Bool = false
    @State private var showingFreeWorkoutBigPictureAlert = false

    /// Las rutinas temporales de los entrenamientos libres viven en el mismo
    /// contexto, pero nunca se listan ni se editan desde aquí.
    private var visibleRoutines: [Routine] {
        return routines.filter { $0.isTemplate }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                TechnicalGridBackground()

                List {
                    if !isEditing {
                        quickActionsRow
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8.0, leading: 16.0, bottom: 6.0, trailing: 16.0))
                    }

                    ForEach(visibleRoutines) { routine in
                        RoutineRowView(
                            routine: routine,
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
                            onRequestDelete: { routinePendingDeletion = routine }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4.0, leading: 16.0, bottom: 4.0, trailing: 16.0))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "EDITAR RUTINAS" : "RUTINAS")
            .navigationBarTitleDisplayMode(.inline)
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
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button(action: confirmEditMode) {
                            Image(systemName: "checkmark")
                                .font(EndfieldFont.mono(12.0, weight: .bold))
                                .foregroundStyle(EndfieldPalette.accentYellow)
                        }
                        .accessibilityLabel("Confirmar cambios")
                    } else {
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
            .alert(
                "Eliminar rutina",
                isPresented: Binding(
                    get: { routinePendingDeletion != nil },
                    set: { if !$0 { routinePendingDeletion = nil } }
                )
            ) {
                Button("Eliminar", role: .destructive) {
                    if let routine = routinePendingDeletion {
                        deleteRoutine(routine)
                    }
                }
                Button("Cancelar", role: .cancel) {
                    routinePendingDeletion = nil
                }
            } message: {
                Text("Se eliminará \"\(routinePendingDeletion?.name ?? "")\". Esta acción no se puede deshacer.")
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
        let routine = FreeWorkoutRoutineStore.prepare(modelContext: modelContext)

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

        let nextOrder = (visibleRoutines.map(\.sortOrder).max() ?? -1) + 1
        let routine = Routine(name: "Nueva rutina", isTemplate: true, sortOrder: nextOrder, exercises: [])
        isCreatingNewRoutine = true
        routineToEdit = routine
    }

    private func canMoveUp(_ routine: Routine) -> Bool {
        guard let index = visibleRoutines.firstIndex(where: { $0.id == routine.id }) else { return false }
        return index > 0
    }

    private func canMoveDown(_ routine: Routine) -> Bool {
        guard let index = visibleRoutines.firstIndex(where: { $0.id == routine.id }) else { return false }
        return index < visibleRoutines.count - 1
    }

    private func moveRoutine(_ routine: Routine, offset: Int) {
        var ordered = visibleRoutines
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
    }

    private func confirmEditMode() {
        PersistenceService.save(modelContext, operation: "guardar la edición de rutinas")
        exitEditMode()
    }

    private func deleteRoutine(_ routine: Routine) {
        modelContext.delete(routine)

        let remaining = visibleRoutines.filter { $0.id != routine.id }
        for (index, item) in remaining.enumerated() {
            item.sortOrder = index
        }

        guard PersistenceService.saveOrRollback(modelContext, operation: "eliminar la rutina") else {
            saveErrorMessage = "No se ha podido eliminar la rutina. Vuelve a intentarlo."
            return
        }

        routinePendingDeletion = nil
    }
}

struct RoutineRowView: View {
    let routine: Routine
    let isEditing: Bool
    let onStart: () -> Void
    let onEdit: () -> Void
    let onLongPress: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRequestDelete: () -> Void

    @State private var suppressNextTap = false
    @State private var dragOffset: CGFloat = 0
    @State private var thresholdHapticTriggered = false

    private let deleteThreshold: CGFloat = 120

    var body: some View {
        ZStack {
            if isEditing && abs(dragOffset) > 24 {
                deleteBackground
                    .opacity(min(1, abs(dragOffset) / CGFloat(120)))
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
                    Text(String(format: "RT-%02d", routine.sortOrder + 1))
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
            .frame(
                maxWidth: .infinity,
                alignment: dragOffset >= 0 ? .leading : .trailing
            )
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

                let horizontal = value.translation.width
                let isHorizontal = abs(horizontal) > abs(value.translation.height)
                let passedThreshold = isHorizontal && abs(horizontal) >= deleteThreshold

                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    dragOffset = 0
                }
                thresholdHapticTriggered = false

                if passedThreshold {
                    onRequestDelete()
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
