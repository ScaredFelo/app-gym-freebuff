import SwiftUI

/// Constructor asistido de la semana: siete casillas independientes, sin
/// asignaciones automáticas iniciales. La vista solo presenta el estado del
/// ViewModel y abre el selector de rutinas.
struct AssistedSplitConfigurationView: View {
    let chrome: OnboardingChrome
    @ObservedObject var viewModel: AssistedSplitViewModel
    let onContinue: () -> Void

    @State private var editingWeekday: AssistedWeekday?

    var body: some View {
        OnboardingStepLayout(
            chrome: chrome,
            title: "Construir mi semana",
            subtitle: "Asigna una rutina o descanso a cada día. Los días vacíos no son días de descanso y no se pueden confirmar.",
            footer: footer
        ) {
            weekPanel
            validationPanel

            if let message = viewModel.generationError {
                TacticalPanel(code: "ASD.E1", title: "No se puede generar la semana", contentPadding: 12.0) {
                    Text(message)
                        .font(EndfieldFont.mono(10.0))
                        .foregroundStyle(EndfieldPalette.accentRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            OnboardingInfoNote(
                text: "El constructor usa las diez rutinas base del catálogo. Las variantes A/B/C se asignan automáticamente según las apariciones y la disponibilidad real; nunca se inventan ni se duplican. Los avisos de recuperación y frecuencia son informativos."
            )
        }
        .sheet(item: $editingWeekday) { (weekday: AssistedWeekday) in
            AssistedRoutinePickerView(
                weekday: weekday,
                current: viewModel.selection(for: weekday)
            ) { (selection: AssistedDaySelection) in
                switch selection {
                case .unassigned:
                    viewModel.clear(weekday)
                case .rest:
                    viewModel.selectRest(for: weekday)
                case .routine(let routine):
                    viewModel.selectRoutine(routine, for: weekday)
                }
            }
        }
    }

    // MARK: - Semana

    private var weekPanel: some View {
        TacticalPanel(code: "ASD.01", title: "Distribución semanal", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                HStack(alignment: .firstTextBaseline, spacing: 8.0) {
                    Text("\(viewModel.configuredCount)/7 DÍAS CONFIGURADOS")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.accentYellow)

                    Spacer(minLength: 4.0)

                    Text("\(viewModel.restDayCount) DESCANSO")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.0)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                }

                ForEach(viewModel.days) { (day: AssistedDaySlot) in
                    dayRow(day)
                }
            }
        }
    }

