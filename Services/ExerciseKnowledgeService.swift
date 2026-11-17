import Foundation

// MARK: - Resultado resuelto

/// Información biomecánica final de un ejercicio, ya sea la guardada en el
/// modelo o la inferida automáticamente a partir de su nombre y equipamiento.
public struct ResolvedExerciseInfo: Equatable {
    public var primaryMuscles: [MuscleGroup]
    public var secondaryMuscles: [MuscleGroup]
    public var isCompound: Bool
    public var requiresStraps: Bool
    public var targetRepsText: String
    public var whyGoodExercise: String
    public var whyBadExercise: String
    public var whenRecommended: String
    public var whenNotRecommended: String

    public init(
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleGroup],
        isCompound: Bool,
        requiresStraps: Bool,
        targetRepsText: String,
        whyGoodExercise: String,
        whyBadExercise: String,
        whenRecommended: String,
        whenNotRecommended: String
    ) {
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.isCompound = isCompound
        self.requiresStraps = requiresStraps
        self.targetRepsText = targetRepsText
        self.whyGoodExercise = whyGoodExercise
        self.whyBadExercise = whyBadExercise
        self.whenRecommended = whenRecommended
        self.whenNotRecommended = whenNotRecommended
    }
}

// MARK: - Perfil interno

private struct ExerciseKnowledgeProfile {
    let keywords: [String]
    let primaryMuscles: [MuscleGroup]
    let secondaryMuscles: [MuscleGroup]
    let isCompound: Bool
    let requiresStraps: Bool
    let targetRepsText: String
    let whyGoodExercise: String
    let whyBadExercise: String
    let whenRecommended: String
    let whenNotRecommended: String
}

// MARK: - Servicio

/// Base de conocimiento biomecánica local. Si el nombre del ejercicio coincide
/// con un patrón conocido se devuelve su perfil realista; si no, se construye
/// un perfil genérico a partir del equipamiento y del grupo muscular objetivo.
public enum ExerciseKnowledgeService {

    // MARK: API pública

    public static func resolvedInfo(for exercise: Exercise) -> ResolvedExerciseInfo {
        let inferred: ResolvedExerciseInfo = inferredInfo(for: exercise)

        let storedPrimary: [MuscleGroup] = exercise.primaryMuscles
        let storedSecondary: [MuscleGroup] = exercise.secondaryMuscles
        let hasStoredMuscles: Bool = !storedPrimary.isEmpty || !storedSecondary.isEmpty
        let hasStoredTexts: Bool = !exercise.whyGoodExercise.isEmpty
            || !exercise.whyBadExercise.isEmpty
            || !exercise.whenRecommended.isEmpty
            || !exercise.whenNotRecommended.isEmpty
        let hasStoredKnowledge: Bool = hasStoredMuscles || hasStoredTexts

        let primary: [MuscleGroup] = hasStoredMuscles ? storedPrimary : inferred.primaryMuscles
        let rawSecondary: [MuscleGroup] = hasStoredMuscles ? storedSecondary : inferred.secondaryMuscles
        let secondary: [MuscleGroup] = rawSecondary.filter { (muscle: MuscleGroup) -> Bool in
            return !primary.contains(muscle)
        }
        let isCompound: Bool = hasStoredKnowledge ? exercise.isCompound : inferred.isCompound
        let requiresStraps: Bool = exercise.requiresStraps || (!hasStoredKnowledge && inferred.requiresStraps)

        return ResolvedExerciseInfo(
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            isCompound: isCompound,
            requiresStraps: requiresStraps,
            targetRepsText: exercise.targetRepsText,
            whyGoodExercise: firstNonEmpty(exercise.whyGoodExercise, fallback: inferred.whyGoodExercise),
            whyBadExercise: firstNonEmpty(exercise.whyBadExercise, fallback: inferred.whyBadExercise),
            whenRecommended: firstNonEmpty(exercise.whenRecommended, fallback: inferred.whenRecommended),
            whenNotRecommended: firstNonEmpty(exercise.whenNotRecommended, fallback: inferred.whenNotRecommended)
        )
    }

    // MARK: Inferencia

    private static func inferredInfo(for exercise: Exercise) -> ResolvedExerciseInfo {
        let normalizedName: String = normalize(exercise.name)

        if !normalizedName.isEmpty {
            for profile in allProfiles {
                for keyword in profile.keywords {
                    if normalizedName.contains(keyword) {
                        return info(from: profile, targetRepsText: exercise.targetRepsText)
                    }
                }
            }
        }

        return fallbackInfo(for: exercise)
    }

