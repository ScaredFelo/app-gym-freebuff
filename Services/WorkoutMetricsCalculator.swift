import Foundation

// MARK: - Resultado de métricas

struct WorkoutMetrics {
    let totalVolumeKg: Double
    let duration: TimeInterval
    let durationFormatted: String
    let averageTimeBetweenSets: TimeInterval
    let averageTimeBetweenSetsFormatted: String
    let averageBPM: Double
    let maxBPMAbsolute: Int
    let maxBPMAverage: Double
    let minBPMAbsolute: Int
    let minBPMAverage: Double
    let exerciseHeartRateRows: [ExerciseHeartRateRow]
    let edwardsTrainingLoad: Double
    let trimp: Double
    let recoveryRate: Double
    let cardiovascularDensity: Double

    var hasHeartRateData: Bool {
        return maxBPMAbsolute > 0 || minBPMAbsolute > 0 || averageBPM > 0
    }
}

// MARK: - Resultado de métricas de cardio

/// Resumen de una sesión de cardio. No hay series ni peso levantado, así que
/// solo se publican los valores que se pueden calcular con tiempo y pulsaciones.
struct CardioMetrics {
    let duration: TimeInterval
    let durationFormatted: String
    let averageBPM: Double
    let maxBPM: Int
    let minBPM: Int
    let edwardsTrainingLoad: Double
    let trimp: Double
    /// FC máxima con la que se han calculado las zonas y la carga.
    let hrMax: Double
    /// Tiempo medido en cada zona Z1–Z5.
    let zones: [CardioZoneMetrics]

    var hasHeartRateData: Bool {
        return maxBPM > 0 || averageBPM > 0
    }
}

/// Tiempo medido dentro de una zona de frecuencia cardíaca.
struct CardioZoneMetrics: Identifiable {
    let id: Int
    let lowerFraction: Double
    let upperFraction: Double
    let seconds: TimeInterval
    /// Parte del tiempo en zona que corresponde a esta zona (0...1).
    let fraction: Double

    var percent: Int {
        return Int((fraction * 100.0).rounded())
    }
}

struct ExerciseHeartRateRow: Identifiable {
    let id: UUID
    let exerciseName: String
    let peakBPM: Int
    let previousLowBPM: Int
}

// MARK: - Comparativa con la última sesión

/// Fila de la comparativa entre la sesión de cardio revisada y la última del
/// mismo tipo: valor actual, valor anterior y diferencia entre ambos.
struct CardioComparisonRow: Identifiable {
    let id: String
    let code: String
    let title: String
    let currentValue: String
    let previousValue: String
    let delta: Double
    let deltaText: String

    /// Signo de la diferencia: 1 sube, -1 baja, 0 se mantiene. La vista lo usa
    /// solo para elegir el color, no para valorar si es mejor o peor.
    var direction: Int {
        if delta > 0.0 { return 1 }
        if delta < 0.0 { return -1 }
        return 0
    }
}

/// Estadísticas de una sesión de cardio frente a las de la anterior.
struct CardioComparison {
    let previousDate: Date
    let rows: [CardioComparisonRow]
}

// MARK: - Motor de cálculo

/// Cálculos fisiológicos y de carga de la sesión. Se mantiene fuera de
/// SwiftUI y con tipos explícitos para aligerar la inferencia del compilador.
enum WorkoutMetricsCalculator {
    static let fallbackHRMax: Double = 190
    static let fallbackHRRest: Double = 60

    // MARK: API pública

