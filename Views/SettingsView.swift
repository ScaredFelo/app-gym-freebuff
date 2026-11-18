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
    @State private var safetyCopies: [PreImportBackup] = []
    @State private var safetyCopyPendingRestore: PreImportBackup?

    private var availablePlates: [Double] {
        return UserSettingsManager.parsePlates(availablePlatesRaw)
    }

    var body: some View {
        ZStack {
            TechnicalGridBackground()

            ScrollView {
                VStack(spacing: 12.0) {
                    equipmentPanel
                    platesPanel
                    visualModePanel
                    backupPanel

                    if !safetyCopies.isEmpty {
                        safetyCopiesPanel
                    }
                }
                .padding(.horizontal, 16.0)
                .padding(.vertical, 14.0)
            }
        }
        .onAppear {
            reloadSafetyCopies()
        }
        .preferredColorScheme(.dark)
        .tint(EndfieldPalette.accentYellow)
        .navigationTitle("AJUSTES")
        .navigationBarTitleDisplayMode(.inline)
        .withKeyboardDismiss()
        .fileExporter(
            isPresented: $showFileExporter,
            document: backupDocument,
            contentTypes: [.json],
            defaultFilename: backupFileName,
            onCompletion: { (result: Result<URL, Error>) in
                handleExportResult(result)
            },
            onCancellation: {
                // El usuario ha cerrado el selector sin guardar: sin cambios.
            }
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            onCompletion: { (result: Result<URL, Error>) in
                handleImportResult(result)
            }
        )
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
            Button("Entendido", role: .cancel) {}
        } message: {
            Text(backupResultMessage)
        }
        .alert(
            "Cuidado: sobrescritura de datos",
            isPresented: Binding(
                get: { safetyCopyPendingRestore != nil },
                set: { (isPresented: Bool) in
                    if !isPresented {
                        safetyCopyPendingRestore = nil
                    }
                }
            )
        ) {
            Button("Cancelar", role: .cancel) {
                safetyCopyPendingRestore = nil
            }

            Button("Continuar y restaurar", role: .destructive) {
                let pending: PreImportBackup? = safetyCopyPendingRestore
                safetyCopyPendingRestore = nil

                if let pending: PreImportBackup = pending {
                    performRestore(pending)
                }
            }
        } message: {
            Text("Al restaurar esta copia se sobrescribirán las rutinas y las sesiones de entrenamiento actuales. ¿Quieres continuar?")
        }
    }

    // MARK: - Paneles

    private var equipmentPanel: some View {
        TacticalPanel(code: "EQP.01", title: "Equipamiento y discos", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 12.0) {
                barWeightBlock(
                    title: "Peso barra Multipower",
                    value: $multipowerBarWeight,
                    stepperLabel: "Ajustar Multipower: \(UserSettingsManager.formatted(multipowerBarWeight)) kg",
                    range: 0...100
                )

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                barWeightBlock(
                    title: "Peso barra EZ",
                    value: $ezBarWeight,
                    stepperLabel: "Ajustar barra EZ: \(UserSettingsManager.formatted(ezBarWeight)) kg",
                    range: 0...100
                )

                Text("Estos pesos se usan como base al calcular los discos de Multipower y de barra EZ.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var platesPanel: some View {
        EndfieldDisclosure(
            code: "PLT.02",
            title: "Discos disponibles (\(availablePlates.count) activos)",
            isExpanded: $arePlatesExpanded
        ) {
            VStack(alignment: .leading, spacing: 6.0) {
                ForEach(UserSettingsManager.plateOptions, id: \.self) { (plate: Double) in
                    Toggle(isOn: plateBinding(for: plate)) {
                        plateLabel(for: plate)
                    }
                    .tint(EndfieldPalette.accentYellow)
                }

                Text("Activa solo los discos de los que dispone tu gimnasio.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2.0)
            }
        }
    }

    private var visualModePanel: some View {
        TacticalPanel(code: "UI.03", title: "Modo visual", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 6.0) {
                Toggle(isOn: $isBigPictureModeEnabled) {
                    HStack(spacing: 7.0) {
                        Image(systemName: "textformat.size")
                            .font(EndfieldFont.mono(11.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.accentYellow)

                        Text("BIG PICTURE")
                            .font(EndfieldFont.label(10.0))
                            .tracking(1.0)
                            .foregroundStyle(EndfieldPalette.textPrimary)
                    }
                }
                .tint(EndfieldPalette.accentYellow)

                Text("Aumenta la tipografía y el contraste durante el entrenamiento activo.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var backupPanel: some View {
        TacticalPanel(code: "BK.04", title: "Copia de seguridad", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                BackupSettingsSectionView(
                    onExportTapped: { () -> Void in exportBackup() },
                    onImportTapped: { () -> Void in showImportWarningAlert = true }
                )

                Text("Exporta o restaura rutinas, ejercicios, sesiones de entrenamiento y ajustes del gimnasio en un archivo JSON.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var safetyCopiesPanel: some View {
        TacticalPanel(code: "BK.05", title: "Copias automáticas", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                SafetyBackupSectionView(
                    copies: safetyCopies,
                    onRestoreTapped: { (copy: PreImportBackup) -> Void in
                        safetyCopyPendingRestore = copy
                    }
                )

                Text("Se guardan antes de cada importación. Restaurar una copia sustituye las rutinas y las sesiones actuales.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Filas auxiliares

    private func barWeightBlock(
        title: String,
        value: Binding<Double>,
        stepperLabel: String,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6.0) {
            Text(title.uppercased())
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary)

            HStack(spacing: 6.0) {
                TextField("0", value: value, format: .number)
                    .textFieldStyle(.plain)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(EndfieldFont.mono(14.0, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .tint(EndfieldPalette.accentYellow)
                    .frame(width: 74.0)
                    .padding(.vertical, 8.0)
                    .padding(.horizontal, 8.0)
                    .background(EndfieldPalette.bgElevated)
                    .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
                    .overlay {
                        ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                            .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                    }

                Text("KG")
                    .font(EndfieldFont.label(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)

                Spacer(minLength: 0.0)
            }

            Stepper(value: value, in: range, step: 0.5) {
                Text(stepperLabel)
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .tint(EndfieldPalette.accentYellow)
        }
    }

    private func plateLabel(for plate: Double) -> some View {
        return HStack(spacing: 8.0) {
            Rectangle()
                .fill(PlateCalculatorService.color(for: plate))
                .frame(width: 10.0, height: 10.0)
                .overlay {
                    Rectangle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                }

            Text("\(UserSettingsManager.formatted(plate)) KG")
                .font(EndfieldFont.mono(11.0, weight: .bold))
                .foregroundStyle(EndfieldPalette.textPrimary)
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
            backupDocument = try BackupManager.createBackupDocument(context: modelContext)
            backupFileName = BackupManager.defaultFileName()
            showFileExporter = true
        } catch {
            presentBackupResult(message: error.localizedDescription)
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            presentBackupResult(
                message: "Exportación completada. El archivo incluye tus rutinas, ejercicios, sesiones de entrenamiento y ajustes del gimnasio."
            )
        case .failure(let error):
            presentBackupResult(message: error.localizedDescription)
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                try BackupManager.restoreBackup(from: url, context: modelContext)
                reloadSafetyCopies()
                presentBackupResult(
                    message: "Importación completada. Se han restaurado las rutinas, las sesiones de entrenamiento y los ajustes del archivo, y se ha guardado una copia automática de los datos anteriores."
                )
            } catch {
                presentBackupResult(message: error.localizedDescription)
            }
        case .failure(let error):
            presentBackupResult(message: error.localizedDescription)
        }
    }

    private func reloadSafetyCopies() {
        safetyCopies = BackupManager.availableSafetyCopies()
    }

    private func performRestore(_ copy: PreImportBackup) {
        do {
            try BackupManager.restoreBackup(from: copy.url, context: modelContext)
            reloadSafetyCopies()
            presentBackupResult(
                message: "Copia automática restaurada. Se han recuperado los datos tal y como estaban antes de esa importación."
            )
        } catch {
            presentBackupResult(message: error.localizedDescription)
        }
    }

    private func presentBackupResult(message: String) {
        backupResultMessage = message
        showBackupResultAlert = true
    }
}

// MARK: - Sección modular de copias automáticas

struct SafetyBackupSectionView: View {
    let copies: [PreImportBackup]
    let onRestoreTapped: (PreImportBackup) -> Void

    var body: some View {
        VStack(spacing: 6.0) {
            ForEach(copies) { (copy: PreImportBackup) in
                Button {
                    onRestoreTapped(copy)
                } label: {
                    HStack(spacing: 10.0) {
                        VStack(alignment: .leading, spacing: 2.0) {
                            Text(copy.date.formatted(date: .numeric, time: .shortened))
                                .font(EndfieldFont.mono(10.0, weight: .bold))
                                .foregroundStyle(EndfieldPalette.textPrimary)

                            Text(ByteCountFormatter.string(fromByteCount: Int64(copy.byteCount), countStyle: .file).uppercased())
                                .font(EndfieldFont.label(7.0))
                                .foregroundStyle(EndfieldPalette.textSecondary)
                        }

                        Spacer(minLength: 6.0)

                        Image(systemName: "arrow.counterclockwise")
                            .font(EndfieldFont.mono(10.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.accentYellow)
                            .fixedSize()
                    }
                    .padding(9.0)
                    .background(EndfieldPalette.bgElevated)
                    .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
                    .overlay {
                        ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                            .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Sección modular de exportación / importación

struct BackupSettingsSectionView: View {
    let onExportTapped: () -> Void
    let onImportTapped: () -> Void

    var body: some View {
        VStack(spacing: 7.0) {
            Button(action: onExportTapped) {
                HStack(spacing: 7.0) {
                    Image(systemName: "square.and.arrow.up")
                        .font(EndfieldFont.mono(11.0, weight: .bold))

                    Text("EXPORTAR DATOS")
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .tracking(1.0)
                }
            }
            .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentYellow))

            Button(action: onImportTapped) {
                HStack(spacing: 7.0) {
                    Image(systemName: "square.and.arrow.down")
                        .font(EndfieldFont.mono(11.0, weight: .bold))

                    Text("IMPORTAR DATOS")
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .tracking(1.0)
                }
            }
            .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentCyan))
        }
    }
}