    private func dayRow(_ day: AssistedDaySlot) -> some View {
        let isConfigured: Bool = day.selection.isConfigured
        let tint: Color = day.selection.isRest
            ? EndfieldPalette.accentCyan
            : (isConfigured ? EndfieldPalette.accentYellow : EndfieldPalette.accentRed)

        return Button {
            OnboardingHaptics.selection()
            editingWeekday = day.weekday
        } label: {
            HStack(alignment: .center, spacing: 10.0) {
                Text(day.weekday.shortCode)
                    .font(EndfieldFont.mono(12.0, weight: .heavy))
                    .foregroundStyle(tint)
                    .frame(width: 22.0, alignment: .leading)

                VStack(alignment: .leading, spacing: 3.0) {
                    Text(day.weekday.displayName)
                        .font(EndfieldFont.label(8.0))
                        .tracking(0.9)
                        .foregroundStyle(EndfieldPalette.textSecondary)

                    Text(day.selection.label.uppercased())
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .foregroundStyle(isConfigured ? EndfieldPalette.textPrimary : EndfieldPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 6.0)

                if day.selection.isRest {
                    Image(systemName: "moon.zzz.fill")
                        .font(EndfieldFont.mono(12.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.accentCyan)
                        .fixedSize()
                } else if !isConfigured {
                    Image(systemName: "questionmark.square.dashed")
                        .font(EndfieldFont.mono(12.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.accentRed)
                        .fixedSize()
                } else if let label = day.variantLabel {
                    TacticalTagBadge(text: label, tint: EndfieldPalette.accentCyan)
                } else {
                    Text("SIN VARIANTE")
                        .font(EndfieldFont.label(7.0))
                        .tracking(0.8)
                        .foregroundStyle(EndfieldPalette.accentRed)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10.0)
            .padding(.vertical, 9.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.7)
                    .fill(EndfieldPalette.bgElevated)
            )
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.7)
                    .stroke(tint.opacity(isConfigured ? 0.45 : 0.35), lineWidth: 1.0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: day))
        .accessibilityHint("Abre el selector de rutina o descanso")
    }

    private func accessibilityLabel(for day: AssistedDaySlot) -> String {
        if !day.selection.isConfigured {
            return "\(day.weekday.displayName): sin configurar"
        }
        if day.selection.isRest {
            return "\(day.weekday.displayName): descanso"
        }
        if let label = day.variantLabel {
            return "\(day.weekday.displayName): \(day.selection.label), \(label)"
        }
        return "\(day.weekday.displayName): \(day.selection.label), sin variante disponible"
    }

    // MARK: - Validación

    private var validationPanel: some View {
        TacticalPanel(code: "ASD.02", title: "Validación de la semana", contentPadding: 12.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                if !viewModel.missingWeekdays.isEmpty {
                    Text("Faltan por configurar: \(viewModel.missingWeekdays.map(\.displayName).joined(separator: ", ")).")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.accentRed)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(viewModel.validationErrors, id: \.self) { (message: String) in
                    Text("· \(message)")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.accentRed)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.canContinue {
                    Text("Los siete días están configurados y las variantes necesarias existen en el catálogo.")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.accentCyan)
                        .fixedSize(horizontal: false, vertical: true)
                } else if viewModel.missingWeekdays.isEmpty && viewModel.validationErrors.isEmpty {
                    Text("No se ha podido leer la disponibilidad de variantes del catálogo.")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.accentRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: AnyView {
        return AnyView(
            OnboardingPrimaryFooter(
                title: "CONTINUAR AL RESUMEN",
                isEnabled: viewModel.canContinue
            ) {
                guard viewModel.buildWeek() else { return }
                OnboardingHaptics.confirmation()
                onContinue()
            }
        )
    }
}

// MARK: - Selector de rutina

/// Selector de una casilla. Incluye explícitamente «Descanso» y «Sin
/// configurar» para que un día vacío nunca se confunda con descanso.
struct AssistedRoutinePickerView: View {
    let weekday: AssistedWeekday
    let current: AssistedDaySelection
    let onSelect: (AssistedDaySelection) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10.0) {
                    Text(weekday.displayName)
                        .font(EndfieldFont.mono(18.0, weight: .heavy))
                        .foregroundStyle(EndfieldPalette.textPrimary)

                    selectionRow(
                        code: "—",
                        title: "Sin configurar",
                        subtitle: "El día queda pendiente y no se puede confirmar.",
                        selection: .unassigned
                    )

                    selectionRow(
                        code: "REST",
                        title: "Descanso",
                        subtitle: "No se genera ninguna sesión para este día.",
                        selection: .rest
                    )

                    Text("RUTINAS BASE")
                        .font(EndfieldFont.label(8.0))
                        .tracking(1.2)
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .padding(.top, 6.0)

                    ForEach(CatalogRoutine.allCases) { (routine: CatalogRoutine) in
                        selectionRow(
                            code: routineCode(routine),
                            title: routine.displayName,
                            subtitle: "Plantilla del catálogo de AppGym.",
                            selection: .routine(routine)
                        )
                    }
                }
                .padding(16.0)
            }
            .background(TechnicalGridBackground())
            .navigationTitle("Seleccionar día")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundStyle(EndfieldPalette.accentYellow)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func selectionRow(
        code: String,
        title: String,
        subtitle: String,
        selection: AssistedDaySelection
    ) -> some View {
        let isSelected: Bool = current == selection
        let tint: Color = isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.textSecondary

        return Button {
            OnboardingHaptics.selection()
            onSelect(selection)
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: 10.0) {
                Text(code)
                    .font(EndfieldFont.label(8.0))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                    .frame(width: 42.0, alignment: .leading)

                VStack(alignment: .leading, spacing: 3.0) {
                    Text(title.uppercased())
                        .font(EndfieldFont.mono(11.0, weight: .bold))
                        .foregroundStyle(isSelected ? EndfieldPalette.accentYellow : EndfieldPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(subtitle)
                        .font(EndfieldFont.mono(8.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6.0)

                if isSelected {
                    Image(systemName: "checkmark.square.fill")
                        .font(EndfieldFont.mono(13.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.accentYellow)
                }
            }
            .padding(10.0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.7)
                    .fill(isSelected ? EndfieldPalette.bgElevated : EndfieldPalette.bgPanel)
            )
            .overlay {
                ChamferedRectangle(cut: EndfieldMetrics.tightCut * 0.7)
                    .stroke(isSelected ? EndfieldPalette.accentYellow.opacity(0.7) : EndfieldPalette.borderSubtle, lineWidth: 1.0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }

    private func routineCode(_ routine: CatalogRoutine) -> String {
        switch routine {
        case .arms: return "ARM"
        case .chestBack: return "CHB"
        case .fullBody: return "FB"
        case .hamstrings: return "HAM"
        case .legs: return "LEG"
        case .lower: return "LOW"
        case .pull: return "PUL"
        case .push: return "PSH"
        case .quads: return "QUA"
        case .upper: return "UPP"
        }
    }
}
