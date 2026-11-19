import SwiftUI

/// Generación automática de la semana a partir de la matriz W/L/U.
///
/// La vista solo recoge la entrada del usuario y presenta los resultados de
/// `SplitGenerator`, `RoutineGenerator` y los análisis. Toda la lógica vive en
/// los servicios.
struct AutomaticSplitConfigurationView: View {
    let chrome: OnboardingChrome
    @ObservedObject var viewModel: RoutineConfigurationViewModel
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "Generar mi split automáticamente",
            subtitle: "Indica los días y la frecuencia de piernas y tren superior. La app consulta la matriz oficial y propone los splits disponibles.",
            footer: footer
        ) {
            inputsPanel
            statusPanels

            Button {
                OnboardingHaptics.selection()
                viewModel.consultSplitMatrix()
            } label: {
                Text("CONSULTAR SPLITS")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(EndfieldSecondaryButtonStyle())
            .frame(maxWidth: .infinity)

            if !viewModel.automatic.proposals.isEmpty {
                proposalsPanel
            }

            if let week = viewModel.automatic.week {
                weekPanel(week)
                noticesPanel(week)
            }

            OnboardingInfoNote(
                text: "La generación usa la matriz W/L/U y el catálogo de ejercicios incluidos en la app. No se inventan combinaciones, variantes ni ejercicios. Los avisos de recuperación y fatiga son informativos: la decisión final es tuya."
            )
        }
    }

    // MARK: - Entrada

    private var inputsPanel: some View {
        TacticalPanel(code: "AUT.01", title: "Parámetros W/L/U", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                TacticalStepperRow(
                    code: "W",
                    title: "Días de entrenamiento",
                    value: daysBinding,
                    range: 1...7,
                    unit: " D"
                )

                TacticalStepperRow(
                    code: "L",
                    title: "Frecuencia de piernas",
                    value: legsBinding,
                    range: 0...viewModel.automatic.days,
                    unit: "×"
                )

                TacticalStepperRow(
                    code: "U",
                    title: "Frecuencia tren superior",
                    value: upperBinding,
                    range: 0...viewModel.automatic.days,
                    unit: "×"
                )

                Text("W = días por semana · L = sesiones con piernas · U = sesiones de tren superior")
                    .font(EndfieldFont.mono(8.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var daysBinding: Binding<Int> {
        return Binding(
            get: { viewModel.automatic.days },
            set: { viewModel.setAutomaticDays($0) }
        )
    }

    private var legsBinding: Binding<Int> {
        return Binding(
            get: { viewModel.automatic.legs },
            set: { viewModel.setAutomaticLegs($0) }
        )
    }

    private var upperBinding: Binding<Int> {
        return Binding(
            get: { viewModel.automatic.upper },
            set: { viewModel.setAutomaticUpper($0) }
        )
    }

    // MARK: - Validación

    @ViewBuilder
    private var statusPanels: some View {
        if let message = viewModel.automatic.inputError {
            messagePanel(
                code: "AUT.E1",
                title: "Revisa los parámetros",
                message: message,
                tint: EndfieldPalette.accentRed
            )
        }

        if let warning = viewModel.automatic.warning {
            messagePanel(
                code: weeklyRestCode(warning),
                title: weeklyRestTitle(warning),
                message: warning.message,
                tint: weeklyRestTint(warning)
            )
        } else if viewModel.automatic.days == 7 {
            // La regla W = 7 se muestra en cuanto se selecciona, sin esperar a
            // pulsar «Consultar»: nunca se permite generar con 7 días.
            messagePanel(
                code: "AUT.W7",
                title: "7 días sin descanso",
                message: SplitGenerator.weeklyRestMessage,
                tint: EndfieldPalette.accentYellow
            )
        }

        if !viewModel.automatic.incidences.isEmpty {
            TacticalPanel(code: "AUT.I1", title: "Incidencias de la matriz", contentPadding: 12.0) {
                VStack(alignment: .leading, spacing: 6.0) {
                    ForEach(viewModel.automatic.incidences, id: \.self) { (incidence: String) in
                        Text("· \(incidence)")
                            .font(EndfieldFont.mono(9.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        if let message = viewModel.automatic.generationError {
            messagePanel(
                code: "AUT.E2",
                title: "No se puede generar la rutina",
                message: message,
                tint: EndfieldPalette.accentRed
            )
        }
    }

    private func messagePanel(code: String, title: String, message: String, tint: Color) -> some View {
        TacticalPanel(code: code, title: title, contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 6.0) {
                Text(message)
                    .font(EndfieldFont.mono(10.0))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Aviso informativo: no se generará ninguna rutina para esta combinación.")
                    .font(EndfieldFont.label(7.0))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func weeklyRestCode(_ warning: SplitValidationWarning) -> String {
        switch warning.kind {
        case .weeklyRest:
            return "AUT.W7"
        case .insufficientRest:
            return "AUT.W1"
        }
    }

    private func weeklyRestTitle(_ warning: SplitValidationWarning) -> String {
        switch warning.kind {
        case .weeklyRest:
            return "7 días sin descanso"
        case .insufficientRest:
            return "La matriz marca esta combinación"
        }
    }

    private func weeklyRestTint(_ warning: SplitValidationWarning) -> Color {
        switch warning.kind {
        case .weeklyRest:
            return EndfieldPalette.accentYellow
        case .insufficientRest:
            return EndfieldPalette.accentRed
        }
    }

    // MARK: - Propuestas

    private var proposalsPanel: some View {
        TacticalPanel(code: "AUT.02", title: "Propuestas de la matriz", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                Text("La combinación tiene \(viewModel.automatic.proposals.count) propuesta(s). Selecciona una para generar la semana.")
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(viewModel.automatic.proposals) { (proposal: SplitProposal) in
                    proposalRow(proposal)
                }
            }
        }
    }

    private func proposalRow(_ proposal: SplitProposal) -> some View {
        let isSelected: Bool = viewModel.automatic.selectedProposalID == proposal.id
        let tint: Color = isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.textSecondary

        return Button {
            OnboardingHaptics.selection()
            viewModel.selectProposal(proposal)
        } label: {
            VStack(alignment: .leading, spacing: 6.0) {
                HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                    Text(proposal.expression)
                        .font(EndfieldFont.mono(11.0, weight: .heavy))
                        .foregroundStyle(isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4.0)

                    Text("\(proposal.sessionCount) SESIONES")
                        .font(EndfieldFont.label(7.0))
                        .tracking(0.8)
                        .foregroundStyle(tint)
                        .fixedSize()
                }

                Text(proposal.structurePreview)
                    .font(EndfieldFont.mono(9.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(proposal.blockCodes.joined(separator: " · "))
                    .font(EndfieldFont.label(7.0))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                    .fill(isSelected ? EndfieldPalette.bgElevated : EndfieldPalette.bgPanel)
            )
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.8)
                    .stroke(isSelected ? EndfieldPalette.accentYellow.opacity(0.65) : EndfieldPalette.borderSubtle, lineWidth: 1.0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Split \(proposal.expression), \(proposal.sessionCount) sesiones")
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }

    // MARK: - Semana generada

    private func weekPanel(_ week: GeneratedWeek) -> some View {
        let totalSets: Int = week.sessions.reduce(0) { (partial: Int, session: GeneratedSession) -> Int in
            return partial + session.totalSets
        }

        return TacticalPanel(code: "AUT.03", title: "Semana generada", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 12.0) {
                HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                    Text("\(week.sessions.count) SESIONES")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.accentYellow)

                    Spacer(minLength: 4.0)

                    Text("\(week.restDays) DÍAS SIN SESIÓN")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                }

                ForEach(week.sessions) { (session: GeneratedSession) in
                    sessionBlock(session)

                    if session.index < week.sessions.count - 1 {
                        Rectangle()
                            .fill(EndfieldPalette.borderSubtle)
                            .frame(height: 1.0)
                    }
                }

                Text("\(week.totalExercises) ejercicios · \(totalSets) series en total")
                    .font(EndfieldFont.mono(8.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sessionBlock(_ session: GeneratedSession) -> some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                Text(String(format: "SESIÓN %02d", session.index + 1))
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.0)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize()

                Text(session.name.uppercased())
                    .font(EndfieldFont.mono(11.0, weight: .heavy))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4.0)

                if !session.variantSuffix.isEmpty {
                    TacticalTagBadge(text: "VAR \(session.variantSuffix)", tint: EndfieldPalette.accentCyan)
                }
            }

            ForEach(session.exercises) { (exercise: GeneratedExercise) in
                HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                    Text(exercise.isCompound ? "C" : "A")
                        .font(EndfieldFont.label(7.0))
                        .foregroundStyle(exercise.isCompound ? EndfieldPalette.accentCyan : EndfieldPalette.textSecondary)
                        .frame(width: 10.0, alignment: .leading)

                    Text(exercise.name)
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 6.0)

                    Text("\(exercise.sets)×\(exercise.repsLabel) · \(exercise.restSeconds)S")
                        .font(EndfieldFont.mono(9.0, weight: .semibold))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Avisos

    private func noticesPanel(_ week: GeneratedWeek) -> some View {
        TacticalPanel(code: "AUT.04", title: "Recuperación y distribución", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 10.0) {
                if week.notices.isEmpty {
                    Text("No hay grupos principales repetidos ni solapamientos entre sesiones consecutivas en esta semana.")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(week.notices) { (notice: RoutineNotice) in
                        RoutineNoticeBanner(notice: notice)
                    }
                }

                if week.hasPartialMuscleAnalysis {
                    Text("ANÁLISIS PARCIAL")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.accentYellow)
                }

                ForEach(Array(week.limitations.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                    Text("· \(item.element)")
                        .font(EndfieldFont.mono(8.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Frecuencia y solapamiento son indicadores descriptivos: no estiman fatiga fisiológica ni tiempos de recuperación.")
                    .font(EndfieldFont.label(7.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Footer

    private var footer: AnyView {
        return AnyView(
            OnboardingPrimaryFooter(
                title: "CONTINUAR AL RESUMEN",
                isEnabled: viewModel.canContinueFromAutomatic
            ) {
                onContinue()
            }
        )
    }
}
