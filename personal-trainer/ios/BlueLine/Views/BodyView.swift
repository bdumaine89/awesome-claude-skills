import SwiftUI
import SwiftData
import Charts
import BlueLineCore

/// Weight trend (raw weigh-ins + gap-adjusted EMA) with the 170 lb goal line.
struct BodyView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \DayRecord.date) private var days: [DayRecord]

    var body: some View {
        let weighIns = days.compactMap { d in d.weight.map { WeighIn(date: d.date, lb: $0) } }
        let series = WeightTrend.series(weighIns)
        let goal = model.profile.goalLb
        let proj = WeightTrend.projection(weighIns, goalLb: goal)
        let lbs = series.flatMap { [$0.lb, $0.trend] } + [goal, model.profile.startLb]
        let lo = (lbs.min() ?? goal) - 2, hi = (lbs.max() ?? model.profile.startLb) + 2
        NavigationStack {
            List {
                Section("Weight") {
                    if series.isEmpty {
                        Text("No weigh-ins in Apple Health yet. Withings → Health sync brings them in automatically.")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart {
                            ForEach(series) { p in
                                PointMark(x: .value("Date", p.date.dayDate, unit: .day), y: .value("Weight", p.lb))
                                    .foregroundStyle(Color.gray.opacity(0.6)).symbolSize(24)
                                LineMark(x: .value("Date", p.date.dayDate, unit: .day), y: .value("Trend", p.trend))
                                    .foregroundStyle(Theme.blue).interpolationMethod(.monotone)
                            }
                            RuleMark(y: .value("Goal", goal))
                                .foregroundStyle(Theme.go)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Goal \(fmtNum(goal))").font(.caption2).foregroundStyle(Theme.go)
                                }
                        }
                        .chartYScale(domain: lo...hi)
                        .frame(height: 240)
                        .accessibilityLabel("Weight trend chart")
                    }
                }
                Section("Trend") {
                    if let last = series.last {
                        LabeledContent("Trend weight", value: String(format: "%.1f lb", last.trend))
                        LabeledContent("To goal", value: String(format: "%.1f lb", last.trend - goal))
                    }
                    if let proj {
                        LabeledContent("Rate (28-day Theil–Sen)", value: String(format: "%+.2f lb/wk", proj.perWeek))
                        LabeledContent("Projected goal date", value: proj.eta ?? "not losing")
                        Text(rateNote(proj.perWeek)).font(.footnote)
                    }
                    if let bf = days.last(where: { $0.bodyFat != nil })?.bodyFat {
                        LabeledContent("Body fat (Withings)", value: String(format: "%.1f%%", bf))
                    }
                }
            }
            .navigationTitle("Body")
        }
    }

    /// Coaching rules from SKILL.md: target −0.6 to −1.0 lb/week.
    private func rateNote(_ perWeek: Double) -> String {
        if perWeek < -1.2 { return "Faster than 1.2 lb/wk. If this holds for two weeks, add 150 kcal back." }
        if perWeek > -0.2 { return "Trend is flat. After 3 flat weeks, cut 150 kcal or add 2,000 steps a day." }
        if perWeek <= -0.6 { return "On target (−0.6 to −1.0 lb/wk)." }
        return "Slightly slow; judge over another week before changing anything."
    }
}
