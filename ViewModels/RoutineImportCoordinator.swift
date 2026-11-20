import Foundation
import SwiftData

// MARK: - Aviso de importación

/// Mensaje mostrado al terminar (o al rechazar) una importación.
struct RoutineImportNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case failure
    }

    let id: UUID
    let kind: Kind
    let title: String
    let message: String

    init(id: UUID = UUID(), kind: Kind, title: String, message: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
    }

    static func success(routineName: String) -> RoutineImportNotice {
        return RoutineImportNotice(
            kind: .success,
            title: "Rutina importada correctamente",
            message: "La rutina «\(routineName)» está en la lista principal, sin carpeta."
        )
    }

    static func splitSuccess(routineCount: Int) -> RoutineImportNotice {
        let noun: String = routineCount == 1 ? "rutina" : "rutinas"
        return RoutineImportNotice(
            kind: .success,
            title: "Split importado correctamente",
            message: "Se han añadido \(routineCount) \(noun)."
        )
    }

    static func failure(message: String) -> RoutineImportNotice {
        return RoutineImportNotice(
            kind: .failure,
            title: "No se ha podido importar",
            message: message
        )
    }
}

// MARK: - Coordinador

/// Orquesta la recepción de archivos abiertos desde otras aplicaciones:
/// `.appgymroutine` (rutina individual) y `.appgymsplit` (split completo).
///
/// - Valida cada archivo antes de mostrar nada.
/// - Mantiene una única confirmación pendiente y encola el resto, de modo que
///   varios archivos consecutivos no mezclan sus diálogos.
/// - Ignora entregas repetidas de la misma URL en una ventana corta, pero
///   permite volver a importar el mismo archivo más tarde de forma deliberada.
/// - No escribe en SwiftData hasta que el usuario confirma.
final class RoutineImportCoordinator: ObservableObject {

    static let shared: RoutineImportCoordinator = RoutineImportCoordinator()

    /// Ventana en la que una misma URL se considera una entrega duplicada.
    static let duplicateDeliveryWindow: TimeInterval = 5.0

    private enum IncomingFile {
        case routine(URL)
        case split(URL)
        case unsupported
    }

    /// Rutina validada pendiente de confirmación.
    @Published var pendingRequest: RoutineImportRequest?
    /// Split validado pendiente de confirmación.
    @Published var pendingSplit: SplitImportRequest?
    /// Aviso de éxito o de error.
    @Published var notice: RoutineImportNotice?
    /// Se pone a `true` tras importar para llevar al usuario a Rutinas.
    @Published var revealRoutines: Bool = false
    /// Carpeta que debe abrirse al llegar a Rutinas tras importar un split.
    @Published var folderToReveal: UUID?

    private var queue: [IncomingFile] = []
    private var lastDelivered: [String: Date] = [:]
    /// Cierto entre que una hoja se cierra y su `onDismiss` llega. Evita
    /// presentar la siguiente importación encima de la que aún se está
    /// despidiendo.
    private var isSheetClosing: Bool = false
    /// Aviso que se publica cuando la hoja de confirmación ya se ha cerrado.
    /// Así el alert no compite con la animación de cierre.
    private var noticeAfterDismiss: RoutineImportNotice?

    init() {}

    /// Número de archivos en espera. Expuesto para las pruebas.
    var queuedCount: Int {
        return queue.count
    }

    private var isBusy: Bool {
        return pendingRequest != nil
            || pendingSplit != nil
            || notice != nil
            || isSheetClosing
    }

    // MARK: - Recepción

    /// Punto de entrada para `onOpenURL`. Distingue rutina y split por el tipo
    /// de archivo; cualquier otra cosa se rechaza con un aviso.
    func receive(_ url: URL, now: Date = Date()) {
        let key: String = url.standardizedFileURL.path

        if let delivered: Date = lastDelivered[key],
           now.timeIntervalSince(delivered) < Self.duplicateDeliveryWindow {
            return
        }
        lastDelivered[key] = now

        let file: IncomingFile
        if RoutineImportService.isRoutineFile(url) {
            file = .routine(url)
        } else if SplitImportService.isSplitFile(url) {
            file = .split(url)
        } else {
            // Se encola como rechazo para no pisar el aviso de la importación
            // que ya está en curso.
            if isBusy {
                queue.append(.unsupported)
            } else {
                notice = RoutineImportNotice.failure(
                    message: RoutineImportError.unsupportedFileType.errorDescription
                        ?? "El archivo no es válido."
                )
            }
            return
        }

        if isBusy {
            queue.append(file)
            return
        }
        process(file)
    }

