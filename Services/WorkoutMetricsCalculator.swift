import Foundation

// MARK: - Resultado de métricas

struct WorkoutMetrics {
    let totalVolumeKg: Double
    let duration: TimeInterval
    let durationFormatted: String
    let medianExerciseGap: TimeInterval
    let medianExerciseGapFormatted: String
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

struct ExerciseHeartRateRow: Identifiable {
    let id: UUID
    let exerciseName: String
    let peakBPM: Int
    let previousLowBPM: Int
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
        let gap: TimeInterval = medianInterExerciseGap(records: records)
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

        let gapFormatted: String = records.count >= 2 ? formatInterval(gap) : "—"

        return WorkoutMetrics(
            totalVolumeKg: volume,
            duration: duration,
            durationFormatted: formatDuration(duration),
            medianExerciseGap: gap,
            medianExerciseGapFormatted: gapFormatted,
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

    // MARK: Mediana entre ejercicios

    private static func medianInterExerciseGap(records: [WorkoutExerciseRecord]) -> TimeInterval {
        guard records.count >= 2 else { return 0 }

        let startTimes: [Date] = records.map { (record: WorkoutExerciseRecord) -> Date in
            return record.exerciseStartTime
        }.sorted()

        var intervals: [TimeInterval] = []
        for index in 1..<startTimes.count {
            let interval: TimeInterval = startTimes[index].timeIntervalSince(startTimes[index - 1])
            if interval > 0 {
                intervals.append(interval)
            }
        }
        return median(intervals)
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted: [TimeInterval] = values.sorted()
        guard !sorted.isEmpty else { return 0 }

        let middle: Int = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2.0
        }
        return sorted[middle]
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
