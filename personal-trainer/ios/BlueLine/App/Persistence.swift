import Foundation
import SwiftData
import BlueLineCore

/// SwiftData store. This is the app's own store: it does not sync with the web app's artifact database.

@Model final class ProfileRecord {
    var data: Data = Data()
    /// Only hour and minute are used. nil = reminder off.
    var trainingReminder: Date?
    var proteinReminder: Date?
    init() {}

    var profile: Profile {
        get { (try? JSONDecoder().decode(Profile.self, from: data)) ?? Profile() }
        set { data = (try? JSONEncoder().encode(newValue)) ?? data }
    }
}

/// `log/w<W>d<D>`, stored as JSON so the nested set rows stay one value.
@Model final class SessionRecord {
    @Attribute(.unique) var key: String
    var week: Int
    var day: Int
    var data: Data = Data()
    var startedAt: Date?
    var completedAt: Date?
    /// At least one set arrived from the Watch: the Watch owns the Health workout for this session.
    var watchSets: Bool = false
    var workoutSaved: Bool = false

    init(week: Int, day: Int, location: Location) {
        self.key = Program.logKey(week: week, day: day)
        self.week = week
        self.day = day
        self.data = (try? JSONEncoder().encode(SessionLog(week: week, day: day, location: location))) ?? Data()
    }

    var log: SessionLog {
        get { (try? JSONDecoder().decode(SessionLog.self, from: data)) ?? SessionLog(week: week, day: day, location: .gym) }
        set {
            data = (try? JSONEncoder().encode(newValue)) ?? data
            completedAt = newValue.completedAt
        }
    }
}

/// Meal entry (`days/<date>.meals[]`), entered by hand for now.
@Model final class MealRecord {
    @Attribute(.unique) var id: String
    var day: String
    var time: Date
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// "manual" or, later, "photo-estimate".
    var source: String
    var items: [String]
    var inHealth: Bool = false

    init(id: String = MealRecord.newID(), time: Date = .now, name: String, kcal: Double, protein: Double,
         carbs: Double, fat: Double, source: String = "manual", items: [String] = []) {
        self.id = id
        self.day = DayKey.from(time)
        self.time = time
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.source = source
        self.items = items
    }

    /// Random 7-character id, like the web app.
    static func newID() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<7).map { _ in chars.randomElement()! })
    }
}

/// Daily Health snapshot (`days/<date>` minus meals). Refreshed from HealthKit; `recovery` is typed in.
@Model final class DayRecord {
    @Attribute(.unique) var date: String
    var weight: Double?
    var bodyFat: Double?
    var activeKcal: Double?
    var restingKcal: Double?
    var steps: Double?
    var hrv: Double?
    var rhr: Double?
    var sleepH: Double?
    var recovery: Double?
    var sportKcal: Double = 0

    init(date: String) { self.date = date }
}

enum Store {
    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: ProfileRecord.self, SessionRecord.self, MealRecord.self, DayRecord.self)
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }

    /// Merge day snapshots and meals into the core model's input.
    static func metrics(days: [DayRecord], meals: [MealRecord]) -> [String: DayMetrics] {
        var out: [String: DayMetrics] = [:]
        for d in days {
            var m = DayMetrics(date: d.date)
            m.weight = d.weight; m.bodyFat = d.bodyFat; m.activeKcal = d.activeKcal; m.restingKcal = d.restingKcal
            m.steps = d.steps; m.hrv = d.hrv; m.rhr = d.rhr; m.sleepH = d.sleepH; m.recovery = d.recovery
            m.sportKcal = d.sportKcal
            out[d.date] = m
        }
        for meal in meals {
            var m = out[meal.day] ?? DayMetrics(date: meal.day)
            m.intakeKcal += meal.kcal
            m.mealCount += 1
            out[meal.day] = m
        }
        return out
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
