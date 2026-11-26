import SwiftUI
import SwiftData

/// Pantalla independiente para cambiar el ejercicio de una fila de rutina.
///
/// Gestiona su propio `@Query` y su propio estado de filtros: el editor de la
/// rutina no observa el catálogo ni reparte arrays de ejercicios entre sus
/// filas. La vista **no** modifica la rutina; devuelve la selección por
/// `onSelect` y el editor decide qué fila cambia.
struct ExerciseSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    /// Ejercicio actual de la fila que se sustituye, para marcarlo en la lista.
    let currentExerciseID: UUID?
    let onSelect: (Exercise) -> Void

    @State private var filter = ExerciseFilterState()

    private var filteredExercises: [Exercise] {
        filter.apply(to: exercises)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TechnicalGridBackground()

                VStack(spacing: 8.0) {
                    filterBar

                    if filteredExercises.isEmpty {
                        emptyState
                    } else {
                        exerciseList
                    }
                }
            }
            .navigationTitle("CAMBIAR EJERCICIO")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $filter.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Buscar ejercicio..."
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("LIMPIAR") { filter.reset() }
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.accentYellow)
                        .disabled(!filter.hasActiveCriteria)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(EndfieldPalette.accentYellow)
    }

    // MARK: - Filtros

    /// Tres filas compactas: músculo, material y tipo (compuesto/aislamiento).
    /// Cada fila se desplaza en horizontal para no recortar los valores ni
    /// empujar la lista fuera de la pantalla en dispositivos estrechos.
    private var filterBar: some View {
        VStack(spacing: 6.0) {
            filterRow(label: "MÚSCULO") {
                FilterChip(
                    title: "Todos",
                    isSelected: filter.selectedMuscleGroup == nil
                ) {
                    filter.selectedMuscleGroup = nil
                }

                ForEach(MuscleGroup.allCases) { group in
                    FilterChip(
                        title: group.shortName,
                        isSelected: filter.selectedMuscleGroup == group
                    ) {
                        filter.selectedMuscleGroup = (filter.selectedMuscleGroup == group) ? nil : group
                    }
                }
            }

            filterRow(label: "MATERIAL") {
                FilterChip(
                    title: "Todos",
                    isSelected: filter.selectedEquipment == nil
                ) {
                    filter.selectedEquipment = nil
                }

                ForEach(EquipmentType.allCases) { equipment in
                    FilterChip(
                        title: equipment.rawValue,
                        isSelected: filter.selectedEquipment == equipment
                    ) {
                        filter.selectedEquipment = (filter.selectedEquipment == equipment) ? nil : equipment
                    }
                }
            }

            filterRow(label: "TIPO") {
                FilterChip(
                    title: "Todos",
                    isSelected: filter.selectedIsCompound == nil
                ) {
                    filter.selectedIsCompound = nil
                }

                FilterChip(
                    title: "Compuesto",
                    isSelected: filter.selectedIsCompound == true
                ) {
                    filter.selectedIsCompound = (filter.selectedIsCompound == true) ? nil : true
                }

                FilterChip(
                    title: "Aislamiento",
                    isSelected: filter.selectedIsCompound == false
                ) {
                    filter.selectedIsCompound = (filter.selectedIsCompound == false) ? nil : false
                }
            }
        }
        .padding(.vertical, 4.0)
    }

    private func filterRow<Chips: View>(
        label: String,
        @ViewBuilder chips: () -> Chips
    ) -> some View {
        HStack(spacing: 8.0) {
            Text(label)
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary)
                .frame(width: 56.0, alignment: .leading)
                .fixedSize()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5.0) {
                    chips()
                }
                .padding(.trailing, 16.0)
            }
        }
        .padding(.leading, 16.0)
    }

    // MARK: - Lista

    private var exerciseList: some View {
        List {
            ForEach(filteredExercises) { exercise in
                Button {
                    select(exercise)
                } label: {
                    ExerciseSelectionRow(
                        exercise: exercise,
                        isCurrent: exercise.id == currentExerciseID
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(
                    EdgeInsets(top: 3.0, leading: 16.0, bottom: 3.0, trailing: 16.0)
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 0.0) {
            Spacer(minLength: 0.0)

            TacticalPanel(code: "EX.404", title: "SIN RESULTADOS", contentPadding: 12.0) {
                VStack(alignment: .leading, spacing: 10.0) {
                    Text("Ningún ejercicio cumple los filtros actuales.")
                        .font(EndfieldFont.mono(10.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if filter.hasActiveCriteria {
                        Button {
                            filter.reset()
                        } label: {
                            HStack(spacing: 8.0) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(EndfieldFont.mono(11.0, weight: .bold))

                                Text("RESTABLECER FILTROS")
                                    .font(EndfieldFont.mono(11.0, weight: .bold))
                                    .tracking(1.0)
                            }
                        }
                        .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentYellow))
                    }
                }
            }
            .padding(.horizontal, 16.0)

            Spacer(minLength: 0.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Acciones

    private func select(_ exercise: Exercise) {
        onSelect(exercise)
        dismiss()
    }
}

// MARK: - Fila

/// Fila del selector: nombre y metadatos (músculo, material y tipo de
/// registro). Marca el ejercicio que la fila ya tiene para que se vea el punto
/// de partida.
private struct ExerciseSelectionRow: View {
    let exercise: Exercise
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 9.0) {
            VStack(alignment: .leading, spacing: 5.0) {
                Text(exercise.name.uppercased())
                    .font(EndfieldFont.mono(12.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 5.0) {
                    TacticalTagBadge(
                        text: exercise.muscleGroup.shortName,
                        tint: EndfieldPalette.textSecondary
                    )

                    TacticalTagBadge(
                        text: exercise.equipmentType.rawValue,
                        tint: EndfieldPalette.accentCyan
                    )

                    TacticalTagBadge(
                        text: exercise.trackingMode.unitLabel,
                        tint: EndfieldPalette.accentYellow
                    )

                    Spacer(minLength: 0.0)
                }
            }

            Image(systemName: isCurrent ? "checkmark.circle.fill" : "chevron.right")
                .font(EndfieldFont.mono(10.0, weight: .bold))
                .foregroundStyle(
                    isCurrent ? EndfieldPalette.accentYellow : EndfieldPalette.textSecondary
                )
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, 10.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EndfieldPalette.bgPanel)
        .clipShape(ChamferedRectangle(cut: 8.0))
        .overlay {
            ChamferedRectangle(cut: 8.0)
                .stroke(
                    isCurrent
                        ? EndfieldPalette.accentYellow.opacity(0.6)
                        : EndfieldPalette.borderSubtle,
                    lineWidth: 1.0
                )
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}
