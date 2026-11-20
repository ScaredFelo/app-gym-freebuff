import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Importación opcional de la copia de seguridad durante el onboarding.
///
/// Reutiliza el motor de `BackupManager` a través de `OnboardingService`, con
/// confirmación de sobrescritura, revisión de integridad antes de aplicar el
/// archivo, mensaje de éxito o error y reintento. La revisión es la misma que
/// usa Ajustes (`BackupImportReviewSheet`), incluido el aviso de pérdida de
/// historial.
struct BackupImportStepView: View {
    let chrome: OnboardingChrome
    @ObservedObject var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showsFileImporter: Bool = false
    @State private var showsOverwriteConfirmation: Bool = false

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "Importar copia de seguridad",
            subtitle: "Restaura tus datos desde el archivo JSON que exportaste en AppGym.",
            footer: footer
        ) {
            TacticalPanel(code: "BK.01", title: "Archivo de copia", contentPadding: 12.0) {
                VStack(alignment: .leading, spacing: 10.0) {
                    Text("El archivo incluye rutinas, ejercicios, sesiones de entrenamiento, pesos, series y ajustes del gimnasio. Al importarlo se sustituyen los datos actuales de la app y se guarda antes una copia automática de los que había.")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showsOverwriteConfirmation = true
                    } label: {
                        HStack(spacing: 7.0) {
                            Image(systemName: "square.and.arrow.down")
                                .font(EndfieldFont.mono(11.0, weight: .bold))

                            Text("IMPORTAR COPIA")
                                .font(EndfieldFont.mono(11.0, weight: .bold))
                                .tracking(1.0)
                        }
                    }
                    .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentCyan))
                    .disabled(isImporting)

                    statusView
                }
            }

            OnboardingInfoNote(
                text: "Si decides continuar sin importar, la app seguirá con los datos que ya tenga. Podrás importar la copia más adelante desde Configuración → Copia de seguridad."
            )
        }
        .alert("Cuidado: sobrescritura de datos", isPresented: $showsOverwriteConfirmation) {
            Button("Cancelar", role: .cancel) {}

            Button("Continuar e importar", role: .destructive) {
                showsFileImporter = true
            }
        } message: {
            Text("Al importar un archivo se sobrescribirán las rutinas y las sesiones de entrenamiento actuales. Después podrás revisar los avisos antes de aplicarlo. ¿Quieres continuar?")
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.json],
            onCompletion: handleImportResult
        )
        .sheet(isPresented: reviewBinding) {
            if let plan: BackupImportPlan = viewModel.preparedBackupPlan {
                BackupImportReviewSheet(
                    plan: plan,
                    successLead: "",
                    presentsResultAlert: false,
                    performsImport: {
                        return viewModel.confirmPreparedBackup(context: modelContext)
                    },
                    onImported: { (_: BackupImportResult) in
                        // El view model ya ha pasado a `.imported` y el panel de
                        // éxito del paso sustituye al formulario.
                    },
                    onDismiss: {
                        viewModel.cancelPreparedBackup()
                    }
                )
            }
        }
    }

    /// La hoja existe mientras haya un plan preparado sin aplicar. Se mantiene
    /// abierta durante la importación y se cierra cuando el view model descarta
    /// el plan (éxito o error), para que nunca quede una importación pendiente.
    private var reviewBinding: Binding<Bool> {
        return Binding(
            get: { viewModel.preparedBackupPlan != nil },
            set: { (isPresented: Bool) in
                if !isPresented {
                    viewModel.cancelPreparedBackup()
                }
            }
        )
    }

    // MARK: - Estado

    private var isImporting: Bool {
        return viewModel.backupState == .importing
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.backupState {
        case .idle:
            EmptyView()

        case .reviewing:
            HStack(spacing: 6.0) {
                Image(systemName: "checkmark.seal.fill")
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(EndfieldPalette.accentCyan)

                Text("COPIA VALIDADA — REVISA LOS AVISOS")
                    .font(EndfieldFont.label(9.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

        case .importing:
            HStack(spacing: 8.0) {
                ProgressView()
                    .tint(EndfieldPalette.accentCyan)

                Text("IMPORTANDO COPIA...")
                    .font(EndfieldFont.label(9.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }
            .accessibilityElement(children: .combine)

        case .imported:
            VStack(alignment: .leading, spacing: 6.0) {
                HStack(spacing: 6.0) {
                    Image(systemName: "checkmark.square.fill")
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.accentCyan)

                    Text("IMPORTACIÓN COMPLETADA")
                        .font(EndfieldFont.label(9.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.accentCyan)
                }

                Text("Se han restaurado las rutinas, las sesiones y los ajustes del archivo. El equipamiento y las pulsaciones muestran ahora los valores importados.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8.0) {
                HStack(alignment: .top, spacing: 6.0) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.accentRed)

                    Text(message)
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.accentRed)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("REINTENTAR") {
                    showsOverwriteConfirmation = true
                }
                .buttonStyle(EndfieldSecondaryButtonStyle(compact: true, tint: EndfieldPalette.accentRed))
                .accessibilityHint("Vuelve a abrir el selector de archivo para importar la copia")
            }
        }
    }

    // MARK: - Footer

    private var footer: AnyView {
        if viewModel.backupState == .imported {
            return AnyView(
                OnboardingPrimaryFooter(title: "CONTINUAR", isEnabled: true) {
                    onContinue()
                }
            )
        }

        return AnyView(
            Button {
                viewModel.resetBackupState()
                onContinue()
            } label: {
                Text("CONTINUAR SIN IMPORTAR")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentYellow))
            .disabled(isImporting)
        )
    }

    // MARK: - Acciones

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            // Validar y revisar antes de aplicar: el archivo no toca la base
            // hasta que el usuario confirma en la hoja de revisión.
            viewModel.prepareBackupImport(from: url, context: modelContext)

        case .failure(let error):
            // Cancelar el selector no es un error que deba mostrarse.
            if (error as NSError).code == NSUserCancelledError {
                return
            }
            viewModel.resetBackupState()
        }
    }
}
