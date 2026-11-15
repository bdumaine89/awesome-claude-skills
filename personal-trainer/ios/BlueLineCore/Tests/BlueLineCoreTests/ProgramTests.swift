import XCTest
import BlueLineCore

final class ProgramTests: XCTestCase {
    func testWeekMath() {
        let start = "2026-11-16"
        XCTAssertEqual(Program.week(on: "2026-11-10", start: start), 1)   // before start clamps to 1
        XCTAssertEqual(Program.week(on: "2026-11-16", start: start), 1)
        XCTAssertEqual(Program.week(on: "2026-11-22", start: start), 1)
        XCTAssertEqual(Program.week(on: "2026-11-23", start: start), 2)
        XCTAssertEqual(Program.week(on: "2027-02-22", start: start), 15)  // 98 days
        XCTAssertEqual(Program.week(on: "2027-06-01", start: start), 16)  // clamps to 16
    }

    func testBlocksDeloadsAndTest() {
        XCTAssertEqual((1...16).map(Program.blockIndex(week:)), [0,0,0,0, 1,1,1,1, 2,2,2,2, 3,3,3,3])
        XCTAssertEqual((1...16).filter(Program.isDeload), [4, 8, 12])
        XCTAssertTrue(Program.isTest(16))
        XCTAssertEqual(Program.blocks.map(\.mainFactor), [1, 1.15, 1.25, 1.2])
        XCTAssertEqual(Program.blocks.map(\.accFactor), [1, 1.08, 1.12, 1.05])
        XCTAssertEqual(Program.blocks.map { $0.days.count }, [4, 4, 4, 4])
    }

    func testSessionItems() {
        let items = Program.items(week: 1, day: 1)
        XCTAssertEqual(items.map(\.slot), ["", "A1", "A2", "B1", "B2", "C1", "C2"])
        XCTAssertEqual(items.map(\.exercise), ["warm", "squat", "pallof", "bss", "dbbench", "nordic", "copen"])
        XCTAssertEqual(Program.items(week: 9, day: 1)[2].exercise, "boxjump")    // Block 3 contrast pair
        XCTAssertEqual(Program.items(week: 1, day: 5).map(\.exercise), ["warm", "z2", "mobflow"])
        let swapped = Program.items(week: 1, day: 1, swaps: ["squat": "fsquat"])
        XCTAssertEqual(swapped[1].exercise, "fsquat")
        XCTAssertEqual(swapped[1].original, "squat")
    }

    func testEveryPlannedExerciseExists() {
        for w in 1...16 { for d in 1...5 { for it in Program.items(week: w, day: d) {
            XCTAssertNotNil(ExerciseLibrary[it.exercise], it.exercise)
        } } }
    }

    func testNoBands() {
        for e in ExerciseLibrary.all {
            for text in [e.name, e.hotelName, e.cue] {
                XCTAssertNil(text.range(of: "band", options: .caseInsensitive), "\(e.id): \(text)")
            }
        }
    }

    func testPrescriptions() {
        func rx(_ w: Int, _ d: Int, _ id: String) -> Prescription {
            Program.prescription(week: w, day: d, item: Program.items(week: w, day: d).first { $0.exercise == id }!)
        }
        XCTAssertEqual(rx(1, 1, "squat"), Prescription(sets: 3, reps: "10–12", rpe: "7", rest: "60 s"))
        XCTAssertEqual(rx(4, 1, "squat").sets, 2)
        XCTAssertEqual(rx(4, 1, "squat").rpe, "6")
        XCTAssertEqual(rx(5, 1, "squat").sets, 4)
        XCTAssertEqual(rx(5, 1, "squat").reps, "6–8")
        XCTAssertEqual(rx(1, 1, "bss").reps, "10–12/leg")
        XCTAssertEqual(rx(1, 1, "copen").reps, "20–30 s/side")
        XCTAssertEqual(rx(1, 1, "copen").sets, 3)
        XCTAssertEqual(rx(1, 4, "bike").sets, 1)
        XCTAssertEqual(rx(1, 4, "boxjump").reps, "4")
        XCTAssertEqual(rx(1, 5, "z2").sets, 1)
        XCTAssertTrue(rx(16, 1, "squat").amrapLastSet)
        XCTAssertEqual(rx(9, 1, "squat").restSeconds, 90)
        XCTAssertEqual(rx(1, 1, "squat").restSeconds, 60)
    }

    func testYellowReadinessTrimsAndCaps() {
        let it = Program.items(week: 5, day: 1)[1]
        let r = Program.adjusted(Program.prescription(week: 5, day: 1, item: it), item: it, week: 5, day: 1, band: .yellow)
        XCTAssertEqual(r.sets, 3)
        XCTAssertEqual(r.rpe, "7")
    }

    func testNextSessionAndBlockProgress() {
        var logs: [String: SessionLog] = [:]
        XCTAssertEqual(Program.nextSession(week: 1, logs: logs).day, 1)
        var L = SessionLog(week: 1, day: 1, location: .gym)
        for it in L.items { L.setDone(it.exercise, true) }
        logs[L.key] = L
        XCTAssertEqual(Program.nextSession(week: 1, logs: logs).day, 2)
        XCTAssertEqual(Program.blockProgress(0, logs: logs).done, 1)
        XCTAssertEqual(Program.blockProgress(0, logs: logs).total, 16)
    }

    func testGuidedPlanInterleavesSupersets() {
        let p = Guided.plan(week: 1, day: 1, log: nil, location: .gym, band: .green, engine: LoadEngine(), logs: [])
        XCTAssertEqual(Array(p.steps.prefix(5).map(\.slot)), ["", "A1", "A2", "A1", "A2"])
        XCTAssertEqual(p.steps[1].restAfter, 0)
        XCTAssertEqual(p.steps[2].restAfter, 60)
        XCTAssertEqual(p.steps.count, 1 + 6 * 3)
        let y = Guided.plan(week: 1, day: 1, log: nil, location: .gym, band: .yellow, engine: LoadEngine(), logs: [])
        XCTAssertEqual(y.steps.count, 1 + 6 * 2)
    }

    func testSetCompletionApplies() {
        let p = Guided.plan(week: 1, day: 1, log: nil, location: .gym, band: .green, engine: LoadEngine(), logs: [])
        var L = SessionLog(week: 1, day: 1, location: .gym)
        let step = p.steps.first { $0.exercise == "squat" && $0.round == 3 }!
        SetCompletion(step: step, plan: p, reps: 10, rpe: 7.5).apply(to: &L)
        XCTAssertEqual(L.ex["squat"]?.sets.count, 3)
        XCTAssertEqual(L.ex["squat"]?.sets[2].load, 135)
        XCTAssertEqual(L.ex["squat"]?.rpe, 7.5)
    }
}