    private static func info(
        from profile: ExerciseKnowledgeProfile,
        targetRepsText: String
    ) -> ResolvedExerciseInfo {
        return ResolvedExerciseInfo(
            primaryMuscles: profile.primaryMuscles,
            secondaryMuscles: profile.secondaryMuscles,
            isCompound: profile.isCompound,
            requiresStraps: profile.requiresStraps,
            targetRepsText: targetRepsText,
            whyGoodExercise: profile.whyGoodExercise,
            whyBadExercise: profile.whyBadExercise,
            whenRecommended: profile.whenRecommended,
            whenNotRecommended: profile.whenNotRecommended
        )
    }

    private static func fallbackInfo(for exercise: Exercise) -> ResolvedExerciseInfo {
        let primary: MuscleGroup = exercise.muscleGroup
        let secondary: [MuscleGroup] = defaultSecondaryMuscles(for: primary)
        let compound: Bool = compoundGroups.contains(primary)
        let equipment: EquipmentType = exercise.equipmentType

        return ResolvedExerciseInfo(
            primaryMuscles: [primary],
            secondaryMuscles: secondary,
            isCompound: compound,
            requiresStraps: equipment == .olympicBar && compound,
            targetRepsText: exercise.targetRepsText,
            whyGoodExercise: fallbackGoodText(equipment: equipment, compound: compound),
            whyBadExercise: fallbackBadText(equipment: equipment, compound: compound),
            whenRecommended: fallbackWhenText(compound: compound),
            whenNotRecommended: fallbackWhenNotText(equipment: equipment, compound: compound)
        )
    }

    private static func defaultSecondaryMuscles(for primary: MuscleGroup) -> [MuscleGroup] {
        switch primary {
        case .chest:
            return [.frontShoulders, .triceps]
        case .upperBack:
            return [.biceps, .rearShoulders]
        case .lats:
            return [.biceps, .upperBack]
        case .lowerBack:
            return [.glutes, .hamstrings]
        case .frontShoulders:
            return [.triceps, .upperBack]
        case .rearShoulders:
            return [.upperBack, .forearms]
        case .biceps:
            return [.forearms]
        case .triceps:
            return [.forearms]
        case .forearms:
            return [.biceps]
        case .abs:
            return [.lowerBack]
        case .quads:
            return [.glutes, .hamstrings]
        case .hamstrings:
            return [.glutes, .lowerBack]
        case .glutes:
            return [.hamstrings, .lowerBack]
        case .adductors:
            return [.quads, .glutes]
        case .calves:
            return []
        }
    }

    private static var compoundGroups: Set<MuscleGroup> {
        return [.chest, .upperBack, .lats, .lowerBack, .frontShoulders, .quads, .hamstrings, .glutes]
    }

    // MARK: Textos del fallback por equipamiento

    private static func fallbackGoodText(equipment: EquipmentType, compound: Bool) -> String {
        switch equipment {
        case .cable:
            return "La polea mantiene tensión constante durante todo el recorrido, lo que permite acumular volumen con una curva de resistencia estable y poco riesgo en el fallo."
        case .dumbbell:
            return "El rango de movimiento libre y el trabajo unilateral permiten corregir desequilibrios entre lados y exigen estabilización activa del hombro y del core."
        case .fixedBar:
            return "El recorrido fijo y la carga corporal o prefijada hacen que el ejercicio sea muy repetible, ideal para medir progreso con criterios claros."
        case .plateLoadedMachine, .smithMachine:
            return "La trayectoria guiada reduce la demanda técnica y de estabilidad, así que puedes acercarte al fallo con seguridad y acumular volumen de calidad."
        case .olympicBar, .ezBar:
            if compound {
                return "Permite mover cargas altas con progresión sencilla y un estímulo sistémico fuerte, lo que se traduce en ganancias de fuerza y masa muscular medibles."
            }
            return "La barra fija el recorrido de las manos y facilita cargar más que con mancuernas, manteniendo una tensión continua sobre el músculo objetivo."
        }
    }

