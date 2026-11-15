import Foundation

public struct Scheme: Sendable, Hashable {
    public let sets: Int
    public let reps: String?
    public let rpe: String
    public let rest: String
}

public struct Slot: Sendable, Hashable {
    public let exercise: String
    public let role: Role
}

public struct Superset: Sendable, Hashable {
    public let first: Slot
    public let second: Slot
}

public struct DayPlan: Sendable, Hashable {
    public let name: String
    public let supersets: [Superset]
}

public struct Block: Sendable {
    public let name: String
    public let weeks: ClosedRange<Int>
    public let goal: String
    public let mainFactor: Double
    public let accFactor: Double
    public let schemes: [Role: Scheme]
    public let days: [DayPlan]

    /// Block load multiplier: main lifts use the main factor, everything else the accessory factor.
    public func factor(for role: Role) -> Double { role == .main ? mainFactor : accFactor }
}

/// One line of a session: warm-up or A1/A2/B1/... (`sessionItems()` in the web app).
public struct SessionItem: Sendable, Hashable, Identifiable {
    public let exercise: String
    /// Planned exercise when swapped.
    public let original: String?
    public let role: Role
    /// "W", "A", "B", "C"
    public let tag: String
    /// "A1", "B2", ... (empty for warm-up)
    public let slot: String
    public var id: String { exercise }
    public var info: Exercise { ExerciseLibrary[exercise]! }
}

public struct Prescription: Sendable, Hashable {
    public var sets: Int
    public var reps: String
    public var rpe: String
    public var rest: String
    /// Week 16: last set of each main lift is AMRAP at the week-1 load.
    public var amrapLastSet: Bool = false

    /// Rest in seconds ("full" → 90; unparsable → 60), as in the guided mode.
    public var restSeconds: Int {
        if rest.range(of: "full", options: .caseInsensitive) != nil { return 90 }
        // First "<n> s" or "<n> min".
        let pattern = try? NSRegularExpression(pattern: "(\\d+)\\s*(min|s)")
        let ns = rest as NSString
        if let m = pattern?.firstMatch(in: rest, range: NSRange(location: 0, length: ns.length)),
           let n = Int(ns.substring(with: m.range(at: 1))) {
            let s = ns.substring(with: m.range(at: 2)) == "min" ? n * 60 : n
            return s > 0 ? s : 60
        }
        return 60
    }

    /// Leading target number of the rep scheme, e.g. "10–12" → "10".
    public var targetReps: Int? {
        Int(reps.prefix { $0.isNumber })
    }
}

private func ss(_ a: String, _ ra: Role, _ b: String, _ rb: Role) -> Superset {
    Superset(first: Slot(exercise: a, role: ra), second: Slot(exercise: b, role: rb))
}

private func schemes(main: Scheme, acc: Scheme, powerRPE: String, powerRest: String, coreRest: String) -> [Role: Scheme] {
    [.main: main, .acc: acc,
     .power: Scheme(sets: 3, reps: nil, rpe: powerRPE, rest: powerRest),
     .core: Scheme(sets: 3, reps: nil, rpe: "—", rest: coreRest),
     .cond: Scheme(sets: 1, reps: nil, rpe: "9", rest: "—")]
}

public enum Program {
    public static let totalWeeks = 16
    public static let lastLiftingDay = 4
    public static let recoveryDayIndex = 5

    // D1 and the B1/B2 day 1 are identical across blocks except Block 3's contrast pair.
    private static let d1Standard = DayPlan(name: "Lower · Knee + Push", supersets: [
        ss("squat", .main, "pallof", .core), ss("bss", .acc, "dbbench", .acc), ss("nordic", .acc, "copen", .core)])

