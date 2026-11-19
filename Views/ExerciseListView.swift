import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

public struct ExerciseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var selectedEquipment: EquipmentType? = nil
    @State private var searchText = ""
    @State private var showingAddModal = false
    @State private var selectedExerciseForDetail: Exercise?
    @State private var selectedExerciseToEdit: Exercise?

    public var body: some View {
        NavigationStack {
            ZStack {
                TechnicalGridBackground()

                VStack(spacing: 10.0) {
                    // Filter Chips
                    filterSection

                    // Exercises List
                    List {
                        ForEach(Array(filteredExercises.enumerated()), id: \.element.id) { index, exercise in
                            ExerciseRowView(exercise: exercise, index: index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard selectedExerciseToEdit == nil else { return }
                                    selectedExerciseForDetail = exercise
                                }
                                .onLongPressGesture(minimumDuration: 0.45) {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    selectedExerciseToEdit = exercise
                                }
                                .accessibilityHint("Toca para ver el detalle y mantén pulsado para editar")
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 3.0, leading: 16.0, bottom: 3.0, trailing: 16.0))
                        }
                        .onDelete(perform: deleteExercises)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("EJERCICIOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddModal = true }) {
                        Image(systemName: "plus")
                            .font(EndfieldFont.mono(12.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.accentYellow)
                    }
                    .accessibilityLabel("Nuevo ejercicio")
                }
            }
            .sheet(isPresented: $showingAddModal) {
                AddExerciseView()
            }
            .sheet(item: $selectedExerciseForDetail) { exercise in
                ExerciseDetailSheetView(exercise: exercise)
            }
            .sheet(item: $selectedExerciseToEdit) { exercise in
                ExerciseSettingsView(exercise: exercise)
            }
            .searchable(text: $searchText, prompt: "Buscar ejercicio...")
        }
    }

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5.0) {
                // All button
                FilterChip(title: "Todos", isSelected: selectedMuscleGroup == nil && selectedEquipment == nil) {
                    selectedMuscleGroup = nil
                    selectedEquipment = nil
                }

                // Muscle Groups
                ForEach(MuscleGroup.allCases) { group in
                    FilterChip(title: group.shortName, isSelected: selectedMuscleGroup == group) {
                        selectedMuscleGroup = (selectedMuscleGroup == group) ? nil : group
                    }
                }
            }
            .padding(.horizontal, 16.0)
            .padding(.vertical, 2.0)
        }
    }

    private var filteredExercises: [Exercise] {
        exercises.filter { exercise in
            let matchesSearch = searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText)
            let matchesMuscle = selectedMuscleGroup == nil || exercise.muscleGroup == selectedMuscleGroup
            let matchesEquipment = selectedEquipment == nil || exercise.equipmentType == selectedEquipment
            return matchesSearch && matchesMuscle && matchesEquipment
        }
    }

    private func deleteExercises(at offsets: IndexSet) {
        for index in offsets {
            let exercise = filteredExercises[index]
            modelContext.delete(exercise)
        }
        PersistenceService.save(modelContext, operation: "guardar los ejercicios")
    }
}

// MARK: - Filter Chip