    private static func fallbackBadText(equipment: EquipmentType, compound: Bool) -> String {
        switch equipment {
        case .cable:
            return "La tensión del cable y la inercia al final del recorrido pueden alterar la técnica, y la carga no es comparable con la de un ejercicio libre."
        case .dumbbell:
            return "Estabilizar dos implementos independientes limita la carga absoluta y alarga la curva de aprendizaje antes de poder progresar."
        case .fixedBar:
            return "El recorrido es tan guiado que el trabajo de estabilizadores es mínimo y la transferencia a patrones libres puede quedarse corta."
        case .plateLoadedMachine, .smithMachine:
            return "La trayectoria fija puede no encajar con tu antropometría y reduce el trabajo de estabilizadores, así que no sustituye a un patrón libre."
        case .olympicBar, .ezBar:
            if compound {
                return "La demanda de estabilidad y la fatiga general son altas: cuando la técnica se degrada, la columna y las articulaciones absorben el esfuerzo."
            }
            return "La posición fija de las manos puede forzar la muñeca y el codo; además es fácil compensar con balanceo del torso."
        }
    }

    private static func fallbackWhenText(compound: Bool) -> String {
        if compound {
            return "Al inicio de la sesión, con el sistema nervioso fresco, en bloques de fuerza (4-8 reps) o hipertrofia (8-12 reps) y descansos largos."
        }
        return "A mitad o al final de la sesión, cuando el objetivo es acumular volumen y tensión mecánica sin añadir fatiga sistémica."
    }

    private static func fallbackWhenNotText(equipment: EquipmentType, compound: Bool) -> String {
        if compound {
            return "Con fatiga lumbar o técnica inestable, con molestias articulares específicas del patrón o si aún no dominas la ejecución sin carga."
        }
        switch equipment {
        case .cable, .plateLoadedMachine, .smithMachine:
            return "Si buscas el máximo estímulo de fuerza o necesitas mover cargas absolutas altas; en ese caso prioriza un patrón libre."
        default:
            return "Con dolor articular activo o cuando la fatiga ya impide controlar la fase excéntrica del movimiento."
        }
    }

    // MARK: Utilidades

    private static func firstNonEmpty(_ value: String, fallback: String) -> String {
        let trimmed: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : value
    }

    private static func normalize(_ text: String) -> String {
        let lowered: String = text.lowercased()
        return lowered.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
    }

    private static func make(
        keywords: [String],
        primary: [MuscleGroup],
        secondary: [MuscleGroup],
        compound: Bool,
        straps: Bool,
        reps: String,
        good: String,
        bad: String,
        when: String,
        whenNot: String
    ) -> ExerciseKnowledgeProfile {
        return ExerciseKnowledgeProfile(
            keywords: keywords,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            isCompound: compound,
            requiresStraps: straps,
            targetRepsText: reps,
            whyGoodExercise: good,
            whyBadExercise: bad,
            whenRecommended: when,
            whenNotRecommended: whenNot
        )
    }

    // MARK: Base de conocimiento

