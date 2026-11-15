import Foundation
import HealthKit
import BlueLineCore

/// HealthKit access for the iPhone app. Withings (weight, body fat %) and the Watch (energy, HRV, RHR,
/// sleep, workouts) already write to Health, so reading Health covers them; there is no direct Withings API here.
/// UNTESTED on device: written without Xcode; verify on hardware.
@MainActor final class HealthService {
    let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let dietary: [HKQuantityTypeIdentifier] = [.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal]

    private var readTypes: Set<HKObjectType> {
        let q: [HKQuantityTypeIdentifier] = [.activeEnergyBurned, .basalEnergyBurned, .heartRateVariabilitySDNN,
                                             .restingHeartRate, .bodyMass, .bodyFatPercentage, .stepCount] + Self.dietary
        return Set(q.map { HKQuantityType($0) as HKObjectType } + [HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()])
    }

    private var shareTypes: Set<HKSampleType> {
        Set(Self.dietary.map { HKQuantityType($0) as HKSampleType } + [HKObjectType.workoutType()])
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: Reading

    enum Aggregate { case sum, average, latest }

    /// One value per local day via `HKStatisticsCollectionQuery` (sums de-duplicate iPhone + Watch overlap).
    func daily(_ id: HKQuantityTypeIdentifier, unit: HKUnit, _ agg: Aggregate, days: Int) async throws -> [String: Double] {
        let cal = DayKey.calendar
        let end = Date()
        let anchor = cal.startOfDay(for: end)
        let start = cal.date(byAdding: .day, value: -days, to: anchor)!
        let options: HKStatisticsOptions = agg == .sum ? .cumulativeSum : (agg == .average ? .discreteAverage : .mostRecent)
        let query = HKStatisticsCollectionQuery(
            quantityType: HKQuantityType(id),
            quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
            options: options, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
        return try await withCheckedThrowingContinuation { cont in
            query.initialResultsHandler = { _, results, error in
                if let error { cont.resume(throwing: error); return }
                var out: [String: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { s, _ in
                    let q: HKQuantity?
                    switch agg {
                    case .sum: q = s.sumQuantity()
                    case .average: q = s.averageQuantity()
                    case .latest: q = s.mostRecentQuantity()
                    }
                    if let v = q?.doubleValue(for: unit) { out[DayKey.from(s.startDate, calendar: cal)] = v }
                }
                cont.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Hours asleep (core + deep + REM + unspecified), keyed to the wake day. Overlapping samples from
    /// several sources are merged so they are not double-counted.
    func sleepHours(days: Int) async throws -> [String: Double] {
        let cal = DayKey.calendar
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now))!
        let asleep: Set<Int> = Set([HKCategoryValueSleepAnalysis.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM].map(\.rawValue))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await descriptor.result(for: store).filter { asleep.contains($0.value) }
        var byDay: [String: [(Date, Date)]] = [:]
        for s in samples { byDay[DayKey.from(s.endDate, calendar: cal), default: []].append((s.startDate, s.endDate)) }
        return byDay.mapValues { (intervals: [(Date, Date)]) -> Double in
            var total: TimeInterval = 0
            var cur: (Date, Date)?
            for iv in intervals.sorted(by: { $0.0 < $1.0 }) {
                if let c = cur, iv.0 <= c.1 { cur = (c.0, max(c.1, iv.1)) } else {
                    if let c = cur { total += c.1.timeIntervalSince(c.0) }
                    cur = iv
                }
            }
            if let c = cur { total += c.1.timeIntervalSince(c.0) }
            return total / 3600
        }
    }

    func workouts(days: Int) async throws -> [HKWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }

    struct Snapshot {
        var active: [String: Double] = [:], basal: [String: Double] = [:], steps: [String: Double] = [:]
        var hrv: [String: Double] = [:], rhr: [String: Double] = [:], weightLb: [String: Double] = [:]
        var bodyFatPct: [String: Double] = [:], sleepH: [String: Double] = [:], sportKcal: [String: Double] = [:]
        var dates: Set<String> {
            Set([active, basal, steps, hrv, rhr, weightLb, bodyFatPct, sleepH, sportKcal].flatMap(\.keys))
        }
    }

    /// Everything the Today/Body/Fuel screens need, for the last `days` days.
    func snapshot(days: Int = 60, weightLb: Double) async throws -> Snapshot {
        let kcal = HKUnit.kilocalorie()
        var s = Snapshot()
        s.active = try await daily(.activeEnergyBurned, unit: kcal, .sum, days: days)
        s.basal = try await daily(.basalEnergyBurned, unit: kcal, .sum, days: days)
        s.steps = try await daily(.stepCount, unit: .count(), .sum, days: days)
        s.hrv = try await daily(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), .average, days: days)
        s.rhr = try await daily(.restingHeartRate, unit: .count().unitDivided(by: .minute()), .average, days: days)
        s.weightLb = try await daily(.bodyMass, unit: .pound(), .latest, days: max(days, 180))
        s.bodyFatPct = try await daily(.bodyFatPercentage, unit: .percent(), .latest, days: days).mapValues { $0 * 100 }
        s.sleepH = try await sleepHours(days: days)
        // Hockey and golf: Watch active energy if recorded, else the MET estimate.
        for w in try await workouts(days: days) {
            let type: ActivityType
            switch w.workoutActivityType {
            case .hockey: type = .hockey
            case .golf: type = .golfwalk
            default: continue
            }
            let measured = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: kcal)
            let est = type.netKcal(minutes: w.duration / 60, weightLb: weightLb)
            s.sportKcal[DayKey.from(w.startDate), default: 0] += measured ?? est
        }
        return s
    }

    // MARK: Writing

    /// Save a phone-logged strength session. Sessions run on the Watch are saved there instead.
    func saveStrengthWorkout(start: Date, end: Date, title: String) async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Blue Line Training", "BLSession": title])
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    private static let mealKey = "BLMealID"

    /// Write a meal as a food correlation (energy, protein, carbs, fat).
    func saveMeal(id: String, name: String, time: Date, kcal: Double, protein: Double, carbs: Double, fat: Double) async throws {
        let meta: [String: Any] = [HKMetadataKeyFoodType: name, Self.mealKey: id]
        let values: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.dietaryEnergyConsumed, .kilocalorie(), kcal), (.dietaryProtein, .gram(), protein),
            (.dietaryCarbohydrates, .gram(), carbs), (.dietaryFatTotal, .gram(), fat)]
        let samples: Set<HKSample> = Set(values.filter { $0.2 > 0 }.map { t, unit, v in
            HKQuantitySample(type: HKQuantityType(t), quantity: HKQuantity(unit: unit, doubleValue: v),
                             start: time, end: time, metadata: meta) as HKSample
        })
        guard !samples.isEmpty else { return }
        let food = HKCorrelation(type: HKCorrelationType(.food), start: time, end: time, objects: samples, metadata: meta)
        try await store.save(food)
    }

    /// Remove a meal's samples (matched by our metadata id). Fire-and-forget.
    func deleteMeal(id: String) {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.mealKey, allowedValues: [id])
        for t in Self.dietary {
            store.deleteObjects(of: HKQuantityType(t), predicate: predicate) { _, _, _ in }
        }
    }
}