    static func calculate(for session: WorkoutSession) -> WorkoutMetrics {
        let records: [WorkoutExerciseRecord] = exerciseRecords(for: session)
        let samples: [BPMSample] = bpmSamples(for: session)
        let hrMax: Double = resolvedHRMax()
        let hrRest: Double = resolvedHRRest(hrMax: hrMax)

        let endDate: Date = session.endDate ?? Date()
        let duration: TimeInterval = max(0, endDate.timeIntervalSince(session.startDate))
        let volume: Double = totalVolume(for: session)
        let averageSetGap: TimeInterval = averageInterSetInterval(records: records)
        let stats: HeartRateStats = heartRateStats(records: records, samples: samples)
        let averageBPM: Double = averageValue(samples: samples)
        let edwards: Double = edwardsTrainingLoad(samples: samples, hrMax: hrMax)
        let trimpValue: Double = trimpLoad(
            duration: duration,
            averageBPM: averageBPM,
            hrMax: hrMax,
            hrRest: hrRest
        )
        let recovery: Double = recoveryRate(records: records, samples: samples)
        let density: Double = volume / max(trimpValue, 1.0)

        let averageSetGapFormatted: String = formattedSetInterval(averageSetGap)

        return WorkoutMetrics(
            totalVolumeKg: volume,
            duration: duration,
            durationFormatted: formatDuration(duration),
            averageTimeBetweenSets: averageSetGap,
            averageTimeBetweenSetsFormatted: averageSetGapFormatted,
            averageBPM: averageBPM,
            maxBPMAbsolute: stats.maxAbsolute,
            maxBPMAverage: stats.maxAverage,
            minBPMAbsolute: stats.minAbsolute,
            minBPMAverage: stats.minAverage,
            exerciseHeartRateRows: stats.rows,
            edwardsTrainingLoad: edwards,
            trimp: trimpValue,
            recoveryRate: recovery,
            cardiovascularDensity: density
        )
    }

    /// Métricas de una sesión de cardio: tiempo, pulsaciones y carga. El
    /// volumen, la densidad cardiovascular y la recuperación entre series no
    /// se calculan porque no hay series ni kg.
    static func calculateCardio(duration: TimeInterval, samples: [BPMSample]) -> CardioMetrics {
        let sorted: [BPMSample] = samples.sorted { (lhs: BPMSample, rhs: BPMSample) -> Bool in
            return lhs.timestamp < rhs.timestamp
        }
        let hrMax: Double = resolvedHRMax()
        let hrRest: Double = resolvedHRRest(hrMax: hrMax)
        let averageBPM: Double = averageValue(samples: sorted)
        let edwards: Double = edwardsTrainingLoad(samples: sorted, hrMax: hrMax)
        let trimpValue: Double = trimpLoad(
            duration: duration,
            averageBPM: averageBPM,
            hrMax: hrMax,
            hrRest: hrRest
        )
        let values: [Int] = sorted.map { (sample: BPMSample) -> Int in
            return Int(sample.bpm.rounded())
        }.filter { (value: Int) -> Bool in
            return value > 0
        }
        let zones: [CardioZoneMetrics] = zoneDistribution(samples: sorted, hrMax: hrMax)

        return CardioMetrics(
            duration: duration,
            durationFormatted: formatDuration(duration),
            averageBPM: averageBPM,
            maxBPM: values.max() ?? 0,
            minBPM: values.min() ?? 0,
            edwardsTrainingLoad: edwards,
            trimp: trimpValue,
            hrMax: hrMax,
            zones: zones
        )
    }

