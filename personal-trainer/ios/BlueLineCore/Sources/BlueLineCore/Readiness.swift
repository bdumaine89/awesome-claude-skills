import Foundation

/// Daily metrics the readiness and energy models need. Mirrors `days/<date>` minus meals.
public struct DayMetrics: Codable, Hashable, Sendable {
    public var date: String
    public var weight: Double?
    public var bodyFat: Double?
    public var activeKcal: Double?
    public var restingKcal: Double?
    public var steps: Double?
    public var hrv: Double?
    public var rhr: Double?
    public var sleepH: Double?
    /// Athlytic recovery %, typed in by hand (Athlytic doesn't write it to Health).
    public var recovery: Double?
    /// Logged intake for the day.
    public var intakeKcal: Double = 0
    public var mealCount: Int = 0
    /// Hockey + golf kcal for the day (for the sport adjustment).
    public var sportKcal: Double = 0

    public init(date: String) { self.date = date }
}

public enum ReadinessBand: String, Sendable {
    case green, yellow, red, none

    public init(score: Int?) {
        guard let s = score else { self = .none; return }
        self = s >= 67 ? .green : (s >= 34 ? .yellow : .red)
    }

    public var advice: String {
        switch self {
        case .green: return "Train as written. Push the top of the rep range."
        case .yellow: return "Train, but drop the last set of each superset and cap effort at RPE 7."
        case .red: return "Swap today for the Recovery session (Zone 2 + mobility). Protect sleep tonight."
        case .none: return "Enter your Athlytic recovery % or allow Health access to get a readiness call."
        }
    }
}

public struct Readiness: Sendable, Hashable {
    public let score: Int?
    public let source: String
    public var band: ReadinessBand { ReadinessBand(score: score) }
}

/// Port of `readiness()`: Athlytic recovery if entered, else HRV (log, 3-day mean) / RHR / sleep vs a 30-day baseline.
public enum ReadinessModel {
    /// - Parameters:
    ///   - day: today's metrics.
    ///   - history: any metrics; only the 30 days before `day.date` are used.
    public static func evaluate(_ day: DayMetrics, history: [DayMetrics]) -> Readiness? {
        if let r = day.recovery { return Readiness(score: Int(r), source: "Athlytic") }
        guard let todayHRV = day.hrv, todayHRV > 0 else { return nil }
        let prior = history
            .filter { let n = DayKey.days(from: $0.date, to: day.date); return n >= 1 && n <= 30 && ($0.hrv ?? 0) > 0 }
            .sorted { $0.date > $1.date }
        guard prior.count >= 5 else { return Readiness(score: nil, source: "need 5+ days of HRV for a baseline") }

        let H = stats(prior.map { log($0.hrv!) })
        let rhrs = prior.compactMap(\.rhr)
        let R: (mean: Double, sd: Double)? = rhrs.count >= 5 ? stats(rhrs) : nil
        let r3 = ([todayHRV] + prior.prefix(2).map { $0.hrv! }).map { log($0) }
        let zh = clamp((r3.reduce(0, +) / Double(r3.count) - H.mean) / H.sd, -2, 2)
        var zr = 0.0
        if let rhr = day.rhr, rhr > 0, let R { zr = clamp((rhr - R.mean) / R.sd, -2, 2) }
        let sl = day.sleepH.flatMap { s -> Double? in s > 0 ? clamp((s - 5) / 3, 0, 1) : nil } ?? 0.5
        let score = jsRound(clamp(55 + 16 * zh - 10 * zr + 30 * (sl - 0.5), 1, 99))
        return Readiness(score: Int(score), source: "HRV / RHR / sleep model")
    }

    /// Mean and population SD (SD 0 → 1, as in the web app).
    static func stats(_ a: [Double]) -> (mean: Double, sd: Double) {
        let m = a.reduce(0, +) / Double(a.count)
        let sd = (a.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(a.count)).squareRoot()
        return (m, sd == 0 ? 1 : sd)
    }
}
