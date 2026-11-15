import SwiftUI
import SwiftData
import BlueLineCore

/// Readiness gauge, kcal / protein rings, next session, weigh-in trend.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Query private var days: [DayRecord]
    @Query private var meals: [MealRecord]
    @Query private var sessions: [SessionRecord]
    @State private var showSettings = false
    @State private var recoveryText = ""

    var body: some View {
        let m = Store.metrics(days: days, meals: meals)
        let today = model.today
        let r = ReadinessModel.evaluate(m[today] ?? DayMetrics(date: today), history: Array(m.values))
        let band = r?.band ?? .none
        let t = EnergyModel(profile: model.profile, days: m, today: today).targets(for: today)
        let eaten = meals.filter { $0.day == today }
        let weighIns = days.compactMap { d in d.weight.map { WeighIn(date: d.date, lb: $0) } }
        let trend = WeightTrend.series(weighIns).last
        let proj = WeightTrend.projection(weighIns, goalLb: model.profile.goalLb)
        let logs = Dictionary(sessions.map { ($0.key, $0.log) }, uniquingKeysWith: { a, _ in a })
        let n0 = Program.nextSession(week: model.week, logs: logs)
        let next = band == .red ? (week: n0.week, day: Program.recoveryDayIndex) : n0

        NavigationStack {
            List {
                Section("Readiness") {
                    HStack(spacing: 16) {
                        Gauge(value: Double(r?.score ?? 0), in: 0...100) {
                            Text("Ready")
                        } currentValueLabel: {
                            Text(r?.score.map { String($0) } ?? "–")
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(Theme.color(band))
                        .scaleEffect(1.3)
                        .frame(width: 80, height: 80)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(band == .none ? "No data" : band.rawValue.capitalized).font(.headline).foregroundStyle(Theme.color(band))
                            Text(band.advice).font(.footnote)
                            if let r { Text(r.source).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    HStack {
                        TextField("Athlytic recovery %", text: $recoveryText).keyboardType(.numberPad)
                        Button("Save") { model.setRecovery(Double(recoveryText)) }.buttonStyle(.bordered)
                    }
                }
                Section("Fuel") {
                    HStack {
                        Spacer()
                        Ring(value: eaten.reduce(0) { $0 + $1.kcal }, target: t.kcal, label: "kcal", unit: "", color: Theme.blue)
                        Spacer()
                        Ring(value: eaten.reduce(0) { $0 + $1.protein }, target: t.protein, label: "Protein", unit: "g", color: Theme.red)
                        Spacer()
                    }
                    Text("Target \(Int(t.kcal)) kcal · TDEE \(Int(t.tdee.kcal)) (\(t.tdee.source))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Next session") {
                    NavigationLink {
                        SessionView(week: next.week, day: next.day)
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Week \(next.week) · \(next.day == Program.recoveryDayIndex ? "Recovery" : "Day \(next.day)")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(Program.dayPlan(week: next.week, day: next.day).name).font(.headline)
                            Text(model.profile.loc == .hotel ? "Hotel version" : "Work gym").font(.caption)
                        }
                    }
                }
                Section("Weigh-in trend") {
                    if let trend {
                        LabeledContent("Latest", value: "\(fmtNum(trend.lb)) lb")
                        LabeledContent("Trend", value: String(format: "%.1f lb", trend.trend))
                        if let proj {
                            LabeledContent("Rate", value: String(format: "%+.2f lb/wk", proj.perWeek))
                            if let eta = proj.eta { LabeledContent("Goal \(fmtNum(model.profile.goalLb)) lb by", value: eta) }
                        } else {
                            Text("Rate needs 6+ weigh-ins over 10+ days.").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No weigh-ins yet. Step on the Withings scale; it syncs through Apple Health.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let msg = model.healthMessage {
                    Section { Text(msg).font(.footnote).foregroundStyle(Theme.warn) }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .refreshable { await model.refreshHealth() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear { recoveryText = m[today]?.recovery.map { String(Int($0)) } ?? "" }
        }
    }
}