    private static let pressProfiles: [ExerciseKnowledgeProfile] = [
        make(
            keywords: ["press banca inclinado", "press inclinado", "incline press", "inclined press"],
            primary: [.chest],
            secondary: [.frontShoulders, .triceps],
            compound: true,
            straps: false,
            reps: "6-10",
            good: "Prioriza la porción clavicular del pectoral con un perfil de resistencia estable y cargas progresables, sobre todo en Multipower donde la trayectoria es fija.",
            bad: "Si la inclinación pasa de 45 grados el trabajo se traslada al deltoides anterior y el hombro pierde margen de seguridad en la fase baja.",
            when: "Como primer ejercicio de pecho para la porción superior, en 6-10 reps con descansos de 2 minutos.",
            whenNot: "Con molestia en el hombro anterior en abducción y rotación externa, o si el banco supera los 45 grados."
        ),
        make(
            keywords: ["press banca", "bench press", "press plano", "press de banca"],
            primary: [.chest],
            secondary: [.frontShoulders, .triceps],
            compound: true,
            straps: false,
            reps: "5-10",
            good: "Es el mayor estímulo mecánico para el pectoral con cargas progresables: el perfil de resistencia del press plano es muy estable y permite medir la sobrecarga semana a semana.",
            bad: "Exige estabilidad escapular y control del arco torácico; con fatiga alta el hombro pierde posición y el estrés se concentra en la articulación.",
            when: "Como primer ejercicio de empuje, en bloques de fuerza (3-6 reps) o hipertrofia (6-12 reps) con descansos largos.",
            whenNot: "Con fatiga de empuje acumulada, molestia de hombro anterior o sin control escapular para fijar la escápula."
        ),
        make(
            keywords: ["cable fly", "aperturas", "pec deck", "cruces de polea", "contractor", "seated fly", "aperturas con mancuerna"],
            primary: [.chest],
            secondary: [.frontShoulders],
            compound: false,
            straps: false,
            reps: "10-15",
            good: "Aísla el pectoral con tensión constante en el punto de máxima contracción y permite un estiramiento controlado sin perder carga en el recorrido.",
            bad: "El torso apoyado reduce el trabajo de estabilizadores y la lectura de progresión con cable engaña: la tensión inicial ya es alta.",
            when: "A mitad o final de la sesión de pecho para acumular volumen, con 2-3 series de 10-15 reps y pausa en la contracción.",
            whenNot: "Si es el único estímulo de pecho de la sesión o cuando el hombro anterior está irritado."
        ),
        make(
            keywords: ["press militar", "shoulder press", "press hombro", "press de hombro", "push press"],
            primary: [.frontShoulders],
            secondary: [.triceps, .upperBack, .abs],
            compound: true,
            straps: false,
            reps: "6-10",
            good: "Patrón de empuje vertical con gran transferencia y alta demanda de estabilidad del core; permite una progresión clara en fuerza de hombro.",
            bad: "La demanda escapular y lumbar es alta: sin movilidad torácica suficiente la carga se escapa a la zona lumbar y el deltoides anterior se lleva el trabajo.",
            when: "Al inicio de la sesión de hombro, en 4-8 reps para fuerza o 8-12 para hipertrofia.",
            whenNot: "Con movilidad torácica limitada, hombro doloroso en flexión alta o fatiga lumbar acumulada."
        ),
        make(
            keywords: ["elevaciones laterales", "elevacion lateral", "lateral raise", "vuelo lateral", "vuelos laterales"],
            primary: [.frontShoulders],
            secondary: [.upperBack],
            compound: false,
            straps: false,
            reps: "12-20",
            good: "Aísla el deltoides medio, el principal responsable de la amplitud del hombro, con el pico de tensión cerca de la horizontal.",
            bad: "Se convierte en un balanceo con cargas altas y el supraespinoso recibe estrés si se sube por encima del hombro; además el trapecio compensa con facilidad.",
            when: "A mitad o final de la sesión, con 3-4 series de 12-20 reps buscando congestión y tolerancia alta a la fatiga.",
            whenNot: "Con pinzamiento subacromial activo o si el torso acaba impulsando las repeticiones."
        ),
        make(
            keywords: ["reverse fly", "pajaros", "deltoide posterior", "rear delt", "posterior fly"],
            primary: [.rearShoulders],
            secondary: [.upperBack],
            compound: false,
            straps: false,
            reps: "12-20",
            good: "Aísla el deltoides posterior con tensión constante desde el cruce, clave para equilibrar el hombro y mejorar la postura tras mucho press.",
            bad: "Las cargas son muy ligeras y es fácil compensar con trapecio; si se eleva el codo de más, el rango útil se acorta.",
            when: "Al final del entreno de tirón o de hombro, 3 series de 12-20 reps con pausa en la apertura.",
            whenNot: "Con dolor en la inserción posterior del hombro o cuando la prioridad es el deltoides medio."
        ),
        make(
            keywords: ["face pull"],
            primary: [.rearShoulders],
            secondary: [.upperBack, .forearms],
            compound: false,
            straps: false,
            reps: "15-20",
            good: "Combina rotación externa y retracción escapular, un patrón que equilibra el trabajo de press y protege la articulación del hombro.",
            bad: "La carga es muy ligera y se puede ejecutar con el trapecio alto en vez del deltoides posterior, acumulando tensión cervical.",
            when: "Al final de empuje o tirón, 2-3 series de 15-20 reps como trabajo correctivo.",
            whenNot: "Si necesitas fuerza o hipertrofia como objetivo principal: es un ejercicio de salud articular, no el motor del bloque."
        )
    ]

