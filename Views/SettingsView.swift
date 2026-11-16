import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(UserSettingsManager.multipowerBarWeightKey)
    private var multipowerBarWeight: Double = UserSettingsManager.defaultMultipowerBarWeight

    @AppStorage(UserSettingsManager.ezBarWeightKey)
    private var ezBarWeight: Double = UserSettingsManager.defaultEZBarWeight

    @AppStorage(UserSettingsManager.availablePlatesKey)
    private var availablePlatesRaw: String = UserSettingsManager.defaultAvailablePlates

    @AppStorage(UserSettingsManager.isBigPictureModeEnabledKey)
    private var isBigPictureModeEnabled: Bool = false

    /// Desplegable de discos: plegado por defecto.
    @State private var arePlatesExpanded: Bool = false

    /// Copia de seguridad.
    @State private var showFileExporter: Bool = false
    @State private var showImportWarningAlert: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var showBackupResultAlert: Bool = false
    @State private var backupResultMessage: String = ""
    @State private var backupDocument: WorkoutBackupDocument?
    @State private var backupFileName: String = BackupManager.defaultFileName()

    private var availablePlates: [Double] {
        return UserSettingsManager.parsePlates(availablePlatesRaw)
    }

    var body: some View {
        Form {
            Section {
                barWeightRow(
                    title: "Peso barra Multipower",
                    value: $multipowerBarWeight
                )

                Stepper(
                    "Ajustar Multipower: \(UserSettingsManager.formatted(multipowerBarWeight)) kg",
                    value: $multipowerBarWeight,
                    in: 0...100,
                    step: 0.5
                )

                barWeightRow(
                    title: "Peso barra EZ",
                    value: $ezBarWeight
                )

                Stepper(
                    "Ajustar barra EZ: \(UserSettingsManager.formatted(ezBarWeight)) kg",
                    value: $ezBarWeight,
                    in: 0...100,
                    step: 0.5
                )

                DisclosureGroup(isExpanded: $arePlatesExpanded) {
                    ForEach(UserSettingsManager.plateOptions, id: \.self) { (plate: Double) in
                        Toggle(isOn: plateBinding(for: plate)) {
                            plateLabel(for: plate)
                        }
                        .tint(.green)
                    }
                } label: {
                    HStack(spacing: 8.0) {
                        Text("Discos disponibles en el gimnasio")

                        Spacer(minLength: 8.0)

                        Text("\(availablePlates.count) activos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            } header: {
                Text("Equipamiento y Discos")
            } footer: {
                Text("Estos pesos se usan como base al calcular los discos de Multipower y de barra EZ. Activa solo los discos de los que dispone tu gimnasio.")
            }

            Section {
                Toggle(isOn: $isBigPictureModeEnabled) {
                    Label("BIG PICTURE", systemImage: "textformat.size")
                }
                .tint(.green)
            } header: {
                Text("Modo visual")
            } footer: {
                Text("Aumenta la tipografía y el contraste durante el entrenamiento activo.")
            }

            BackupSettingsSectionView(
                onExportTapped: { () -> Void in exportBackup() },
                onImportTapped: { () -> Void in showImportWarningAlert = true }
            )
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .tint(.green)
        .navigationTitle("Configuración")
        .withKeyboardDismiss()
        .fileExporter(
            isPresented: $showFileExporter,
            document: backupDocument,
            contentTypes: [.json],
            defaultFilename: backupFileName
        ) { (result: Result<URL, Error>) in
            handleExportResult(result)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json]
        ) { (result: Result<URL, Error>) in
            handleImportResult(result)
        }
        .alert("Cuidado: sobrescritura de datos", isPresented: $showImportWarningAlert) {
            Button("Cancelar", role: .cancel) {
                // Sin acción: se conserva la base de datos actual.
            }

            Button("Continuar e importar", role: .destructive) {
                showFileImporter = true
            }
        } message: {
            Text("Al importar un archivo se sobrescribirán las rutinas y las sesiones de entrenamiento actuales. ¿Quieres continuar?")
        }
        .alert("Copia de seguridad", isPresented: $showBackupResultAlert) {
            Button("Entendido", role: .cancel) {
                backupResultMessage = ""
            }
        } message: {
            Text(backupResultMessage)
        }
    }

    // MARK: - Filas auxiliares

    private func barWeightRow(title: String, value: Binding<Double>) -> some View {
        return HStack {
            Text(title)

            Spacer()

            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72.0)

            Text("kg")
                .foregroundStyle(.secondary)
        }
    }

    private func plateLabel(for plate: Double) -> some View {
        return HStack(spacing: 10.0) {
            Circle()
                .fill(PlateCalculatorService.color(for: plate))
                .frame(width: 14.0, height: 14.0)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.55), lineWidth: 0.8)
                )

            Text("\(UserSettingsManager.formatted(plate)) kg")
        }
    }

    private func plateBinding(for plate: Double) -> Binding<Bool> {
        return Binding(
            get: {
                return availablePlates.contains(plate)
            },
            set: { (isEnabled: Bool) in
                var plates: Set<Double> = Set(availablePlates)
                if isEnabled {
                    plates.insert(plate)
                } else {
                    plates.remove(plate)
                }
                availablePlatesRaw = UserSettingsManager.serializePlates(plates)
            }
        )
    }

    // MARK: - Copia de seguridad

    private func exportBackup() {
        do {
            backupDocument = try BackupManager.createBackupDocument(
                context: modelContext,
                settings: UserSettingsManager.self
            )
            backupFileName = BackupManager.defaultFileName()
            showFileExporter = true
        } catch {
            presentBackupResult(message: BackupManager.message(for: error))
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            presentBackupResult(
                message: "Exportación completada. El archivo incluye tus rutinas, ejercicios, sesiones de entrenamiento y ajustes del gimnasio."
            )
        case .failure(let error):
            presentBackupResult(message: BackupManager.message(for: error))
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                try BackupManager.restoreBackup(
                    from: url,
                    context: modelContext,
                    settings: UserSettingsManager.self
                )
                presentBackupResult(
                    message: "Importación completada. Se han restaurado las rutinas, las sesiones de entrenamiento y los ajustes del archivo."
                )
            } catch {
                presentBackupResult(message: BackupManager.message(for: error))
            }
        case .failure(let error):
            presentBackupResult(message: BackupManager.message(for: error))
        }
    }

    private func presentBackupResult(message: String) {
        backupResultMessage = message
        showBackupResultAlert = true
    }
}

// MARK: - Sección modular de exportación / importación

struct BackupSettingsSectionView: View {
    let onExportTapped: () -> Void
    let onImportTapped: () -> Void

    var body: some View {
        Section {
            Button(action: onExportTapped) {
                Label("Exportar datos", systemImage: "square.and.arrow.up")
                    .fontWeight(.semibold)
            }

            Button(action: onImportTapped) {
                Label("Importar datos", systemImage: "square.and.arrow.down")
                    .fontWeight(.semibold)
            }
        } header: {
            Text("Copia de seguridad")
        } footer: {
            Text("Exporta o restaura rutinas, ejercicios, sesiones de entrenamiento y ajustes del gimnasio en un archivo JSON.")
        }
    }
}
