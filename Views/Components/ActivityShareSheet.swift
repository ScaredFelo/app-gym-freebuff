import SwiftUI
import UIKit

/// Hoja nativa de compartir de iOS (`UIActivityViewController`) para presentar
/// desde SwiftUI. Se usa para compartir el archivo `.appgymroutine` generado.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller: UIActivityViewController = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            // El cierre de la hoja se gestiona desde el `sheet` que la presenta.
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
