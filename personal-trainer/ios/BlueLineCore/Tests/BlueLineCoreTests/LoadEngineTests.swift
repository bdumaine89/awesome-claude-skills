import XCTest
import BlueLineCore

final class LoadEngineTests: XCTestCase {
    let engine = LoadEngine()

    private func item(_ id: String, week: Int = 1, day: Int = 1) -> SessionItem {
        Program.items(week: week, day: day).first { $0.exercise == id }!
    }

    private func log(_ w: Int, _ d: Int, _ ex: String, load: Double, rpe: Double?, loc: Location = .gym) -> SessionLog {
        var L = SessionLog(week: w, day: d, location: loc)
        var e = ExerciseEntry()
        e.load = load; e.rpe = rpe; e.done = true
        L.ex[ex] = e
        return L
    }

    func testPlanLoadsFollowBlockFactorAndWeeklyBump() {
        let sq = { (w: Int) in self.engine.suggest(week: w, day: 1, item: self.item("squat", week: w), location: .gym, logs: []).lb }
        XCTAssertEqual(sq(1), 135)   // 135 × 1.00
        XCTAssertEqual(sq(2), 140)   // 139.05 → 140
        XCTAssertEqual(sq(3), 145)   // 143.1 → 145
        XCTAssertEqual(sq(4), 125)   // 147.15 → 145, deload ×0.85 = 123.25 → 125
        XCTAssertEqual(sq(5), 155)   // 135 × 1.15 = 155.25 → 155
        XCTAssertEqual(engine.suggest(week: 1, day: 1, item: item("squat"), location: .gym, logs: []).text, "135 lb")
    }

    func testRPEProgressionWithinBlock() {
        let it = item("squat", week: 2)
        func next(_ rpe: Double?) -> Suggestion {
            engine.suggest(week: 2, day: 1, item: it, location: .gym, logs: [log(1, 1, "squat", load: 135, rpe: rpe)])
        }
        XCTAssertEqual(next(7).lb, 145)        // ≤ 7.5: +10 lb barbell lower
        XCTAssertEqual(next(7).why, "last 135 @RPE 7")
        XCTAssertEqual(next(8.5).lb, 135)      // 8–9: hold
        XCTAssertEqual(next(9.5).lb, 130)      // ≥ 9.5: −5% → 128.25 → 130
        XCTAssertEqual(next(nil).lb, 140)      // no RPE: max(plan 140, last 135)
    }

    func testDumbbellIncrementIsFive() {
        let it = item("dbbench", week: 2)
        let s = engine.suggest(week: 2, day: 1, item: it, location: .gym, logs: [log(1, 1, "dbbench", load: 55, rpe: 7)])
        XCTAssertEqual(s.lb, 60)
        XCTAssertEqual(s.text, "60 lb ×2")
    }

    func testCarryAcrossBlocksScalesByFactorRatio() {
        let it = item("squat", week: 5)
        let s = engine.suggest(week: 5, day: 1, item: it, location: .gym, logs: [log(3, 1, "squat", load: 150, rpe: 8)])
        XCTAssertEqual(s.lb, 175)              // 150 × 1.15 / 1.00 = 172.5 → 175
        XCTAssertEqual(s.why, "carried from block 1")
        // A deload load is un-discounted first: 125 / 0.85 × 1.15 = 169.1 → 170
        let d = engine.suggest(week: 5, day: 1, item: it, location: .gym, logs: [log(4, 1, "squat", load: 125, rpe: 6)])
        XCTAssertEqual(d.lb, 170)
    }

    func testDeloadCutsFifteenPercentOfProgression() {
        let it = item("squat", week: 4)
        let s = engine.suggest(week: 4, day: 1, item: it, location: .gym, logs: [log(3, 1, "squat", load: 150, rpe: 8)])
        XCTAssertEqual(s.lb, 130)              // hold 150 × 0.85 = 127.5 → 130
        XCTAssertEqual(s.why, "deload −15%")
    }

