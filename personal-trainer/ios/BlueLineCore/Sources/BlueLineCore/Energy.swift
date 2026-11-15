import Foundation

public enum Sex: String, Codable, Sendable { case male = "m", female = "f" }

/// `settings/profile`.
public struct Profile: Codable, Hashable, Sendable {
    public var start = "2026-11-16"
    public var age = 37
    public var heightCm = 172.7
    public var startLb = 182.0
    public var goalLb = 170.0
    public var sex = Sex.male
    public var loc = Location.gym
    public var hotelMax = 50.0
    public var deficit = 500.0
    public var protein = 175.0
    public var fat = 70.0
    public var neat = 1.4
    public var calib: [String: Double] = [:]
    public init() {}
}

/// Activity MET table (`ACT`). Net kcal = (MET − 1) × kg × h.
public enum ActivityType: String, Codable, Sendable, CaseIterable {
    case hockey, golfwalk, golfcart, range, strength, z2, walk

    public var name: String {
        switch self {
        case .hockey: return "Rec hockey"
        case .golfwalk: return "Golf, 18 walking"
        case .golfcart: return "Golf, 18 cart"
        case .range: return "Driving range"
        case .strength: return "Strength session"
        case .z2: return "Zone 2 cardio"
        case .walk: return "Walk"
        }
    }

    public var met: Double {
        switch self {
        case .hockey: return 7
        case .golfwalk: return 4.8
        case .golfcart: return 2.8
        case .range: return 3
        case .strength: return 4.5
        case .z2: return 6
        case .walk: return 3.5
        }
    }

    public var isSport: Bool { self == .hockey || self == .golfwalk || self == .golfcart }

    public func netKcal(minutes: Double, weightLb: Double) -> Double {
        jsRound((met - 1) * Energy.kg(weightLb) * minutes / 60)
    }
}

public struct TDEE: Sendable, Hashable {
    public let kcal: Double
    public let sportAvg: Double
    public let source: String
}

public struct Targets: Sendable, Hashable {
    public let kcal: Double
    public let protein: Double
    public let carbs: Double
    public let fat: Double
    public let tdee: TDEE
    public let sportKcal: Double
    public let sportAdjust: Double
}

public enum Energy {
    public static let floorKcal = 1800.0
    @inlinable public static func kg(_ lb: Double) -> Double { lb * 0.4536 }

    /// Mifflin-St Jeor.
    public static func bmr(weightLb: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        10 * kg(weightLb) + 6.25 * heightCm - 5 * Double(age) + (sex == .female ? -161 : 5)
    }
}

/// Port of the web app's `adaptiveTDEE()`, `baseTDEE()` and `targets()`.
public struct EnergyModel: Sendable {
    public var profile: Profile
    public var days: [String: DayMetrics]
    public var today: String

    public init(profile: Profile, days: [String: DayMetrics], today: String = DayKey.today()) {
        self.profile = profile; self.days = days; self.today = today
    }

    public var latestWeight: Double {
        days.values.filter { ($0.weight ?? 0) > 0 }.max { $0.date < $1.date }?.weight ?? profile.startLb
    }

    public var bmr: Double {
        Energy.bmr(weightLb: latestWeight, heightCm: profile.heightCm, age: profile.age, sex: profile.sex)
    }

    /// Mean logged intake − (Theil–Sen weight slope × 3,500) over the last 21 days,
    /// skipping the first 10 days of the cut. Needs 14 days, 10 logged days and 8 weigh-ins spanning 10+ days.
    public func adaptiveTDEE() -> (kcal: Double, n: Int, sportAvg: Double, slope: Double)? {
        let end = DayKey.adding(-1, to: today)
        var start = DayKey.adding(-20, to: end)
        let s0 = DayKey.adding(10, to: profile.start)
        if start < s0 { start = s0 }
        if start > end { return nil }
        var ins: [Double] = [], xs: [Double] = [], ys: [Double] = []
        var sport = 0.0, nd = 0
        var d = start
        while d <= end {
            nd += 1
            if let D = days[d] {
                sport += D.sportKcal
                if D.mealCount >= 2 && D.intakeKcal >= 1200 { ins.append(D.intakeKcal) }
                if let w = D.weight, w > 0 { xs.append(Double(DayKey.days(from: start, to: d))); ys.append(w) }
            }
            d = DayKey.adding(1, to: d)
        }
        guard nd >= 14, ins.count >= 10, xs.count >= 8, xs.last! - xs.first! >= 10 else { return nil }
        let slope = TheilSen.slope(x: xs, y: ys)
        let inAvg = ins.reduce(0, +) / Double(ins.count)
        let b = bmr
        return (clamp(inAvg - slope * 3500, b * 1.2, b * 2.2), ins.count, sport / Double(nd), slope)
    }

    public func baseTDEE() -> TDEE {
        var vals: [Double] = []
        var sport = 0.0
        for i in 1...14 {
            if let D = days[DayKey.adding(-i, to: today)], let r = D.restingKcal, let a = D.activeKcal, r > 0, a > 0 {
                vals.append(r + a)
                sport += D.sportKcal
            }
        }
        let prior: TDEE = vals.count >= 5
            ? TDEE(kcal: vals.reduce(0, +) / Double(vals.count), sportAvg: sport / Double(vals.count),
                   source: "\(vals.count)-day Apple Health avg")
            : TDEE(kcal: bmr * profile.neat + 250, sportAvg: 0, source: "Mifflin-St Jeor × \(fmtNum(profile.neat)) + training")
        guard let A = adaptiveTDEE() else { return TDEE(kcal: jsRound(prior.kcal), sportAvg: prior.sportAvg, source: prior.source) }
        let w = clamp(Double(A.n - 7) / 14, 0, 1)
        return TDEE(kcal: jsRound(w * A.kcal + (1 - w) * prior.kcal),
                    sportAvg: w * A.sportAvg + (1 - w) * prior.sportAvg,
                    source: "adaptive (\(A.n) logged days, \(Int(jsRound(w * 100)))% weight) + \(prior.source)")
    }

    /// Maintenance − deficit + ½ × (today's sport kcal − average sport kcal), floor 1,800.
    /// Protein and fat fixed; carbs take the rest (min 100 g).
    public func targets(for day: String) -> Targets {
        let T = baseTDEE()
        let sport = days[day]?.sportKcal ?? 0
        let adj = jsRound(0.5 * (sport - T.sportAvg))
        let kcal = max(Energy.floorKcal, jsRound(T.kcal - profile.deficit + adj))
        let p = profile.protein, f = profile.fat
        let c = max(100, jsRound((kcal - p * 4 - f * 9) / 4))
        return Targets(kcal: kcal, protein: p, carbs: c, fat: f, tdee: T, sportKcal: sport, sportAdjust: adj)
    }
}
