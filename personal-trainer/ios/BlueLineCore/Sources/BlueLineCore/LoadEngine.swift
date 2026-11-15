import Foundation

public struct Suggestion: Sendable, Hashable {
    public let unit: LoadUnit
    public let lb: Double
    /// "plan", "last 140 @RPE 7", "carried from block 1", "deload −15%"
    public let why: String
    /// Set when the hotel dumbbell cap kicked in.
    public let cap: String?
    /// Week 16 main lifts: the week-1 load for the AMRAP last set.
    public let amrapLoad: Double?

    public var text: String { LoadEngine.format(lb, unit) }
}

/// Port of `suggest()` / `lastLog()` from trainer.html.
///
/// - Plan load = base (calibrated or library) × block factor × (1 + 3% per week into the block).
/// - Same block, last session not a deload: RPE ≤ 7.5 adds one increment, 8–9 holds, ≥ 9.5 drops 5%.
///   No RPE logged: keep the higher of plan and last.
/// - Earlier block: last load carried over, scaled by the ratio of block factors (deload loads un-discounted first).
/// - Deload week: −15%. Hotel dumbbells capped at `hotelMax`.
public struct LoadEngine: Sendable {
    /// Calibrated base loads: `exId` (gym) and `exId_h` (hotel), as in `settings.calib`.
    public var calibration: [String: Double]
    public var hotelMax: Double

    public init(calibration: [String: Double] = [:], hotelMax: Double = 50) {
        self.calibration = calibration
        self.hotelMax = hotelMax
    }

    public struct LastEntry: Sendable {
        public let entry: ExerciseEntry
        public let week: Int
        public let day: Int
        public var load: Double { entry.load ?? 0 }
        public var block: Int { Program.blockIndex(week: week) }
    }

    /// Most recent logged load for `exercise` at `location`, strictly before (week, day).
    public static func lastLog(_ exercise: String, location: Location, before week: Int, _ day: Int,
                               logs: some Sequence<SessionLog>) -> LastEntry? {
        var best: LastEntry?
        for L in logs {
            if L.w > week || (L.w == week && L.d >= day) { continue }
            guard L.loc == location, let x = L.ex[exercise], let load = x.load, load != 0 else { continue }
            if best == nil || L.w * 10 + L.d > best!.week * 10 + best!.day {
                best = LastEntry(entry: x, week: L.w, day: L.d)
            }
        }
        return best
    }

    public func suggest(week w: Int, day d: Int, item: SessionItem, location: Location,
                        logs: some Sequence<SessionLog>) -> Suggestion {
        let e = item.info
        let hotel = location == .hotel
        let u = e.unit(at: location)
        if u.isUnloaded || item.role == .warm {
            return Suggestion(unit: u, lb: 0, why: "", cap: nil, amrapLoad: nil)
        }
        let b = Program.blockIndex(week: w)
        let block = Program.blocks[b]
        let base = calibration[item.exercise + (hotel ? "_h" : "")] ?? e.baseLoad(at: location) ?? 0
        let f = block.factor(for: item.role) * (1 + 0.03 * Double((w - block.weeks.lowerBound) % 4))
        let step: Double = u == .barbell ? 5 : (u == .medBall ? 2 : (e.hotelIncrement == 2.5 && hotel ? 2.5 : 5))
        var lb = roundTo(base * f, step: step)
        var why = "plan"

        if let L = Self.lastLog(item.exercise, location: location, before: w, d, logs: logs) {
            let k: Role = item.role == .main ? .main : .acc
            if L.block == b && !Program.isDeload(L.week) {
                let inc = (hotel ? e.hotelIncrement : e.increment) ?? 5
                var n = L.load
                if let rpe = L.entry.rpe, rpe != 0 {
                    if rpe <= 7.5 { n += inc } else if rpe >= 9.5 { n = roundTo(L.load * 0.95, step: step) }
                    why = "last \(fmtNum(L.load)) @RPE \(fmtNum(rpe))"
                } else {
                    n = max(lb, L.load)
                    why = "last \(fmtNum(L.load))"
                }
                lb = n
            } else if L.block < b {
                let src = Program.isDeload(L.week) ? L.load / 0.85 : L.load
                lb = roundTo(src * block.factor(for: k) / Program.blocks[L.block].factor(for: k), step: step)
                why = "carried from block \(L.block + 1)"
            }
        }
        if Program.isDeload(w) {
            lb = roundTo(lb * 0.85, step: step)
            why = "deload −15%"
        }
        var cap: String?
        if hotel && u.isDumbbell && lb > hotelMax {
            lb = hotelMax
            cap = "Hotel cap: use a 4 s lowering phase or 1¼ reps to make up the load."
        }
        // Week 16 test: AMRAP the last set at the week-1 (base) load. Not in the web app's suggest(); added per program.md.
        var amrap: Double?
        if Program.isTest(w) && item.role == .main {
            amrap = roundTo(base, step: step)
            if hotel && u.isDumbbell { amrap = min(amrap!, hotelMax) }
        }
        return Suggestion(unit: u, lb: lb, why: why, cap: cap, amrapLoad: amrap)
    }

    /// `fmtLoad()`.
    public static func format(_ lb: Double, _ u: LoadUnit) -> String {
        let n = fmtNum(lb)
        switch u {
        case .bodyweight: return lb != 0 ? "BW +\(n) lb" : "BW"
        case .time: return ""
        case .dumbbellPair: return "\(n) lb ×2"
        case .dumbbell: return "\(n) lb DB"
        case .cable: return "\(n) lb stack"
        case .landmine: return "+\(n) lb plates"
        case .medBall: return "\(n) lb ball"
        case .barbell: return "\(n) lb"
        }
    }

    /// RPE-adjusted Epley e1RM (reps in reserve = 10 − RPE, capped 0–4; no RPE → 8).
    public static func e1rm(load: Double, reps: Int, rpe: Double?) -> Double {
        let rir = clamp(10 - (rpe ?? 8), 0, 4)
        let n = Double(reps) + rir
        return n <= 1 ? load : load * (1 + n / 30)
    }
}
