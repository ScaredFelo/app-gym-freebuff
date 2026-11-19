import SwiftUI
import SwiftData

// MARK: - Esquema versionado

/// Versión 1 del esquema de datos.
///
/// Es el ancla para futuras migraciones: cualquier cambio de modelo debe
/// añadir la siguiente `AppSchemaVN` y su `MigrationStage` aquí, en lugar de
/// dejar que SwiftData intente una migración implícita y bloquee el arranque.
enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            Routine.self,
            RoutineExercise.self,
            WorkoutSession.self,
            WorkoutSetLog.self
        ]
    }
}

/// Versión 2: añade `Routine.isArchived` para archivar las rutinas que dejan de
/// estar activas sin borrarlas ni tocar el historial de sesiones.
enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            Routine.self,
            RoutineExercise.self,
            WorkoutSession.self,
            WorkoutSetLog.self
        ]
    }
}

/// Versión 3: conserva el texto muscular original del catálogo en cada
/// ejercicio generado, para no perder tokens sin equivalencia exacta.
enum AppSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            Routine.self,
            RoutineExercise.self,
            WorkoutSession.self,
            WorkoutSetLog.self
        ]
    }
}

/// Versión 4: añade la procedencia de la rutina (`automatic` / `manual`) para
/// archivar solo las rutinas automáticas al aplicar un plan nuevo. El campo es
/// opcional, así que las filas antiguas quedan con `nil` y se interpretan como
/// manuales.
enum AppSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            Routine.self,
            RoutineExercise.self,
            WorkoutSession.self,
            WorkoutSetLog.self
        ]
    }
}

/// Versión 5: añade la semana del constructor asistido. Se guarda como un
/// registro con los siete días serializados para no crear relaciones que
/// puedan afectar a las rutinas personales.
enum AppSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Exercise.self,
            Routine.self,
            RoutineExercise.self,
            WorkoutSession.self,
            WorkoutSetLog.self,
            AssistedWeekPlan.self
        ]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self, AppSchemaV4.self, AppSchemaV5.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: AppSchemaV1.self, toVersion: AppSchemaV2.self),
            .lightweight(fromVersion: AppSchemaV2.self, toVersion: AppSchemaV3.self),
            .lightweight(fromVersion: AppSchemaV3.self, toVersion: AppSchemaV4.self),
            .lightweight(fromVersion: AppSchemaV4.self, toVersion: AppSchemaV5.self)
        ]
    }
}

// MARK: - Contenedor tolerante a fallos

/// Abre el contenedor sin apartar, borrar ni sustituir nunca el store original.
///
/// Si SwiftData no puede abrirlo o migrarlo, la app queda en un estado de
/// recuperación bloqueante: no se crea una base vacía, no se abre en memoria y
/// no se ejecutan las tareas de arranque. Los archivos originales permanecen en
/// su sitio para que el usuario pueda reintentar o recuperarlos explícitamente.
enum StoreBootstrap {
    struct Failure: Equatable {
        let message: String
        let technicalDetails: String
        let storeWasPresent: Bool
    }

    struct Outcome {
        let container: ModelContainer?
        let failure: Failure?

        var isReady: Bool {
            return container != nil
        }
    }

    static let lastErrorKey: String = "AppGym.StoreBootstrap.lastOpenError"

