import Foundation

/// Centraliza las reglas de selección y orden de los ejercicios del catálogo.
/// Ni las vistas ni `RoutineGenerator` duplican estas decisiones.
enum ExerciseRules {
    // MARK: - Orden

    /// Complejos primero y, dentro de cada grupo, orden alfabético.
    /// También elimina duplicados exactos por nombre normalizado.
    static func orderedExercises(from records: [CatalogExerciseRecord]) -> [CatalogExerciseRecord] {
        var seen: Set<String> = []
        var unique: [CatalogExerciseRecord] = []

        for record in records {
            let key: String = normalizedName(record.name)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(record)
        }

        let compound: [CatalogExerciseRecord] = unique
            .filter { (record: CatalogExerciseRecord) -> Bool in
                return record.isCompound
            }
            .sorted { (first: CatalogExerciseRecord, second: CatalogExerciseRecord) -> Bool in
                return normalizedName(first.name) < normalizedName(second.name)
            }

        let isolation: [CatalogExerciseRecord] = unique
            .filter { (record: CatalogExerciseRecord) -> Bool in
                return !record.isCompound
            }
            .sorted { (first: CatalogExerciseRecord, second: CatalogExerciseRecord) -> Bool in
                return normalizedName(first.name) < normalizedName(second.name)
            }

        return compound + isolation
    }

    static func normalizedName(_ name: String) -> String {
        let folded: String = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )

        let collapsed: String = folded.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Equipamiento

    /// El Excel no contiene una columna de equipamiento. Solo se asigna un tipo
    /// cuando el nombre aporta evidencia explícita. «Máquina», sin más detalle,
    /// no permite distinguir selectorizada de discos, así que queda como
    /// `pendingClassification` en lugar de aproximarse a un tipo no confirmado.
    ///
    /// Evidencia aceptada:
    /// - `multipower` → Multipower.
    /// - `polea`, `cable`, `gironda`, `jalón`, `face pull` → Poleas.
    /// - `mancuerna` → Mancuernas.
    /// - `barra Z` → Barra EZ.
    /// - `barra olímpica` explícita → Barra olímpica.
    /// - `barra fija` explícita → Barra fija.
    /// - `barra` sin más detalle → Barra estándar.
    /// - `prensa` → máquina de discos (la prensa se carga con discos).
    /// - `peso corporal` → peso corporal.
    ///
    /// `paralelas` no basta para barra fija: «Fondos en paralelas lastrados»
    /// queda pendiente porque el modelo no representa el lastre añadido.
    ///
    /// Las máquinas selectorizadas solo se asignan desde una lista explícita de
    /// ejercicios cuyo formato habitual integra la pila de discos. La palabra
    /// «máquina» por sí sola no basta: hack, pendular, isolateral, Scott, hip
    /// thrust y las máquinas convergentes pueden ser de discos.
    static func equipment(for name: String) -> EquipmentType {
        let normalized: String = normalizedName(name)

        if selectorizedMachineNames.contains(normalized) {
            return .selectorizedMachine
        }
        if normalized.contains("multipower") {
            return .smithMachine
        }
        if normalized.contains("barra z") {
            return .ezBar
        }
        if normalized.contains("barra olimpica") {
            return .olympicBar
        }
        if normalized.contains("barra fija") {
            return .fixedBar
        }
        if normalized.contains("mancuerna") {
            return .dumbbell
        }
        if normalized.contains("polea") || normalized.contains("cable") || normalized.contains("gironda")
            || normalized.contains("jalon") || normalized.contains("face pull") {
            return .cable
        }
        if normalized.contains("prensa") {
            return .plateLoadedMachine
        }
        if normalized.contains("barra") {
            return .standardBar
        }
        if normalized.contains("peso corporal") {
            return .bodyweight
        }

        return .pendingClassification
    }

