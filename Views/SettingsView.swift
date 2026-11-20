import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Apartados de Configuración

/// Apartados de Configuración en el orden en que se muestran. El código se
/// deriva de la posición real, así que la numeración no puede desincronizarse
/// al mover un apartado.
enum SettingsSection: String, CaseIterable, Identifiable {
    case equipment
    case plates
    case visualMode
    case heartRate
    case organization
    case weeklyGoal
    case backup
    case safetyCopies

    var id: String { rawValue }

    /// Posición real dentro de la pantalla, empezando en 1.
    var position: Int {
        return (SettingsSection.allCases.firstIndex(of: self) ?? 0) + 1
    }

    var code: String {
        return String(format: "RT.%02d", position)
    }

    var title: String {
        switch self {
        case .equipment: return "Equipamiento"
        case .plates: return "Discos"
        case .visualMode: return "Modo visual"
        case .heartRate: return "Pulsaciones"
        case .organization: return "Organización del entrenamiento"
        case .weeklyGoal: return "Objetivo semanal"
        case .backup: return "Copia de seguridad"
        case .safetyCopies: return "Copias automáticas"
        }
    }
}

/// Estado del acordeón de Configuración: como mucho un apartado abierto.
/// `nil` deja todos cerrados.
struct SettingsAccordionState: Equatable {
    private(set) var expandedSection: SettingsSection?

    init(expandedSection: SettingsSection? = nil) {
        self.expandedSection = expandedSection
    }

    func isExpanded(_ section: SettingsSection) -> Bool {
        return expandedSection == section
    }

    mutating func expand(_ section: SettingsSection) {
        expandedSection = section
    }

    mutating func collapse() {
        expandedSection = nil
    }

    mutating func toggle(_ section: SettingsSection) {
        expandedSection = (expandedSection == section) ? nil : section
    }
}

/// Aviso obligatorio antes de abrir el flujo de cambio de rutina: hasta que el
/// usuario no confirma, no se abre el flujo y no se modifica nada.
struct RoutineChangeGate: Equatable {
    private(set) var isAwaitingConfirmation: Bool = false
    private(set) var isPresentingFlow: Bool = false

    mutating func requestChange() {
        isAwaitingConfirmation = true
    }

    mutating func cancel() {
        isAwaitingConfirmation = false
    }

    mutating func confirm() {
        isAwaitingConfirmation = false
        isPresentingFlow = true
    }

    mutating func dismissFlow() {
        isPresentingFlow = false
    }
}

/// Textos únicos del aviso de cambio de rutina.
enum RoutineChangeMessages {
    static let title: String = "¿Cambiar la organización de tus rutinas?"
    static let message: String = "Al cambiar tu organización, las rutinas actuales serán sustituidas por las nuevas. Los datos y el historial de tus entrenamientos no se perderán, pero las rutinas actuales dejarán de estar disponibles."
    static let cancelTitle: String = "Cancelar"
    static let confirmTitle: String = "Continuar"
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(UserSettingsManager.multipowerBarWeightKey)
    private var multipowerBarWeight: Double = UserSettingsManager.defaultMultipowerBarWeight

    @AppStorage(UserSettingsManager.ezBarWeightKey)
    private var ezBarWeight: Double = UserSettingsManager.defaultEZBarWeight

    @AppStorage(UserSettingsManager.standardBarWeightKey)
    private var standardBarWeight: Double = UserSettingsManager.defaultStandardBarWeight

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

    /// Acordeón de Configuración: un único estado compartido decide qué
    /// apartado está abierto (ninguno cuando es `nil`).
    @State private var accordion: SettingsAccordionState = SettingsAccordionState()

    /// Confirmación previa obligatoria antes de abrir Ajustes → Cambiar rutina.
    @State private var changeGate: RoutineChangeGate = RoutineChangeGate()

    /// Copia de seguridad.
    @State private var showFileExporter: Bool = false
    @State private var showImportWarningAlert: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var showBackupResultAlert: Bool = false
    @State private var backupResultMessage: String = ""
    @State private var backupDocument: WorkoutBackupDocument?
    @State private var backupFileName: String = BackupManager.defaultFileName()
    @State private var backupExportWarnings: [String] = []
    @State private var safetyCopies: [PreImportBackup] = []
    @State private var safetyCopyPendingRestore: PreImportBackup?

    /// Importación validada pendiente de revisión. Mientras exista, la hoja de
    /// revisión es la única vía para aplicar el archivo preparado.
    @State private var reviewPlan: BackupImportPlan?
    @State private var reviewSuccessLead: String = ""

