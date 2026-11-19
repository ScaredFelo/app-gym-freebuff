import SwiftUI
import SwiftData

/// Editor de rutinas con la identidad "Endfield": paneles angulares, telemetría
/// monoespaciada y controles `−  valor  +` en lugar de los `Form`/`Stepper`
/// nativos. Toda la lógica de persistencia se mantiene intacta.
struct EditRoutineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var routine: Routine
    let isNewRoutine: Bool

    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var showingExercisePicker = false
    @State private var exercisePendingRemoval: RoutineExercise?
    @State private var exerciseToConfigure: Exercise?

    private var sortedExercises: [RoutineExercise] {
        routine.exercises.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ZStack {
            TechnicalGridBackground()

            ScrollView {
                LazyVStack(spacing: 14.0) {
                    modePanel
                    namePanel

                    if sortedExercises.isEmpty {
                        emptyStatePanel
                    } else {
                        ForEach(Array(sortedExercises.enumerated()), id: \.element.id) { index, routineExercise in
                            RoutineExerciseEditorRow(
                                routineExercise: routineExercise,
                                exercises: exercises,
                                index: index,
                                onRemove: { exercisePendingRemoval = routineExercise }
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
        }
        .preferredColorScheme(.dark)
        .tint(EndfieldPalette.accentYellow)
        .navigationTitle("EDITAR RUTINA")
        .navigationBarTitleDisplayMode(.inline)
        .withKeyboardDismiss()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") {
                    discardNewRoutineIfNeeded()
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
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

                    try? modelContext.save()
                    dismiss()
                }
                .fontWeight(.bold)
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                let nextOrder = (routine.exercises.map(\.sortOrder).max() ?? -1) + 1
                let routineExercise = RoutineExercise(
                    exercise: exercise,
                    targetRepsMin: exercise.targetRepsMin,
                    targetRepsMax: exercise.targetRepsMax,
                    sortOrder: nextOrder
                )
                if !isNewRoutine {
                    modelContext.insert(routineExercise)
                }
                routine.exercises.append(routineExercise)
                if !isNewRoutine {
                    try? modelContext.save()
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
                        try? modelContext.save()
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
        .accessibilityLabel("Añadir ejercicio a la rutina")
    }

    // MARK: - Lógica

    private func normalizeSortOrder() {
        for (index, routineExercise) in routine.exercises.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            routineExercise.sortOrder = index
        }
    }

    private func discardNewRoutineIfNeeded() {
        guard isNewRoutine, routine.modelContext != nil else { return }
        modelContext.delete(routine)
        try? modelContext.save()
    }
}

// MARK: - Fila de ejercicio

private struct RoutineExerciseEditorRow: View {
    @Bindable var routineExercise: RoutineExercise
    let exercises: [Exercise]
    let index: Int
    let onRemove: () -> Void

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

                TacticalStepperRow(
                    code: "SET",
                    title: "Series",
                    value: $routineExercise.defaultSets,
                    range: 1...12
                )

                repsBlock

                weightRow

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

            Menu {
                ForEach(exercises) { exercise in
                    Button {
                        routineExercise.exercise = exercise
                    } label: {
                        if routineExercise.exercise?.id == exercise.id {
                            Label(exercise.name, systemImage: "checkmark")
                        } else {
                            Text(exercise.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(EndfieldFont.mono(12.0, weight: .bold))
            }
            .buttonStyle(EndfieldSquareButtonStyle(tint: EndfieldPalette.accentCyan, size: 34.0))
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
