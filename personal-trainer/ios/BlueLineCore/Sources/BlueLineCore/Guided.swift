import Foundation

/// One set in the guided (Watch / full-screen) walkthrough.
public struct GuidedStep: Codable, Hashable, Sendable, Identifiable {
    public var exercise: String
    public var name: String
    public var slot: String
    public var round: Int
    public var of: Int
    public var reps: String
    public var rpe: String
    public var load: Double
    public var unit: LoadUnit
    public var restAfter: Int
    public var cap: String?
    public var amrap: Bool
    public var isWarmup: Bool
    public var id: String { "\(exercise)#\(round)" }
    public var loadText: String { LoadEngine.format(load, unit) }
    public var isLastSet: Bool { round == of }
}

public struct GuidedPlan: Codable, Hashable, Sendable {
    public var week: Int
    public var day: Int
    public var title: String
    public var location: Location
    /// Yellow readiness: last round dropped, RPE capped at 7.
    public var trimmed: Bool
    public var steps: [GuidedStep]
    public var key: String { Program.logKey(week: week, day: day) }
}

public enum Guided {
    /// Port of `buildPilot()`: supersets interleaved round by round (A1, A2, rest, A1, A2, ...), skipping done items.
    public static func plan(week w: Int, day d: Int, log: SessionLog?, location: Location, band: ReadinessBand,
                            engine: LoadEngine, logs: [SessionLog]) -> GuidedPlan {
        let items = Program.items(week: w, day: d, swaps: log?.swaps ?? [:])
        var groups: [(tag: String, items: [SessionItem])] = []
        for it in items {
            if let i = groups.firstIndex(where: { $0.tag == it.tag }) { groups[i].items.append(it) } else { groups.append((it.tag, [it])) }
        }
        let trimmed = band == .yellow && !Program.isDeload(w) && d < Program.recoveryDayIndex
        var steps: [GuidedStep] = []
        for g in groups {
            let rx = Dictionary(uniqueKeysWithValues: g.items.map {
                ($0.exercise, Program.adjusted(Program.prescription(week: w, day: d, item: $0), item: $0, week: w, day: d, band: band))
            })
            let rounds = g.items.map { rx[$0.exercise]!.sets }.max() ?? 1
            let rest = g.tag == "W" ? 0 : rx[g.items[0].exercise]!.restSeconds
            for r in 1...max(1, rounds) {
                let here = g.items.filter { r <= rx[$0.exercise]!.sets && log?.ex[$0.exercise]?.done != true }
                for (k, it) in here.enumerated() {
                    let p = rx[it.exercise]!
                    let sg = engine.suggest(week: w, day: d, item: it, location: location, logs: logs)
                    let logged = log?.ex[it.exercise]?.load
                    let amrap = p.amrapLastSet && r == p.sets
                    steps.append(GuidedStep(
                        exercise: it.exercise, name: it.info.name(at: location), slot: it.slot, round: r, of: p.sets,
                        reps: amrap ? "AMRAP" : p.reps, rpe: p.rpe,
                        load: amrap ? (sg.amrapLoad ?? sg.lb) : ((logged ?? 0) > 0 ? logged! : sg.lb),
                        unit: sg.unit, restAfter: k == here.count - 1 ? rest : 0, cap: sg.cap, amrap: amrap,
                        isWarmup: it.role == .warm))
                }
            }
        }
        return GuidedPlan(week: w, day: d, title: Program.dayPlan(week: w, day: d).name, location: location,
                          trimmed: trimmed, steps: steps)
    }
}

/// Watch → phone: one completed set (sent with `transferUserInfo`, so it queues while the phone is away).
public struct SetCompletion: Codable, Hashable, Sendable {
    public var week: Int
    public var day: Int
    public var exercise: String
    /// 1-based set number.
    public var round: Int
    public var of: Int
    public var load: Double?
    public var reps: Int?
    public var rpe: Double?
    public var location: Location
    public var at: Date

    public init(step: GuidedStep, plan: GuidedPlan, reps: Int?, rpe: Double?, at: Date = Date()) {
        week = plan.week; day = plan.day; exercise = step.exercise; round = step.round; of = step.of
        load = step.unit.isUnloaded ? nil : step.load
        self.reps = reps; self.rpe = rpe; location = plan.location; self.at = at
    }

    /// Apply to a session log (creating the row if needed).
    public func apply(to log: inout SessionLog) {
        log.loc = location
        if exercise == "warm" { log.setDone(exercise, true); return }
        log.setSet(exercise, index: round - 1, count: of) { s in
            s.done = true
            if let load { s.load = load }
            if let reps { s.reps = reps }
        }
        if let rpe, round == of { log.setRPE(exercise, rpe) }
    }
}

/// WatchConnectivity payload keys. Values are JSON `Data`.
public enum WatchKeys {
    public static let plan = "plan"
    public static let set = "set"
    public static let workoutSaved = "workoutSaved"
}

public extension Encodable {
    func jsonData() -> Data? { try? JSONEncoder().encode(self) }
}

public extension Decodable {
    static func fromJSON(_ data: Any?) -> Self? {
        guard let d = data as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: d)
    }
}