/// Pestaña angular horizontal: activa en amarillo táctico con texto negro.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(EndfieldFont.mono(10.0, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(isSelected ? EndfieldPalette.bgPrimary : EndfieldPalette.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 11.0)
                .padding(.vertical, 8.0)
                .background(isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.bgPanel)
                .clipShape(ChamferedRectangle(cut: 4.0))
                .overlay {
                    ChamferedRectangle(cut: 4.0)
                        .stroke(
                            isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.borderSubtle,
                            lineWidth: 1.0
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Exercise Row

struct ExerciseRowView: View {
    let exercise: Exercise
    let index: Int

    init(exercise: Exercise, index: Int = 0) {
        self.exercise = exercise
        self.index = index
    }

    var body: some View {
        HStack(spacing: 9.0) {
            Text(String(format: "%02d", index + 1))
                .font(EndfieldFont.mono(10.0, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(EndfieldPalette.accentYellow.opacity(0.85))
                .frame(width: 24.0, alignment: .leading)

            VStack(alignment: .leading, spacing: 5.0) {
                Text(exercise.name.uppercased())
                    .font(EndfieldFont.mono(12.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 5.0) {
                    TacticalTagBadge(text: exercise.muscleGroup.shortName, tint: EndfieldPalette.textSecondary)
                    TacticalTagBadge(text: exercise.equipmentType.rawValue, tint: EndfieldPalette.accentCyan)
                    TacticalTagBadge(text: exercise.targetRangeLabel, tint: EndfieldPalette.accentYellow)

                    if exercise.requiresStraps {
                        TacticalTagBadge(text: "STRAPS", tint: EndfieldPalette.accentRed)
                    }

                    Spacer(minLength: 0.0)
                }
            }

            Image(systemName: "chevron.right")
                .font(EndfieldFont.mono(9.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textSecondary)
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, 10.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EndfieldPalette.bgPanel)
        .clipShape(ChamferedRectangle(cut: 8.0))
        .overlay {
            ChamferedRectangle(cut: 8.0)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Add Exercise View

public struct AddExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var muscleGroup: MuscleGroup = .chest
    @State private var equipmentType: EquipmentType = .dumbbell
    @State private var isCompound: Bool = true
    @State private var requiresStraps = false
    @State private var targetRepsMin = 6
    @State private var targetRepsMax = 8
    @State private var restSeconds = 90
    @State private var useBpmDrop = false
    @State private var targetBpm = 110

    @AppStorage(UserSettingsManager.isHeartRateTrackingEnabledKey)
    private var isHeartRateTrackingEnabled: Bool = true

    public var body: some View {
        NavigationStack {
            ZStack {
                TechnicalGridBackground()

                ScrollView {
                    VStack(spacing: 12.0) {
                        TacticalPanel(code: "EX.NEW", title: "Detalles del ejercicio", contentPadding: 12.0) {
                            VStack(spacing: 12.0) {
                                nameField

                                Rectangle()
                                    .fill(EndfieldPalette.borderSubtle)
                                    .frame(height: 1.0)

                                musclePicker
                                equipmentPicker
                                movementTypeSelector
                                targetRepsBlock
                                strapsToggle
                            }
                        }

                        TacticalPanel(code: "RST.01", title: "Condición de descanso", contentPadding: 12.0) {
                            VStack(spacing: 12.0) {
                                // El descanso por recuperación necesita el pulsómetro:
                                // sin medición activa solo se ofrece el temporizador.
                                if isHeartRateTrackingEnabled {
                                    Toggle(isOn: $useBpmDrop) {
                                        Text("DESCANSO POR BAJADA DE BPM")
                                            .font(EndfieldFont.label(9.0))
                                            .tracking(0.8)
                                            .foregroundStyle(EndfieldPalette.textPrimary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                    }
                                    .tint(EndfieldPalette.accentYellow)
                                }

                                if useBpmDrop {
                                    Stepper(value: $targetBpm, in: 80...160, step: 5) {
                                        numericRow(label: "BPM OBJETIVO", value: "\(targetBpm)")
                                    }
                                    .tint(EndfieldPalette.accentYellow)
                                } else {
                                    Stepper(value: $restSeconds, in: 30...300, step: 15) {
                                        numericRow(label: "TIEMPO", value: "\(restSeconds) s")
                                    }
                                    .tint(EndfieldPalette.accentYellow)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16.0)
                    .padding(.vertical, 12.0)
                }
            }
            .navigationTitle("NUEVO EJERCICIO")
            .navigationBarTitleDisplayMode(.inline)
            .withKeyboardDismiss()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let restCondition: RestCondition = useBpmDrop ? .bpmDrop(targetBpm: targetBpm) : .timer(seconds: restSeconds)
                        let newExercise = Exercise(
                            name: name,
                            muscleGroup: muscleGroup,
                            equipmentType: equipmentType,
                            requiresStraps: requiresStraps,
                            targetRepsMin: targetRepsMin,
                            targetRepsMax: targetRepsMax,
                            defaultRestCondition: restCondition,
                            isCompound: isCompound,
                            primaryMuscles: [muscleGroup]
                        )
                        // El equipamiento y el descanso los eligió el usuario.
                        newExercise.hasCustomEquipment = true
                        newExercise.hasCustomRestCondition = true
                        if requiresStraps {
                            newExercise.hasCustomRequiresStraps = true
                        } else {
                            let info: ResolvedExerciseInfo = ExerciseKnowledgeService.resolvedInfo(for: newExercise)
                            newExercise.requiresStraps = info.requiresStraps
                            newExercise.secondaryMuscles = info.secondaryMuscles
                        }
                        modelContext.insert(newExercise)
                        PersistenceService.save(modelContext, operation: "guardar los ejercicios")
                        dismiss()
                    }
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: Componentes

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 5.0) {
            fieldLabel("NOMBRE DEL EJERCICIO")

            TextField("", text: $name, prompt: Text("Ej. Press banca").foregroundColor(EndfieldPalette.textSecondary.opacity(0.6)))
                .textFieldStyle(.plain)
                .font(EndfieldFont.mono(13.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .tint(EndfieldPalette.accentYellow)
                .padding(.horizontal, 9.0)
                .padding(.vertical, 9.0)
                .background(EndfieldPalette.bgElevated)
                .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
                .overlay {
                    ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                        .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                }
        }
    }

    private var musclePicker: some View {
        VStack(alignment: .leading, spacing: 5.0) {
            fieldLabel("GRUPO MUSCULAR")

            Picker(selection: $muscleGroup) {
                ForEach(MuscleGroup.allCases) { group in
                    Text(group.rawValue).tag(group)
                }
            } label: {
                Text(muscleGroup.rawValue.uppercased())
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .tint(EndfieldPalette.accentYellow)
        }
    }

    private var equipmentPicker: some View {
        VStack(alignment: .leading, spacing: 5.0) {
            fieldLabel("EQUIPAMIENTO")

            Picker(selection: $equipmentType) {
                ForEach(EquipmentType.allCases) { eq in
                    Text(eq.rawValue).tag(eq)
                }
            } label: {
                Text(equipmentType.rawValue.uppercased())
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .tint(EndfieldPalette.accentYellow)
        }
    }

    private var movementTypeSelector: some View {
        VStack(alignment: .leading, spacing: 5.0) {
            fieldLabel("TIPO DE MOVIMIENTO")

            HStack(spacing: 5.0) {
                movementButton(title: "COMPLEJO", isActive: isCompound) {
                    isCompound = true
                }

                movementButton(title: "AISLAMIENTO", isActive: !isCompound) {
                    isCompound = false
                }
            }
        }
        .onChange(of: isCompound) { _, newValue in
            applyDefaultTargetReps(for: newValue)
        }
    }

    private func movementButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(EndfieldFont.mono(10.0, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(isActive ? EndfieldPalette.bgPrimary : EndfieldPalette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9.0)
                .background(isActive ? EndfieldPalette.accentYellow : EndfieldPalette.bgElevated)
                .clipShape(ChamferedRectangle(cut: 4.0))
                .overlay {
                    ChamferedRectangle(cut: 4.0)
                        .stroke(
                            isActive ? EndfieldPalette.accentYellow : EndfieldPalette.borderSubtle,
                            lineWidth: 1.0
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private var targetRepsBlock: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(spacing: 6.0) {
                fieldLabel("REPS OBJETIVO")

                Spacer(minLength: 0.0)

                Text("\(targetRepsMin) - \(targetRepsMax)")
                    .font(EndfieldFont.mono(12.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.accentYellow)
            }

            Stepper(value: $targetRepsMin, in: 1...50) {
                numericRow(label: "MÍNIMO", value: "\(targetRepsMin)")
            }
            .tint(EndfieldPalette.accentYellow)
            .onChange(of: targetRepsMin) { _, newValue in
                if newValue > targetRepsMax {
                    targetRepsMax = newValue
                }
            }

            Stepper(value: $targetRepsMax, in: 1...50) {
                numericRow(label: "MÁXIMO", value: "\(targetRepsMax)")
            }
            .tint(EndfieldPalette.accentYellow)
            .onChange(of: targetRepsMax) { _, newValue in
                if newValue < targetRepsMin {
                    targetRepsMin = newValue
                }
            }
        }
    }

    private var strapsToggle: some View {
        Toggle(isOn: $requiresStraps) {
            Text("REQUIERE STRAPS")
                .font(EndfieldFont.label(9.0))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.textPrimary)
        }
        .tint(EndfieldPalette.accentYellow)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(EndfieldFont.label(8.0))
            .tracking(1.0)
            .foregroundStyle(EndfieldPalette.textSecondary)
    }

    private func numericRow(label: String, value: String) -> some View {
        HStack(spacing: 6.0) {
            Text(label)
                .font(EndfieldFont.label(8.0))
                .tracking(0.8)
                .foregroundStyle(EndfieldPalette.textSecondary)

            Spacer(minLength: 4.0)

            Text(value)
                .font(EndfieldFont.mono(11.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textPrimary)
        }
    }

    /// Mantiene la regla global 6-8 / 8-10 mientras el usuario no haya
    /// personalizado el rango de repeticiones.
    private func applyDefaultTargetReps(for isCompound: Bool) {
        let isDefaultRange: Bool = (targetRepsMin == 6 && targetRepsMax == 8)
            || (targetRepsMin == 8 && targetRepsMax == 10)
        guard isDefaultRange else { return }

        let range: (min: Int, max: Int) = Exercise.defaultTargetReps(for: isCompound)
        targetRepsMin = range.min
        targetRepsMax = range.max
    }
}
