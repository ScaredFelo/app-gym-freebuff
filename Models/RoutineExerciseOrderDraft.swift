import Foundation
import CoreGraphics

/// Métricas de la lista compacta del modo reordenación.
///
/// Viven junto al cálculo de la posición destino para que la vista y las
/// pruebas compartan exactamente los mismos números: el umbral de cambio de
/// fila es la mitad de la **separación efectiva** entre dos filas consecutivas
/// (altura + espaciado), no la altura de la fila.
public enum RoutineReorderRowMetrics {
    /// Altura de cada fila compacta.
    public static let rowHeight: CGFloat = 46.0
    /// Separación vertical entre dos filas consecutivas.
    public static let rowSpacing: CGFloat = 6.0
    /// Distancia entre los centros de dos filas consecutivas.
    public static var rowStride: CGFloat { return rowHeight + rowSpacing }
    /// Desplazamiento mínimo del dedo para que el ejercicio cambie de fila.
    public static var moveThreshold: CGFloat { return rowStride / 2.0 }
}

/// Borrador del orden de los ejercicios de una rutina mientras se arrastran.
///
/// Es un valor puro: no conoce SwiftUI ni SwiftData. Durante el arrastre solo
/// cambia esta lista de identificadores; la rutina no se toca hasta confirmar
/// con «HECHO», así que ni un arrastre ni cien fotogramas escriben en SwiftData,
/// ni crean, borran o sustituyen ningún `RoutineExercise`.
///
/// La detección de cambios efectivos de posición vive aquí —`move(from:to:)`
/// devuelve cuántas posiciones se han cruzado— y la vibración se emite en la
/// vista, de modo que la primera puede probarse de forma determinista sin
/// medir ninguna señal física.
public struct RoutineExerciseOrderDraft: Equatable {
    /// `true` mientras la pantalla está en modo reordenación compacto.
    public private(set) var isActive: Bool = false
    /// Identificadores de los ejercicios en el orden que se está viendo.
    public private(set) var orderedIDs: [UUID] = []

    public init() {}

    /// Entra en modo reordenación con el orden real de la rutina (`sortOrder`).
    ///
    /// Devuelve `false` y deja el borrador inactivo cuando no hay ejercicios
    /// que ordenar. El desempate por identificador solo se aplica a filas con
    /// el mismo `sortOrder`, para que el orden mostrado sea siempre el mismo.
    @discardableResult
    public mutating func begin(with exercises: [RoutineExercise]) -> Bool {
        let ordered: [RoutineExercise] = exercises.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        guard !ordered.isEmpty else {
            isActive = false
            orderedIDs = []
            return false
        }

        orderedIDs = ordered.map(\.id)
        isActive = true
        return true
    }

    /// Sale del modo y descarta el borrador. El orden ya vive en la rutina, así
    /// que salir no modifica nada.
    public mutating func finish() {
        isActive = false
        orderedIDs = []
    }

    /// Posición destino de un arrastre vertical.
    ///
    /// `startIndex` es la posición al empezar a arrastrar y `translation` el
    /// desplazamiento total del dedo desde ese momento: el destino no depende
    /// de cuántas veces se haya recalculado, así que un arrastre de dos filas
    /// termina dos posiciones más arriba aunque SwiftUI actualice el gesto mil
    /// veces. El resultado se acota a los extremos de la lista.
    public static func destinationIndex(
        startIndex: Int,
        translation: CGFloat,
        rowStride: CGFloat,
        count: Int
    ) -> Int {
        guard count > 0, rowStride > 0, startIndex >= 0, startIndex < count else {
            return startIndex
        }

        let steps: Int = Int((translation / rowStride).rounded())
        return min(max(startIndex + steps, 0), count - 1)
    }

    /// Índice actual de un ejercicio dentro del borrador.
    public func index(of id: UUID) -> Int? {
        return orderedIDs.firstIndex(of: id)
    }

    /// Mueve el ejercicio de `source` a `destination`.
    ///
    /// Devuelve cuántas posiciones ha cambiado **realmente** (0 si se queda en
    /// su sitio) para que la vista emita exactamente una señal por cada cruce:
    /// ni vibraciones repetidas sin cambio, ni una sola señal para un arrastre
    /// que ha recorrido tres posiciones.
    @discardableResult
    public mutating func move(from source: Int, to destination: Int) -> Int {
        guard orderedIDs.indices.contains(source),
              orderedIDs.indices.contains(destination),
              source != destination else {
            return 0
        }

        let movedID: UUID = orderedIDs.remove(at: source)
        orderedIDs.insert(movedID, at: destination)
        return abs(destination - source)
    }

