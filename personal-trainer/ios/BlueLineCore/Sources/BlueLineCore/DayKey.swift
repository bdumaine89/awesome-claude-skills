import Foundation

/// Local calendar day as "YYYY-MM-DD", the web app's day key. String order equals date order.
public enum DayKey {
    /// The athlete's home zone; the web app keys days in Mountain Time.
    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Edmonton") ?? .current
        return c
    }()

    public static func from(_ date: Date, calendar cal: Calendar = DayKey.calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Start of that day (local midnight), or nil for a malformed key.
    public static func date(_ key: String, calendar cal: Calendar = DayKey.calendar) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    public static func adding(_ days: Int, to key: String, calendar cal: Calendar = DayKey.calendar) -> String {
        guard let d = date(key, calendar: cal), let n = cal.date(byAdding: .day, value: days, to: d) else { return key }
        return from(n, calendar: cal)
    }

    /// Whole calendar days from `a` to `b` (DST-safe).
    public static func days(from a: String, to b: String, calendar cal: Calendar = DayKey.calendar) -> Int {
        guard let da = date(a, calendar: cal), let db = date(b, calendar: cal) else { return 0 }
        return cal.dateComponents([.day], from: da, to: db).day ?? 0
    }

    public static func today(calendar cal: Calendar = DayKey.calendar) -> String { from(Date(), calendar: cal) }
}

/// JavaScript `Math.round` (half rounds toward +∞), so ports match the web app on negatives too.
@inlinable public func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

/// `r5()` in the web app: round to the nearest `step`.
@inlinable public func roundTo(_ x: Double, step: Double = 5) -> Double { jsRound(x / step) * step }

@inlinable public func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, x)) }

/// "52.5" or "50": the web app prints numbers without trailing ".0".
public func fmtNum(_ x: Double) -> String {
    x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
}
