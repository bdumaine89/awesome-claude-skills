import Foundation

public enum TheilSen {
    /// Median of pairwise slopes (upper median for even counts, as in the web app).
    public static func slope(x: [Double], y: [Double]) -> Double {
        var s: [Double] = []
        for i in x.indices {
            for j in (i + 1)..<x.count where x[j] != x[i] {
                s.append((y[j] - y[i]) / (x[j] - x[i]))
            }
        }
        guard !s.isEmpty else { return 0 }
        s.sort()
        return s[s.count / 2]
    }
}

public struct WeighIn: Sendable, Hashable, Identifiable {
    public let date: String
    public let lb: Double
    public var id: String { date }
    public init(date: String, lb: Double) { self.date = date; self.lb = lb }
}

public struct TrendPoint: Sendable, Hashable, Identifiable {
    public let date: String
    public let lb: Double
    /// Gap-adjusted EMA.
    public let trend: Double
    public var id: String { date }
}

public struct Projection: Sendable, Hashable {
    /// lb per week (negative = losing).
    public let perWeek: Double
    /// Day the trend reaches the goal at the current rate, if losing.
    public let eta: String?
    public let trend: Double
    public let remaining: Double
}

public enum WeightTrend {
    /// `weightSeries()`: EMA with α = 1 − e^(−Δt/10), i.e. a 10-day time constant that respects gaps.
    public static func series(_ weighIns: [WeighIn]) -> [TrendPoint] {
        var ema: Double?
        var prev: String?
        return weighIns.sorted { $0.date < $1.date }.map { (w: WeighIn) -> TrendPoint in
            let dt = prev.map { Double(DayKey.days(from: $0, to: w.date)) } ?? 1
            let a = 1 - exp(-dt / 10)
            let e = ema.map { $0 + a * (w.lb - $0) } ?? w.lb
            ema = e
            prev = w.date
            return TrendPoint(date: w.date, lb: w.lb, trend: e)
        }
    }

    /// `projection()`: Theil–Sen over the last 28 days of raw weigh-ins (needs 6+ points spanning 10+ days).
    public static func projection(_ weighIns: [WeighIn], goalLb: Double) -> Projection? {
        let ser = weighIns.sorted { $0.date < $1.date }
        guard ser.count >= 4, let last = ser.last else { return nil }
        let cutoff = DayKey.adding(-28, to: last.date)
        let pts = ser.filter { $0.date >= cutoff }
        guard pts.count >= 6 else { return nil }
        let x = pts.map { Double(DayKey.days(from: pts[0].date, to: $0.date)) }
        let y = pts.map(\.lb)
        guard x.last! >= 10 else { return nil }
        let slope = TheilSen.slope(x: x, y: y)
        let intercepts = zip(x, y).map { $1 - slope * $0 }.sorted()
        let trend = intercepts[intercepts.count / 2] + slope * x.last!
        let remain = trend - goalLb
        let eta = slope < -0.005 && remain > 0 ? DayKey.adding(Int(jsRound(remain / -slope)), to: last.date) : nil
        return Projection(perWeek: slope * 7, eta: eta, trend: trend, remaining: remain)
    }
}
