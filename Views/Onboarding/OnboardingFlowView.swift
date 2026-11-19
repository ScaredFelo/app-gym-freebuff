import SwiftUI
import SwiftData

/// Flujo único de configuración de rutinas.
///
/// Se abre en dos contextos:
/// - `.initialSetup` desde el arranque de la app (bienvenida → copia →
///   personalización → modalidad → resumen).
/// - `.changeRoutine` desde Ajustes (modalidad → configuración → resumen).
///
/// En ambos casos las pantallas, los ViewModels y el guardado son los mismos.
struct OnboardingFlowView: View {

    enum Step: Hashable {
        case welcome
        case backupImport
        case personalize
        case equipment
        case heartRate
        case organization
        case ownRoutines
        case templateBuilder
        case automaticConfiguration
        case summary
    }

    let context: RoutineFlowContext
    var onFinished: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @StateObject private var onboarding: OnboardingViewModel
    @StateObject private var configuration: RoutineConfigurationViewModel

    @State private var path: [Step] = []
    @State private var showsChangeConfirmation: Bool = false

    init(context: RoutineFlowContext, onFinished: @escaping () -> Void = {}) {
        self.context = context
        self.onFinished = onFinished
        _onboarding = StateObject(wrappedValue: OnboardingViewModel(context: context))
        _configuration = StateObject(wrappedValue: RoutineConfigurationViewModel(context: context))
        EndfieldAppearance.apply()
    }

    var body: some View {
        NavigationStack(path: $path) {
            stepView(rootStep)
                .navigationDestination(for: Step.self) { step in
                    stepView(step)
                }
        }
        .tint(EndfieldPalette.accentYellow)
        .preferredColorScheme(.dark)
        .alert("No se pudo guardar", isPresented: saveErrorBinding) {
            Button("Entendido", role: .cancel) {
                configuration.errorMessage = nil
            }
        } message: {
            Text(configuration.errorMessage ?? "")
        }
        .alert("Confirmar cambio de rutina", isPresented: $showsChangeConfirmation) {
            Button("Cancelar", role: .cancel) {}

            Button("Aplicar cambio") {
                confirmPlan()
            }
        } message: {
            Text("Se archivarán las rutinas generadas anteriores y se aplicará la nueva organización. Las rutinas manuales y tus cinco rutinas personales se conservan, junto con tu historial, tus pesos y tus récords.")
        }
    }

    // MARK: - Raíz

    private var rootStep: Step {
        return context == .initialSetup ? .welcome : .organization
    }

    // MARK: - Pantallas

    @ViewBuilder
    private func stepView(_ step: Step) -> some View {
        switch step {
        case .welcome:
            OnboardingWelcomeView(
                chrome: chrome(for: step),
                viewModel: onboarding,
                onSelect: handlePreviousUse
            )

        case .backupImport:
            BackupImportStepView(
                chrome: chrome(for: step),
                viewModel: onboarding,
                onContinue: { advance(to: .personalize) }
            )

        case .personalize:
            OnboardingPersonalizationView(
                chrome: chrome(for: step),
                viewModel: onboarding,
                onSelect: handlePersonalization
            )

        case .equipment:
            EquipmentSetupView(
                chrome: chrome(for: step),
                viewModel: onboarding,
                onContinue: { advance(to: .heartRate) }
            )

        case .heartRate:
            HeartRateSetupView(
                chrome: chrome(for: step),
                viewModel: onboarding,
                onContinue: { advance(to: .organization) }
            )

        case .organization:
            RoutineSelectionView(
                chrome: chrome(for: step),
                viewModel: configuration,
                onContinue: handleOrganizationContinue
            )

        case .ownRoutines:
            CreateOwnRoutinesView(
                chrome: chrome(for: step),
                viewModel: configuration,
                onContinue: { advance(to: .summary) }
            )

        case .templateBuilder:
            AssistedSplitConfigurationView(
                chrome: chrome(for: step),
                viewModel: configuration.assisted,
                onContinue: { advance(to: .summary) }
            )

        case .automaticConfiguration:
            AutomaticSplitConfigurationView(
                chrome: chrome(for: step),
                viewModel: configuration,
                onContinue: { advance(to: .summary) }
            )

        case .summary:
            if configuration.plan.mode == .templates {
                AssistedRoutineSummaryView(
                    chrome: chrome(for: step),
                    context: context,
                    viewModel: configuration.assisted,
                    isSaving: configuration.isSaving,
                    onEdit: {
                        if !path.isEmpty {
                            path.removeLast()
                        }
                    },
                    onConfirm: requestConfirmation
                )
            } else {
                RoutineSummaryView(
                    chrome: chrome(for: step),
                    context: context,
                    sections: configuration.summarySections(preferences: onboarding.preferences),
                    notices: configuration.activeNotices,
                    isSaving: configuration.isSaving,
                    onConfirm: requestConfirmation
                )
            }
        }
    }