    /// Devuelve un ejercicio a la posición que tenía al empezar un arrastre.
    ///
    /// Se usa cuando el sistema cancela el gesto: deshace solo el movimiento
    /// provisional de ese arrastre y conserva los que ya se habían completado
    /// antes en el borrador. No aplica nada a la rutina ni emite señales.
    @discardableResult
    public mutating func restore(_ id: UUID, to index: Int) -> Bool {
        guard let current = orderedIDs.firstIndex(of: id),
              orderedIDs.indices.contains(index),
              current != index else {
            return false
        }

        let movedID: UUID = orderedIDs.remove(at: current)
        orderedIDs.insert(movedID, at: index)
        return true
    }
}

/// Estado de un arrastre vertical de la lista compacta.
///
/// Separa las cuatro magnitudes que intervienen para que ninguna realimente a
/// las demás:
///
/// 1. `startIndex`: posición del ejercicio en el momento de agarrarlo.
/// 2. `currentIndex`: posición que ocupa ahora mismo en el borrador.
/// 3. `translation`: desplazamiento **absoluto** del dedo, medido en el sistema
///    de coordenadas del contenedor de la lista, nunca respecto de la fila que
///    se mueve (esa fila cambia de sitio al reordenar).
/// 4. `visualOffset`: desplazamiento residual que mantiene la fila agarrada bajo
///    el dedo una vez recolocada en su nueva posición.
///
/// Es un valor puro: no conoce SwiftUI. El destino se calcula siempre desde
/// `startIndex` y `translation`, así que repetir el mismo fotograma da el mismo
/// resultado y un reordenado intermedio no puede desviar el gesto.
public struct RoutineReorderDrag: Equatable {
    /// Identificador del `RoutineExercise` agarrado. Nunca un índice.
    public let id: UUID
    /// Posición al agarrar la fila: la única referencia fija del arrastre.
    public let startIndex: Int
    /// Posición que ocupa ahora mismo en el borrador.
    public private(set) var currentIndex: Int
    /// Desplazamiento total del dedo desde que agarró la fila.
    public private(set) var translation: CGFloat

    public init(id: UUID, startIndex: Int) {
        self.id = id
        self.startIndex = startIndex
        self.currentIndex = startIndex
        self.translation = 0.0
    }

    /// Posición destino para un desplazamiento total del dedo.
    ///
    /// Usa las métricas compartidas de la lista compacta (46 pt de fila + 6 pt
    /// de separación = 52 pt por posición, umbral de 26 pt), de modo que no
    /// existe una segunda fuente de verdad para las distancias.
    public func destinationIndex(translation: CGFloat, count: Int) -> Int {
        return RoutineExerciseOrderDraft.destinationIndex(
            startIndex: startIndex,
            translation: translation,
            rowStride: RoutineReorderRowMetrics.rowStride,
            count: count
        )
    }

    /// Registra un fotograma: desplazamiento del dedo y posición ya aplicada al
    /// borrador.
    public mutating func apply(translation: CGFloat, destination: Int) {
        self.translation = translation
        self.currentIndex = destination
    }

    /// Desplazamiento visual que deja la fila justo bajo el dedo.
    ///
    /// La fila ya ocupa `currentIndex` en el layout, así que solo hay que
    /// descontar la distancia recorrida en el layout; el resto es lo que el dedo
    /// ha avanzado dentro de la posición actual (siempre menos de media
    /// separación de 26 pt). Al soltar se descarta y la fila se queda en su
    /// posición definitiva.
    public var visualOffset: CGFloat {
        return translation - CGFloat(currentIndex - startIndex) * RoutineReorderRowMetrics.rowStride
    }
}

extension Routine {
    /// Ejercicios en el orden que muestra la app.
    public var orderedExercises: [RoutineExercise] {
        return exercises.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Aplica un orden de identificadores a la rutina.
    ///
    /// Es el único punto de mutación de la reordenación: renumera `sortOrder`
    /// de 0 a n-1 y no toca nada más. Ni identificadores, ni el ejercicio
    /// enlazado, ni series, repeticiones, descanso, peso, `hasCustomRest` ni
    /// notas. Tampoco crea, borra ni sustituye `RoutineExercise`, y como el
    /// historial apunta a esos identificadores, los registros de entrenamiento
    /// siguen intactos.
    ///
    /// Devuelve `false` sin aplicar nada si la lista no contiene exactamente
    /// los mismos ejercicios que la rutina: un orden a medias nunca se escribe.
    @discardableResult
    public func applyExerciseOrder(_ orderedIDs: [UUID]) -> Bool {
        let current: [RoutineExercise] = orderedExercises
        guard current.count == orderedIDs.count,
              Set(current.map(\.id)) == Set(orderedIDs) else {
            return false
        }

        let byID: [UUID: RoutineExercise] = Dictionary(
            uniqueKeysWithValues: current.map { ($0.id, $0) }
        )

        var changed: Bool = false
        for (index, id) in orderedIDs.enumerated() {
            guard let routineExercise = byID[id] else { return false }
            if routineExercise.sortOrder != index {
                routineExercise.sortOrder = index
                changed = true
            }
        }

        return changed
    }
}