    private func process(_ file: IncomingFile) {
        switch file {
        case .routine(let url):
            do {
                pendingRequest = try RoutineImportService.makeRequest(fromFileAt: url)
            } catch {
                notice = RoutineImportNotice.failure(
                    message: (error as? LocalizedError)?.errorDescription
                        ?? "El archivo no es válido."
                )
            }

        case .split(let url):
            do {
                pendingSplit = try SplitImportService.makeRequest(fromFileAt: url)
            } catch {
                notice = RoutineImportNotice.failure(
                    message: (error as? LocalizedError)?.errorDescription
                        ?? "El archivo no es válido."
                )
            }

        case .unsupported:
            notice = RoutineImportNotice.failure(
                message: RoutineImportError.unsupportedFileType.errorDescription
                    ?? "El archivo no es válido."
            )
        }
    }

    // MARK: - Cancelación

    /// «No»: descarta la rutina pendiente sin tocar SwiftData. La cola no
    /// arranca hasta que la hoja termina de cerrarse.
    func cancel() {
        pendingRequest = nil
        isSheetClosing = true
    }

    /// «No» o cierre de la hoja del split, sin escribir nada.
    func cancelSplit() {
        pendingSplit = nil
        isSheetClosing = true
    }

    /// Al cerrar la hoja de rutina (botón, «No» o deslizamiento). Si la petición
    /// seguía pendiente equivale a «No», pero nunca toca un split que ya esté
    /// en curso: cada hoja informa solo de la suya.
    func routineSheetDismissed() {
        if pendingRequest != nil {
            pendingRequest = nil
        }
        finishDismissal()
    }

    /// Al cerrar la hoja de split. Nunca toca una rutina que ya esté en curso.
    func splitSheetDismissed() {
        if pendingSplit != nil {
            pendingSplit = nil
        }
        finishDismissal()
    }

    /// Compatibilidad con el flujo de 08B: cierra el ciclo de presentación sin
    /// cancelar ninguna importación pendiente.
    func cancelIfPending() {
        finishDismissal()
    }

    /// Publica el aviso pendiente y arranca el siguiente archivo solo cuando la
    /// hoja anterior ya ha desaparecido del todo.
    private func finishDismissal() {
        isSheetClosing = false

        guard pendingRequest == nil, pendingSplit == nil else { return }

        if let notice: RoutineImportNotice = noticeAfterDismiss {
            noticeAfterDismiss = nil
            self.notice = notice
        }
        advance()
    }

    // MARK: - Rutina individual

    /// «Sí»: importa la rutina y deja la app en la pestaña Rutinas.
    func confirm(in context: ModelContext) {
        guard let request: RoutineImportRequest = pendingRequest else { return }
        pendingRequest = nil
        isSheetClosing = true

        do {
            let routine: Routine = try RoutineImportService.importRoutine(request, into: context)
            revealRoutines = true
            noticeAfterDismiss = RoutineImportNotice.success(routineName: routine.name)
        } catch {
            noticeAfterDismiss = RoutineImportNotice.failure(
                message: (error as? LocalizedError)?.errorDescription
                    ?? "No se ha podido importar la rutina."
            )
        }
    }

    // MARK: - Split completo

    /// Opción A: crea una carpeta nueva y deja el split dentro.
    func importSplit(asNewFolderNamed name: String, in context: ModelContext) {
        performSplitImport(mode: .newFolder(name: name), in: context)
    }

    /// Opción B: archiva la organización activa y deja el split como nueva
    /// organización. No borra rutinas ni historial.
    func replaceOrganizationWithSplit(in context: ModelContext) {
        performSplitImport(mode: .replaceOrganization, in: context)
    }

    private func performSplitImport(mode: SplitImportMode, in context: ModelContext) {
        guard let request: SplitImportRequest = pendingSplit else { return }
        pendingSplit = nil
        isSheetClosing = true

        do {
            let result: SplitImportResult = try SplitImportService.importSplit(
                request,
                mode: mode,
                into: context
            )
            folderToReveal = result.folderID
            revealRoutines = true
            noticeAfterDismiss = RoutineImportNotice.splitSuccess(routineCount: result.routineCount)
        } catch {
            noticeAfterDismiss = RoutineImportNotice.failure(
                message: (error as? LocalizedError)?.errorDescription
                    ?? "No se ha podido importar el split."
            )
        }
    }

    // MARK: - Cola

    /// Cierra el aviso y continúa con el siguiente archivo recibido.
    func dismissNotice() {
        notice = nil
        advance()
    }

    private func advance() {
        guard pendingRequest == nil,
              pendingSplit == nil,
              notice == nil,
              !isSheetClosing,
              !queue.isEmpty else { return }
        let next: IncomingFile = queue.removeFirst()
        process(next)
    }
}
