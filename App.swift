import SwiftUI
import SwiftData

// MARK: - Esquema versionado

/// Versión 1 del esquema de datos.
///
/// Es el ancla para futuras migraciones: cualquier cambio de modelo debe
/// añadir una `AppSchemaV2` y su `MigrationStage` aquí, en lugar de dejar que
/// SwiftData intente una migración implícita y acabe bloqueando el arranque.
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

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - Contenedor tolerante a fallos

/// Crea el `ModelContainer` sin `fatalError`.
///
/// Si el store no se puede abrir (archivo corrupto, disco lleno, migración
/// imposible) se aparta a una carpeta con fecha y se reintenta con uno nuevo;
/// si tampoco así, se abre en memoria para que la app siga siendo utilizable y
/// el usuario pueda exportar su copia de seguridad.
enum StoreBootstrap {
    struct Outcome {
        let container: ModelContainer
        /// Mensaje para avisar de que se ha recuperado de un fallo.
        let recoveryMessage: String?
    }

    static func makeContainer() -> Outcome {
        let schema = Schema(versionedSchema: AppSchemaV1.self)

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: false)]
            )
            return Outcome(container: container, recoveryMessage: nil)
        } catch {
            print("[Store] No se pudo abrir la base de datos: \(error)")
        }

        if let quarantined = quarantineExistingStore() {
            do {
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: AppMigrationPlan.self,
                    configurations: [ModelConfiguration(isStoredInMemoryOnly: false)]
                )
                return Outcome(
                    container: container,
                    recoveryMessage: "No se pudo abrir la base de datos anterior. Se ha guardado una copia en «\(quarantined.lastPathComponent)» y se ha empezado con una base nueva."
                )
            } catch {
                print("[Store] La base de datos nueva tampoco se pudo abrir: \(error)")
            }
        }

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
            return Outcome(
                container: container,
                recoveryMessage: "La base de datos no está disponible. La app funciona en modo temporal: lo que registres ahora no se guardará al cerrar."
            )
        } catch {
            // Sin almacenamiento ni en memoria no hay app posible.
            fatalError("SwiftData no puede inicializarse ni en memoria: \(error)")
        }
    }

    /// Mueve el store y sus archivos auxiliares a una carpeta con fecha para no
    /// destruirlos nunca. Devuelve la carpeta si se movió algo.
    private static func quarantineExistingStore() -> URL? {
        let fileManager = FileManager.default
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let directory = support
            .appendingPathComponent("AppGym", isDirectory: true)
            .appendingPathComponent("Store-corrupto-\(stamp)", isDirectory: true)

        let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
        var movedSomething = false

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            for name in storeFiles {
                let source = support.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.moveItem(at: source, to: directory.appendingPathComponent(name))
                movedSomething = true
            }
        } catch {
            print("[Store] No se pudo apartar el store dañado: \(error)")
            return nil
        }

        return movedSomething ? directory : nil
    }
}

// MARK: - App

@main
struct AppGymApp: App {
    let container: ModelContainer
    private let recoveryMessage: String?

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bpmManager = BPMManager.shared
    @State private var didRunLaunchTasks = false
    @State private var bannerMessage: String?

    init() {
        let outcome = StoreBootstrap.makeContainer()
        container = outcome.container
        recoveryMessage = outcome.recoveryMessage
    }

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                MainTabView()
                    .environmentObject(bpmManager)

                if let bannerMessage {
                    StoreRecoveryBanner(message: bannerMessage) {
                        self.bannerMessage = nil
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear(perform: runLaunchTasksOnce)
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
        .modelContainer(container)
    }

    /// Tareas de arranque. Se ejecutan una sola vez por proceso: `.onAppear`
    /// puede dispararse varias veces al volver de una pantalla completa.
    private func runLaunchTasksOnce() {
        guard !didRunLaunchTasks else { return }
        didRunLaunchTasks = true

        if let recoveryMessage {
            bannerMessage = recoveryMessage
        }

        let context = container.mainContext
        MockDataGenerator.seedIfNeeded(context: context)
        ExerciseKnowledgeService.migrateExistingExercisesIfNeeded(context: context)
        ExerciseKnowledgeService.alignStrapsWithKnowledgeIfNeeded(context: context)
        MockDataGenerator.seedMissingCatalogExercisesIfNeeded(context: context)
        MockDataGenerator.seedCardioAndIsometricExercisesIfNeeded(context: context)
        ExerciseDuplicateService.mergeIfNeeded(context: context)
        MockDataGenerator.applyRoutineTableUpdateIfNeeded(context: context)

        // Sesiones que quedaron abiertas tras un cierre inesperado. La que se
        // va a reanudar se conserva intacta.
        WorkoutSessionCleanup.closeStaleSessions(
            context: context,
            keeping: ActiveWorkoutStateStore.load()?.activeWorkoutID
        )

        WidgetStreakStore.refresh(modelContext: context)
    }
}

// MARK: - Aviso de recuperación

private struct StoreRecoveryBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10.0) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12.0, weight: .bold, design: .monospaced))
                .foregroundStyle(EndfieldPalette.accentYellow)
                .fixedSize()

            Text(message)
                .font(.system(size: 10.0, weight: .medium, design: .monospaced))
                .foregroundStyle(EndfieldPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4.0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.0, weight: .bold, design: .monospaced))
                    .foregroundStyle(EndfieldPalette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ocultar aviso")
        }
        .padding(12.0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EndfieldPalette.bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 10.0, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10.0, style: .continuous)
                .stroke(EndfieldPalette.borderSubtle, lineWidth: 1.0)
        }
        .padding(.horizontal, 16.0)
        .padding(.top, 8.0)
        .shadow(color: Color.black.opacity(0.35), radius: 12.0, y: 6.0)
    }
}
