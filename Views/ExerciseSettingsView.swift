import SwiftUI
import SwiftData

/// Edición completa del ejercicio (mantener pulsado en la lista).
/// Permite ajustar los datos básicos, el tipo de movimiento, los straps, los
/// músculos implicados y los textos biomecánicos.
/// Rediseñada con la identidad "Endfield"; la lógica de guardado y la
/// precarga del análisis automático se mantienen sin cambios.
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
            ZStack {
                TechnicalGridBackground()

                ScrollView {
                    LazyVStack(spacing: 14.0) {
                        identityPanel
                        configurationPanel
                        executionPanel
                        musclesPanel
                        biomechanicsPanel
                        notesPanel

                        if requiresStraps {
                            strapsPanel
                        }

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
            .navigationTitle("AJUSTAR EJERCICIO")
            .navigationBarTitleDisplayMode(.inline)
            .withKeyboardDismiss()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("LISTO") {
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

    // MARK: - Paneles

    private var identityPanel: some View {
        TacticalPanel(code: "EJ.01", title: "IDENTIFICACIÓN", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 6.0) {
                Text("NOMBRE")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                TextField("Nombre del ejercicio", text: $exercise.name)
                    .tacticalField()
                    .accessibilityLabel("Nombre del ejercicio")
            }
        }
    }

    private var configurationPanel: some View {
        TacticalPanel(code: "CFG.02", title: "CONFIGURACIÓN", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 10.0) {
                menuRow(
                    code: "MSC",
                    title: "Grupo muscular objetivo",
                    currentValue: exercise.muscleGroup.rawValue
                ) {
                    ForEach(MuscleGroup.allCases) { group in
                        Button {
                            exercise.muscleGroup = group
                        } label: {
                            if exercise.muscleGroup == group {
                                Label(group.rawValue, systemImage: "checkmark")
                            } else {
                                Text(group.rawValue)
                            }
                        }
                    }
                }

                menuRow(
                    code: "EQP",
                    title: "Equipamiento",
                    currentValue: exercise.equipmentType.rawValue
                ) {
                    ForEach(EquipmentType.allCases) { equipment in
                        Button {
                            equipmentBinding.wrappedValue = equipment
                        } label: {
                            if exercise.equipmentType == equipment {
                                Label(equipment.rawValue, systemImage: "checkmark")
                            } else {
                                Text(equipment.rawValue)
                            }
                        }
                    }
                }

                tacticalRule

                HStack(spacing: 6.0) {
                    Text(exercise.targetUnitLabel + " // OBJETIVO")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.2)
                        .foregroundStyle(EndfieldPalette.textSecondary)

                    Text(exercise.targetRepsText)
                        .font(EndfieldFont.mono(12.0, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(EndfieldPalette.accentYellow)

                    Rectangle()
                        .fill(EndfieldPalette.borderSubtle)
                        .frame(height: 1.0)
                }

                TacticalStepperRow(
                    code: "MIN",
                    title: exercise.trackingMode == .reps ? "Repeticiones mínimas" : "Valor mínimo",
                    value: $exercise.targetRepsMin,
                    range: exercise.trackingMode == .reps ? (1...50) : (1...300)
                )
                .onChange(of: exercise.targetRepsMin) { _, newValue in
                    if newValue > exercise.targetRepsMax {
                        exercise.targetRepsMax = newValue
                    }
                }

                TacticalStepperRow(
                    code: "MAX",
                    title: exercise.trackingMode == .reps ? "Repeticiones máximas" : "Valor máximo",
                    value: $exercise.targetRepsMax,
                    range: exercise.trackingMode == .reps ? (1...50) : (1...300)
                )
                .onChange(of: exercise.targetRepsMax) { _, newValue in
                    if newValue < exercise.targetRepsMin {
                        exercise.targetRepsMin = newValue
                    }
                }
            }
        }
    }

    private var executionPanel: some View {
        TacticalPanel(code: "EJE.03", title: "EJECUCIÓN", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 10.0) {
                Text("TIPO DE MOVIMIENTO")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                HStack(spacing: 6.0) {
                    movementButton(title: "COMPLEJO", isSelected: isCompound) {
                        isCompound = true
                    }

                    movementButton(title: "AISLAMIENTO", isSelected: !isCompound) {
                        isCompound = false
                    }
                }
                .onChange(of: isCompound) { _, newValue in
                    applyDefaultTargetRepsIfNeeded(for: newValue)
                }

                tacticalRule

                Button {
                    requiresStraps.toggle()
                } label: {
                    HStack(spacing: 8.0) {
                        VStack(alignment: .leading, spacing: 2.0) {
                            Text("STR")
                                .font(EndfieldFont.label(8.0))
                                .tracking(1.2)
                                .foregroundStyle(EndfieldPalette.textSecondary)

                            Text("Requiere Straps")
                                .font(EndfieldFont.mono(11.0, weight: .semibold))
                                .foregroundStyle(EndfieldPalette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }

                        Spacer(minLength: 6.0)

                        Text(requiresStraps ? "ON" : "OFF")
                            .font(EndfieldFont.label(9.0))
                            .tracking(1.0)
                            .foregroundStyle(requiresStraps ? EndfieldPalette.bgPrimary : EndfieldPalette.textSecondary)
                            .padding(.horizontal, 7.0)
                            .padding(.vertical, 4.0)
                            .background(requiresStraps ? EndfieldPalette.accentYellow : EndfieldPalette.bgElevated)
                            .clipShape(ChamferedRectangle(cut: 3.0))
                            .overlay {
                                ChamferedRectangle(cut: 3.0)
                                    .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                            }
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
                .buttonStyle(.plain)
                .accessibilityLabel("Requiere Straps")
                .accessibilityValue(requiresStraps ? "Activado" : "Desactivado")
            }
        }
    }

    private var musclesPanel: some View {
        TacticalPanel(code: "MSC.04", title: "MÚSCULOS IMPLICADOS", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 12.0) {
                MuscleSelectionGrid(
                    title: "Principales",
                    code: "PRI",
                    selection: $primaryMuscles,
                    tint: EndfieldPalette.accentYellow
                )

                MuscleSelectionGrid(
                    title: "Secundarios",
                    code: "SEC",
                    selection: $secondaryMuscles,
                    tint: EndfieldPalette.accentCyan
                )
            }
        }
    }

    private var biomechanicsPanel: some View {
        TacticalPanel(code: "BIO.05", title: "ANÁLISIS BIOMECÁNICO", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 12.0) {
                BiomechanicalTextEditor(
                    title: "Por qué es un buen ejercicio",
                    code: "A-01",
                    text: $whyGoodExercise
                )
                BiomechanicalTextEditor(
                    title: "Por qué no es un buen ejercicio",
                    code: "A-02",
                    text: $whyBadExercise
                )
                BiomechanicalTextEditor(
                    title: "Cuándo se recomienda",
                    code: "A-03",
                    text: $whenRecommended
                )
                BiomechanicalTextEditor(
                    title: "Cuándo NO se recomienda",
                    code: "A-04",
                    text: $whenNotRecommended
                )
            }
        }
    }

    private var notesPanel: some View {
        TacticalPanel(code: "NOTE.06", title: "NOTAS", contentPadding: 12.0) {
            TextField("Notas apuntadas del ejercicio", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .tacticalField()
                .accessibilityLabel("Notas del ejercicio")
        }
    }

    private var strapsPanel: some View {
        HStack(spacing: 6.0) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(EndfieldFont.mono(9.0, weight: .bold))

            Text("RECOGER STRAPS")
                .font(EndfieldFont.label(9.0))
                .tracking(1.2)
        }
        .foregroundStyle(EndfieldPalette.accentRed)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10.0)
        .padding(.vertical, 8.0)
        .background(EndfieldPalette.bgPanel)
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8))
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                .stroke(EndfieldPalette.accentRed.opacity(0.55), lineWidth: 1.0)
        }
    }

    // MARK: - Piezas reutilizables

    private var tacticalRule: some View {
        Rectangle()
            .fill(EndfieldPalette.borderSubtle)
            .frame(height: 1.0)
    }

    private func movementButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(EndfieldFont.label(9.0))
                .tracking(1.0)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? EndfieldPalette.bgPrimary : EndfieldPalette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8.0)
                .background(isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.bgElevated)
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
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    @ViewBuilder
    private func menuRow<MenuContent: View>(
        code: String,
        title: String,
        currentValue: String,
        @ViewBuilder menuContent: () -> MenuContent
    ) -> some View {
        HStack(spacing: 8.0) {
            VStack(alignment: .leading, spacing: 2.0) {
                Text(code)
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                Text(title)
                    .font(EndfieldFont.mono(11.0, weight: .semibold))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6.0)

            Menu {
                menuContent()
            } label: {
                HStack(spacing: 5.0) {
                    Text(currentValue.uppercased())
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
            .accessibilityLabel(title)
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

    // MARK: - Bindings

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
        guard exercise.trackingMode == .reps, exercise.hasDefaultTargetReps else { return }
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
        PersistenceService.save(modelContext, operation: "guardar los ajustes del ejercicio")
    }
}

// MARK: - Selección de músculos

/// Rejilla de chips para marcar músculos implicados.
struct MuscleSelectionGrid: View {
    let title: String
    let code: String
    @Binding var selection: [MuscleGroup]
    let tint: Color

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 104.0), spacing: 6.0)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            HStack(spacing: 6.0) {
                Text(code)
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(tint)

                Text(title.uppercased())
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.2)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                Text("\(selection.count)")
                    .font(EndfieldFont.mono(9.0, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.textSecondary)

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6.0) {
                ForEach(MuscleGroup.allCases) { (group: MuscleGroup) in
                    muscleChip(for: group)
                }
            }
        }
    }

    private func muscleChip(for group: MuscleGroup) -> some View {
        let isSelected: Bool = selection.contains(group)

        return Button {
            toggle(group)
        } label: {
            HStack(spacing: 4.0) {
                Text(group.shortName.uppercased())
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.0, weight: .black))
                }
            }
            .foregroundStyle(isSelected ? EndfieldPalette.bgPrimary : EndfieldPalette.textPrimary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6.0)
            .padding(.horizontal, 6.0)
            .background(isSelected ? tint : EndfieldPalette.bgElevated)
            .clipShape(ChamferedRectangle(cut: 3.0))
            .overlay {
                ChamferedRectangle(cut: 3.0)
                    .stroke(
                        isSelected ? tint : EndfieldPalette.borderSubtle,
                        lineWidth: 1.0
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
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
    let code: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5.0) {
            HStack(spacing: 6.0) {
                Text(code)
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.accentCyan)

                Text(title.uppercased())
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            TextField(title, text: $text, axis: .vertical)
                .lineLimit(2...5)
                .tacticalField()
                .accessibilityLabel(title)
        }
    }
}