    /// Compara la sesión de cardio revisada con la última del mismo tipo. Las
    /// filas siguen el orden del informe: tiempo, pulsaciones y carga. Cuando
    /// alguna de las dos sesiones no tiene telemetría cardíaca, las métricas
    /// que dependen de ella se marcan sin comparación.
    static func compareCardio(
        current: CardioMetrics,
        previous: CardioMetrics,
        previousDate: Date
    ) -> CardioComparison {
        let hasHeartRate: Bool = current.hasHeartRateData && previous.hasHeartRateData
        let durationDelta: TimeInterval = current.duration - previous.duration
        let averageDelta: Double = hasHeartRate ? current.averageBPM - previous.averageBPM : 0.0
        let maxDelta: Double = hasHeartRate ? Double(current.maxBPM - previous.maxBPM) : 0.0
        let edwardsDelta: Double = hasHeartRate ? current.edwardsTrainingLoad - previous.edwardsTrainingLoad : 0.0
        let trimpDelta: Double = hasHeartRate ? current.trimp - previous.trimp : 0.0

        func row(
            id: String,
            code: String,
            title: String,
            currentValue: String,
            previousValue: String,
            delta: Double,
            deltaText: String
        ) -> CardioComparisonRow {
            return CardioComparisonRow(
                id: id,
                code: code,
                title: title,
                currentValue: currentValue,
                previousValue: previousValue,
                delta: delta,
                deltaText: deltaText
            )
        }

        let rows: [CardioComparisonRow] = [
            row(
                id: "duration",
                code: "T+",
                title: "TIEMPO",
                currentValue: current.durationFormatted,
                previousValue: previous.durationFormatted,
                delta: durationDelta,
                deltaText: signedDuration(durationDelta)
            ),
            row(
                id: "averageBPM",
                code: "MEDIA",
                title: "BPM MEDIOS",
                currentValue: hasHeartRate ? "\(Int(current.averageBPM.rounded()))" : "—",
                previousValue: hasHeartRate ? "\(Int(previous.averageBPM.rounded()))" : "—",
                delta: averageDelta,
                deltaText: signedInteger(averageDelta)
            ),
            row(
                id: "maxBPM",
                code: "PICO",
                title: "BPM MÁX",
                currentValue: hasHeartRate ? "\(current.maxBPM)" : "—",
                previousValue: hasHeartRate ? "\(previous.maxBPM)" : "—",
                delta: maxDelta,
                deltaText: signedInteger(maxDelta)
            ),
            row(
                id: "edwards",
                code: "EDW",
                title: "CARGA EDWARDS",
                currentValue: hasHeartRate ? String(format: "%.0f", current.edwardsTrainingLoad) : "—",
                previousValue: hasHeartRate ? String(format: "%.0f", previous.edwardsTrainingLoad) : "—",
                delta: edwardsDelta,
                deltaText: signedInteger(edwardsDelta)
            ),
            row(
                id: "trimp",
                code: "TRIMP",
                title: "TRIMP BANISTER",
                currentValue: hasHeartRate ? String(format: "%.1f", current.trimp) : "—",
                previousValue: hasHeartRate ? String(format: "%.1f", previous.trimp) : "—",
                delta: trimpDelta,
                deltaText: signedDecimal(trimpDelta)
            )
        ]

        return CardioComparison(previousDate: previousDate, rows: rows)
    }

    /// Diferencia de tiempo con signo, en el mismo formato que el informe.
    private static func signedDuration(_ delta: TimeInterval) -> String {
        let rounded: Int = Int(delta.rounded())
        guard rounded != 0 else { return "0" }
        return (rounded > 0 ? "+" : "\u{2212}") + formatDuration(TimeInterval(abs(rounded)))
    }

    /// Diferencia entera con signo (BPM, carga de Edwards).
    private static func signedInteger(_ delta: Double) -> String {
        let rounded: Int = Int(delta.rounded())
        guard rounded != 0 else { return "0" }
        return (rounded > 0 ? "+" : "\u{2212}") + "\(abs(rounded))"
    }

    /// Diferencia con un decimal y signo (TRIMP).
    private static func signedDecimal(_ delta: Double) -> String {
        let rounded: Double = (delta * 10.0).rounded() / 10.0
        guard rounded != 0 else { return "0" }
        return (rounded > 0 ? "+" : "\u{2212}") + String(format: "%.1f", abs(rounded))
    }