    private static let pullProfiles: [ExerciseKnowledgeProfile] = [
        make(
            keywords: ["jalon", "pulldown", "pull down", "pull-down", "traccion vertical"],
            primary: [.lats],
            secondary: [.biceps, .upperBack, .rearShoulders],
            compound: true,
            straps: true,
            reps: "8-12",
            good: "Trabaja el dorsal en aducción desde un estiramiento largo y con tensión mantenida: excelente para acumular volumen de espalda sin cargar la lumbar.",
            bad: "Si se convierte en un remo hacia atrás con balanceo, el dorsal pierde tensión; además el bíceps y los flexores del antebrazo limitan antes que la espalda.",
            when: "Como primer ejercicio de tirón vertical (6-10 reps) o al final de la sesión para acumular volumen.",
            whenNot: "Con molestia de hombro en abducción alta o sin control escapular para iniciar el tirón."
        ),
        make(
            keywords: ["dominadas", "pull up", "pull-up", "tracciones en barra"],
            primary: [.lats],
            secondary: [.biceps, .upperBack, .rearShoulders],
            compound: true,
            straps: true,
            reps: "5-10",
            good: "Ejercicio de tracción con peso corporal que combina dorsal, espalda media y agarre con una gran transferencia a la fuerza relativa.",
            bad: "El agarre falla antes que la espalda y la técnica se degrada al final de la serie; sin control escapular el hombro se lleva el esfuerzo.",
            when: "Al inicio de la sesión de espalda, en series de 5-10 reps o con lastre en bloques de fuerza.",
            whenNot: "Si aún no puedes dominar el rango completo sin balanceo o con molestias de codo y hombro."
        ),
        make(
            keywords: ["remo en maquina", "remo maquina", "remo sentado", "seated row", "remo polea"],
            primary: [.upperBack],
            secondary: [.lats, .biceps, .rearShoulders],
            compound: true,
            straps: true,
            reps: "8-15",
            good: "El soporte del torso elimina la demanda lumbar y permite acercarse al fallo con un recorrido estable y tensión constante en la espalda media.",
            bad: "El trabajo de estabilizadores es bajo y la trayectoria fija puede no coincidir con tu anatomía, limitando el rango útil del dorsal.",
            when: "Como segundo ejercicio de espalda o al final, en 8-15 reps buscando volumen con buena conexión.",
            whenNot: "Si buscas transferencia a patrones libres o hay molestia en el hombro posterior con la máquina."
        ),
        make(
            keywords: ["remo", "row"],
            primary: [.upperBack],
            secondary: [.lats, .biceps, .rearShoulders, .lowerBack],
            compound: true,
            straps: true,
            reps: "6-10",
            good: "Carga alta en el plano horizontal con gran estímulo para espalda media y dorsal, y buena transferencia a la fuerza general y a la postura.",
            bad: "La demanda lumbar es alta: cuando la técnica falla, la columna absorbe el esfuerzo. Además el bíceps y el agarre suelen limitar antes que la espalda.",
            when: "Al inicio de la sesión de espalda, en 5-10 reps con el torso estable y descansos de 2 minutos.",
            whenNot: "Con fatiga lumbar acumulada, dolor discal o si no puedes mantener la bisagra de cadera sin redondear la espalda."
        ),
        make(
            keywords: ["encogimiento", "shrug", "trapecio superior"],
            primary: [.upperBack],
            secondary: [.forearms],
            compound: false,
            straps: true,
            reps: "10-15",
            good: "Estímulo directo del trapecio superior con un recorrido corto que admite mucha carga y progresión sencilla.",
            bad: "El rango es corto y se compensa fácilmente con rotación de hombro; el exceso de trapecio superior sin trabajo escapular puede empeorar la postura.",
            when: "Al final de la sesión de espalda u hombro, 2-3 series de 10-15 reps con pausa arriba.",
            whenNot: "Con cervicobraquialgia o tensión cervical alta, donde el trabajo de trapecio superior añade síntomas."
        ),
        make(
            keywords: ["peso muerto rumano", "rumano", "rdl", "romanian deadlift", "stiff leg"],
            primary: [.hamstrings],
            secondary: [.glutes, .lowerBack, .upperBack],
            compound: true,
            straps: true,
            reps: "6-10",
            good: "Excelente bisagra de cadera para isquios y glúteo en estiramiento con cargas altas y una transferencia directa a la fuerza posterior.",
            bad: "Si la barra se aleja del cuerpo o la lumbar se redondea, la carga se traslada a la columna; el agarre suele fallar antes que los isquios, de ahí el uso de straps.",
            when: "Como primer ejercicio de femoral, en 6-10 reps con descansos de 2-3 minutos.",
            whenNot: "Con fatiga lumbar acumulada, isquios acortados con molestia o sin control de la bisagra de cadera."
        ),
        make(
            keywords: ["peso muerto", "deadlift"],
            primary: [.glutes],
            secondary: [.hamstrings, .lowerBack, .upperBack, .forearms],
            compound: true,
            straps: true,
            reps: "3-6",
            good: "El ejercicio con mayor producción de fuerza total: recluta glúteo, isquios y espalda en un patrón que transfiere a casi todo lo demás.",
            bad: "La fatiga sistémica y el estrés lumbar son máximos; un fallo técnico o un exceso de volumen comprometen la recuperación de toda la semana.",
            when: "Al inicio de la sesión, en bloques de fuerza de 3-6 reps y con descansos de 3 minutos o más.",
            whenNot: "Con molestias lumbares, técnica inestable o si acumulas mucho volumen de bisagra en la misma semana."
        )
    ]

