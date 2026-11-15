import Foundation

/// One set row: done toggle, load (lb) and reps. Shape matches `log/w<W>d<D>.ex[id].sets[i]`.
public struct SetEntry: Codable, Hashable, Sendable {
    public var done: Bool
    public var load: Double?
    public var reps: Int?
    public init(done: Bool = false, load: Double? = nil, reps: Int? = nil) {
        self.done = done; self.load = load; self.reps = reps
    }
}

/// Per-exercise log. `load` = heaviest completed set, `done` = all sets done, `rpe` = last set.
public struct ExerciseEntry: Codable, Hashable, Sendable {
    public var done: Bool = false
    public var load: Double?
    public var reps: Int?
    public var rpe: Double?
    public var sets: [SetEntry] = []
    public init() {}

    /// Port of `syncEx()`.
    public mutating func sync() {
        guard !sets.isEmpty else { return }
        done = sets.allSatisfy(\.done)
        let loaded = sets.filter { $0.done && $0.load != nil }
        if let top = loaded.max(by: { ($0.load ?? 0) < ($1.load ?? 0) }) {
            load = top.load
            reps = top.reps
        }
    }

    /// Resize to `count` rows, keeping existing entries.
    public mutating func ensureSets(_ count: Int) {
        if sets.count < count { sets += Array(repeating: SetEntry(), count: count - sets.count) }
        if sets.count > count { sets.removeLast(sets.count - count) }
    }
}

/// `log/w<week>d<day>`. Day 5 is the recovery session.
public struct SessionLog: Codable, Hashable, Sendable {
    public var w: Int
    public var d: Int
    public var loc: Location
    public var ex: [String: ExerciseEntry] = [:]
    public var completedAt: Date?
    public var swaps: [String: String] = [:]

    public init(week: Int, day: Int, location: Location) {
        w = week; d = day; loc = location
    }

    public var key: String { Program.logKey(week: w, day: d) }
    public var items: [SessionItem] { Program.items(week: w, day: d, swaps: swaps) }

    public var progress: (done: Int, total: Int) {
        let its = items
        return (its.filter { ex[$0.exercise]?.done == true }.count, its.count)
    }

    public var isComplete: Bool { let p = progress; return p.done == p.total }

    /// Update one set row and re-derive the exercise roll-up and `completedAt`.
    public mutating func setSet(_ exercise: String, index: Int, count: Int, _ update: (inout SetEntry) -> Void) {
        var e = ex[exercise] ?? ExerciseEntry()
        e.ensureSets(count)
        guard e.sets.indices.contains(index) else { return }
        update(&e.sets[index])
        e.sync()
        ex[exercise] = e
        refreshCompletion()
    }

    public mutating func setRPE(_ exercise: String, _ rpe: Double?) {
        var e = ex[exercise] ?? ExerciseEntry()
        e.rpe = rpe
        ex[exercise] = e
    }

    /// Mark an item without set rows (warm-up, timed work) done or not.
    public mutating func setDone(_ exercise: String, _ done: Bool, count: Int = 1) {
        var e = ex[exercise] ?? ExerciseEntry()
        e.ensureSets(count)
        for i in e.sets.indices { e.sets[i].done = done }
        e.sync()
        if e.sets.isEmpty { e.done = done }
        ex[exercise] = e
        refreshCompletion()
    }

    public mutating func refreshCompletion(now: Date = Date()) {
        if isComplete { if completedAt == nil { completedAt = now } } else { completedAt = nil }
    }
}

public extension Program {
    /// Sessions 1–4 of a block fully done (`blockProgress()`).
    static func blockProgress(_ blockIndex: Int, logs: [String: SessionLog]) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for w in blocks[blockIndex].weeks {
            for d in 1...lastLiftingDay {
                total += 1
                if logs[logKey(week: w, day: d)]?.isComplete == true { done += 1 }
            }
        }
        return (done, total)
    }

    /// Next incomplete lifting day in the current week, or the recovery day when all four are done.
    static func nextSession(week: Int, logs: [String: SessionLog]) -> (week: Int, day: Int) {
        for d in 1...lastLiftingDay where logs[logKey(week: week, day: d)]?.isComplete != true {
            return (week, d)
        }
        return (week, recoveryDayIndex)
    }
}