    /// Cabeceras del mensaje final. La revisión compartida añade las rutinas
    /// protegidas conservadas y los avisos de integridad.
    private static let importSuccessLead: String = "Importación completada. Se han restaurado las rutinas, las sesiones de entrenamiento y los ajustes del archivo, y se ha guardado una copia automática de los datos anteriores."
    private static let safetyCopySuccessLead: String = "Copia automática restaurada. Se han recuperado los datos tal y como estaban antes de esa importación."

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
                    ForEach(SettingsSection.allCases) { (section: SettingsSection) in
                        EndfieldDisclosure(
                            code: section.code,
                            title: section.title,
                            isExpanded: expansionBinding(for: section)
                        ) {
                            sectionContent(for: section)
                        }
                    }
                }
                .padding(.horizontal, 16.0)
                .padding(.vertical, 14.0)
            }
        }
        .onAppear {
            reloadSafetyCopies()
        }
        .fullScreenCover(isPresented: routineFlowBinding) {
            OnboardingFlowView(context: .changeRoutine) {
                changeGate.dismissFlow()
            }
        }
        .alert(RoutineChangeMessages.title, isPresented: awaitingRoutineChangeBinding) {
            Button(RoutineChangeMessages.cancelTitle, role: .cancel) {
                changeGate.cancel()
            }

            Button(RoutineChangeMessages.confirmTitle) {
                changeGate.confirm()
            }
        } message: {
            Text(RoutineChangeMessages.message)
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
        .sheet(item: $reviewPlan) { (plan: BackupImportPlan) in
            BackupImportReviewSheet(
                plan: plan,
                successLead: reviewSuccessLead,
                performsImport: {
                    return performPreparedImport(plan)
                },
                onImported: { (_: BackupImportResult) in
                    reviewPlan = nil
                    reloadSafetyCopies()
                },
                onDismiss: {
                    reviewPlan = nil
                }
            )
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
                    beginImportReview(
                        url: pending.url,
                        successLead: Self.safetyCopySuccessLead
                    )
                }
            }
        } message: {
            Text("Al restaurar esta copia se sobrescribirán las rutinas y las sesiones de entrenamiento actuales. ¿Quieres continuar?")
        }
    }

    // MARK: - Acordeón

    /// Todos los apartados comparten el mismo estado: abrir uno cierra el que
    /// estuviera abierto y volver a pulsarlo lo cierra.
    private func expansionBinding(for section: SettingsSection) -> Binding<Bool> {
        return Binding(
            get: { accordion.isExpanded(section) },
            set: { (isExpanded: Bool) in
                if isExpanded {
                    accordion.expand(section)
                } else {
                    accordion.collapse()
                }
            }
        )
    }

    @ViewBuilder
    private func sectionContent(for section: SettingsSection) -> some View {
        switch section {
        case .equipment:
            equipmentContent
        case .plates:
            platesContent
        case .visualMode:
            visualModeContent
        case .heartRate:
            heartRateContent
        case .organization:
            organizationContent
        case .weeklyGoal:
            weeklyGoalContent
        case .backup:
            backupContent
        case .safetyCopies:
            safetyCopiesContent
        }
    }

    // MARK: - Confirmación de cambio de rutina

    private var awaitingRoutineChangeBinding: Binding<Bool> {
        return Binding(
            get: { changeGate.isAwaitingConfirmation },
            set: { (isPresented: Bool) in
                if !isPresented {
                    changeGate.cancel()
                }
            }
        )
    }

    private var routineFlowBinding: Binding<Bool> {
        return Binding(
            get: { changeGate.isPresentingFlow },
            set: { (isPresented: Bool) in
                if !isPresented {
                    changeGate.dismissFlow()
                }
            }
        )
    }

    // MARK: - Paneles

    private var equipmentContent: some View {
        Group {
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

                Rectangle()
                    .fill(EndfieldPalette.borderSubtle)
                    .frame(height: 1.0)

                barWeightBlock(
                    title: "Peso barra estándar",
                    value: $standardBarWeight,
                    stepperLabel: "Ajustar barra estándar: \(UserSettingsManager.formatted(standardBarWeight)) kg",
                    range: 0...100
                )

                Text("Estos pesos se usan como base al calcular los discos de Multipower, barra EZ y barra estándar. La barra estándar no tiene un peso universal: ajusta el de tu gimnasio.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var platesContent: some View {
        Group {
            VStack(alignment: .leading, spacing: 6.0) {
                Text("\(availablePlates.count) DISCOS ACTIVOS")
                    .font(EndfieldFont.label(9.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.accentYellow)
                    .fixedSize()

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

    private var weeklyGoalContent: some View {
        Group {
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

    // MARK: - Organización del entrenamiento

    private var organizationContent: some View {
        Group {
            VStack(alignment: .leading, spacing: 9.0) {
                HStack(spacing: 8.0) {
                    Text("MODALIDAD ACTUAL")
                        .font(EndfieldFont.label(9.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4.0)

                    Text(UserSettingsManager.routineOrganizationMode?.title.uppercased() ?? "SIN DEFINIR")
                        .font(EndfieldFont.mono(10.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.accentYellow)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }

                Button {
                    changeGate.requestChange()
                } label: {
                    HStack(spacing: 7.0) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(EndfieldFont.mono(11.0, weight: .bold))

                        Text("CAMBIAR RUTINA")
                            .font(EndfieldFont.mono(11.0, weight: .bold))
                            .tracking(1.0)
                    }
                }
                .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.accentCyan))
                .accessibilityHint("Muestra el aviso de confirmación antes de abrir el cambio de organización")

                Text("Sustituye tu organización de entrenamiento por una nueva. Las rutinas actuales dejan de estar activas, pero no se borran: sus sesiones, pesos, series y récords se conservan.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var visualModeContent: some View {
        Group {
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

    private var heartRateContent: some View {
        Group {
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

    private var backupContent: some View {
        Group {
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

    private var safetyCopiesContent: some View {
        Group {
            VStack(alignment: .leading, spacing: 8.0) {
                if safetyCopies.isEmpty {
                    Text("Todavía no hay copias automáticas. Se guardan antes de cada importación.")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    SafetyBackupSectionView(
                        copies: safetyCopies,
                        onRestoreTapped: { (copy: PreImportBackup) -> Void in
                            safetyCopyPendingRestore = copy
                        }
                    )
                }

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
            let result: BackupExportResult = try BackupManager.createBackup(context: modelContext)
            backupDocument = result.document
            backupExportWarnings = result.report.warnings.map(\.message)
            backupFileName = BackupManager.defaultFileName()
            showFileExporter = true
        } catch {
            backupExportWarnings = []
            presentBackupResult(message: error.localizedDescription)
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            var message: String = "Exportación completada. El archivo incluye tus rutinas, ejercicios, sesiones de entrenamiento y ajustes del gimnasio."
            if !backupExportWarnings.isEmpty {
                message += "\n\nAvisos de integridad:\n" + backupExportWarnings.map { "• \($0)" }.joined(separator: "\n")
            }
            presentBackupResult(message: message)
        case .failure(let error):
            presentBackupResult(message: error.localizedDescription)
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            beginImportReview(url: url, successLead: Self.importSuccessLead)
        case .failure(let error):
            presentBackupResult(message: error.localizedDescription)
        }
    }

    private func reloadSafetyCopies() {
        safetyCopies = BackupManager.availableSafetyCopies()
    }

    /// Valida el archivo sin modificar SwiftData y abre la revisión compartida.
    /// La restauración solo se ejecuta después de esa revisión, nunca antes.
    private func beginImportReview(url: URL, successLead: String) {
        do {
            reviewSuccessLead = successLead
            reviewPlan = try BackupManager.prepareImport(from: url, context: modelContext)
        } catch {
            presentBackupResult(message: error.localizedDescription)
        }
    }

    private func performPreparedImport(_ plan: BackupImportPlan) -> Result<BackupImportResult, Error> {
        do {
            return .success(try BackupManager.restoreBackup(using: plan, context: modelContext))
        } catch {
            return .failure(error)
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

// MARK: - Revisión compartida de importaciones

/// Textos únicos del aviso de pérdida de historial. Ajustes y onboarding usan
/// los mismos, de modo que la consecuencia se explica igual en ambos flujos.
enum BackupImportMessages {
    static let historyLossTitle: String = "El backup no contiene historial"
    static let historyLossMessage: String = "El backup seleccionado no contiene sesiones de entrenamiento. Si continúas, el historial actual será sustituido y dejará de aparecer en AppGym. Antes de continuar se guardará una copia de seguridad automática."
}

/// Presentación del resultado de `prepareImport`.
///
/// Es el único sistema de avisos de integridad de la app: lo usan tanto la
/// importación desde Ajustes como la del onboarding. No modifica ningún dato;
/// solo describe el plan que se aplicará si el usuario confirma.
struct BackupValidationReportView: View {
    let plan: BackupImportPlan

    var body: some View {
        VStack(spacing: 10.0) {
            statusPanel

            if !plan.report.blockingIssues.isEmpty {
                issuePanel(
                    title: "IMPORTACIÓN BLOQUEADA",
                    issues: plan.report.blockingIssues,
                    tint: EndfieldPalette.accentRed
                )
            }

            if !plan.report.warnings.isEmpty {
                issuePanel(
                    title: "AVISOS DE INTEGRIDAD",
                    issues: plan.report.warnings,
                    tint: EndfieldPalette.accentYellow
                )
            }

            if !plan.preservedProtectedRoutines.isEmpty {
                preservedRoutinesPanel
            }

            if plan.replacesSessionHistoryWithEmpty {
                historyLossPanel
            }
        }
    }

    // MARK: Estado general

    private var statusTitle: String {
        switch plan.report.status {
        case .valid:
            return "COPIA VÁLIDA"
        case .validWithWarnings:
            return "COPIA VÁLIDA CON AVISOS"
        case .incompatible:
            return "COPIA INCOMPATIBLE"
        case .corrupt:
            return "COPIA CORRUPTA"
        case .requiresUserIntervention:
            return "REQUIERE INTERVENCIÓN"
        }
    }

    private var statusMessage: String {
        switch plan.report.status {
        case .valid:
            return "La copia puede restaurarse tal y como está."
        case .validWithWarnings:
            return "La copia puede restaurarse, pero algunos datos pueden no recuperarse exactamente como estaban. Revisa los avisos antes de continuar."
        case .incompatible:
            return "Esta copia no es compatible con la versión actual de AppGym. No se ha modificado ningún dato."
        case .corrupt:
            return "La copia contiene datos ilegibles. No se ha modificado ningún dato."
        case .requiresUserIntervention:
            return "La copia entra en conflicto con tus rutinas protegidas y no se puede aplicar sin resolverlo antes. No se ha modificado ningún dato."
        }
    }

    private var statusTint: Color {
        return plan.report.canImport ? EndfieldPalette.accentCyan : EndfieldPalette.accentRed
    }

    private var statusPanel: some View {
        TacticalPanel(code: "BK.02", title: "Revisión de la copia", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 6.0) {
                Text(statusTitle)
                    .font(EndfieldFont.label(10.0))
                    .tracking(1.0)
                    .foregroundStyle(statusTint)
                    .fixedSize(horizontal: false, vertical: true)

                Text(statusMessage)
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Incidencias

    private func issuePanel(
        title: String,
        issues: [BackupIssue],
        tint: Color
    ) -> some View {
        TacticalPanel(code: "BK.03", title: title, contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 6.0) {
                ForEach(issues) { (issue: BackupIssue) in
                    HStack(alignment: .top, spacing: 5.0) {
                        Text("•")
                            .font(EndfieldFont.mono(9.0, weight: .bold))
                            .foregroundStyle(tint)

                        Text(issue.message)
                            .font(EndfieldFont.mono(9.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: Rutinas protegidas

    private var preservedRoutinesPanel: some View {
        TacticalPanel(code: "PRT.01", title: "Rutinas protegidas", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 6.0) {
                Text("Estas rutinas personales se conservarán tal y como están en esta instalación. Las versiones del backup no las sustituirán, aunque el archivo las contenga.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(plan.preservedProtectedRoutines) { (routine: BackupPreservedRoutine) in
                    HStack(alignment: .top, spacing: 6.0) {
                        Image(systemName: "lock.fill")
                            .font(EndfieldFont.mono(9.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.accentYellow)

                        VStack(alignment: .leading, spacing: 1.0) {
                            Text(routine.name.uppercased())
                                .font(EndfieldFont.label(9.0))
                                .tracking(0.8)
                                .foregroundStyle(EndfieldPalette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(String(routine.id.uuidString.prefix(8)))
                                .font(EndfieldFont.mono(8.0))
                                .foregroundStyle(EndfieldPalette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Historial

    private var historyLossPanel: some View {
        TacticalPanel(code: "HST.01", title: "Historial de entrenamiento", contentPadding: 12.0) {
            Text(BackupImportMessages.historyLossMessage)
                .font(EndfieldFont.mono(9.0))
                .foregroundStyle(EndfieldPalette.accentRed)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Revisión de una importación ya preparada, con el diálogo de pérdida de
/// historial y la ejecución del plan mostrado.
///
/// La usan Ajustes y el onboarding. La confirmación nunca recalcula la
/// validación: aplica exactamente el plan recibido.
struct BackupImportReviewSheet: View {
    let plan: BackupImportPlan
    let successLead: String
    /// El onboarding muestra su propio panel de éxito; Ajustes mantiene la
    /// alerta de resultado que ya utilizaba.
    var presentsResultAlert: Bool = true
    let performsImport: () -> Result<BackupImportResult, Error>
    let onImported: (BackupImportResult) -> Void
    let onDismiss: () -> Void

    @State private var isWorking: Bool = false
    @State private var showsHistoryConfirmation: Bool = false
    @State private var isShowingResultAlert: Bool = false
    @State private var resultMessage: String = ""
    @State private var importedResult: BackupImportResult?

    var body: some View {
        NavigationStack {
            ZStack {
                TechnicalGridBackground()

                ScrollView {
                    VStack(spacing: 10.0) {
                        BackupValidationReportView(plan: plan)
                        actions
                    }
                    .padding(.horizontal, 16.0)
                    .padding(.vertical, 14.0)
                }
            }
            .navigationTitle("IMPORTAR COPIA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        onDismiss()
                    }
                    .disabled(isWorking)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(EndfieldPalette.accentYellow)
        .interactiveDismissDisabled(isWorking)
        .alert(BackupImportMessages.historyLossTitle, isPresented: $showsHistoryConfirmation) {
            Button("Cancelar", role: .cancel) {
                // Sin acción: no se ejecuta ninguna importación.
            }

            Button("Continuar", role: .destructive) {
                runImport()
            }
        } message: {
            Text(BackupImportMessages.historyLossMessage)
        }
        .alert("Copia de seguridad", isPresented: $isShowingResultAlert) {
            Button("Entendido", role: .cancel) {
                if let result: BackupImportResult = importedResult {
                    onImported(result)
                } else {
                    onDismiss()
                }
            }
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: Acciones

    private var actions: some View {
        VStack(spacing: 8.0) {
            if !plan.report.canImport {
                Text("Esta copia no se puede importar. No se ha modificado ningún dato.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.accentRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isWorking {
                HStack(spacing: 8.0) {
                    ProgressView()
                        .tint(EndfieldPalette.accentCyan)

                    Text("IMPORTANDO COPIA...")
                        .font(EndfieldFont.label(9.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            Button("CANCELAR") {
                onDismiss()
            }
            .buttonStyle(EndfieldSecondaryButtonStyle(tint: EndfieldPalette.textSecondary))
            .disabled(isWorking)

            Button("IMPORTAR Y SUSTITUIR DATOS") {
                requestImport()
            }
            .buttonStyle(
                EndfieldSecondaryButtonStyle(
                    tint: plan.report.canImport ? EndfieldPalette.accentRed : EndfieldPalette.textSecondary.opacity(0.6)
                )
            )
            .disabled(!plan.report.canImport || isWorking)
            .accessibilityHint("Aplica la copia revisada. Antes se guarda una copia automática de los datos actuales.")
        }
    }

    /// Solo pide confirmación cuando el plan realmente sustituye un historial
    /// existente por uno vacío. El resto de importaciones siguen su curso.
    private func requestImport() {
        guard plan.report.canImport, !isWorking else { return }

        if plan.replacesSessionHistoryWithEmpty {
            showsHistoryConfirmation = true
        } else {
            runImport()
        }
    }

    private func runImport() {
        guard plan.report.canImport, !isWorking else { return }

        isWorking = true
        let outcome: Result<BackupImportResult, Error> = performsImport()
        isWorking = false

        switch outcome {
        case .success(let result):
            if presentsResultAlert {
                importedResult = result
                resultMessage = Self.successMessage(result: result, lead: successLead)
                isShowingResultAlert = true
            } else {
                onImported(result)
            }

        case .failure(let error):
            if presentsResultAlert {
                importedResult = nil
                resultMessage = error.localizedDescription
                isShowingResultAlert = true
            } else {
                onDismiss()
            }
        }
    }

    private static func successMessage(result: BackupImportResult, lead: String) -> String {
        var message: String = lead
        if !result.preservedProtectedRoutineIDs.isEmpty {
            message += " Se han conservado las \(result.preservedProtectedRoutineIDs.count) rutina(s) personal(es) protegida(s) de esta instalación."
        }
        if !result.report.warnings.isEmpty {
            message += "\n\nAvisos:\n" + result.report.warnings.map { "• \($0.message)" }.joined(separator: "\n")
        }
        return message
    }
}
