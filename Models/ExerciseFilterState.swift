import Foundation

/// Estado y reglas de filtrado del catálogo de ejercicios.
///
/// Vive fuera de las vistas para que la pestaña Ejercicios y el selector de
/// sustitución apliquen exactamente las mismas reglas: una sola implementación
/// y ningún riesgo de que dos listas muestren resultados distintos con el mismo
/// criterio.
///
/// Es un valor puro: no conoce SwiftUI, ni SwiftData, ni la rutina que se está
/// editando.
public struct ExerciseFilterState: Equatable {
    /// Texto del buscador. Vacío = sin criterio de nombre.
    public var searchText: String = ""
    /// Grupo muscular elegido. `nil` = todos.
    public var selectedMuscleGroup: MuscleGroup? = nil
    /// Equipamiento elegido. `nil` = todos.
    public var selectedEquipment: EquipmentType? = nil
    /// Clasificación elegida: `true` = solo compuestos, `false` = solo
    /// aislamiento, `nil` = todos. Usa el atributo real `Exercise.isCompound`.
    public var selectedIsCompound: Bool? = nil

    public init(
        searchText: String = "",
        selectedMuscleGroup: MuscleGroup? = nil,
        selectedEquipment: EquipmentType? = nil,
        selectedIsCompound: Bool? = nil
    ) {
        self.searchText = searchText
        self.selectedMuscleGroup = selectedMuscleGroup
        self.selectedEquipment = selectedEquipment
        self.selectedIsCompound = selectedIsCompound
    }

    /// `true` cuando hay algún criterio activo: texto o cualquiera de los filtros.
    public var hasActiveCriteria: Bool {
        return !searchText.isEmpty
            || selectedMuscleGroup != nil
            || selectedEquipment != nil
            || selectedIsCompound != nil
    }

    /// Vuelve al estado recién abierto, sin texto y sin filtros.
    public mutating func reset() {
        searchText = ""
        selectedMuscleGroup = nil
        selectedEquipment = nil
        selectedIsCompound = nil
    }

    /// `true` si el ejercicio cumple **todos** los criterios activos.
    ///
    /// El nombre se compara sin distinguir mayúsculas ni minúsculas con el
    /// mismo criterio que usaba la pestaña Ejercicios.
    public func matches(_ exercise: Exercise) -> Bool {
        if !searchText.isEmpty,
           !exercise.name.localizedCaseInsensitiveContains(searchText) {
            return false
        }

        if let selectedMuscleGroup, exercise.muscleGroup != selectedMuscleGroup {
            return false
        }

        if let selectedEquipment, exercise.equipmentType != selectedEquipment {
            return false
        }

        if let selectedIsCompound, exercise.isCompound != selectedIsCompound {
            return false
        }

        return true
    }

    /// Aplica el estado a una lista ya ordenada, conservando su orden original.
    public func apply(to exercises: [Exercise]) -> [Exercise] {
        guard hasActiveCriteria else { return exercises }
        return exercises.filter { matches($0) }
    }
}