    func testHotelCapAndHotelVariants() {
        let it = item("squat", week: 6)
        let s = engine.suggest(week: 6, day: 1, item: it, location: .hotel, logs: [])
        XCTAssertEqual(s.lb, 50)               // 50 × 1.15 × 1.03 = 59.2 → 60, capped at 50
        XCTAssertNotNil(s.cap)
        XCTAssertEqual(s.unit, .dumbbell)
        XCTAssertEqual(it.info.name(at: .hotel), "DB Goblet Squat")
        // Prone Y-T-W steps in 2.5 lb: 8 → 7.5
        let fp = engine.suggest(week: 1, day: 3, item: item("facepull", day: 3), location: .hotel, logs: [])
        XCTAssertEqual(fp.lb, 7.5)
    }

    func testLogsAreSeparatedByLocationAndOrder() {
        let it = item("squat", week: 2)
        let s = engine.suggest(week: 2, day: 1, item: it, location: .hotel, logs: [log(1, 1, "squat", load: 135, rpe: 7)])
        XCTAssertEqual(s.why, "plan")
        // A later session never informs an earlier one.
        let early = engine.suggest(week: 1, day: 1, item: item("squat"), location: .gym, logs: [log(2, 1, "squat", load: 200, rpe: 7)])
        XCTAssertEqual(early.lb, 135)
    }

    func testCalibrationOverridesLibraryBase() {
        let e = LoadEngine(calibration: ["squat": 155, "squat_h": 40])
        XCTAssertEqual(e.suggest(week: 1, day: 1, item: item("squat"), location: .gym, logs: []).lb, 155)
        XCTAssertEqual(e.suggest(week: 1, day: 1, item: item("squat"), location: .hotel, logs: []).lb, 40)
    }

    func testUnloadedExercises() {
        let s = engine.suggest(week: 5, day: 2, item: item("pullup", week: 5, day: 2), location: .gym, logs: [])
        XCTAssertEqual(s.unit, .bodyweight)
        XCTAssertEqual(s.lb, 0)
        XCTAssertEqual(s.text, "BW")
        // Lat pulldown becomes bodyweight pull-ups in a hotel.
        XCTAssertEqual(engine.suggest(week: 1, day: 2, item: item("pulldown", day: 2), location: .hotel, logs: []).text, "BW")
    }

    func testTestWeekAMRAPUsesWeekOneLoad() {
        let s = engine.suggest(week: 16, day: 1, item: item("squat", week: 16), location: .gym, logs: [])
        XCTAssertEqual(s.amrapLoad, 135)
    }

    func testSetLogRollUp() {
        var L = SessionLog(week: 1, day: 1, location: .gym)
        L.setSet("squat", index: 0, count: 3) { $0.done = true; $0.load = 135; $0.reps = 12 }
        L.setSet("squat", index: 1, count: 3) { $0.done = true; $0.load = 140; $0.reps = 10 }
        XCTAssertEqual(L.ex["squat"]?.load, 140)
        XCTAssertEqual(L.ex["squat"]?.reps, 10)
        XCTAssertEqual(L.ex["squat"]?.done, false)
        L.setSet("squat", index: 2, count: 3) { $0.done = true; $0.load = 140; $0.reps = 9 }
        XCTAssertEqual(L.ex["squat"]?.done, true)
        XCTAssertEqual(L.ex["squat"]?.reps, 10)   // first heaviest set wins ties
        XCTAssertNil(L.completedAt)
        for it in L.items { L.setDone(it.exercise, true) }
        XCTAssertNotNil(L.completedAt)
    }

    func testE1RM() {
        // 100 lb × 10 @ RPE 8 → 12 reps equivalent → 140
        XCTAssertEqual(LoadEngine.e1rm(load: 100, reps: 10, rpe: 8), 140, accuracy: 0.001)
    }
}