    public static let blocks: [Block] = [
        Block(name: "Foundation", weeks: 1...4,
              goal: "Build work capacity and tendon tolerance. Learn the patterns at 10–12 reps.",
              mainFactor: 1, accFactor: 1,
              schemes: schemes(main: Scheme(sets: 3, reps: "10–12", rpe: "7", rest: "60 s"),
                               acc: Scheme(sets: 3, reps: "10–12", rpe: "7", rest: "45 s"), powerRPE: "—", powerRest: "full", coreRest: "30 s"),
              days: [
                d1Standard,
                DayPlan(name: "Pull + Rotation", supersets: [ss("pulldown", .main, "chop", .core), ss("csrow", .acc, "landmine", .acc), ss("mbtoss", .power, "hipir", .core)]),
                DayPlan(name: "Lower · Hip + Push", supersets: [ss("rdl", .main, "deadbug", .core), ss("latlunge", .acc, "incdb", .acc), ss("hipthrust", .acc, "facepull", .acc)]),
                DayPlan(name: "Athletic + Conditioning", supersets: [ss("boxjump", .power, "skater", .power), ss("slrdl", .acc, "cablerow", .acc), ss("carry", .core, "bike", .cond)]),
              ]),
        Block(name: "Strength", weeks: 5...8,
              goal: "Heavier main lifts at 6–8 reps. Same patterns, more load.",
              mainFactor: 1.15, accFactor: 1.08,
              schemes: schemes(main: Scheme(sets: 4, reps: "6–8", rpe: "8", rest: "60 s"),
                               acc: Scheme(sets: 3, reps: "8–10", rpe: "8", rest: "45 s"), powerRPE: "—", powerRest: "full", coreRest: "30 s"),
              days: [
                d1Standard,
                DayPlan(name: "Pull + Rotation", supersets: [ss("pullup", .main, "chop", .core), ss("csrow", .acc, "landmine", .acc), ss("mbtoss", .power, "hipir", .core)]),
                DayPlan(name: "Lower · Hip + Push", supersets: [ss("trapdl", .main, "deadbug", .core), ss("slrdl", .acc, "incdb", .acc), ss("hipthrust", .acc, "facepull", .acc)]),
                DayPlan(name: "Athletic + Conditioning", supersets: [ss("broadjump", .power, "skater", .power), ss("latlunge", .acc, "cablerow", .acc), ss("carry", .core, "bike", .cond)]),
              ]),
        Block(name: "Power-Strength", weeks: 9...12,
              goal: "Contrast supersets: a heavy set, then an explosive set. Strength turns into speed on the ice and off the tee.",
              mainFactor: 1.25, accFactor: 1.12,
              schemes: schemes(main: Scheme(sets: 3, reps: "4–6", rpe: "8", rest: "90 s after the power set"),
                               acc: Scheme(sets: 3, reps: "6–8", rpe: "8", rest: "45 s"), powerRPE: "max intent", powerRest: "—", coreRest: "30 s"),
              days: [
                DayPlan(name: "Lower · Knee + Push", supersets: [ss("squat", .main, "boxjump", .power), ss("bss", .acc, "dbbench", .acc), ss("nordic", .acc, "copen", .core)]),
                DayPlan(name: "Pull + Rotation", supersets: [ss("pullup", .main, "mbtoss", .power), ss("csrow", .acc, "landmine", .acc), ss("chop", .core, "facepull", .acc)]),
                DayPlan(name: "Lower · Hip + Push", supersets: [ss("trapdl", .main, "broadjump", .power), ss("slrdl", .acc, "incdb", .acc), ss("hipthrust", .acc, "pushup", .acc)]),
                DayPlan(name: "Athletic + Conditioning", supersets: [ss("skater", .power, "mbslam", .power), ss("latlunge", .acc, "cablerow", .acc), ss("carry", .core, "bike", .cond)]),
              ]),
        Block(name: "Athletic Peak", weeks: 13...16,
              goal: "Keep the main lifts heavy while the cut finishes; density lives in the accessories. Week 16 is test week.",
              mainFactor: 1.2, accFactor: 1.05,
              schemes: schemes(main: Scheme(sets: 3, reps: "5–6", rpe: "8", rest: "75 s"),
                               acc: Scheme(sets: 3, reps: "10–12", rpe: "8", rest: "30 s"), powerRPE: "max intent", powerRest: "—", coreRest: "20 s"),
              days: [
                d1Standard,
                DayPlan(name: "Pull + Rotation", supersets: [ss("pulldown", .main, "lift", .core), ss("cablerow", .acc, "landmine", .acc), ss("mbtoss", .power, "hipir", .core)]),
                DayPlan(name: "Lower · Hip + Push", supersets: [ss("trapdl", .main, "deadbug", .core), ss("latlunge", .acc, "pushup", .acc), ss("hipthrust", .acc, "facepull", .acc)]),
                DayPlan(name: "Athletic + Conditioning", supersets: [ss("boxjump", .power, "skater", .power), ss("slrdl", .acc, "csrow", .acc), ss("carry", .core, "bike", .cond)]),
              ]),
    ]

