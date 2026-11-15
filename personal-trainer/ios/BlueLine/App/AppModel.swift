import Foundation
import Observation
import SwiftData
import BlueLineCore

/// App-wide state and the glue between SwiftData, HealthKit, the Watch and the core models.
@Observable @MainActor final class AppModel {
    let container: ModelContainer
    let health = HealthService()
    let phone = PhoneConnectivity()
    private(set) var healthMessage: String?
    private var profileRecord: ProfileRecord

    var profile: Profile {
        didSet { profileRecord.profile = profile; try? context.save() }
    }

    var trainingReminder: Date? {
        didSet { profileRecord.trainingReminder = trainingReminder; persistReminders() }
    }

    var proteinReminder: Date? {
        didSet { profileRecord.proteinReminder = proteinReminder; persistReminders() }
    }

    var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
        let ctx = container.mainContext
        let rec = (try? ctx.fetch(FetchDescriptor<ProfileRecord>()))?.first ?? {
            let r = ProfileRecord()
            r.profile = Profile()
            ctx.insert(r)
            return r
        }()
        profileRecord = rec
        profile = rec.profile
        trainingReminder = rec.trainingReminder
        proteinReminder = rec.proteinReminder
        phone.onSet = { [weak self] in self?.apply($0) }
        phone.onWorkoutSaved = { [weak self] key in self?.record(key: key)?.workoutSaved = true }
    }

    // MARK: Program state

    var today: String { DayKey.today() }
    var week: Int { Program.week(on: today, start: profile.start) }
    var engine: LoadEngine { LoadEngine(calibration: profile.calib, hotelMax: profile.hotelMax) }

    func allLogs() -> [SessionLog] { ((try? context.fetch(FetchDescriptor<SessionRecord>())) ?? []).map(\.log) }

    func record(key: String) -> SessionRecord? {
        var d = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    func log(week: Int, day: Int) -> SessionLog {
        record(key: Program.logKey(week: week, day: day))?.log ?? SessionLog(week: week, day: day, location: profile.loc)
    }

    /// Persist a session log. A session finished on the phone (no Watch sets) is saved to Health as a strength workout.
    func save(_ log: SessionLog, fromWatch: Bool = false) {
        let rec = record(key: log.key) ?? {
            let r = SessionRecord(week: log.w, day: log.d, location: log.loc)
            context.insert(r)
            return r
        }()
        let wasComplete = rec.completedAt != nil
        if rec.startedAt == nil, log.ex.values.contains(where: { $0.sets.contains(where: \.done) || $0.done }) { rec.startedAt = .now }
        if fromWatch { rec.watchSets = true }
        rec.log = log
        try? context.save()

        if !wasComplete, let end = log.completedAt, !rec.watchSets, !rec.workoutSaved, log.d < Program.recoveryDayIndex {
            let start = rec.startedAt.map { end.timeIntervalSince($0) > 5 * 60 ? $0 : end.addingTimeInterval(-30 * 60) }
                ?? end.addingTimeInterval(-30 * 60)
            let title = "W\(log.w) D\(log.d) " + Program.dayPlan(week: log.w, day: log.d).name
            Task {
                do {
                    try await health.saveStrengthWorkout(start: start, end: end, title: title)
                    rec.workoutSaved = true
                    try? context.save()
                } catch { healthMessage = "Couldn't save the workout to Health: \(error.localizedDescription)" }
            }
        }
        pushPlanToWatch()
    }

    private func apply(_ c: SetCompletion) {
        var L = log(week: c.week, day: c.day)
        c.apply(to: &L)
        save(L, fromWatch: true)
    }

    // MARK: Day metrics

    func metrics() -> [String: DayMetrics] {
        Store.metrics(days: (try? context.fetch(FetchDescriptor<DayRecord>())) ?? [],
                      meals: (try? context.fetch(FetchDescriptor<MealRecord>())) ?? [])
    }

    func readiness(_ m: [String: DayMetrics]) -> Readiness? {
        ReadinessModel.evaluate(m[today] ?? DayMetrics(date: today), history: Array(m.values))
    }

    /// Next session for this week; a red readiness day becomes the recovery session.
    func nextSession(band: ReadinessBand) -> (week: Int, day: Int) {
        let logs = Dictionary(allLogs().map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let n = Program.nextSession(week: week, logs: logs)
        return band == .red ? (week: n.week, day: Program.recoveryDayIndex) : n
    }

    func dayRecord(_ date: String) -> DayRecord {
        var d = FetchDescriptor<DayRecord>(predicate: #Predicate { $0.date == date })
        d.fetchLimit = 1
        if let r = (try? context.fetch(d))?.first { return r }
        let r = DayRecord(date: date)
        context.insert(r)
        return r
    }

    func setRecovery(_ value: Double?) {
        dayRecord(today).recovery = value.map { clamp($0, 0, 100) }
        try? context.save()
        pushPlanToWatch()
    }

    // MARK: Health

    func connectHealth() async {
        do {
            try await health.requestAuthorization()
            await refreshHealth()
        } catch { healthMessage = "Health access failed: \(error.localizedDescription)" }
    }

    func refreshHealth() async {
        guard health.isAvailable else { healthMessage = "Health isn't available on this device."; return }
        do {
            let latest = metrics().values.filter { $0.weight != nil }.max { $0.date < $1.date }?.weight ?? profile.startLb
            let s = try await health.snapshot(weightLb: latest)
            for date in s.dates {
                let r = dayRecord(date)
                r.activeKcal = s.active[date] ?? r.activeKcal
                r.restingKcal = s.basal[date] ?? r.restingKcal
                r.steps = s.steps[date] ?? r.steps
                r.hrv = s.hrv[date] ?? r.hrv
                r.rhr = s.rhr[date] ?? r.rhr
                r.weight = s.weightLb[date].map { ($0 * 10).rounded() / 10 } ?? r.weight
                r.bodyFat = s.bodyFatPct[date] ?? r.bodyFat
                r.sleepH = s.sleepH[date] ?? r.sleepH
                r.sportKcal = s.sportKcal[date] ?? 0
            }
            try? context.save()
            healthMessage = nil
            pushPlanToWatch()
        } catch { healthMessage = "Couldn't read Health: \(error.localizedDescription)" }
    }

    // MARK: Meals

    func addMeal(_ meal: MealRecord) {
        context.insert(meal)
        try? context.save()
        Task {
            do {
                try await health.saveMeal(id: meal.id, name: meal.name, time: meal.time, kcal: meal.kcal,
                                          protein: meal.protein, carbs: meal.carbs, fat: meal.fat)
                meal.inHealth = true
                try? context.save()
            } catch { healthMessage = "Meal saved here but not to Health: \(error.localizedDescription)" }
        }
    }

    func deleteMeal(_ meal: MealRecord) {
        if meal.inHealth { health.deleteMeal(id: meal.id) }
        context.delete(meal)
        try? context.save()
    }

    // MARK: Watch

    func pushPlanToWatch() {
        let band = readiness(metrics())?.band ?? .none
        let n = nextSession(band: band)
        let plan = Guided.plan(week: n.week, day: n.day, log: log(week: n.week, day: n.day), location: profile.loc,
                               band: band, engine: engine, logs: allLogs())
        phone.send(plan)
    }

    private func persistReminders() {
        try? context.save()
        Reminders.schedule(training: trainingReminder, protein: proteinReminder, proteinTarget: profile.protein)
    }
}