    private static let legProfiles: [ExerciseKnowledgeProfile] = [
        make(
            keywords: ["curl femoral", "flexion de pierna", "leg curl", "femoral tumbado", "femoral sentado"],
            primary: [.hamstrings],
            secondary: [.calves],
            compound: false,
            straps: false,
            reps: "8-15",
            good: "Es el único patrón que flexiona la rodilla contra resistencia y trabaja los isquios en acortamiento, complementando el estímulo del peso muerto rumano.",
            bad: "El pico de tensión llega en la flexión y el estiramiento queda poco cargado; con el pie en flexión plantar el gemelo se lleva parte del trabajo.",
            when: "Después del trabajo de bisagra, 3 series de 8-15 reps con control excéntrico de 2-3 segundos.",
            whenNot: "Con molestia en la parte posterior de la rodilla o tendinopatía de isquios en fase aguda."
        ),
        make(
            keywords: ["extension de cuadriceps", "extension de quadriceps", "leg extension", "extension de piernas", "extension de cuadricep"],
            primary: [.quads],
            secondary: [],
            compound: false,
            straps: false,
            reps: "10-15",
            good: "Aísla el cuádriceps con tensión constante en la extensión y permite acumular volumen cuando la sentadilla ya no es de calidad.",
            bad: "Genera fuerzas de cizallamiento sobre la rótula y poca transferencia a patrones multiarticulares; el rango final suele completarse por inercia.",
            when: "Al final de la sesión de pierna, 3 series de 10-15 reps con pausa de un segundo en la extensión.",
            whenNot: "Con dolor patelofemoral o tras un gran volumen de sentadillas y prensa con la rodilla irritada."
        ),
        make(
            keywords: ["sentadilla", "squat", "prensa", "leg press", "hack", "bulgaras", "bulgara", "zancada", "lunge", "subida al cajon", "step up"],
            primary: [.quads],
            secondary: [.glutes, .hamstrings, .adductors, .lowerBack],
            compound: true,
            straps: false,
            reps: "6-10",
            good: "El patrón de sentadilla con carga desarrolla cuádriceps y glúteo con el mayor estímulo sistémico y la mejor transferencia global de pierna.",
            bad: "Es muy demandante: la técnica se degrada con la fatiga y la lumbar o la rodilla absorben el fallo antes que el músculo objetivo.",
            when: "Al inicio de la sesión de pierna, en 5-10 reps con descansos largos y la rodilla bien alineada.",
            whenNot: "Con fatiga acumulada, dolor lumbar o de rodilla, o como último ejercicio de una sesión ya larga."
        ),
        make(
            keywords: ["hip thrust", "empuje de cadera", "puente de gluteo", "glute bridge"],
            primary: [.glutes],
            secondary: [.hamstrings, .lowerBack],
            compound: true,
            straps: false,
            reps: "8-12",
            good: "Maximiza la tensión del glúteo en su rango de máxima contracción (extensión de cadera) con una demanda lumbar muy controlada.",
            bad: "El rango útil es corto y es fácil compensar con la lumbar o con los isquios si se empuja con los pies demasiado lejos.",
            when: "Como primer ejercicio de glúteo, en 8-12 reps con pausa de un segundo arriba.",
            whenNot: "Con molestia en la cadera anterior o si no puedes mantener la pelvis neutra en la extensión."
        ),
        make(
            keywords: ["patada de gluteo", "patada gluteo", "glute kickback", "kickback de gluteo"],
            primary: [.glutes],
            secondary: [.hamstrings],
            compound: false,
            straps: false,
            reps: "12-20",
            good: "Aísla la extensión de cadera con poca fatiga general, útil para acumular volumen de glúteo al final de la sesión.",
            bad: "El recorrido es corto y la tensión se pierde en el punto de máxima extensión; sin control lumbar es fácil arquear la espalda.",
            when: "Al final de la sesión de pierna o glúteo, 2-3 series de 12-20 reps por lado.",
            whenNot: "Si la prioridad es fuerza o hipertrofia con carga alta: aquí el estímulo es limitado."
        ),
        make(
            keywords: ["talones", "gemelos", "calf", "soleo"],
            primary: [.calves],
            secondary: [],
            compound: false,
            straps: false,
            reps: "12-20",
            good: "Trabaja el tríceps sural con un rango completo y alta tolerancia al volumen; con la rodilla flexionada se prioriza el sóleo, con la rodilla extendida el gastrocnemio.",
            bad: "El recorrido es corto y muy fácil de rebotar: sin pausa arriba y sin bajar el talón el estímulo se pierde casi por completo.",
            when: "Al final de la sesión de pierna, 3-4 series de 12-20 reps con pausa de un segundo en la contracción.",
            whenNot: "Con tendinopatía aquílea en fase irritada o justo antes de un ejercicio que necesite el tobillo estable."
        ),
        make(
            keywords: ["hiperextension", "extension lumbar", "back extension", "good morning", "extension de espalda"],
            primary: [.lowerBack],
            secondary: [.glutes, .hamstrings],
            compound: true,
            straps: false,
            reps: "12-15",
            good: "Refuerza erectores y glúteo con un patrón de extensión de cadera que protege la lumbar en el resto de la sesión.",
            bad: "Si se hiperextiende la columna al final del recorrido, el estrés se concentra en la lumbar sin ganancia extra y aumenta el riesgo de molestia.",
            when: "Como calentamiento específico o al final de piernas y espalda, con 2-3 series de 12-15 reps controladas.",
            whenNot: "Con dolor lumbar agudo o inmediatamente después de un peso muerto pesado."
        ),
        make(
            keywords: ["aductor", "aductores", "copenhagen", "aduccion de cadera"],
            primary: [.adductors],
            secondary: [.quads, .glutes],
            compound: false,
            straps: false,
            reps: "12-15",
            good: "Trabaja el aductor con control, clave para la estabilidad de cadera y para tolerar mejor la sentadilla y los cambios de dirección.",
            bad: "El rango se acorta si no se controla y es fácil cargar en exceso un músculo poco acostumbrado a la tensión directa.",
            when: "Como accesorio de pierna, 2-3 series de 12-15 reps con progresión lenta semana a semana.",
            whenNot: "Con molestia inguinal aguda o sin haber calentado la cadera."
        )
    ]