    /// Construye los registros detallados de ejercicios y series a partir de
    /// los `WorkoutSetLog` persistidos. Se usa al finalizar la sesión para que
    /// el review y el histórico dispongan de marcas temporales completas.
    static func buildExerciseRecords(for session: WorkoutSession) -> [WorkoutExerciseRecord] {
        let completedLogs: [WorkoutSetLog] = session.setsCompleted.filter { (log: WorkoutSetLog) -> Bool in
            return log.isCompleted
        }
        let sortedLogs: [WorkoutSetLog] = completedLogs.sorted { (lhs: WorkoutSetLog, rhs: WorkoutSetLog) -> Bool in
            return lhs.date < rhs.date
        }
        guard !sortedLogs.isEmpty else { return [] }

        var nextCompletionByLogID: [UUID: Date] = [:]
        for index in 0..<sortedLogs.count {
            guard index + 1 < sortedLogs.count else { continue }
            nextCompletionByLogID[sortedLogs[index].id] = sortedLogs[index + 1].date
        }

        var groupedLogs: [String: [WorkoutSetLog]] = [:]
        for log in sortedLogs {
            let key: String = groupingKey(for: log)
            groupedLogs[key, default: []].append(log)
        }

        var records: [WorkoutExerciseRecord] = []
        for (_, logs) in groupedLogs {
            let exerciseLogs: [WorkoutSetLog] = logs.sorted { (lhs: WorkoutSetLog, rhs: WorkoutSetLog) -> Bool in
                return lhs.date < rhs.date
            }
            guard let firstLog: WorkoutSetLog = exerciseLogs.first,
                  let lastLog: WorkoutSetLog = exerciseLogs.last else { continue }

            var setRecords: [WorkoutSetRecord] = []
            for log in exerciseLogs {
                let rest: TimeInterval
                if let nextDate: Date = nextCompletionByLogID[log.id] {
                    rest = max(0, nextDate.timeIntervalSince(log.date))
                } else {
                    rest = 0
                }

                setRecords.append(WorkoutSetRecord(
                    id: log.id,
                    setNumber: log.setNumber ?? (setRecords.count + 1),
                    weight: log.weight,
                    reps: log.reps,
                    setCompletedTime: log.date,
                    restDuration: rest
                ))
            }

            let recordID: UUID = firstLog.routineExerciseID
                ?? firstLog.exercise?.id
                ?? UUID()

            records.append(WorkoutExerciseRecord(
                id: recordID,
                exerciseID: firstLog.exercise?.id,
                exerciseName: firstLog.exercise?.name ?? "Ejercicio",
                exerciseStartTime: firstLog.date,
                exerciseEndTime: lastLog.date,
                sets: setRecords
            ))
        }

        return records.sorted { (lhs: WorkoutExerciseRecord, rhs: WorkoutExerciseRecord) -> Bool in
            return lhs.exerciseStartTime < rhs.exerciseStartTime
        }
    }

    // MARK: Datos de entrada

    private static func bpmSamples(for session: WorkoutSession) -> [BPMSample] {
        let samples: [BPMSample] = session.bpmSamples
        return samples.sorted { (lhs: BPMSample, rhs: BPMSample) -> Bool in
            return lhs.timestamp < rhs.timestamp
        }
    }

    private static func exerciseRecords(for session: WorkoutSession) -> [WorkoutExerciseRecord] {
        let stored: [WorkoutExerciseRecord] = session.exerciseRecords
        if !stored.isEmpty {
            return stored.sorted { (lhs: WorkoutExerciseRecord, rhs: WorkoutExerciseRecord) -> Bool in
                return lhs.exerciseStartTime < rhs.exerciseStartTime
            }
        }
        return buildExerciseRecords(for: session)
    }

    private static func groupingKey(for log: WorkoutSetLog) -> String {
        if let routineExerciseID: UUID = log.routineExerciseID {
            return routineExerciseID.uuidString
        }
        if let exerciseID: UUID = log.exercise?.id {
            return exerciseID.uuidString
        }
        return log.exercise?.name ?? "ejercicio-sin-identificador"
    }

    // MARK: Volumen y duración

    private static func totalVolume(for session: WorkoutSession) -> Double {
        let completedLogs: [WorkoutSetLog] = session.setsCompleted.filter { (log: WorkoutSetLog) -> Bool in
            return log.isCompleted
        }
        let volume: Double = completedLogs.reduce(0.0) { (total: Double, log: WorkoutSetLog) -> Double in
            return total + log.weight * Double(log.reps)
        }
        return volume
    }

    // MARK: Media de tiempo entre series

