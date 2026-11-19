import XCTest
import Foundation

@testable import AppGym

final class VariantAndExerciseTests: XCTestCase {

    func testVariantAvailabilityComesFromTheCatalog() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()

        XCTAssertNotNil(catalog.variant(for: .push, occurrences: 1, suffix: ""))
        XCTAssertNotNil(catalog.variant(for: .arms, occurrences: 2, suffix: "A"))
        XCTAssertNotNil(catalog.variant(for: .arms, occurrences: 2, suffix: "B"))
        XCTAssertNil(catalog.variant(for: .arms, occurrences: 3, suffix: "C"))

        XCTAssertNotNil(catalog.variant(for: .legs, occurrences: 3, suffix: "C"))
        XCTAssertNotNil(catalog.variant(for: .upper, occurrences: 3, suffix: "C"))
        XCTAssertNotNil(catalog.variant(for: .fullBody, occurrences: 3, suffix: "C"))
    }

    func testVariantsAreAssignedChronologically() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 3,
            l: 3,
            u: 0,
            expression: "Legs x3",
            sessions: [.legs, .legs, .legs]
        )

        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)

        XCTAssertEqual(week.sessionNames, ["Legs A", "Legs B", "Legs C"])
        XCTAssertEqual(week.sessions.map { $0.variantSuffix }, ["A", "B", "C"])
    }

    func testMissingVariantStopsGeneration() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 3,
            l: 0,
            u: 3,
            expression: "Arms x3",
            sessions: [.arms, .arms, .arms]
        )

        XCTAssertThrowsError(try RoutineGenerator.generate(proposal: proposal, catalog: catalog))
    }

    func testTooManyOccurrencesStopsGeneration() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 4,
            l: 0,
            u: 4,
            expression: "Upper x4",
            sessions: [.upper, .upper, .upper, .upper]
        )

        XCTAssertThrowsError(try RoutineGenerator.generate(proposal: proposal, catalog: catalog))
    }

    func testExercisesAreCompoundFirstThenAlphabetical() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 1,
            l: 0,
            u: 1,
            expression: "Upper",
            sessions: [.upper]
        )

        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)
        let session: GeneratedSession = try XCTUnwrap(week.sessions.first)

        var isolationStarted: Bool = false
        for exercise in session.exercises {
            if exercise.isCompound && isolationStarted {
                XCTFail("Un ejercicio complejo aparece después de un aislamiento")
            }
            if !exercise.isCompound {
                isolationStarted = true
            }
        }

        let compoundNames: [String] = session.exercises
            .filter { $0.isCompound }
            .map { ExerciseRules.normalizedName($0.name) }
        XCTAssertEqual(compoundNames, compoundNames.sorted())

        let isolationNames: [String] = session.exercises
            .filter { !$0.isCompound }
            .map { ExerciseRules.normalizedName($0.name) }
        XCTAssertEqual(isolationNames, isolationNames.sorted())
    }

    func testCatalogSetsRepsAndRestArePreserved() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 1,
            l: 3,
            u: 0,
            expression: "Legs",
            sessions: [.legs]
        )

        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)
        let session: GeneratedSession = try XCTUnwrap(week.sessions.first)
        let variant: CatalogRoutineVariant = try XCTUnwrap(
            catalog.variant(for: .legs, occurrences: 1, suffix: "")
        )

        XCTAssertEqual(session.exercises.count, variant.exercises.count)

        for generated in session.exercises {
            guard let record = variant.exercises.first(where: { $0.name == generated.name }) else {
                XCTFail("El ejercicio \(generated.name) no pertenece a la variante")
                continue
            }

            XCTAssertEqual(generated.sets, record.sets)
            XCTAssertEqual(generated.repsMin, record.repsMin)
            XCTAssertEqual(generated.repsMax, record.repsMax)
            XCTAssertEqual(generated.restSeconds, record.restSeconds)
            XCTAssertEqual(generated.isCompound, record.isCompound)
            XCTAssertEqual(generated.requiresStraps, record.requiresStraps)
        }
    }

    func testEveryCatalogExerciseHasMappedPrimaryMuscle() throws {
        for record in try allCatalogRecords() {
            XCTAssertFalse(
                ExerciseRules.primaryMuscles(for: record).isEmpty,
                "Sin grupo muscular principal: \(record.name) (\(record.primaryRaw))"
            )
        }
    }

    func testEquipmentAssignmentsAreBackedByTheExerciseName() throws {
        for record in try allCatalogRecords() {
            let normalized: String = ExerciseRules.normalizedName(record.name)
            let equipment: EquipmentType = ExerciseRules.equipment(for: record.name)

            switch equipment {
            case .cable:
                XCTAssertTrue(
                    normalized.contains("polea") || normalized.contains("cable")
                        || normalized.contains("gironda") || normalized.contains("jalon")
                        || normalized.contains("face pull"),
                    "Polea sin evidencia en el nombre: \(record.name)"
                )
            case .plateLoadedMachine:
                XCTAssertTrue(normalized.contains("prensa"), "Disco sin «prensa» en el nombre: \(record.name)")
            case .selectorizedMachine:
                XCTAssertTrue(
                    normalized.contains("maquina") || normalized.contains("curl femoral"),
                    "Selectorizada sin evidencia en el nombre: \(record.name)"
                )
            case .smithMachine:
                XCTAssertTrue(normalized.contains("multipower"), "Multipower sin evidencia: \(record.name)")
            case .dumbbell:
                XCTAssertTrue(normalized.contains("mancuerna"), "Mancuerna sin evidencia: \(record.name)")
            case .ezBar:
                XCTAssertTrue(normalized.contains("barra z"), "Barra EZ sin evidencia: \(record.name)")
            case .olympicBar:
                XCTAssertTrue(normalized.contains("barra olimpica"), "Olímpica sin evidencia: \(record.name)")
            case .standardBar:
                XCTAssertTrue(normalized.contains("barra"), "Barra estándar sin evidencia: \(record.name)")
                XCTAssertFalse(normalized.contains("barra z"), "Una barra Z no es estándar: \(record.name)")
                XCTAssertFalse(normalized.contains("barra olimpica"), "Una olímpica no es estándar: \(record.name)")
            case .fixedBar:
                XCTAssertTrue(normalized.contains("paralelas"), "Barra fija sin evidencia: \(record.name)")
            case .bodyweight:
                XCTAssertTrue(normalized.contains("peso corporal"), "Peso corporal sin evidencia: \(record.name)")
            case .cardioMachine, .pendingClassification:
                break
            }
        }
    }

    func testGenericMachineStaysPending() throws {
        let records: [CatalogExerciseRecord] = try allCatalogRecords()

        XCTAssertEqual(ExerciseRules.equipment(for: "Curl femoral sentado"), .selectorizedMachine)
        XCTAssertEqual(ExerciseRules.equipment(for: "Extensión de cuádriceps en máquina"), .selectorizedMachine)
        XCTAssertEqual(ExerciseRules.equipment(for: "Sentadilla hack en máquina"), .pendingClassification)
        XCTAssertEqual(ExerciseRules.equipment(for: "Sentadilla pendular en máquina"), .pendingClassification)
        XCTAssertEqual(ExerciseRules.equipment(for: "Isolateral reverse fly en máquina"), .pendingClassification)
        XCTAssertEqual(ExerciseRules.equipment(for: "Curl de bíceps en banco Scott en máquina"), .pendingClassification)
        XCTAssertEqual(ExerciseRules.equipment(for: "Hip thrust en máquina"), .pendingClassification)
        XCTAssertEqual(ExerciseRules.equipment(for: "Press plano en máquina convergente"), .pendingClassification)
        XCTAssertEqual(ExerciseRules.equipment(for: "Remo con pecho apoyado en máquina"), .pendingClassification)
        XCTAssertEqual(ExerciseRules.equipment(for: "Encogimientos de trapecio en máquina"), .pendingClassification)
        XCTAssertEqual(ExerciseRules.equipment(for: "Prensa de piernas inclinada"), .plateLoadedMachine)
        XCTAssertEqual(ExerciseRules.equipment(for: "Press banca inclinado en multipower"), .smithMachine)
        XCTAssertEqual(ExerciseRules.equipment(for: "Curl de bíceps con barra Z"), .ezBar)
        XCTAssertEqual(ExerciseRules.equipment(for: "Peso muerto rumano con barra"), .standardBar)
        XCTAssertEqual(ExerciseRules.equipment(for: "Remo libre con barra"), .standardBar)
        XCTAssertEqual(ExerciseRules.equipment(for: "Sentadilla búlgara con mancuernas"), .dumbbell)
        XCTAssertEqual(ExerciseRules.equipment(for: "Fondos en paralelas lastrados"), .pendingClassification)
        XCTAssertEqual(ExerciseRules.equipment(for: "Press banca con barra olímpica"), .olympicBar)

        let pending: [CatalogExerciseRecord] = records.filter {
            ExerciseRules.equipment(for: $0.name) == .pendingClassification
        }
        XCTAssertFalse(pending.isEmpty, "El catálogo debe marcar como pendientes las máquinas no distinguibles")
    }

    func testSelectorizedMachinesAreAnExplicitSubset() throws {
        let selectorized: [String] = [
            "Abducción de cadera en máquina",
            "Aductores en máquina",
            "Aperturas en máquina contractora (Peck deck)",
            "Curl femoral sentado",
            "Curl femoral tumbado",
            "Elevaciones laterales en máquina",
            "Elevación de talones de pie en máquina",
            "Elevación de talones sentado en máquina",
            "Extensión de cuádriceps en máquina",
            "Press de hombro en máquina"
        ]

        for name in selectorized {
            XCTAssertEqual(ExerciseRules.equipment(for: name), .selectorizedMachine, name)
        }

        XCTAssertFalse(EquipmentType.selectorizedMachine.usesPlates)
        XCTAssertEqual(EquipmentType.selectorizedMachine.baseWeight, 0.0)
        XCTAssertTrue(EquipmentType.standardBar.usesPlates)
        XCTAssertNotEqual(EquipmentType.standardBar, .olympicBar)
        XCTAssertNotEqual(EquipmentType.standardBar, .ezBar)

        let selectorizedResult = PlateCalculatorService.calculate(
            totalWeight: 60.0,
            equipmentType: .selectorizedMachine,
            availablePlates: [20.0, 10.0, 5.0]
        )
        XCTAssertFalse(selectorizedResult.usesPlates)
        XCTAssertTrue(selectorizedResult.platesPerSide.isEmpty)
        XCTAssertEqual(selectorizedResult.achievedTotalWeight, 60.0)

        let standardBar = PlateCalculatorService.calculate(
            totalWeight: 60.0,
            equipmentType: .standardBar,
            availablePlates: [20.0, 10.0, 5.0]
        )
        XCTAssertTrue(standardBar.usesPlates)
        XCTAssertEqual(standardBar.barWeight, UserSettingsManager.standardBarWeight)
    }

    func testStandardBarWeightIsConfigurableAndKeepsPlateMath() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: UserSettingsManager.standardBarWeightKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: UserSettingsManager.standardBarWeightKey)
            } else {
                defaults.removeObject(forKey: UserSettingsManager.standardBarWeightKey)
            }
        }

        defaults.set(12.0, forKey: UserSettingsManager.standardBarWeightKey)
        XCTAssertEqual(EquipmentType.standardBar.baseWeight, 12.0)

        let result = PlateCalculatorService.calculate(
            totalWeight: 32.0,
            equipmentType: .standardBar,
            availablePlates: [10.0, 5.0, 2.5, 1.25]
        )
        XCTAssertEqual(result.barWeight, 12.0)
        XCTAssertEqual(result.platesPerSide.reduce(0.0) { $0 + $1 }, 10.0)
        XCTAssertEqual(result.achievedTotalWeight, 32.0)
    }

    func testUniqueSheetPreservesNotationsAndBiomechanics() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()

        XCTAssertEqual(catalog.file.uniqueExercises.count, 47)

        let exercise = try XCTUnwrap(catalog.file.uniqueExercises.first)
        XCTAssertFalse(exercise.notations.isEmpty)
        XCTAssertFalse(exercise.whyGood.isEmpty)
        XCTAssertFalse(exercise.whyBad.isEmpty)
        XCTAssertFalse(exercise.whenRecommended.isEmpty)
        XCTAssertFalse(exercise.whenNotRecommended.isEmpty)
    }

    func testMuscleSourceTextAndUnmappedTokensArePreserved() throws {
        let records: [CatalogExerciseRecord] = try allCatalogRecords()

        guard let record = records.first(where: { $0.secondaryRaw.contains("Manguito") }) else {
            return XCTFail("El catálogo debe conservar el token «Manguito»")
        }

        let unmapped: [String] = ExerciseRules.unmappedMuscles(in: record.secondaryRaw)
        XCTAssertTrue(unmapped.contains("Manguito"))
    }

    func testDorsalAndMediaAreBothPreserved() {
        let groups: [MuscleGroup] = ExerciseRules.muscleList(from: "Espalda (Dorsal/Media)")
        XCTAssertTrue(groups.contains(.lats))
        XCTAssertTrue(groups.contains(.upperBack))
    }

    func testGeneratedExerciseKeepsCatalogMuscleText() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 1,
            l: 0,
            u: 1,
            expression: "Upper",
            sessions: [.upper]
        )

        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)
        let variant: CatalogRoutineVariant = try XCTUnwrap(catalog.variant(for: .upper, occurrences: 1, suffix: ""))

        for generated in week.sessions.flatMap({ $0.exercises }) {
            guard let record = variant.exercises.first(where: { $0.name == generated.name }) else {
                XCTFail("Ejercicio fuera de la variante: \(generated.name)")
                continue
            }

            XCTAssertEqual(generated.primaryMuscleText, record.primaryRaw)
            XCTAssertEqual(generated.secondaryMuscleText, record.secondaryRaw)
        }
    }

    private func allCatalogRecords() throws -> [CatalogExerciseRecord] {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        return catalog.file.levels.single.flatMap { $0.exercises }
            + catalog.file.levels.double.flatMap { $0.exercises }
            + catalog.file.levels.triple.flatMap { $0.exercises }
    }

    func testWeekSessionCountMatchesW() throws {
        let catalog: ExerciseCatalogStore = try TestResources.catalogStore()
        let proposal = SplitProposal(
            w: 5,
            l: 3,
            u: 2,
            expression: "(Push/Pull) x2/Legs",
            sessions: [.push, .pull, .push, .pull, .legs]
        )

        let week: GeneratedWeek = try RoutineGenerator.generate(proposal: proposal, catalog: catalog)

        XCTAssertEqual(week.sessions.count, 5)
        XCTAssertEqual(week.restDays, 2)
        XCTAssertEqual(week.sessionNames, ["Push A", "Pull A", "Push B", "Pull B", "Legs"])
    }
}
