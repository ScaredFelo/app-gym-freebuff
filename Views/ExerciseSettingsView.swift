import SwiftUI
import SwiftData

/// Edición completa del ejercicio (mantener pulsado en la lista).
/// Permite ajustar los datos básicos, el tipo de movimiento, los straps, los
/// músculos implicados y los textos biomecánicos.
struct ExerciseSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var exercise: Exercise

    @State private var isCompound: Bool = true
    @State private var requiresStraps: Bool = false
    @State private var primaryMuscles: [MuscleGroup] = []
    @State private var secondaryMuscles: [MuscleGroup] = []
    @State private var whyGoodExercise: String = ""
    @State private var whyBadExercise: String = ""
    @State private var whenRecommended: String = ""
    @State private var whenNotRecommended: String = ""
    @State private var notes: String = ""
    @State private var initialRequiresStraps: Bool = false
    @State private var didLoadValues: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Ejercicio") {
                    TextField("Nombre del ejercicio", text: $exercise.name)
                }

                Section("Configuración") {
                    Picker("Grupo muscular objetivo", selection: muscleGroupBinding) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.rawValue).tag(group)
                        }
                    }

                    Picker("Equipamiento", selection: equipmentBinding) {
                        ForEach(EquipmentType.allCases) { equipment in
                            Text(equipment.rawValue).tag(equipment)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reps objetivo: \(exercise.targetRepsText) reps")
                            .font(.subheadline.bold())
                        Stepper("Mínimo: \(exercise.targetRepsMin)", value: $exercise.targetRepsMin, in: 1...50)
                            .onChange(of: exercise.targetRepsMin) { _, newValue in
                                if newValue > exercise.targetRepsMax {
                                    exercise.targetRepsMax = newValue
                                }
                            }
                        Stepper("Máximo: \(exercise.targetRepsMax)", value: $exercise.targetRepsMax, in: 1...50)
                            .onChange(of: exercise.targetRepsMax) { _, newValue in
                                if newValue < exercise.targetRepsMin {
                                    exercise.targetRepsMin = newValue
                                }
                            }
                    }
                }

                Section("Ejecución") {
                    Picker("Tipo de movimiento", selection: $isCompound) {
                        Text("Complejo").tag(true)
                        Text("Aislamiento").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isCompound) { _, newValue in
                        applyDefaultTargetRepsIfNeeded(for: newValue)
                    }

                    Toggle("Requiere Straps", isOn: $requiresStraps)
                }

                Section("Músculos implicados") {
                    MuscleSelectionGrid(
                        title: "Principales",
                        selection: $primaryMuscles,
                        tint: .green
                    )

                    MuscleSelectionGrid(
                        title: "Secundarios",
                        selection: $secondaryMuscles,
                        tint: .orange
                    )
                }

                Section("Análisis biomecánico") {
                    BiomechanicalTextEditor(
                        title: "Por qué es un buen ejercicio",
                        text: $whyGoodExercise
                    )
                    BiomechanicalTextEditor(
                        title: "Por qué no es un buen ejercicio",
                        text: $whyBadExercise
                    )
                    BiomechanicalTextEditor(
                        title: "Cuándo se recomienda",
                        text: $whenRecommended
                    )
                    BiomechanicalTextEditor(
                        title: "Cuándo NO se recomienda",
                        text: $whenNotRecommended
                    )
                }

                Section("Notas") {
                    TextField("Notas apuntadas del ejercicio", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if requiresStraps {
                    Section {
                        Label("Recoger Straps", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .tint(.green)
            .navigationTitle("Ajustar ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .withKeyboardDismiss()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear(perform: loadResolvedValues)
        }
        .presentationDetents([.large])
    }

    // MARK: - Bindings

    private var muscleGroupBinding: Binding<MuscleGroup> {
        Binding(
            get: { exercise.muscleGroup },
            set: { exercise.muscleGroup = $0 }
        )
    }

    private var equipmentBinding: Binding<EquipmentType> {
        Binding(
            get: { exercise.equipmentType },
            set: {
                exercise.equipmentType = $0
                // Elección manual: las migraciones del catálogo no la tocan.
                exercise.hasCustomEquipment = true
            }
        )
    }

    // MARK: - Datos derivados

    /// Precarga los valores del análisis automático cuando el ejercicio no
    /// tenía información biomecánica guardada.
    private func loadResolvedValues() {
        guard !didLoadValues else { return }
        didLoadValues = true

        let resolved: ResolvedExerciseInfo = ExerciseKnowledgeService.resolvedInfo(for: exercise)

        isCompound = resolved.isCompound
        requiresStraps = resolved.requiresStraps
        initialRequiresStraps = resolved.requiresStraps
        primaryMuscles = resolved.primaryMuscles
        secondaryMuscles = resolved.secondaryMuscles
        whyGoodExercise = resolved.whyGoodExercise
        whyBadExercise = resolved.whyBadExercise
        whenRecommended = resolved.whenRecommended
        whenNotRecommended = resolved.whenNotRecommended
        notes = exercise.notes
    }

    /// Si el rango actual es uno de los valores por defecto, al cambiar entre
    /// Complejo y Aislamiento se aplica el objetivo global 6-8 / 8-10.
    private func applyDefaultTargetRepsIfNeeded(for isCompound: Bool) {
        guard exercise.hasDefaultTargetReps else { return }
        let range: (min: Int, max: Int) = Exercise.defaultTargetReps(for: isCompound)
        exercise.targetRepsMin = range.min
        exercise.targetRepsMax = range.max
    }

    private func saveChanges() {
        let selectedGroup: MuscleGroup = exercise.muscleGroup
        var resolvedPrimary: [MuscleGroup] = primaryMuscles

        if let first: MuscleGroup = resolvedPrimary.first {
            if first != selectedGroup {
                resolvedPrimary.removeAll { (muscle: MuscleGroup) -> Bool in
                    return muscle == selectedGroup
                }
                resolvedPrimary.insert(selectedGroup, at: 0)
            }
        } else {
            resolvedPrimary = [selectedGroup]
        }

        exercise.isCompound = isCompound
        if requiresStraps != initialRequiresStraps {
            exercise.hasCustomRequiresStraps = true
        }
        exercise.requiresStraps = requiresStraps
        // El setter sincroniza el grupo muscular objetivo con el primero.
        exercise.primaryMuscles = resolvedPrimary
        exercise.secondaryMuscles = secondaryMuscles.filter { (muscle: MuscleGroup) -> Bool in
            return !resolvedPrimary.contains(muscle)
        }
        exercise.whyGoodExercise = whyGoodExercise
        exercise.whyBadExercise = whyBadExercise
        exercise.whenRecommended = whenRecommended
        exercise.whenNotRecommended = whenNotRecommended
        exercise.notes = notes
        try? modelContext.save()
    }
}

// MARK: - Selección de músculos

/// Rejilla de chips para marcar músculos implicados.
struct MuscleSelectionGrid: View {
    let title: String
    @Binding var selection: [MuscleGroup]
    let tint: Color

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 128.0), spacing: 6.0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6.0) {
                ForEach(MuscleGroup.allCases) { (group: MuscleGroup) in
                    muscleChip(for: group)
                }
            }
        }
        .padding(.vertical, 4.0)
    }

    private func muscleChip(for group: MuscleGroup) -> some View {
        let isSelected: Bool = selection.contains(group)

        return Button {
            toggle(group)
        } label: {
            HStack(spacing: 4.0) {
                Text(group.shortName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.0, weight: .black))
                }
            }
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6.0)
            .padding(.horizontal, 6.0)
            .background(
                isSelected ? tint : Color.white.opacity(0.08),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ group: MuscleGroup) {
        if let index: Int = selection.firstIndex(of: group) {
            selection.remove(at: index)
        } else {
            selection.append(group)
        }
    }
}

// MARK: - Editor de texto biomecánico

/// Campo multilínea con título para los textos del análisis.
struct BiomechanicalTextEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4.0) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            TextField(title, text: $text, axis: .vertical)
                .font(.footnote)
                .lineLimit(2...5)
        }
        .padding(.vertical, 2.0)
    }
}
