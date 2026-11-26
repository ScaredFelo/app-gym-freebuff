import SwiftUI
import SwiftData
import UIKit

/// Editor de rutinas con la identidad "Endfield": paneles angulares, telemetría
/// monoespaciada y controles `−  valor  +` en lugar de los `Form`/`Stepper`
/// nativos. Toda la lógica de persistencia se mantiene intacta.
///
/// Incluye el modo reordenación: una pulsación larga sobre el nombre de un
/// ejercicio comprime todas las filas a su nombre y activa el arrastre. Mientras
/// se arrastra solo cambia el borrador de orden: la rutina no se toca hasta
/// pulsar «HECHO», y entonces solo se renumera `sortOrder`, sin modificar
/// ninguna otra propiedad ni el historial.
struct EditRoutineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var routine: Routine
    let isNewRoutine: Bool

    /// Nombre del sistema de coordenadas del contenedor de la lista compacta.
    ///
    /// Se declara una sola vez y no depende del orden: el contenedor no se mueve
    /// cuando las filas se recolocan, así que la traslación del dedo se mide
    /// siempre contra la misma referencia espacial.
    private static let reorderCoordinateSpaceName: String = "appgym.routine.reorder"

    @State private var showingExercisePicker = false
    @State private var exercisePendingRemoval: RoutineExercise?
    @State private var exerciseToConfigure: Exercise?
    /// Fila cuya sustitución de ejercicio está abierta. Se guarda el propio
    /// `RoutineExercise` (identidad estable) en lugar de un índice de la lista.
    @State private var exercisePendingReplacement: RoutineExercise?

    /// Orden que se está viendo en el modo reordenación. Vive aparte de la
    /// rutina para no escribir en SwiftData en cada fotograma del arrastre.
    @State private var orderDraft = RoutineExerciseOrderDraft()
    /// Arrastre en curso. Guarda el identificador de la fila, su posición al
    /// agarrarla y el desplazamiento del dedo, nunca un índice inestable.
    @State private var reorderDrag: RoutineReorderDrag?
    /// Generador preparado al entrar en el modo, para que la señal de cambio de
    /// posición no llegue con retardo. Se descarta al salir del modo.
    @State private var reorderImpact: UIImpactFeedbackGenerator?
    /// Máquina de estados del gesto: un único propietario por interacción. Una
    /// pulsación larga solo prepara la fila; el arrastre no empieza hasta que
    /// el dedo se ha movido de verdad.
    @State private var reorderGesture = RoutineReorderGestureState()
    /// Error recuperable al confirmar el orden. El modo no se cierra solo.
    @State private var reorderErrorMessage: String?

    private var sortedExercises: [RoutineExercise] {
        routine.orderedExercises
    }

    var body: some View {
        ZStack {
            TechnicalGridBackground()

            ScrollView {
                LazyVStack(spacing: 14.0) {
                    modePanel
                    namePanel

                    if orderDraft.isActive {
                        reorderList
                    } else if sortedExercises.isEmpty {
                        emptyStatePanel
                    } else {
                        ForEach(Array(sortedExercises.enumerated()), id: \.element.id) { index, routineExercise in
                            RoutineExerciseEditorRow(
                                routineExercise: routineExercise,
                                index: index,
                                onBeginReorder: beginReordering,
                                onRemove: { exercisePendingRemoval = routineExercise },
                                onChangeExercise: { exercisePendingReplacement = routineExercise }
                            )
                        }
                    }

                    addExerciseButton

                    Color.clear
                        .frame(height: 8.0)
                }
                .padding(.horizontal, 16.0)
                .padding(.vertical, 16.0)
            }
            .scrollIndicators(.hidden)
            .alert(
                "Orden no confirmado",
                isPresented: Binding(
                    get: { reorderErrorMessage != nil },
                    set: { if !$0 { reorderErrorMessage = nil } }
                )
            ) {
                Button("Entendido", role: .cancel) { reorderErrorMessage = nil }
            } message: {
                Text(reorderErrorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .tint(EndfieldPalette.accentYellow)
        .navigationTitle("EDITAR RUTINA")
        .navigationBarTitleDisplayMode(.inline)
        .withKeyboardDismiss()
        // Cualquier salida distinta de «HECHO» (botón atrás, cierre del editor)
        // descarta el borrador. Nunca confirma un orden provisional.
        .onDisappear {
            cancelReordering()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") {
                    // Cancelar descarta toda la sesión de reordenación antes de
                    // cerrar el editor.
                    cancelReordering()
                    discardNewRoutineIfNeeded()
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if orderDraft.isActive {
                    // Salida explícita del modo: guarda el orden y devuelve la
                    // vista normal con toda la información de cada ejercicio.
                    Button("HECHO") {
                        finishReordering()
                    }
                    .fontWeight(.bold)
                    .accessibilityLabel("Terminar de reordenar los ejercicios")
                } else {
                    Menu {
                        ForEach(sortedExercises) { routineExercise in
                            if let exercise = routineExercise.exercise {
                                Button {
                                    exerciseToConfigure = exercise
                                } label: {
                                    Label(exercise.name, systemImage: "gearshape")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .disabled(sortedExercises.isEmpty)
                    .accessibilityLabel("Ajustar ejercicio")

                    Button("GUARDAR") {
                        for routineExercise in routine.exercises where routineExercise.modelContext == nil {
                            modelContext.insert(routineExercise)
                        }

                        if routine.modelContext == nil {
                            modelContext.insert(routine)
                        }

                        PersistenceService.save(modelContext, operation: "guardar la rutina")
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                let nextOrder = (routine.exercises.map(\.sortOrder).max() ?? -1) + 1
                let routineExercise = RoutineExercise(
                    exercise: exercise,
                    defaultSets: exercise.trackingMode == .minutes ? 1 : 3,
                    targetRepsMin: exercise.targetRepsMin,
                    targetRepsMax: exercise.targetRepsMax,
                    sortOrder: nextOrder
                )
                if !isNewRoutine {
                    modelContext.insert(routineExercise)
                }
                routine.exercises.append(routineExercise)
                if !isNewRoutine {
                    PersistenceService.save(modelContext, operation: "guardar la rutina")
                }
            }
        }
        .sheet(item: $exercisePendingReplacement) { routineExercise in
            // El selector no conoce la rutina: devuelve el ejercicio y aquí se
            // aplica el único cambio permitido, sobre la misma fila.
            ExerciseSelectionView(currentExerciseID: routineExercise.exercise?.id) { exercise in
                guard routineExercise.replaceExercise(with: exercise) else { return }

                if !isNewRoutine {
                    PersistenceService.save(modelContext, operation: "guardar la rutina")
                }
            }
        }
        .sheet(item: $exerciseToConfigure) { exercise in
            ExerciseSettingsView(exercise: exercise)
        }
        .alert(
            "Eliminar ejercicio",
            isPresented: Binding(
                get: { exercisePendingRemoval != nil },
                set: { if !$0 { exercisePendingRemoval = nil } }
            )
        ) {
            Button("Eliminar", role: .destructive) {
                if let routineExercise = exercisePendingRemoval {
                    routine.exercises.removeAll { $0.id == routineExercise.id }
                    if !isNewRoutine {
                        modelContext.delete(routineExercise)
                    }
                    normalizeSortOrder()
                    if !isNewRoutine {
                        PersistenceService.save(modelContext, operation: "guardar la rutina")
                    }
                }
                exercisePendingRemoval = nil
            }
            Button("Cancelar", role: .cancel) { exercisePendingRemoval = nil }
        } message: {
            Text("Este ejercicio se quitará de la rutina.")
        }
    }

    // MARK: - Paneles

    private var modePanel: some View {
        TacticalPanel(code: "RUT.EDIT", title: isNewRoutine ? "NUEVA RUTINA" : "MODO EDICIÓN", contentPadding: 12.0) {
            HStack(alignment: .top, spacing: 9.0) {
                Image(systemName: "pencil.and.list.clipboard")
                    .font(EndfieldFont.mono(13.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .fixedSize()

                Text("Los cambios se guardan en esta rutina, no en el entrenamiento activo.")
                    .font(EndfieldFont.mono(10.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var namePanel: some View {
        TacticalPanel(code: "RUT.01", title: "NOMBRE", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 6.0) {
                Text("IDENTIFICADOR")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                TextField("Nombre de la rutina", text: $routine.name)
                    .tacticalField()
                    .accessibilityLabel("Nombre de la rutina")
            }
        }
    }

    private var emptyStatePanel: some View {
        TacticalPanel(code: "RUT.ERR", title: "SIN EJERCICIOS", contentPadding: 12.0) {
            Text("Todavía no hay ejercicios. Añade el primero para empezar.")
                .font(EndfieldFont.mono(10.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addExerciseButton: some View {
        Button {
            showingExercisePicker = true
        } label: {
            HStack(spacing: 8.0) {
                Image(systemName: "plus")
                    .font(EndfieldFont.mono(12.0, weight: .bold))

                Text("AÑADIR EJERCICIO")
                    .font(EndfieldFont.mono(12.0, weight: .bold))
                    .tracking(1.2)
            }
        }
        .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentCyan))
        .disabled(orderDraft.isActive)
        .opacity(orderDraft.isActive ? 0.4 : 1.0)
        .accessibilityLabel("Añadir ejercicio a la rutina")
    }

    // MARK: - Modo reordenación

    /// Lista compacta: una fila por ejercicio con su nombre y el asa de
    /// arrastre. La información secundaria no se borra, solo deja de pintarse
    /// mientras el modo está activo.
    ///
    /// Las filas salen de `reorderRows`, que exige una correspondencia exacta
    /// entre el borrador y la rutina. Si no la hay, la lista se sustituye por
    /// el panel de recuperación: nunca se pinta una lista incompleta.
    @ViewBuilder
    private var reorderList: some View {
        if let rows = reorderRows {
            VStack(spacing: RoutineReorderRowMetrics.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, routineExercise in
                    RoutineReorderRow(
                        routineExercise: routineExercise,
                        index: index,
                        isDragging: reorderDrag?.id == routineExercise.id,
                        offset: reorderDrag?.id == routineExercise.id ? (reorderDrag?.visualOffset ?? 0.0) : 0.0,
                        coordinateSpaceName: Self.reorderCoordinateSpaceName,
                        onLongPressRecognized: { holdReorder(routineExercise.id) },
                        onMovement: { translation in
                            moveReorder(routineExercise.id, translation: translation)
                        },
                        onGestureEnded: { translation in
                            endReorder(routineExercise.id, translation: translation)
                        },
                        onGestureCancelled: { cancelReorderGesture(routineExercise.id) }
                    )
                    .zIndex(reorderDrag?.id == routineExercise.id ? 1.0 : 0.0)
                }

                Text("Mantén pulsado un ejercicio y arrástralo. El resto de datos no cambia.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4.0)
                    .accessibilityLabel("Mantén pulsado un ejercicio y arrástralo para cambiar el orden")
            }
            // Todas las filas miden su gesto en este contenedor, que no cambia de
            // sitio mientras se reordena: la referencia espacial no se desplaza con
            // la fila agarrada.
            .coordinateSpace(.named(Self.reorderCoordinateSpaceName))
        } else {
            reorderRecoveryPanel
        }
    }

    /// Ejercicios en el orden del borrador, resueltos contra la rutina.
    ///
    /// Devuelve `nil` en cuanto el borrador no describe exactamente los
    /// ejercicios de la rutina (identificador ausente, repetido o ajeno). En ese
    /// caso no se oculta ninguna fila: el modo pasa al panel de recuperación.
    private var reorderRows: [RoutineExercise]? {
        switch orderDraft.resolve(against: routine.exercises) {
        case .inconsistent:
            return nil

        case .ordered(let orderedIDs):
            var byID: [UUID: RoutineExercise] = [:]
            for routineExercise in routine.exercises {
                guard byID[routineExercise.id] == nil else { return nil }
                byID[routineExercise.id] = routineExercise
            }

            var rows: [RoutineExercise] = []
            for id in orderedIDs {
                guard let routineExercise = byID[id] else { return nil }
                rows.append(routineExercise)
            }
            return rows
        }
    }

    /// Recuperación segura cuando el borrador y la rutina no coinciden: se ven
    /// todos los ejercicios en su orden guardado y se puede volver al editor sin
    /// perder ninguno. No se aplica ningún orden parcial ni se escribe nada.
    private var reorderRecoveryPanel: some View {
        VStack(spacing: RoutineReorderRowMetrics.rowSpacing) {
            TacticalPanel(code: "RUT.ORD", title: "ORDEN NO VÁLIDO", contentPadding: 12.0) {
                VStack(alignment: .leading, spacing: 8.0) {
                    Text("El orden provisional no coincide con los ejercicios de la rutina. No se ha modificado ni guardado nada.")
                        .font(EndfieldFont.mono(10.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    Button("VOLVER AL EDITOR") {
                        cancelReordering()
                    }
                    .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentYellow))
                    .accessibilityLabel("Volver al editor descartando el orden provisional")
                }
            }

            ForEach(Array(routine.orderedExercises.enumerated()), id: \.element.id) { index, routineExercise in
                RoutineReorderRow(
                    routineExercise: routineExercise,
                    index: index,
                    isDragging: false,
                    offset: 0.0,
                    coordinateSpaceName: Self.reorderCoordinateSpaceName,
                    isInteractive: false,
                    onLongPressRecognized: {},
                    onMovement: { _ in },
                    onGestureEnded: { _ in },
                    onGestureCancelled: {}
                )
            }
        }
    }

    /// Entra en el modo tras la pulsación larga. Afecta a todas las filas y
    /// confirma la activación con una señal breve.
    private func beginReordering() {
        guard !orderDraft.isActive else { return }

        guard orderDraft.begin(with: routine.exercises) else { return }

        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare()
        reorderImpact = impact
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Pulsación larga reconocida. Solo prepara la fila: no crea un arrastre ni
    /// toca el borrador. Repetir el aviso no vuelve a agarrar nada.
    private func holdReorder(_ id: UUID) {
        guard orderDraft.isActive else { return }

        switch reorderGesture.longPressRecognized(id) {
        case .holding:
            reorderImpact?.prepare()

        case .cancelled(let previousID):
            // Un gesto anterior se quedó sin aviso de fin: se deshace su
            // movimiento provisional y la pulsación nueva toma el control.
            cancelDrag(previousID)
            reorderImpact?.prepare()

        default:
            break
        }
    }

    /// Fotograma del gesto. El arrastre no empieza hasta que el dedo se ha
    /// desplazado de verdad; por debajo del umbral no se toca nada.
    private func moveReorder(_ id: UUID, translation: CGFloat) {
        switch reorderGesture.moved(id, translation: translation) {
        case .began(let draggedID, let startTranslation):
            beginDrag(draggedID, translation: startTranslation)

        case .moved(let draggedID, let currentTranslation):
            updateDrag(draggedID, translation: currentTranslation)

        default:
            break
        }
    }

    /// Arrastre confirmado por la máquina de estados: ahora sí existe un dueño
    /// y un punto de partida.
    private func beginDrag(_ id: UUID, translation: CGFloat) {
        guard let index = orderDraft.index(of: id) else {
            // El borrador no describe esta fila: el gesto termina sin cambiar nada.
            reorderGesture.cancelled(id)
            return
        }

        reorderDrag = RoutineReorderDrag(id: id, startIndex: index)
        updateDrag(id, translation: translation)
    }

    /// El dedo se levanta. Un arrastre real termina en su posición; una
    /// pulsación que nunca llegó a moverse no deja rastro alguno.
    private func endReorder(_ id: UUID, translation: CGFloat?) {
        let finalTranslation: CGFloat = translation ?? reorderDrag?.translation ?? 0.0

        switch reorderGesture.ended(id, translation: finalTranslation) {
        case .ended(let draggedID, let finalTranslation):
            endDrag(draggedID, translation: finalTranslation)

        default:
            break
        }
    }

    /// El sistema cancela el gesto: se deshace solo su movimiento provisional.
    private func cancelReorderGesture(_ id: UUID) {
        switch reorderGesture.cancelled(id) {
        case .cancelled(let draggedID):
            cancelDrag(draggedID)

        default:
            break
        }
    }

    /// Un fotograma del arrastre.
    ///
    /// `translation` es el desplazamiento total del dedo en el sistema de
    /// coordenadas del contenedor. El destino se calcula desde la posición
    /// inicial y ese desplazamiento —nunca desde la posición actual de la fila—
    /// y el resto se conserva como desplazamiento visual para no separarse del
    /// dedo. Ambas mutaciones van en la misma transacción: la fila agarrada
    /// mantiene su posición visual mientras el resto se recoloca.
    private func updateDrag(_ id: UUID, translation: CGFloat) {
        guard var drag = reorderDrag, drag.id == id else { return }

        let from: Int = drag.currentIndex
        let destination: Int = drag.destinationIndex(
            translation: translation,
            count: orderDraft.orderedIDs.count
        )
        drag.apply(translation: translation, destination: destination)

        let animation: Animation? = destination == from
            ? nil
            : .spring(response: 0.22, dampingFraction: 0.86)

        var crossed: Int = 0
        withAnimation(animation) {
            crossed = orderDraft.move(from: from, to: destination)
            reorderDrag = drag
        }

        // Una señal por cada posición efectiva, ni una sin cambio de sitio.
        if crossed > 0 {
            for _ in 0..<crossed {
                reorderImpact?.impactOccurred()
            }
        }
    }

    /// Suelta la fila: fija la última posición **en el borrador**. No escribe en
    /// SwiftData; el orden se aplica de una vez al pulsar «HECHO».
    private func endDrag(_ id: UUID, translation: CGFloat) {
        guard let drag = reorderDrag, drag.id == id else { return }

        updateDrag(id, translation: translation)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            reorderDrag = nil
        }
    }

    /// El sistema ha cancelado el gesto: se deshace solo el movimiento
    /// provisional de este arrastre. Los anteriores siguen en el borrador y la
    /// rutina no se ha tocado en ningún momento.
    private func cancelDrag(_ id: UUID) {
        guard let drag = reorderDrag, drag.id == id else { return }

        orderDraft.restore(id, to: drag.startIndex)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
            reorderDrag = nil
        }
    }

    /// «HECHO»: la única ruta que confirma el orden.
    ///
    /// 1. Exige que no haya un arrastre pendiente.
    /// 2. Exige que el borrador contenga exactamente los UUID de la rutina.
    /// 3. Aplica el orden completo de una vez.
    /// 4. Guarda solo si la rutina ya existía y el orden se ha aplicado.
    /// 5. Limpia el estado de reordenación.
    ///
    /// Si la validación falla no se aplica nada, no se guarda nada y el modo
    /// sigue abierto con un aviso recuperable.
    private func finishReordering() {
        guard reorderDrag == nil, !reorderGesture.isDragging else {
            reorderErrorMessage = "Termina el arrastre en curso antes de confirmar el orden. No se ha guardado nada."
            return
        }

        guard case .ordered = orderDraft.resolve(against: routine.exercises) else {
            reorderErrorMessage = "El orden provisional no coincide con los ejercicios de la rutina. Vuelve al editor y repite el cambio: no se ha guardado nada."
            return
        }

        let alreadyInOrder: Bool = routine.orderedExercises.map(\.id) == orderDraft.orderedIDs
        let applied: Bool = routine.applyExerciseOrder(orderDraft.orderedIDs)

        guard applied || alreadyInOrder else {
            reorderErrorMessage = "No se ha podido aplicar el orden completo. No se ha guardado nada."
            return
        }

        reorderDrag = nil
        reorderImpact = nil
        reorderGesture.reset()
        orderDraft.finish()

        if applied && !isNewRoutine {
            PersistenceService.save(modelContext, operation: "guardar el orden de la rutina")
        }
    }

    /// Descarta la sesión de reordenación sin confirmar nada: restaura la
    /// instantánea original del borrador, limpia el arrastre y el generador de
    /// feedback y no escribe en SwiftData ni toca `sortOrder`.
    private func cancelReordering() {
        reorderGesture.reset()
        reorderDrag = nil
        reorderImpact = nil
        orderDraft.cancel()
    }

    // MARK: - Lógica

    private func normalizeSortOrder() {
        // Misma regla que la reordenación: solo se renumera `sortOrder`.
        routine.applyExerciseOrder(routine.orderedExercises.map(\.id))
    }

    private func discardNewRoutineIfNeeded() {
        guard isNewRoutine, routine.modelContext != nil else { return }
        modelContext.delete(routine)
        PersistenceService.save(modelContext, operation: "guardar la rutina")
    }
}

// MARK: - Reordenación compacta

/// Fila del modo reordenación: solo el nombre y el asa.
private struct RoutineReorderRow: View {
    let routineExercise: RoutineExercise
    let index: Int
    let isDragging: Bool
    let offset: CGFloat
    /// Sistema de coordenadas del contenedor, compartido por todas las filas.
    let coordinateSpaceName: String
    /// `false` en la lista de recuperación: la fila se ve pero no se arrastra.
    var isInteractive: Bool = true
    let onLongPressRecognized: () -> Void
    let onMovement: (CGFloat) -> Void
    let onGestureEnded: (CGFloat?) -> Void
    let onGestureCancelled: () -> Void

    /// Pulsación mantenida antes de considerar la fila agarrada. Corta a
    /// propósito: el toque simple no mueve nada y el gesto no se queda el
    /// scroll hasta que el dedo se queda quieto.
    private static let grabDelay: Double = 0.15

    /// El gesto solo informa de eventos: quién empieza, quién sigue y quién
    /// termina lo decide `RoutineReorderGestureState` en la vista. Aquí no se
    /// crea ningún arrastre ni se toca el borrador.
    private var reorderGesture: some Gesture {
        // La traslación se mide en el contenedor, no en la fila: la fila cambia
        // de sitio al reordenar y una referencia local desplazaría el punto de
        // partida en cada fotograma, realimentando el cálculo del destino.
        LongPressGesture(minimumDuration: Self.grabDelay)
            .sequenced(
                before: DragGesture(
                    minimumDistance: 0.0,
                    coordinateSpace: .named(coordinateSpaceName)
                )
            )
            .onChanged { value in
                switch value {
                case .first(true):
                    onLongPressRecognized()

                case .second(true, let drag):
                    if let drag {
                        onMovement(drag.translation.height)
                    }

                default:
                    break
                }
            }
            .onEnded { value in
                switch value {
                case .second(true, let drag):
                    onGestureEnded(drag?.translation.height)

                default:
                    onGestureCancelled()
                }
            }
    }

    var body: some View {
        HStack(spacing: 10.0) {
            Text("EX-\(String(format: "%02d", index + 1))")
                .font(EndfieldFont.mono(10.0, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.accentYellow)
                .monospacedDigit()
                .fixedSize()

            Text((routineExercise.exercise?.name ?? "SIN EJERCICIO").uppercased())
                .font(EndfieldFont.mono(12.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0.0)

            Image(systemName: "line.3.horizontal")
                .font(EndfieldFont.mono(11.0, weight: .bold))
                .foregroundStyle(
                    isDragging ? EndfieldPalette.accentYellow : EndfieldPalette.textSecondary
                )
                .fixedSize()
        }
        .padding(.horizontal, 12.0)
        .frame(height: RoutineReorderRowMetrics.rowHeight)
        .background(
            ChamferedRectangle(cut: 6.0)
                .fill(isDragging ? EndfieldPalette.bgElevated : EndfieldPalette.bgPanel)
        )
        .overlay {
            ChamferedRectangle(cut: 6.0)
                .stroke(
                    isDragging
                        ? EndfieldPalette.accentYellow.opacity(0.8)
                        : EndfieldPalette.borderSubtle,
                    lineWidth: 1.0
                )
        }
        .shadow(color: Color.black.opacity(isDragging ? 0.35 : 0.0), radius: 8.0, y: 3.0)
        .offset(y: offset)
        .contentShape(Rectangle())
        .gesture(reorderGesture, including: isInteractive ? .all : .none)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Posición \(index + 1): \(routineExercise.exercise?.name ?? "sin ejercicio")")
        .accessibilityAddTraits(isDragging ? [.isSelected] : [])
    }
}

// MARK: - Fila de ejercicio

private struct RoutineExerciseEditorRow: View {
    @Bindable var routineExercise: RoutineExercise
    let index: Int
    /// Pulsación larga sobre el nombre: activa el modo reordenación.
    let onBeginReorder: () -> Void
    let onRemove: () -> Void
    /// Abre el selector independiente. La fila no conoce el catálogo.
    let onChangeExercise: () -> Void

    @State private var notesExpanded = false

    private var exerciseNameBinding: Binding<String> {
        Binding(
            get: { routineExercise.exercise?.name ?? "" },
            set: { routineExercise.exercise?.name = $0 }
        )
    }

    private func equipmentBinding(for exercise: Exercise) -> Binding<EquipmentType> {
        return Binding(
            get: { exercise.equipmentType },
            set: {
                exercise.equipmentType = $0
                // Elección manual: las migraciones del catálogo no la tocan.
                exercise.hasCustomEquipment = true
            }
        )
    }

    var body: some View {
        TacticalPanel(contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 10.0) {
                headerStrip
                tacticalRule
                nameRow

                if let exercise = routineExercise.exercise {
                    tagRow(for: exercise)
                    equipmentRow(for: exercise)
                }

                tacticalRule

                if routineExercise.exercise?.trackingMode != .minutes {
                    TacticalStepperRow(
                        code: "SET",
                        title: "Series",
                        value: $routineExercise.defaultSets,
                        range: 1...12
                    )
                }

                repsBlock

                // El cardio y los isométricos se registran con cronómetro: sin
                // peso ni marcas fantasma de kg.
                if routineExercise.exercise?.trackingMode.isTimeBased != true {
                    weightRow
                }

                TacticalStepperRow(
                    code: "REST",
                    title: "Descanso",
                    value: $routineExercise.restSeconds,
                    range: 0...600,
                    step: 15,
                    unit: "s"
                )
                .onChange(of: routineExercise.restSeconds) { _, _ in
                    routineExercise.hasCustomRest = true
                }

                if routineExercise.exercise?.requiresStraps == true {
                    strapsWarning
                }

                EndfieldDisclosure(code: "NOTE", title: "Notas", isExpanded: $notesExpanded) {
                    TextField(
                        "Consejos, altura de poleas, agarre...",
                        text: $routineExercise.notes,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                    .tacticalField()
                }
            }
        }
    }

    // MARK: Cabecera y datos

    private var headerStrip: some View {
        HStack(spacing: 7.0) {
            Text("EX-\(String(format: "%02d", index + 1))")
                .font(EndfieldFont.mono(10.0, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.accentYellow)
                .padding(.horizontal, 5.0)
                .padding(.vertical, 2.0)
                .overlay {
                    ChamferedRectangle(cut: 3.0)
                        .stroke(EndfieldPalette.accentYellow.opacity(0.55), lineWidth: 1.0)
                }
                .fixedSize()

            Text((routineExercise.exercise?.name ?? "SIN EJERCICIO").uppercased())
                .font(EndfieldFont.mono(12.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentShape(Rectangle())
                // Solo la pulsación larga entra en el modo: el toque normal
                // sigue sirviendo para el resto de controles de la fila.
                .onLongPressGesture(minimumDuration: 0.5) {
                    onBeginReorder()
                }

            Rectangle()
                .fill(EndfieldPalette.borderSubtle)
                .frame(height: 1.0)

            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(EndfieldFont.mono(10.0, weight: .bold))
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentRed, size: 26.0))
            .accessibilityLabel("Eliminar ejercicio de la rutina")
        }
    }

    private var nameRow: some View {
        HStack(spacing: 8.0) {
            TextField("Nombre del ejercicio", text: exerciseNameBinding)
                .tacticalField()
                .disabled(routineExercise.exercise == nil)
                .accessibilityLabel("Nombre del ejercicio")

            Button(action: onChangeExercise) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(EndfieldFont.mono(12.0, weight: .bold))
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentCyan, size: 34.0))
            .disabled(routineExercise.exercise == nil)
            .accessibilityLabel("Cambiar ejercicio")
        }
    }

    @ViewBuilder
    private func tagRow(for exercise: Exercise) -> some View {
        HStack(spacing: 5.0) {
            TacticalTagBadge(text: exercise.muscleGroup.shortName, tint: EndfieldPalette.accentCyan)

            TacticalTagBadge(text: exercise.equipmentType.rawValue, tint: EndfieldPalette.textSecondary)

            if exercise.requiresStraps {
                TacticalTagBadge(text: "STRAPS", tint: EndfieldPalette.accentRed)
            }

            Spacer(minLength: 0.0)
        }
        .lineLimit(1)
    }

    private func equipmentRow(for exercise: Exercise) -> some View {
        HStack(spacing: 8.0) {
            VStack(alignment: .leading, spacing: 2.0) {
                Text("EQP")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                Text("Equipamiento")
                    .font(EndfieldFont.mono(11.0, weight: .semibold))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6.0)

            Menu {
                ForEach(EquipmentType.allCases) { equipment in
                    Button {
                        equipmentBinding(for: exercise).wrappedValue = equipment
                    } label: {
                        if exercise.equipmentType == equipment {
                            Label(equipment.rawValue, systemImage: "checkmark")
                        } else {
                            Text(equipment.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5.0) {
                    Text(exercise.equipmentType.rawValue.uppercased())
                        .font(EndfieldFont.label(9.0))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Image(systemName: "chevron.down")
                        .font(EndfieldFont.label(7.0))
                }
                .foregroundStyle(EndfieldPalette.accentYellow)
                .padding(.horizontal, 8.0)
                .padding(.vertical, 6.0)
                .overlay {
                    ChamferedRectangle(cut: 4.0)
                        .stroke(EndfieldPalette.accentYellow.opacity(0.5), lineWidth: 1.0)
                }
            }
            .accessibilityLabel("Equipamiento del ejercicio")
        }
        .padding(.horizontal, 9.0)
        .padding(.vertical, 7.0)
        .background(EndfieldPalette.bgElevated)
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8))
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
    }

    private var repsBlock: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(spacing: 6.0) {
                Text((routineExercise.exercise?.targetUnitLabel ?? "REPS") + " // OBJETIVO")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                Text(routineExercise.targetRepsText)
                    .font(EndfieldFont.mono(12.0, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.accentYellow)

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)
            }

            TacticalStepperRow(
                code: "MIN",
                title: (routineExercise.exercise?.trackingMode ?? .reps) == .reps ? "Repeticiones mínimas" : "Valor mínimo",
                value: $routineExercise.targetRepsMin,
                range: (routineExercise.exercise?.trackingMode ?? .reps) == .reps ? (1...50) : (1...300)
            )
            .onChange(of: routineExercise.targetRepsMin) { _, newValue in
                if newValue > routineExercise.targetRepsMax {
                    routineExercise.targetRepsMax = newValue
                }
            }

            TacticalStepperRow(
                code: "MAX",
                title: (routineExercise.exercise?.trackingMode ?? .reps) == .reps ? "Repeticiones máximas" : "Valor máximo",
                value: $routineExercise.targetRepsMax,
                range: (routineExercise.exercise?.trackingMode ?? .reps) == .reps ? (1...50) : (1...300)
            )
            .onChange(of: routineExercise.targetRepsMax) { _, newValue in
                if newValue < routineExercise.targetRepsMin {
                    routineExercise.targetRepsMin = newValue
                }
            }
        }
    }

    private var weightRow: some View {
        HStack(spacing: 8.0) {
            VStack(alignment: .leading, spacing: 2.0) {
                Text("LOAD")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                Text("Peso por defecto")
                    .font(EndfieldFont.mono(11.0, weight: .semibold))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6.0)

            HStack(spacing: 5.0) {
                TextField(
                    "0",
                    value: $routineExercise.defaultWeight,
                    format: .number
                )
                .keyboardType(.decimalPad)
                .tacticalField(alignment: .trailing)
                .frame(width: 72.0)
                .accessibilityLabel("Peso por defecto en kilogramos")

                Text("KG")
                    .font(EndfieldFont.label(8.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize()
            }
        }
    }

    private var strapsWarning: some View {
        HStack(spacing: 6.0) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(EndfieldFont.mono(9.0, weight: .bold))

            Text("RECOGER STRAPS")
                .font(EndfieldFont.label(9.0))
                .tracking(1.2)
        }
        .foregroundStyle(EndfieldPalette.accentRed)
        .padding(.horizontal, 8.0)
        .padding(.vertical, 5.0)
        .overlay {
            ChamferedRectangle(cut: 4.0)
                .stroke(EndfieldPalette.accentRed.opacity(0.55), lineWidth: 1.0)
        }
    }

    private var tacticalRule: some View {
        Rectangle()
            .fill(EndfieldPalette.borderSubtle)
            .frame(height: 1.0)
    }
}