    /// Media aritmética del tiempo transcurrido entre cada par de series
    /// consecutivas de la sesión, ordenadas cronológicamente por su marca de
    /// finalización.
    private static func averageInterSetInterval(records: [WorkoutExerciseRecord]) -> TimeInterval {
        let sets: [WorkoutSetRecord] = records
            .flatMap { (record: WorkoutExerciseRecord) -> [WorkoutSetRecord] in
                return record.sets
            }
            .sorted { (lhs: WorkoutSetRecord, rhs: WorkoutSetRecord) -> Bool in
                return lhs.setCompletedTime < rhs.setCompletedTime
            }

        guard sets.count >= 2 else { return 0 }

        var intervals: [TimeInterval] = []
        for index in 1..<sets.count {
            let interval: TimeInterval = sets[index].setCompletedTime
                .timeIntervalSince(sets[index - 1].setCompletedTime)
            if interval > 0 {
                intervals.append(interval)
            }
        }

        // Sin marcas consecutivas válidas usamos los descansos registrados.
        guard !intervals.isEmpty else {
            return averageRegisteredRest(sets: sets)
        }

        let total: TimeInterval = intervals.reduce(0.0) { (sum: TimeInterval, value: TimeInterval) -> TimeInterval in
            return sum + value
        }
        return total / TimeInterval(intervals.count)
    }

    private static func averageRegisteredRest(sets: [WorkoutSetRecord]) -> TimeInterval {
        let rests: [TimeInterval] = sets.compactMap { (set: WorkoutSetRecord) -> TimeInterval? in
            return set.restDuration > 0 ? set.restDuration : nil
        }
        guard !rests.isEmpty else { return 0 }

        let total: TimeInterval = rests.reduce(0.0) { (sum: TimeInterval, value: TimeInterval) -> TimeInterval in
            return sum + value
        }
        return total / TimeInterval(rests.count)
    }

    // MARK: Frecuencia cardíaca por ejercicio

    private struct HeartRateStats {
        let maxAbsolute: Int
        let maxAverage: Double
        let minAbsolute: Int
        let minAverage: Double
        let rows: [ExerciseHeartRateRow]

        static let empty = HeartRateStats(
            maxAbsolute: 0,
            maxAverage: 0,
            minAbsolute: 0,
            minAverage: 0,
            rows: []
        )
    }

    private static func heartRateStats(
        records: [WorkoutExerciseRecord],
        samples: [BPMSample]
    ) -> HeartRateStats {
        guard !records.isEmpty, !samples.isEmpty else { return .empty }

        var rows: [ExerciseHeartRateRow] = []
        var peaks: [Int] = []
        var lows: [Int] = []

        for index in 0..<records.count {
            let record: WorkoutExerciseRecord = records[index]

            let peakSamples: [BPMSample] = samples.filter { (sample: BPMSample) -> Bool in
                return sample.timestamp >= record.exerciseStartTime &&
                    sample.timestamp <= record.exerciseEndTime
            }
            let peak: Int = peakSamples.map { (sample: BPMSample) -> Int in
                return Int(sample.bpm.rounded())
            }.max() ?? 0

            let previousEnd: Date
            if index == 0 {
                previousEnd = record.exerciseStartTime.addingTimeInterval(-60.0)
            } else {
                previousEnd = records[index - 1].exerciseEndTime
            }
            let latestWindowStart: Date = record.exerciseStartTime.addingTimeInterval(-1.0)
            let windowStart: Date = min(previousEnd, latestWindowStart)

            let lowSamples: [BPMSample] = samples.filter { (sample: BPMSample) -> Bool in
                return sample.timestamp >= windowStart &&
                    sample.timestamp <= record.exerciseStartTime
            }
            let low: Int = lowSamples.map { (sample: BPMSample) -> Int in
                return Int(sample.bpm.rounded())
            }.min() ?? 0

            if peak > 0 {
                peaks.append(peak)
            }
            if low > 0 {
                lows.append(low)
            }

            rows.append(ExerciseHeartRateRow(
                id: record.id,
                exerciseName: record.exerciseName,
                peakBPM: peak,
                previousLowBPM: low
            ))
        }

        return HeartRateStats(
            maxAbsolute: peaks.max() ?? 0,
            maxAverage: averageIntegers(peaks),
            minAbsolute: lows.min() ?? 0,
            minAverage: averageIntegers(lows),
            rows: rows
        )
    }

