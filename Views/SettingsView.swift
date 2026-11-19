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

    @AppStorage(UserSettingsManager.weeklyWorkoutGoalKey)
    private var weeklyWorkoutGoal: Int = UserSettingsManager.defaultWeeklyWorkoutGoal

    @AppStorage(UserSettingsManager.isBigPictureModeEnabledKey)
    private var isBigPictureModeEnabled: Bool = false

    @AppStorage(UserSettingsManager.isHeartRateTrackingEnabledKey)
    private var isHeartRateTrackingEnabled: Bool = true

    @AppStorage(UserSettingsManager.heartRateDeviceTypeKey)
    private var heartRateDeviceTypeRaw: String = HeartRateDeviceType.heartRateBand.rawValue

    @AppStorage(UserSettingsManager.heartRateDeviceBrandKey)
    private var heartRateDeviceBrand: String = ""

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

    private var selectedHeartRateDevice: HeartRateDeviceType {
        return HeartRateDeviceType.fromStoredRawValue(heartRateDeviceTypeRaw)
    }

    var body: some View {
        ZStack {
            TechnicalGridBackground()

            ScrollView {
                VStack(spacing: 12.0) {
                    equipmentPanel
                    platesPanel
                    weeklyGoalPanel
                    visualModePanel
                    heartRatePanel
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
        .onChange(of: weeklyWorkoutGoal) { (_, newValue: Int) in
            let clamped: Int = min(
                max(newValue, UserSettingsManager.weeklyWorkoutGoalRange.lowerBound),
                UserSettingsManager.weeklyWorkoutGoalRange.upperBound
            )

            if clamped != newValue {
                weeklyWorkoutGoal = clamped
                return
            }

            // Recalcula el snapshot con el nuevo objetivo y refresca los widgets.
            WidgetStreakStore.refresh(modelContext: modelContext)
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
                    TacticalToggleRow(
                        code: "PLT",
                        title: "\(UserSettingsManager.formatted(plate)) KG",
                        isOn: plateBinding(for: plate)
                    ) {
                        Rectangle()
                            .fill(PlateCalculatorService.color(for: plate))
                            .frame(width: 10.0, height: 10.0)
                            .overlay {
                                Rectangle()
                                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                            }
                    }
                }

                Text("Activa solo los discos de los que dispone tu gimnasio.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2.0)
            }
        }
    }

    // MARK: - Objetivo semanal

    private var weeklyGoalPanel: some View {
        TacticalPanel(code: "WKG.02", title: "Objetivo semanal", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                HStack(spacing: 8.0) {
                    Text("Objetivo semanal (días/semana)")
                        .font(EndfieldFont.label(9.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4.0)

                    Text("\(weeklyWorkoutGoal) DÍAS / SEM")
                        .font(EndfieldFont.mono(12.0, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(EndfieldPalette.accentYellow)
                        .lineLimit(1)
                        .fixedSize()
                }

                Stepper(value: $weeklyWorkoutGoal, in: UserSettingsManager.weeklyWorkoutGoalRange) {
                    Text("Ajustar objetivo: \(weeklyWorkoutGoal) días por semana")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .tint(EndfieldPalette.accentYellow)

                Text("La racha cuenta semanas consecutivas alcanzando el objetivo. La semana en curso no la rompe hasta que termina.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var visualModePanel: some View {
        TacticalPanel(code: "UI.03", title: "Modo visual", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                TacticalToggleRow(
                    code: "UI",
                    title: "Big Picture",
                    isOn: $isBigPictureModeEnabled
                )

                Text("Aumenta la tipografía y el contraste durante el entrenamiento activo.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Pulsaciones

    private var heartRatePanel: some View {
        TacticalPanel(code: "BPM.04", title: "Pulsaciones", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 12.0) {
                TacticalToggleRow(
                    code: "BPM",
                    title: "Medir pulsaciones",
                    isOn: $isHeartRateTrackingEnabled
                )

                Text(isHeartRateTrackingEnabled
                     ? "Muestra los BPM durante el entrenamiento, en la Live Activity y en las estadísticas al terminar."
                     : "Medición desactivada: el entrenamiento funciona igual, pero sin datos de frecuencia cardíaca.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isHeartRateTrackingEnabled {
                    Rectangle()
                        .fill(EndfieldPalette.borderSubtle)
                        .frame(height: 1.0)

                    Text("DISPOSITIVO DE MEDICIÓN")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.textSecondary)

                    VStack(spacing: 6.0) {
                        ForEach(HeartRateDeviceType.allCases) { (type: HeartRateDeviceType) in
                            heartRateDeviceRow(type)
                        }
                    }

                    if selectedHeartRateDevice == .heartRateBand {
                        heartRateBrandBlock
                    }

                    HeartRateSensorStatusView(deviceType: selectedHeartRateDevice)
                }
            }
        }
        .onChange(of: isHeartRateTrackingEnabled) { _, _ in
            BPMManager.shared.applySettings()
        }
        .onChange(of: heartRateDeviceTypeRaw) { _, _ in
            BPMManager.shared.applySettings()
        }
        .onChange(of: heartRateDeviceBrand) { _, _ in
            BPMManager.shared.applySettings()
        }
    }

    private func heartRateDeviceRow(_ type: HeartRateDeviceType) -> some View {
        let isSelected: Bool = selectedHeartRateDevice == type

        return Button {
            heartRateDeviceTypeRaw = type.rawValue
            BPMManager.shared.applySettings()
        } label: {
            HStack(spacing: 9.0) {
                Image(systemName: type.symbolName)
                    .font(EndfieldFont.mono(12.0, weight: .bold))
                    .foregroundStyle(isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.textSecondary)
                    .frame(width: 18.0)

                VStack(alignment: .leading, spacing: 2.0) {
                    Text(type.title.uppercased())
                        .font(EndfieldFont.label(9.0))
                        .tracking(0.9)
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(type.subtitle)
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 4.0)

                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(EndfieldFont.mono(11.0, weight: .bold))
                    .foregroundStyle(isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.textSecondary.opacity(0.6))
                    .fixedSize()
            }
            .padding(9.0)
            .background(EndfieldPalette.bgElevated)
            .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                    .stroke(
                        isSelected ? EndfieldPalette.accentYellow.opacity(0.55) : EndfieldPalette.borderSubtle,
                        lineWidth: 1.0
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var heartRateBrandBlock: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            Text("MARCA / MODELO")
                .font(EndfieldFont.label(8.0))
                .tracking(1.0)
                .foregroundStyle(EndfieldPalette.textSecondary)

            TextField(
                "",
                text: $heartRateDeviceBrand,
                prompt: Text("Amazfit, Polar, Garmin...")
                    .foregroundColor(EndfieldPalette.textSecondary.opacity(0.6))
            )
            .textFieldStyle(.plain)
            .font(EndfieldFont.mono(12.0, weight: .bold))
            .foregroundStyle(EndfieldPalette.textPrimary)
            .tint(EndfieldPalette.accentYellow)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .padding(.vertical, 8.0)
            .padding(.horizontal, 8.0)
            .background(EndfieldPalette.bgElevated)
            .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                    .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
            }

            Text("La conexión usa el servicio BLE estándar de pulso (0x180D). Si la pulsera no aparece, activa la emisión de pulso por Bluetooth en su app (Zepp, Polar Flow, Garmin Connect...).")
                .font(EndfieldFont.mono(9.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Estado del sensor cardíaco

/// Vista aislada del sensor: las lecturas llegan a varios Hz y así solo se
/// redibuja este bloque, no toda la pantalla de Ajustes.
private struct HeartRateSensorStatusView: View {
    @ObservedObject private var bpmManager = BPMManager.shared

    let deviceType: HeartRateDeviceType

    private var statusTint: Color {
        return bpmManager.currentBPM > 0 ? EndfieldPalette.accentRed : EndfieldPalette.textSecondary
    }

    private var deviceLabel: String {
        let name: String = bpmManager.connectedDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? deviceType.title.uppercased() : name.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7.0) {
            HStack(spacing: 6.0) {
                EndfieldLiveDot(size: 5.0)

                Text("ESTADO SENSOR")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.textSecondary)

                Spacer(minLength: 4.0)

                Text(bpmManager.isConnected ? "ENLACE OK" : "SIN ENLACE")
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(bpmManager.isConnected ? EndfieldPalette.accentCyan : EndfieldPalette.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4.0) {
                Text(bpmManager.currentBPM > 0 ? "\(bpmManager.currentBPM)" : "--")
                    .font(EndfieldFont.mono(22.0, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(statusTint)

                Text("BPM")
                    .font(EndfieldFont.label(8.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize()

                Spacer(minLength: 4.0)

                Text(deviceLabel)
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.6)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Text(bpmManager.statusText.uppercased())
                .font(EndfieldFont.mono(9.0))
                .foregroundStyle(EndfieldPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                bpmManager.reconnect()
            } label: {
                HStack(spacing: 6.0) {
                    Image(systemName: "arrow.clockwise")
                        .font(EndfieldFont.mono(10.0, weight: .bold))

                    Text(deviceType == .airPods ? "RECONECTAR AIRPODS" : "RECONECTAR SENSOR")
                        .font(EndfieldFont.mono(10.0, weight: .bold))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentCyan))
        }
        .padding(9.0)
        .background(EndfieldPalette.bgElevated)
        .clipShape(ChamferedRectangle(cut: EndfieldMetrics.cellCut))
        .overlay {
            ChamferedRectangle(cut: EndfieldMetrics.cellCut)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
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
