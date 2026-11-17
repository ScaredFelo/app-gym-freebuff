import Foundation
import SwiftData

@MainActor
public final class MockDataGenerator {
    public static func seedIfNeeded(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<Exercise>()
            let existingCount = try context.fetchCount(descriptor)
            guard existingCount == 0 else { return }

            // --- PUSH EXERCISES ---
            let push1 = Exercise(
                name: "Press banca inclinado",
                muscleGroup: .chest,
                equipmentType: .smithMachine,
                requiresStraps: false,
                targetRepsMin: 6,
                targetRepsMax: 8,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: true,
                primaryMuscles: [.chest],
                secondaryMuscles: [.frontShoulders, .triceps]
            )
            let push2 = Exercise(
                name: "Elevaciones laterales mancuerna",
                muscleGroup: .frontShoulders,
                equipmentType: .cable,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: false,
                primaryMuscles: [.frontShoulders],
                secondaryMuscles: [.upperBack]
            )
            let push3 = Exercise(
                name: "Triceps pushdowns",
                muscleGroup: .triceps,
                equipmentType: .cable,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: false,
                primaryMuscles: [.triceps],
                secondaryMuscles: [.forearms]
            )
            let push4 = Exercise(
                name: "Seated cable fly",
                muscleGroup: .chest,
                equipmentType: .cable,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: false,
                primaryMuscles: [.chest],
                secondaryMuscles: [.frontShoulders]
            )
            let push5 = Exercise(
                name: "Press militar",
                muscleGroup: .frontShoulders,
                equipmentType: .dumbbell,
                requiresStraps: false,
                targetRepsMin: 6,
                targetRepsMax: 8,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: true,
                primaryMuscles: [.frontShoulders],
                secondaryMuscles: [.triceps, .upperBack, .abs]
            )
            let push6 = Exercise(
                name: "Extension de triceps",
                muscleGroup: .triceps,
                equipmentType: .cable,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: false,
                primaryMuscles: [.triceps],
                secondaryMuscles: [.forearms]
            )

            context.insert(push1)
            context.insert(push2)
            context.insert(push3)
            context.insert(push4)
            context.insert(push5)
            context.insert(push6)

            let pushRoutine = Routine(
                name: "PUSH",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: push1, defaultSets: 3, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 0),
                    RoutineExercise(exercise: push2, defaultSets: 3, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 1),
                    RoutineExercise(exercise: push3, defaultSets: 3, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 2),
                    RoutineExercise(exercise: push4, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 3),
                    RoutineExercise(exercise: push5, defaultSets: 2, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 4),
                    RoutineExercise(exercise: push6, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 5)
                ]
            )
            context.insert(pushRoutine)

            // --- PULL EXERCISES ---
            let pull1 = Exercise(
                name: "Jalon al pecho",
                muscleGroup: .lats,
                equipmentType: .cable,
                requiresStraps: true,
                targetRepsMin: 6,
                targetRepsMax: 8,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: true,
                primaryMuscles: [.lats],
                secondaryMuscles: [.biceps, .upperBack, .rearShoulders]
            )
            let pull2 = Exercise(
                name: "Curl bayesiano",
                muscleGroup: .biceps,
                equipmentType: .cable,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: false,
                primaryMuscles: [.biceps],
                secondaryMuscles: [.forearms]
            )
            let pull3 = Exercise(
                name: "Remo en maquina",
                muscleGroup: .upperBack,
                equipmentType: .plateLoadedMachine,
                requiresStraps: true,
                targetRepsMin: 6,
                targetRepsMax: 8,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: true,
                primaryMuscles: [.upperBack],
                secondaryMuscles: [.lats, .biceps, .rearShoulders]
            )
            let pull4 = Exercise(
                name: "Spider curl",
                muscleGroup: .biceps,
                equipmentType: .dumbbell,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: false,
                primaryMuscles: [.biceps],
                secondaryMuscles: [.forearms]
            )
            let pull5 = Exercise(
                name: "Remo libre",
                muscleGroup: .lats,
                equipmentType: .olympicBar,
                requiresStraps: true,
                targetRepsMin: 6,
                targetRepsMax: 8,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: true,
                primaryMuscles: [.lats],
                secondaryMuscles: [.upperBack, .biceps, .rearShoulders, .lowerBack]
            )
            let pull6 = Exercise(
                name: "Isololateral reverse fly",
                muscleGroup: .rearShoulders,
                equipmentType: .cable,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 135),
                isCompound: false,
                primaryMuscles: [.rearShoulders],
                secondaryMuscles: [.upperBack]
            )

            context.insert(pull1)
            context.insert(pull2)
            context.insert(pull3)
            context.insert(pull4)
            context.insert(pull5)
            context.insert(pull6)

            let pullRoutine = Routine(
                name: "PULL",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: pull1, defaultSets: 3, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 0),
                    RoutineExercise(exercise: pull2, defaultSets: 3, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 1),
                    RoutineExercise(exercise: pull3, defaultSets: 2, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 2),
                    RoutineExercise(exercise: pull4, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 3),
                    RoutineExercise(exercise: pull5, defaultSets: 2, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 4),
                    RoutineExercise(exercise: pull6, defaultSets: 3, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 5)
                ]
            )
            context.insert(pullRoutine)

            // --- LEGS EXERCISES ---
            let leg1 = Exercise(
                name: "Hiperextensiones",
                muscleGroup: .lowerBack,
                equipmentType: .plateLoadedMachine,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 180),
                isCompound: false,
                primaryMuscles: [.lowerBack],
                secondaryMuscles: [.glutes, .hamstrings]
            )
            let leg2 = Exercise(
                name: "Flexion de pierna estirado",
                muscleGroup: .hamstrings,
                equipmentType: .cable,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 180),
                isCompound: false,
                primaryMuscles: [.hamstrings],
                secondaryMuscles: [.calves]
            )
            let leg3 = Exercise(
                name: "Bulgaras",
                muscleGroup: .quads,
                equipmentType: .dumbbell,
                requiresStraps: false,
                targetRepsMin: 6,
                targetRepsMax: 8,
                defaultRestCondition: .timer(seconds: 180),
                isCompound: true,
                primaryMuscles: [.quads],
                secondaryMuscles: [.glutes, .hamstrings, .adductors]
            )
            let leg4 = Exercise(
                name: "Elevacion talones sentado",
                muscleGroup: .calves,
                equipmentType: .plateLoadedMachine,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 180),
                isCompound: false,
                primaryMuscles: [.calves],
                secondaryMuscles: []
            )
            let leg5 = Exercise(
                name: "Romanian deadlift (RDL)",
                muscleGroup: .hamstrings,
                equipmentType: .olympicBar,
                requiresStraps: true,
                targetRepsMin: 6,
                targetRepsMax: 8,
                defaultRestCondition: .timer(seconds: 180),
                isCompound: true,
                primaryMuscles: [.hamstrings],
                secondaryMuscles: [.glutes, .lowerBack, .upperBack]
            )
            let leg6 = Exercise(
                name: "Extension de quadriceps",
                muscleGroup: .quads,
                equipmentType: .cable,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 180),
                isCompound: false,
                primaryMuscles: [.quads],
                secondaryMuscles: []
            )

            context.insert(leg1)
            context.insert(leg2)
            context.insert(leg3)
            context.insert(leg4)
            context.insert(leg5)
            context.insert(leg6)

            let legsRoutine = Routine(
                name: "LEGS",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: leg1, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 0),
                    RoutineExercise(exercise: leg2, defaultSets: 3, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 1),
                    RoutineExercise(exercise: leg3, defaultSets: 2, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 2),
                    RoutineExercise(exercise: leg4, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 3),
                    RoutineExercise(exercise: leg5, defaultSets: 2, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 4),
                    RoutineExercise(exercise: leg6, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 5)
                ]
            )
            context.insert(legsRoutine)

            // --- UPPER ROUTINE ---
            let upperRoutine = Routine(
                name: "UPPER",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: push1, defaultSets: 3, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 0),
                    RoutineExercise(exercise: push4, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 1),
                    RoutineExercise(exercise: pull1, defaultSets: 3, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 2),
                    RoutineExercise(exercise: push2, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 3),
                    RoutineExercise(exercise: pull5, defaultSets: 2, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 4),
                    RoutineExercise(exercise: push6, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 5),
                    RoutineExercise(exercise: pull2, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 6),
                    RoutineExercise(exercise: pull6, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 7)
                ]
            )
            context.insert(upperRoutine)

            // --- LOWER ROUTINE ---
            let leg7 = Exercise(
                name: "Flexion de pierna sentado",
                muscleGroup: .hamstrings,
                equipmentType: .cable,
                requiresStraps: false,
                targetRepsMin: 8,
                targetRepsMax: 10,
                defaultRestCondition: .timer(seconds: 180),
                isCompound: false,
                primaryMuscles: [.hamstrings],
                secondaryMuscles: [.calves]
            )

            context.insert(leg7)

            let lowerRoutine = Routine(
                name: "LOWER",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: leg1, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 0),
                    RoutineExercise(exercise: leg7, defaultSets: 3, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 1),
                    RoutineExercise(exercise: leg3, defaultSets: 2, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 2),
                    RoutineExercise(exercise: leg4, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 3),
                    RoutineExercise(exercise: leg5, defaultSets: 2, targetRepsMin: 6, targetRepsMax: 8, sortOrder: 4),
                    RoutineExercise(exercise: leg6, defaultSets: 2, targetRepsMin: 8, targetRepsMax: 10, sortOrder: 5)
                ]
            )
            context.insert(lowerRoutine)

            try context.save()
        } catch {
            print("Error seeding mock data: \(error)")
        }
    }
}