    /// Nombres del catálogo que identifican máquinas de pila integrada. Se
    /// revisó una a una la lista de pendientes; no es una regla por la palabra
    /// «máquina». Las que admiten versión de discos permanecen pendientes.
    private static let selectorizedMachineNames: Set<String> = [
        "abduccion de cadera en maquina",
        "aductores en maquina",
        "aperturas en maquina contractora (peck deck)",
        "curl femoral sentado",
        "curl femoral tumbado",
        "elevaciones laterales en maquina",
        "elevacion de talones de pie en maquina",
        "elevacion de talones sentado en maquina",
        "extension de cuadriceps en maquina",
        "press de hombro en maquina"
    ]

    // MARK: - Músculos

    /// Convierte el texto libre del catálogo en un grupo de la app.
    /// `Estabilizadores`, `Manguito`, `Serrato` y `Cabeza lateral y medial` no
    /// tienen equivalente seguro y devuelven `nil`.
    static func muscle(for raw: String) -> MuscleGroup? {
        let text: String = normalizedName(raw)
        guard !text.isEmpty else { return nil }

        if text.contains("pecho") {
            return .chest
        }
        if text.contains("lumbar") || text.contains("erectores") {
            return .lowerBack
        }
        if text.contains("hombro posterior") || text.contains("deltoides posterior") {
            return .rearShoulders
        }
        if text.contains("hombro") || text.contains("deltoides") {
            return .frontShoulders
        }
        if text.contains("trapecio") || text.contains("romboide") || text.contains("elevador") {
            return .upperBack
        }
        if text.contains("dorsal") || text.contains("redondo") {
            return .lats
        }
        if text.contains("espalda") {
            return .upperBack
        }
        // Piernas antes que brazos para que «bíceps femoral» sea isquios.
        if text.contains("cuadriceps") || text.contains("recto femoral") {
            return .quads
        }
        if text.contains("isquio") {
            return .hamstrings
        }
        if text.contains("gluteo") {
            return .glutes
        }
        if text.contains("aductor") {
            return .adductors
        }
        if text.contains("gemelo") || text.contains("gastrocnemio") || text.contains("soleo") {
            return .calves
        }
        if text.contains("biceps") || text.contains("braquial") {
            return .biceps
        }
        if text.contains("triceps") {
            return .triceps
        }
        if text.contains("antebrazo") || text.contains("braquiorradial") {
            return .forearms
        }
        if text.contains("abdominal") || text.contains("core") {
            return .abs
        }
        if text.contains("cardio") {
            return .cardio
        }

        return nil
    }

    static func muscleList(from raw: String) -> [MuscleGroup] {
        var result: [MuscleGroup] = []

        for token in raw.components(separatedBy: ",") {
            let normalized: String = normalizedName(token)
            guard !normalized.isEmpty else { continue }

            // El catálogo nombra explícitamente las dos zonas. Se conservan
            // ambas en lugar de descartar «media» al elegir un solo grupo.
            if normalized.contains("espalda"), normalized.contains("dorsal"), normalized.contains("media") {
                for group in [MuscleGroup.lats, MuscleGroup.upperBack] where !result.contains(group) {
                    result.append(group)
                }
                continue
            }

            guard let group: MuscleGroup = muscle(for: token) else { continue }
            guard !result.contains(group) else { continue }
            result.append(group)
        }

        return result
    }

    /// Devuelve los nombres originales de los músculos que no tienen
    /// equivalencia exacta en `MuscleGroup`, sin modificarlos ni eliminarlos.
    static func unmappedMuscles(in raw: String) -> [String] {
        var result: [String] = []

        for token in raw.components(separatedBy: ",") {
            let trimmed: String = token.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard muscle(for: trimmed) == nil else { continue }
            guard !result.contains(trimmed) else { continue }
            result.append(trimmed)
        }

        return result
    }

    static func primaryMuscles(for record: CatalogExerciseRecord) -> [MuscleGroup] {
        return muscleList(from: record.primaryRaw)
    }

    static func secondaryMuscles(for record: CatalogExerciseRecord) -> [MuscleGroup] {
        let primary: [MuscleGroup] = primaryMuscles(for: record)
        return muscleList(from: record.secondaryRaw).filter { (group: MuscleGroup) -> Bool in
            return !primary.contains(group)
        }
    }
}