    /// `storeURL` existe para las pruebas con un store temporal. En producción
    /// se usa la configuración por defecto de SwiftData.
    static func makeContainer(storeURL: URL? = nil) -> Outcome {
        let schema = Schema(versionedSchema: AppSchemaV5.self)

        do {
            let configuration: ModelConfiguration
            if let storeURL {
                configuration = ModelConfiguration(url: storeURL)
            } else {
                configuration = ModelConfiguration(isStoredInMemoryOnly: false)
            }

            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [configuration]
            )
            return Outcome(container: container, failure: nil)
        } catch {
            let technicalDetails: String = String(describing: error)
            let existed: Bool = storeExists(at: storeURL)
            let message: String = existed
                ? "No se ha podido abrir la base de datos. Tus datos no se han borrado ni se ha creado una base vacía en su lugar."
                : "No se ha podido crear la base de datos. No se ha abierto una base temporal vacía."
            let failure: Failure = Failure(
                message: message,
                technicalDetails: technicalDetails,
                storeWasPresent: existed
            )

            let logLine: String = "\(ISO8601DateFormatter().string(from: Date())) \(technicalDetails)"
            UserDefaults.standard.set(logLine, forKey: lastErrorKey)
            print("[Store] \(message) \(technicalDetails)")

            return Outcome(container: nil, failure: failure)
        }
    }

    static var lastError: String? {
        return UserDefaults.standard.string(forKey: lastErrorKey)
    }

    static func defaultStoreURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("default.store")
    }

    static func storeExists(at customURL: URL? = nil) -> Bool {
        guard let url: URL = customURL ?? defaultStoreURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Store principal y auxiliares. Solo se consultan para diagnóstico y para
    /// mostrar que siguen en disco; nunca se mueven ni se eliminan.
    static func existingStoreFiles(at customURL: URL? = nil) -> [URL] {
        guard let url: URL = customURL ?? defaultStoreURL() else { return [] }
        let fileManager = FileManager.default
        let candidates: [URL] = [
            url,
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal")
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }
}

// MARK: - App

@main
struct AppGymApp: App {
    @State private var storeOutcome: StoreBootstrap.Outcome

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bpmManager = BPMManager.shared
    @State private var didRunLaunchTasks = false
    /// Se lee al arrancar; el flujo de onboarding lo pone a `true` solo cuando
    /// el guardado final ha terminado correctamente.
    @State private var isOnboardingCompleted: Bool = UserSettingsManager.isOnboardingCompleted

    init() {
        _storeOutcome = State(initialValue: StoreBootstrap.makeContainer())
    }

    var body: some Scene {
        WindowGroup {
            if let container = storeOutcome.container {
                appContent(container: container)
                    .modelContainer(container)
            } else {
                StoreRecoveryView(failure: storeOutcome.failure) {
                    didRunLaunchTasks = false
                    storeOutcome = StoreBootstrap.makeContainer()
                }
            }
        }
    }

    @ViewBuilder
    private func appContent(container: ModelContainer) -> some View {
        ZStack(alignment: .top) {
            Group {
                if isOnboardingCompleted {
                    MainTabView()
                } else {
                    OnboardingFlowView(context: .initialSetup) {
                        isOnboardingCompleted = true
                    }
                }
            }
            .environmentObject(bpmManager)
        }
        .onAppear {
            runLaunchTasksOnce(container: container)
        }
        .onChange(of: scenePhase) { (_, newPhase: ScenePhase) in
            // Al volver a la app la racha se calculó con las sesiones de la
            // última vez. El arranque también pasa por `.active`, y ahí ya
            // ha recalculado `runLaunchTasksOnce`: si el snapshot es de
            // hace un instante, no se pide otra recarga.
            guard newPhase == .active,
                  Date().timeIntervalSince(WidgetStreakStore.load().lastUpdated) > 30.0 else { return }
            WidgetStreakStore.refresh(modelContext: container.mainContext)
        }
    }

    /// Tareas de arranque. Se ejecutan una sola vez por proceso: `.onAppear`
    /// puede dispararse varias veces al volver de una pantalla completa.
    private func runLaunchTasksOnce(container: ModelContainer) {
        guard !didRunLaunchTasks else { return }
        didRunLaunchTasks = true

        let context = container.mainContext
        MockDataGenerator.seedIfNeeded(context: context)
        ExerciseKnowledgeService.migrateExistingExercisesIfNeeded(context: context)
        ExerciseKnowledgeService.alignStrapsWithKnowledgeIfNeeded(context: context)
        MockDataGenerator.seedMissingCatalogExercisesIfNeeded(context: context)
        MockDataGenerator.seedCardioAndIsometricExercisesIfNeeded(context: context)
        ExerciseDuplicateService.mergeIfNeeded(context: context)
        MockDataGenerator.applyRoutineTableUpdateIfNeeded(context: context)
        MockDataGenerator.classifyLegacyRoutineSourcesIfNeeded(context: context)
        // Va después de la tabla base para que sus definiciones antiguas no
        // vuelvan a pisar la clasificación nueva.
        MockDataGenerator.alignCatalogEquipmentIfNeeded(context: context)

        // Sesiones que quedaron abiertas tras un cierre inesperado. La que se
        // va a reanudar se conserva intacta.
        WorkoutSessionCleanup.closeStaleSessions(
            context: context,
            keeping: ActiveWorkoutStateStore.load()?.activeWorkoutID
        )

        WidgetStreakStore.refresh(modelContext: context)
    }
}

// MARK: - Recuperación bloqueante

/// Pantalla sin acceso a SwiftData. No permite crear datos nuevos: solo explica
/// el problema y reintenta abrir el mismo store. Así un fallo de migración no
/// puede confundirse con una instalación nueva.
private struct StoreRecoveryView: View {
    let failure: StoreBootstrap.Failure?
    let onRetry: () -> Void

    @State private var showsTechnicalDetails = false

    private var preservedFiles: [URL] {
        return StoreBootstrap.existingStoreFiles()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16.0) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 30.0, weight: .semibold))
                        .foregroundStyle(EndfieldPalette.accentYellow)

                    Text("BASE DE DATOS NO DISPONIBLE")
                        .font(EndfieldFont.mono(17.0, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(EndfieldPalette.textPrimary)

                    Text(failure?.message ?? "No se ha podido abrir la base de datos. No se ha abierto una base vacía.")
                        .font(EndfieldFont.mono(11.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Los archivos originales se conservan en el dispositivo. No se han movido, borrado ni sustituido. No sigas usando una base nueva: reintenta la apertura o recupera una copia de seguridad cuando el almacenamiento vuelva a estar disponible.")
                        .font(EndfieldFont.mono(11.0))
                        .foregroundStyle(EndfieldPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(preservedFiles.count) archivo(s) de almacenamiento conservados")
                        .font(EndfieldFont.mono(9.0, weight: .bold))
                        .foregroundStyle(EndfieldPalette.accentCyan)

                    if let details = failure?.technicalDetails, !details.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsTechnicalDetails.toggle()
                            }
                        } label: {
                            HStack(spacing: 6.0) {
                                Image(systemName: showsTechnicalDetails ? "chevron.down" : "chevron.right")
                                Text("DETALLE TÉCNICO")
                            }
                            .font(EndfieldFont.mono(10.0, weight: .bold))
                            .foregroundStyle(EndfieldPalette.textSecondary)
                        }
                        .buttonStyle(.plain)

                        if showsTechnicalDetails {
                            Text(details)
                                .font(.system(size: 9.0, weight: .regular, design: .monospaced))
                                .foregroundStyle(EndfieldPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(10.0)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(EndfieldPalette.bgPanel)
                                .clipShape(RoundedRectangle(cornerRadius: 8.0, style: .continuous))
                        }
                    }

                    Button(action: onRetry) {
                        Text("REINTENTAR APERTURA")
                            .font(EndfieldFont.mono(11.0, weight: .heavy))
                            .tracking(1.0)
                            .foregroundStyle(EndfieldPalette.bgPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12.0)
                            .background(EndfieldPalette.accentYellow)
                            .clipShape(RoundedRectangle(cornerRadius: 6.0, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Text("No desinstales la app ni borres sus datos antes de recuperar una copia. La recuperación debe ser explícita y reversible.")
                        .font(EndfieldFont.mono(9.0))
                        .foregroundStyle(EndfieldPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24.0)
            }
        }
    }
}