    // MARK: - Navegación

    private func advance(to step: Step) {
        path.append(step)
    }

    private func handlePreviousUse(_ hasUsed: Bool) {
        OnboardingHaptics.selection()
        onboarding.selectPreviousUse(hasUsed)
        advance(to: hasUsed ? .backupImport : .personalize)
    }

    private func handlePersonalization(_ choice: OnboardingViewModel.PersonalizationChoice) {
        OnboardingHaptics.selection()
        onboarding.selectPersonalization(choice)

        switch choice {
        case .customize:
            advance(to: .equipment)
        case .useDefaults:
            advance(to: .organization)
        case .undecided:
            break
        }
    }

    private func handleOrganizationContinue() {
        guard let mode: RoutineOrganizationMode = configuration.plan.mode else { return }
        OnboardingHaptics.selection()
        advance(to: step(for: mode))
    }

    private func step(for mode: RoutineOrganizationMode) -> Step {
        switch mode {
        case .createOwn:
            return .ownRoutines
        case .templates:
            return .templateBuilder
        case .automatic:
            return .automaticConfiguration
        }
    }

    // MARK: - Resumen y guardado

    private func requestConfirmation() {
        if context == .changeRoutine {
            showsChangeConfirmation = true
        } else {
            confirmPlan()
        }
    }

    private func confirmPlan() {
        guard !configuration.isSaving else { return }

        Task { @MainActor in
            let didSave: Bool = await configuration.save(
                preferences: onboarding.preferences,
                modelContext: modelContext
            )

            guard didSave else { return }

            BPMManager.shared.applySettings()
            onboarding.completeSetupIfNeeded()
            OnboardingHaptics.confirmation()
            onFinished()
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        return Binding(
            get: { configuration.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    configuration.errorMessage = nil
                }
            }
        )
    }

    // MARK: - Progreso

    private func chrome(for step: Step) -> OnboardingChrome {
        let sequence: [Step] = orderedSteps()
        let index: Int = sequence.firstIndex(of: step) ?? 0
        let total: Int = max(sequence.count, 1)
        let progress: Double = Double(index + 1) / Double(total)

        return OnboardingChrome(
            contextTitle: context.navigationTitle,
            stepLabel: String(format: "PASO %02d/%02d", index + 1, total),
            progress: progress,
            showsCancel: context.allowsCancellation,
            onCancel: context.allowsCancellation ? cancelFlow : nil
        )
    }

    /// Secuencia de pasos según el contexto y las respuestas dadas. La
    /// selección de rutinas personalizadas solo aparece al personalizar.
    private func orderedSteps() -> [Step] {
        guard context == .initialSetup else {
            return [.organization, modeStep(), .summary]
        }

        var steps: [Step] = [.welcome]

        if onboarding.hasUsedAppPreviously == true {
            steps.append(.backupImport)
        }

        steps.append(.personalize)

        if onboarding.shouldShowPersonalizationSteps {
            steps.append(.equipment)
            steps.append(.heartRate)
        }

        steps.append(.organization)
        steps.append(modeStep())
        steps.append(.summary)

        return steps
    }

    private func modeStep() -> Step {
        guard let mode: RoutineOrganizationMode = configuration.plan.mode else {
            return .ownRoutines
        }
        return step(for: mode)
    }

    private func cancelFlow() {
        path.removeAll()
        onFinished()
    }
}