    private static let armProfiles: [ExerciseKnowledgeProfile] = [
        make(
            keywords: ["curl bayesiano", "bayesian curl"],
            primary: [.biceps],
            secondary: [.forearms],
            compound: false,
            straps: false,
            reps: "8-12",
            good: "La polea baja por detrás del torso mantiene el bíceps en estiramiento con tensión desde el inicio del recorrido, un perfil muy favorable para hipertrofia.",
            bad: "El rango final es corto y el torso puede balancearse para mover más carga, reduciendo el estímulo real sobre el bíceps.",
            when: "Como primer o segundo ejercicio de bíceps, en 8-12 reps con tempo controlado.",
            whenNot: "Con molestia en la porción larga del bíceps en estiramiento máximo o si el apoyo fuerza la lumbar."
        ),
        make(
            keywords: ["spider curl", "curl araña"],
            primary: [.biceps],
            secondary: [.forearms],
            compound: false,
            straps: false,
            reps: "10-12",
            good: "Fija el húmero en posición vertical y concentra el pico de tensión en la flexión máxima, donde el bíceps está más acortado.",
            bad: "El rango de estiramiento es mínimo, así que aporta menos estímulo en longitud larga y limita la ganancia global si es el único curl.",
            when: "Al final del trabajo de bíceps para acumular tensión mecánica con cargas moderadas.",
            whenNot: "Como único ejercicio de bíceps o con molestia en el tendón distal del codo."
        ),
        make(
            keywords: ["curl predicador", "preacher curl", "curl scott"],
            primary: [.biceps],
            secondary: [.forearms],
            compound: false,
            straps: false,
            reps: "8-12",
            good: "El banco predicador elimina el balanceo y aísla el bíceps con una gran tensión en la porción corta durante la flexión.",
            bad: "La fase de estiramiento queda muy cargada y es la posición de mayor riesgo para el tendón distal si se baja sin control.",
            when: "A mitad del trabajo de bíceps, en 8-12 reps con excéntrica lenta.",
            whenNot: "Con antecedentes de molestia en el codo o tendinitis distal del bíceps."
        ),
        make(
            keywords: ["curl martillo", "hammer curl", "curl neutro"],
            primary: [.biceps],
            secondary: [.forearms],
            compound: false,
            straps: false,
            reps: "10-12",
            good: "El agarre neutro reparte el trabajo entre bíceps y braquial, añadiendo grosor al brazo con menos estrés en la muñeca que el curl supinado.",
            bad: "Al mantener el agarre neutro se pierde parte del estímulo específico de la porción corta del bíceps y se carga menos el pico de contracción.",
            when: "Después del curl supinado, en 3 series de 10-12 reps como trabajo complementario.",
            whenNot: "Si el objetivo es maximizar el bíceps en supinación o hay molestia en el codo."
        ),
        make(
            keywords: ["curl de muneca", "curl muneca", "antebrazo", "forearm", "wrist curl", "farmer"],
            primary: [.forearms],
            secondary: [.biceps],
            compound: false,
            straps: false,
            reps: "15-20",
            good: "Refuerza los flexores del antebrazo y mejora el agarre, lo que se traduce en mejor rendimiento en remos, dominadas y peso muerto.",
            bad: "El recorrido es corto y aporta poco a la hipertrofia visible del antebrazo si solo se trabaja la flexión de muñeca.",
            when: "Al final de la sesión, 2 series de 15-20 reps con pausa breve.",
            whenNot: "Con epicondilitis, molestia de muñeca o después de un trabajo de agarre ya muy exigente."
        ),
        make(
            keywords: ["curl"],
            primary: [.biceps],
            secondary: [.forearms],
            compound: false,
            straps: false,
            reps: "8-12",
            good: "Es el estímulo directo más eficiente para el bíceps: la flexión con el brazo en el plano escapular permite cargar tanto la porción corta como la larga.",
            bad: "Con barra recta se fuerza la supinación y puede molestar la muñeca; además es fácil compensar con balanceo del torso y perder tensión.",
            when: "Al inicio del trabajo de bíceps, 3-4 series de 8-12 reps con tempo controlado.",
            whenNot: "Con dolor de muñeca o codo, o al final del entreno cuando el agarre ya está fatigado."
        ),
        make(
            keywords: ["pushdown", "extension de triceps", "extension triceps", "triceps", "press frances", "skull", "fondos", "patada de triceps", "kickback"],
            primary: [.triceps],
            secondary: [.forearms],
            compound: false,
            straps: false,
            reps: "10-15",
            good: "Aísla el tríceps con tensión constante y permite trabajar alto volumen cerca del fallo sin apenas fatiga sistémica.",
            bad: "El cable favorece el pico de tensión en la extensión y relaja el estiramiento; con cargas excesivas se compensa con hombro y torso.",
            when: "Al final del entreno de empuje para completar el volumen de tríceps con 2-3 series de 10-15 reps.",
            whenNot: "Con dolor de codo en extensión forzada o si buscas el estímulo del tríceps largo estirado, que pide trabajo por encima de la cabeza."
        )
    ]

    private static let coreProfiles: [ExerciseKnowledgeProfile] = [
        make(
            keywords: ["crunch", "abdominales", "plancha", "elevacion de piernas", "rueda abdominal", "ab wheel", "core"],
            primary: [.abs],
            secondary: [.lowerBack],
            compound: false,
            straps: false,
            reps: "12-20",
            good: "Trabaja la flexión y la anti-extensión del tronco con un coste sistémico bajo, útil para reforzar el core sin interferir con el resto de la sesión.",
            bad: "El rango es corto y es fácil tirar del cuello o usar inercia; sin control del tempo el estímulo real es muy bajo.",
            when: "Al final de cualquier sesión, 2-3 series de 12-20 reps o isométricos de 30-45 segundos.",
            whenNot: "Con dolor cervical o lumbar agudo, o justo antes de levantamientos pesados que necesitan el core fresco."
        )
    ]

    private static let allProfiles: [ExerciseKnowledgeProfile] =
        pressProfiles + pullProfiles + legProfiles + armProfiles + coreProfiles
}