    public static let recoveryDay = DayPlan(name: "Recovery · Zone 2 + Mobility", supersets: [ss("z2", .cond, "mobflow", .core)])

    private static let defaultReps: [Role: String] = [.power: "4", .core: "10/side"]

    // MARK: Week / block math

    /// Week = floor(days since start / 7) + 1, clamped to 1...16.
    public static func week(on day: String, start: String) -> Int {
        let diff = DayKey.days(from: start, to: day)
        let w = Int((Double(diff) / 7).rounded(.down)) + 1
        return clamp(w, 1, totalWeeks)
    }

    public static func blockIndex(week: Int) -> Int {
        blocks.firstIndex { $0.weeks.contains(week) } ?? (week < 1 ? 0 : blocks.count - 1)
    }

    public static func block(week: Int) -> Block { blocks[blockIndex(week: week)] }
    public static func isDeload(_ week: Int) -> Bool { week == 4 || week == 8 || week == 12 }
    public static func isTest(_ week: Int) -> Bool { week == 16 }

    public static func dayPlan(week: Int, day: Int) -> DayPlan {
        day == recoveryDayIndex ? recoveryDay : block(week: week).days[clamp(day, 1, 4) - 1]
    }

    public static func logKey(week: Int, day: Int) -> String { "w\(week)d\(day)" }

    /// Warm-up plus A1/A2/B1/B2/C1/C2, applying any swaps (`swaps[planned] = replacement`).
    public static func items(week: Int, day: Int, swaps: [String: String] = [:]) -> [SessionItem] {
        var out = [SessionItem(exercise: "warm", original: nil, role: .warm, tag: "W", slot: "")]
        for (i, s) in dayPlan(week: week, day: day).supersets.enumerated() {
            let tag = ["A", "B", "C"][i]
            for (n, slot) in [(1, s.first), (2, s.second)] {
                let swapped = swaps[slot.exercise].flatMap { ExerciseLibrary[$0] != nil ? $0 : nil }
                out.append(SessionItem(exercise: swapped ?? slot.exercise, original: swapped == nil ? nil : slot.exercise,
                                       role: slot.role, tag: tag, slot: "\(tag)\(n)"))
            }
        }
        return out
    }

    /// Port of `rx()`: sets, reps, RPE and rest for one item.
    public static func prescription(week: Int, day: Int, item: SessionItem) -> Prescription {
        let e = item.info
        if item.role == .warm { return Prescription(sets: 1, reps: e.reps ?? "", rpe: "", rest: "") }
        let b = block(week: week)
        let sc = b.schemes[item.role] ?? b.schemes[.acc]!
        var sets = sc.sets
        var reps = sc.reps
        var rpe = sc.rpe
        if let r = e.reps, item.role != .main { reps = r }
        if reps?.isEmpty ?? true { reps = defaultReps[item.role] ?? "8" }
        var repsText = reps!
        if let sfx = e.repsSuffix, !repsText.contains("/") { repsText += sfx }
        if item.role == .cond || (e.unit == .time && item.role != .core) { sets = 1 }
        if isDeload(week) {
            sets = max(2, sets - 1)
            rpe = "6"
            if item.role == .cond { sets = 1 }
        }
        if day == recoveryDayIndex { sets = 1 }
        return Prescription(sets: sets, reps: repsText, rpe: rpe, rest: sc.rest,
                            amrapLastSet: isTest(week) && item.role == .main)
    }

    /// Yellow readiness: drop the last round (not on deloads or the recovery day) and cap at RPE 7.
    public static func adjusted(_ rx: Prescription, item: SessionItem, week: Int, day: Int, band: ReadinessBand) -> Prescription {
        guard band == .yellow, !isDeload(week), day < recoveryDayIndex, item.role != .warm else { return rx }
        var r = rx
        if r.sets > 1 { r.sets -= 1 }
        if let v = Double(r.rpe), v > 7 { r.rpe = "7" }
        return r
    }
}
