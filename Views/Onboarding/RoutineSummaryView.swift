import SwiftUI

/// Resumen previo al guardado. Se adapta a la modalidad elegida y es el único
/// punto donde se confirma la operación completa.
struct RoutineSummaryView: View {
    let chrome: OnboardingChrome
    let context: RoutineFlowContext
    let sections: [RoutineSummarySection]
    var notices: [RoutineNotice] = []
    let isSaving: Bool
    let onConfirm: () -> Void

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "Resumen de la configuración",
            subtitle: "Revisa lo que se va a guardar. Puedes volver atrás para cambiar cualquier elección.",
            footer: footer
        ) {
            if sections.isEmpty {
                TacticalPanel(code: "SUM.00", title: "Sin configuración", contentPadding: 12.0) {
                    Text("Vuelve a la selección de modalidad para elegir cómo organizar tu entrenamiento.")
                        .font(EndfieldFont.mono(10.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(sections) { (section: RoutineSummarySection) in
                    sectionPanel(section)
                }
            }

            if !notices.isEmpty {
                VStack(spacing: 10.0) {
                    ForEach(notices) { (notice: RoutineNotice) in
                        RoutineNoticeBanner(notice: notice)
                    }
                }
            }

            OnboardingInfoNote(
                text: context == .changeRoutine
                    ? "Las rutinas generadas anteriores se archivan, no se borran. Las manuales y las cinco rutinas personales se conservan, junto con sesiones, pesos, series, repeticiones y récords."
                    : "Nada se guarda hasta que pulses «Confirmar y empezar». Si el guardado falla, tus datos actuales se mantienen como están."
            )
        }
    }

    // MARK: - Secciones

    private func sectionPanel(_ section: RoutineSummarySection) -> some View {
        TacticalPanel(code: section.code, title: section.title, contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                ForEach(section.items.indices, id: \.self) { (index: Int) in
                    let item: RoutineSummaryItem = section.items[index]

                    if index > 0 {
                        Rectangle()
                            .fill(EndfieldPalette.borderSubtle)
                            .frame(height: 1.0)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                        Text(item.label.uppercased())
                            .font(EndfieldFont.mono(9.0))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)

                        Spacer(minLength: 4.0)

                        Text(item.value.uppercased())
                            .font(EndfieldFont.mono(11.0, weight: .heavy))
                            .foregroundStyle(EndfieldPalette.accentYellow)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let note = section.note {
                    Text(note)
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: AnyView {
        return AnyView(
            OnboardingPrimaryFooter(
                title: isSaving ? "GUARDANDO..." : "CONFIRMAR Y EMPEZAR",
                isEnabled: !sections.isEmpty,
                isLoading: isSaving,
                action: onConfirm
            )
        )
    }
}

// MARK: - Resumen de la semana asistida

/// Resumen específico del constructor de siete días. Presenta la distribución
/// completa, las sesiones con sus ejercicios y los dos análisis por separado.
struct AssistedRoutineSummaryView: View {
    let chrome: OnboardingChrome
    let context: RoutineFlowContext
    @ObservedObject var viewModel: AssistedSplitViewModel
    let isSaving: Bool
    let onEdit: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "Resumen de la semana",
            subtitle: "Revisa los siete días, las variantes asignadas y las sesiones antes de confirmar.",
            footer: footer
        ) {
            if let week = viewModel.generatedWeek {
                distributionPanel
                trainingSummaryPanel(week)
                sessionsPanel(week)
                recoveryPanel(week)
                frequencyPanel(week)
                partialAnalysisPanel(week)

                OnboardingInfoNote(
                    text: context == .changeRoutine
                        ? "Al confirmar se archivan las rutinas generadas anteriores, nunca las manuales ni tus cinco rutinas personales. Su historial, sus pesos y sus récords se conservan intactos."
                        : "Nada se guarda hasta que pulses «Confirmar semana». Si el guardado falla, la operación se deshace completa y tus datos actuales se mantienen."
                )
            } else {
                TacticalPanel(code: "ASD.S0", title: "Semana sin generar", contentPadding: 12.0) {
                    Text("Vuelve al constructor, completa los siete días y pulsa «Continuar al resumen».")
                        .font(EndfieldFont.mono(10.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Distribución

    private var distributionPanel: some View {
        TacticalPanel(code: "ASD.S1", title: "Distribución semanal", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 7.0) {
                ForEach(viewModel.days) { (day: AssistedDaySlot) in
                    HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                        Text(day.weekday.shortCode)
                            .font(EndfieldFont.label(8.0))
                            .tracking(0.8)
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .frame(width: 16.0, alignment: .leading)

                        Text(day.weekday.displayName)
                            .font(EndfieldFont.label(8.0))
                            .tracking(0.8)
                            .foregroundStyle(EndfieldPalette.textSecondary)
                            .frame(width: 78.0, alignment: .leading)

                        Text(day.selection.label.uppercased())
                            .font(EndfieldFont.mono(10.0, weight: .bold))
                            .foregroundStyle(day.selection.isRest ? EndfieldPalette.accentCyan : EndfieldPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Spacer(minLength: 4.0)

                        if let label = day.variantLabel, !day.selection.isRest {
                            TacticalTagBadge(text: label, tint: EndfieldPalette.accentCyan)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func trainingSummaryPanel(_ week: GeneratedWeek) -> some View {
        let routines: [String] = unique(week.sessions.map { (session: GeneratedSession) -> String in session.routine.displayName })
        let variants: [String] = week.sessions.compactMap { (session: GeneratedSession) -> String? in
            session.variantSuffix.isEmpty ? nil : session.variantSuffix
        }
        let variantsText: String = week.sessions.isEmpty
            ? "—"
            : (variants.isEmpty ? "BASE" : variants.map { "VAR \($0)" }.joined(separator: " / "))

        return TacticalPanel(code: "ASD.S2", title: "Resumen de entrenamiento", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 7.0) {
                summaryRow(label: "Días de entrenamiento", value: "\(week.sessions.count)")
                summaryRow(label: "Días de descanso", value: "\(viewModel.restDayCount)")
                summaryRow(label: "Sesiones generadas", value: "\(week.sessions.count)")
                summaryRow(label: "Rutinas utilizadas", value: routines.isEmpty ? "—" : routines.joined(separator: " / "))
                summaryRow(label: "Variantes asignadas", value: variantsText)
                summaryRow(label: "Ejercicios", value: "\(week.totalExercises)")
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8.0) {
            Text(label.uppercased())
                .font(EndfieldFont.mono(9.0))
                .foregroundStyle(EndfieldPalette.textSecondary)

            Spacer(minLength: 6.0)

            Text(value.uppercased())
                .font(EndfieldFont.mono(10.0, weight: .heavy))
                .foregroundStyle(EndfieldPalette.accentYellow)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sesiones

    private func sessionsPanel(_ week: GeneratedWeek) -> some View {
        TacticalPanel(code: "ASD.S3", title: "Detalle de las sesiones", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 12.0) {
                if viewModel.sessionEntries.isEmpty {
                    Text("No hay sesiones: los siete días están marcados como descanso.")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(viewModel.sessionEntries) { (entry: AssistedSessionEntry) in
                        sessionBlock(entry)

                        if entry.id != (viewModel.sessionEntries.last?.id ?? "") {
                            Rectangle()
                                .fill(EndfieldPalette.borderSubtle)
                                .frame(height: 1.0)
                        }
                    }
                }

                Text("\(week.totalExercises) ejercicios en total")
                    .font(EndfieldFont.mono(8.0))
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }
        }
    }

    private func sessionBlock(_ entry: AssistedSessionEntry) -> some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                Text(entry.weekday.displayName)
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary)
                    .fixedSize()

                Text(entry.session.name.uppercased())
                    .font(EndfieldFont.mono(11.0, weight: .heavy))
                    .foregroundStyle(EndfieldPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 4.0)

                if !entry.session.variantSuffix.isEmpty {
                    TacticalTagBadge(text: "VAR \(entry.session.variantSuffix)", tint: EndfieldPalette.accentCyan)
                }
            }

            ForEach(entry.session.exercises) { (exercise: GeneratedExercise) in
                VStack(alignment: .leading, spacing: 2.0) {
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

                    Text(exercise.equipment.rawValue.uppercased())
                        .font(EndfieldFont.label(7.0))
                        .tracking(0.6)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .padding(.leading, 18.0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Análisis

    private func recoveryPanel(_ week: GeneratedWeek) -> some View {
        analysisPanel(
            code: "ASD.S4",
            title: "Recuperación y solapamiento",
            notices: week.recoveryNotices,
            emptyText: "No hay sesiones en días consecutivos que compartan grupos musculares."
        )
    }

    private func frequencyPanel(_ week: GeneratedWeek) -> some View {
        analysisPanel(
            code: "ASD.S5",
            title: "Frecuencia y distribución",
            notices: week.fatigueNotices,
            emptyText: "No hay solapamientos musculares entre las sesiones de esta semana."
        )
    }

    private func analysisPanel(code: String, title: String, notices: [RoutineNotice], emptyText: String) -> some View {
        TacticalPanel(code: code, title: title, contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 10.0) {
                if notices.isEmpty {
                    Text(emptyText)
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(notices) { (notice: RoutineNotice) in
                        RoutineNoticeBanner(notice: notice)
                    }
                }

                Text("Indicadores descriptivos: no estiman fatiga fisiológica ni tiempos de recuperación. No bloquean la confirmación.")
                    .font(EndfieldFont.label(7.0))
                    .tracking(0.8)
                    .foregroundStyle(EndfieldPalette.textSecondary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func partialAnalysisPanel(_ week: GeneratedWeek) -> some View {
        TacticalPanel(code: "ASD.S6", title: "Análisis parcial", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 6.0) {
                Text(week.hasPartialMuscleAnalysis ? "ANÁLISIS PARCIAL" : "ANÁLISIS COMPLETO")
                    .font(EndfieldFont.label(8.0))
                    .tracking(1.0)
                    .foregroundStyle(week.hasPartialMuscleAnalysis ? EndfieldPalette.accentYellow : EndfieldPalette.accentCyan)

                ForEach(Array(week.limitations.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                    Text("· \(item.element)")
                        .font(EndfieldFont.mono(8.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Acciones

    private var footer: AnyView {
        return AnyView(
            VStack(spacing: 8.0) {
                Button {
                    OnboardingHaptics.selection()
                    onEdit()
                } label: {
                    Text("EDITAR DISTRIBUCIÓN")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(EndfieldSecondaryButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(isSaving)

                OnboardingPrimaryFooter(
                    title: isSaving ? "GUARDANDO..." : "CONFIRMAR SEMANA",
                    isEnabled: viewModel.generatedWeek != nil,
                    isLoading: isSaving,
                    action: onConfirm
                )
            }
        )
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: [String] = []
        for value in values where !seen.contains(value) {
            seen.append(value)
        }
        return seen
    }
}