    private static func averageIntegers(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        let total: Int = values.reduce(0) { (sum: Int, value: Int) -> Int in
            return sum + value
        }
        return Double(total) / Double(values.count)
    }

    private static func averageValue(samples: [BPMSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let total: Double = samples.reduce(0.0) { (sum: Double, sample: BPMSample) -> Double in
            return sum + sample.bpm
        }
        return total / Double(samples.count)
    }

    private static func averageDoubles(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let total: Double = values.reduce(0.0) { (sum: Double, value: Double) -> Double in
            return sum + value
        }
        return total / Double(values.count)
    }

    // MARK: Carga de Edwards

    private static func edwardsTrainingLoad(samples: [BPMSample], hrMax: Double) -> Double {
        guard samples.count >= 2, hrMax > 0 else { return 0 }

        var load: Double = 0
        for index in 0..<(samples.count - 1) {
            let current: BPMSample = samples[index]
            let next: BPMSample = samples[index + 1]
            let minutes: Double = next.timestamp.timeIntervalSince(current.timestamp) / 60.0

            // Ignoramos huecos anómalos (app pausada, lecturas perdidas).
            guard minutes > 0, minutes <= 5.0 else { continue }

            let ratio: Double = current.bpm / hrMax
            let weight: Double = edwardsZoneWeight(for: ratio)
            load += minutes * weight
        }
        return load
    }

    private static func edwardsZoneWeight(for ratio: Double) -> Double {
        if ratio < 0.50 {
            return 0.0
        }
        if ratio < 0.60 {
            return 1.0
        }
        if ratio < 0.70 {
            return 2.0
        }
        if ratio < 0.80 {
            return 3.0
        }
        if ratio < 0.90 {
            return 4.0
        }
        return 5.0
    }

    // MARK: Distribución por zonas de FC

    /// Cortes de zona como fracción de la FC máxima. Coinciden con los pesos
    /// de Edwards para que ambos cálculos cuenten el mismo esfuerzo.
    static let heartRateZoneBounds: [(index: Int, lower: Double, upper: Double)] = [
        (1, 0.50, 0.60),
        (2, 0.60, 0.70),
        (3, 0.70, 0.80),
        (4, 0.80, 0.90),
        (5, 0.90, 1.10)
    ]

    /// Tiempo medido en cada zona: cada muestra se atribuye a la zona de su
    /// pulso hasta la siguiente lectura. Los huecos de más de cinco minutos
    /// (app suspendida, sensor caído) no cuentan, igual que en Edwards.
    static func zoneDistribution(samples: [BPMSample], hrMax: Double) -> [CardioZoneMetrics] {
        var seconds: [Double] = [0, 0, 0, 0, 0]

        if samples.count >= 2, hrMax > 0 {
            for index in 0..<(samples.count - 1) {
                let current: BPMSample = samples[index]
                let next: BPMSample = samples[index + 1]
                let gap: TimeInterval = next.timestamp.timeIntervalSince(current.timestamp)
                guard gap > 0, gap <= 5 * 60 else { continue }

                let ratio: Double = current.bpm / hrMax
                guard ratio >= 0.50 else { continue }

                let zone: Int = heartRateZoneIndex(for: ratio)
                seconds[zone - 1] += gap
            }
        }

        let total: Double = seconds.reduce(0.0, +)

        return heartRateZoneBounds.map { (bound: (index: Int, lower: Double, upper: Double)) -> CardioZoneMetrics in
            let zoneSeconds: Double = seconds[bound.index - 1]
            return CardioZoneMetrics(
                id: bound.index,
                lowerFraction: bound.lower,
                upperFraction: bound.upper,
                seconds: zoneSeconds,
                fraction: total > 0 ? zoneSeconds / total : 0
            )
        }
    }

    private static func heartRateZoneIndex(for ratio: Double) -> Int {
        switch ratio {
        case ..<0.60:
            return 1
        case ..<0.70:
            return 2
        case ..<0.80:
            return 3
        case ..<0.90:
            return 4
        default:
            return 5
        }
    }

    // MARK: TRIMP de Banister

    private static func trimpLoad(
        duration: TimeInterval,
        averageBPM: Double,
        hrMax: Double,
        hrRest: Double
    ) -> Double {
        guard duration > 0, hrMax > hrRest, averageBPM > 0 else { return 0 }

        let deltaHR: Double = min(1.0, max(0.0, (averageBPM - hrRest) / (hrMax - hrRest)))
        let minutes: Double = duration / 60.0
        return minutes * deltaHR * 0.64 * exp(1.92 * deltaHR)
    }

    // MARK: Recuperación cardíaca entre series

    private static func recoveryRate(
        records: [WorkoutExerciseRecord],
        samples: [BPMSample]
    ) -> Double {
        guard !samples.isEmpty else { return 0 }

        var rates: [Double] = []

        for record in records {
            let sets: [WorkoutSetRecord] = record.sets.sorted { (lhs: WorkoutSetRecord, rhs: WorkoutSetRecord) -> Bool in
                return lhs.setCompletedTime < rhs.setCompletedTime
            }

            for index in 0..<sets.count {
                let set: WorkoutSetRecord = sets[index]
                let rest: TimeInterval
                if set.restDuration > 0 {
                    rest = set.restDuration
                } else if index + 1 < sets.count {
                    rest = sets[index + 1].setCompletedTime.timeIntervalSince(set.setCompletedTime)
                } else {
                    rest = 0
                }
                guard rest > 0 else { continue }

                let restEnd: Date = set.setCompletedTime.addingTimeInterval(rest)
                let peakWindowStart: Date = set.setCompletedTime.addingTimeInterval(-30.0)

                let peakSamples: [BPMSample] = samples.filter { (sample: BPMSample) -> Bool in
                    return sample.timestamp >= peakWindowStart &&
                        sample.timestamp <= set.setCompletedTime
                }
                let lowSamples: [BPMSample] = samples.filter { (sample: BPMSample) -> Bool in
                    return sample.timestamp > set.setCompletedTime &&
                        sample.timestamp <= restEnd
                }

                guard let peak: Double = peakSamples.map({ (sample: BPMSample) -> Double in
                    return sample.bpm
                }).max(),
                      let low: Double = lowSamples.map({ (sample: BPMSample) -> Double in
                    return sample.bpm
                }).min(),
                      peak > low else { continue }

                let minutes: Double = rest / 60.0
                guard minutes > 0 else { continue }
                rates.append((peak - low) / minutes)
            }
        }

        return averageDoubles(rates)
    }

    // MARK: Ajustes de usuario

    private static func resolvedHRMax() -> Double {
        let stored: Double = UserSettingsManager.hrMax
        return stored > 0 ? stored : fallbackHRMax
    }

    private static func resolvedHRRest(hrMax: Double) -> Double {
        let stored: Double = UserSettingsManager.hrRest
        let candidate: Double = stored > 0 ? stored : fallbackHRRest
        return min(candidate, max(0, hrMax - 1.0))
    }

    // MARK: Formato

    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds: Int = max(0, Int(duration.rounded()))
        let hours: Int = totalSeconds / 3600
        let minutes: Int = (totalSeconds % 3600) / 60
        let seconds: Int = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        if minutes > 0 {
            return "\(minutes) min"
        }
        return "\(seconds) s"
    }

    /// Formato compacto minuto:segundo para la media entre series.
    static func formattedSetInterval(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "—" }

        let totalSeconds: Int = max(0, Int(interval.rounded()))
        let minutes: Int = totalSeconds / 60
        let seconds: Int = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func formatInterval(_ interval: TimeInterval) -> String {
        let totalSeconds: Int = max(0, Int(interval.rounded()))
        let minutes: Int = totalSeconds / 60
        let seconds: Int = totalSeconds % 60

        if minutes > 0 {
            return "\(minutes) min \(seconds) s"
        }
        return "\(seconds) s"
    }
}
