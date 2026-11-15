import XCTest
import BlueLineCore

final class EnergyTests: XCTestCase {
    func testMifflinStJeor() {
        // 182 lb, 172.7 cm, 37 y male ≈ 1,725 kcal
        XCTAssertEqual(Energy.bmr(weightLb: 182, heightCm: 172.7, age: 37, sex: .male), 1724.93, accuracy: 0.01)
    }

    func testDefaultTargetsWithoutData() {
        let m = EnergyModel(profile: Profile(), days: [:], today: "2026-11-16")
        let t = m.targets(for: "2026-11-16")
        XCTAssertEqual(t.tdee.kcal, 2665)    // 1,724.9 × 1.4 + 250
        XCTAssertEqual(t.kcal, 2165)         // − 500
        XCTAssertEqual(t.protein, 175)
        XCTAssertEqual(t.fat, 70)
        XCTAssertEqual(t.carbs, 209)         // (2165 − 700 − 630) / 4 = 208.75
    }

    func testFloorAt1800() {
        var p = Profile(); p.deficit = 1000
        let t = EnergyModel(profile: p, days: [:], today: "2026-11-16").targets(for: "2026-11-16")
        XCTAssertEqual(t.kcal, 1800)
        XCTAssertEqual(t.carbs, 118)         // (1800 − 1330) / 4 = 117.5
    }

    func testSportDayAddsHalf() {
        var d = DayMetrics(date: "2026-11-16"); d.sportKcal = 500
        let t = EnergyModel(profile: Profile(), days: [d.date: d], today: "2026-11-16").targets(for: "2026-11-16")
        XCTAssertEqual(t.sportAdjust, 250)
        XCTAssertEqual(t.kcal, 2415)
    }

    func testAppleHealthAverageReplacesEstimate() {
        var days: [String: DayMetrics] = [:]
        for i in 1...7 {
            var d = DayMetrics(date: DayKey.adding(-i, to: "2026-11-30"))
            d.restingKcal = 1750; d.activeKcal = 850
            days[d.date] = d
        }
        let t = EnergyModel(profile: Profile(), days: days, today: "2026-11-30").targets(for: "2026-11-30")
        XCTAssertEqual(t.tdee.kcal, 2600)
        XCTAssertEqual(t.kcal, 2100)
    }

    func testActivityKcal() {
        XCTAssertEqual(ActivityType.hockey.netKcal(minutes: 60, weightLb: 182), 495)   // (7 − 1) × 82.56 × 1
    }

    func testEMA() {
        let s = WeightTrend.series([WeighIn(date: "2026-11-17", lb: 181), WeighIn(date: "2026-11-16", lb: 182)])
        XCTAssertEqual(s.map(\.date), ["2026-11-16", "2026-11-17"])
        XCTAssertEqual(s[1].trend, 182 - (1 - exp(-0.1)), accuracy: 1e-9)
    }

    func testTheilSenProjection() {
        let pts = (0...10).map { i in WeighIn(date: DayKey.adding(2 * i, to: "2026-11-16"), lb: 182 - 0.2 * Double(i)) }
        let p = WeightTrend.projection(pts, goalLb: 170)!
        XCTAssertEqual(p.perWeek, -0.7, accuracy: 1e-9)
        XCTAssertEqual(p.trend, 180, accuracy: 1e-9)
        XCTAssertEqual(p.eta, DayKey.adding(100, to: pts.last!.date))
        XCTAssertNil(WeightTrend.projection(Array(pts.prefix(5)), goalLb: 170))
    }

    func testTheilSenIgnoresOutlier() {
        XCTAssertEqual(TheilSen.slope(x: [0, 1, 2, 3, 4], y: [10, 9, 30, 7, 6]), -1, accuracy: 1e-9)
    }

    func testReadiness() {
        var d = DayMetrics(date: "2026-11-30"); d.recovery = 70
        XCTAssertEqual(ReadinessModel.evaluate(d, history: [])?.band, .green)
        d.recovery = nil; d.hrv = 50
        XCTAssertNil(ReadinessModel.evaluate(d, history: [])?.score)
        let hist = (1...10).map { i -> DayMetrics in var h = DayMetrics(date: DayKey.adding(-i, to: d.date)); h.hrv = 50; return h }
        XCTAssertEqual(ReadinessModel.evaluate(d, history: hist)?.score, 55)    // baseline HRV, no RHR, no sleep
        d.sleepH = 8; d.hrv = 70
        XCTAssertEqual(ReadinessModel.evaluate(d, history: hist)?.band, .green)
        XCTAssertEqual(ReadinessBand(score: 33), .red)
        XCTAssertEqual(ReadinessBand(score: 34), .yellow)
    }
}
