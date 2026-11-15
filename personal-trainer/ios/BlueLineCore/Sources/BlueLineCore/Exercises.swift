import Foundation

/// How a load is expressed. Raw values match the web app's `u` field.
public enum LoadUnit: String, Codable, Sendable {
    case barbell = "bb"        // total bar weight
    case dumbbellPair = "db2"  // per hand
    case dumbbell = "db1"      // one DB
    case cable                 // stack
    case landmine = "lm"       // plates on the sleeve
    case bodyweight = "bw"
    case time
    case medBall = "mb"

    /// No load to prescribe or log.
    public var isUnloaded: Bool { self == .bodyweight || self == .time }
    public var isDumbbell: Bool { self == .dumbbell || self == .dumbbellPair }
}

public enum Role: String, Codable, Sendable, CaseIterable {
    case warm, main, acc, power, core, cond
}

public enum Location: String, Codable, Sendable, CaseIterable {
    case gym, hotel
}

/// One entry of the exercise library (port of `EX` in trainer.html).
/// Hotel variants use dumbbells, a bench, a cable if present, or bodyweight. No resistance bands.
public struct Exercise: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let hotelName: String
    public let unit: LoadUnit
    public let hotelUnit: LoadUnit
    public let gymLoad: Double?
    public let hotelLoad: Double?
    public let increment: Double?
    public let hotelIncrement: Double?
    /// Fixed rep/time prescription that overrides the block scheme (except for main lifts).
    public let reps: String?
    /// Appended to the rep scheme, e.g. "/leg".
    public let repsSuffix: String?
    public let cue: String

    public func name(at loc: Location) -> String { loc == .hotel ? hotelName : name }
    public func unit(at loc: Location) -> LoadUnit { loc == .hotel ? hotelUnit : unit }
    public func baseLoad(at loc: Location) -> Double? { loc == .hotel ? hotelLoad : gymLoad }

    /// YouTube search for a form demo, same query as the web app.
    public func demoURL(at loc: Location) -> URL {
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: name(at: loc) + " exercise proper form")]
        return c.url!
    }
}

private func ex(_ id: String, _ n: String, _ h: String? = nil, u: LoadUnit, hu: LoadUnit? = nil,
                g: Double? = nil, hl: Double? = nil, inc: Double? = nil, hinc: Double? = nil,
                reps: String? = nil, reps2: String? = nil, cue: String) -> Exercise {
    Exercise(id: id, name: n, hotelName: h ?? n, unit: u, hotelUnit: hu ?? u, gymLoad: g, hotelLoad: hl,
             increment: inc, hotelIncrement: hinc, reps: reps, repsSuffix: reps2, cue: cue)
}

public enum ExerciseLibrary {
    public static let all: [Exercise] = [
        ex("warm", "RAMP warm-up", u: .time, reps: "5 min",
           cue: "90/90 hip switches ×6 · World's greatest stretch ×3/side · Hip airplanes ×5/side · Prone Y-T raises ×8 (no weight) · Neck 4-way isometric 5 s each · Pogo hops 2×15 s · Last 2 min: 2 ramp sets of A1"),
        ex("squat", "Back Squat", "DB Goblet Squat", u: .barbell, hu: .dumbbell, g: 135, hl: 50, inc: 10, hinc: 5,
           cue: "Big breath, brace, sit between the hips. Knees track over toes."),
        ex("fsquat", "Front Squat", "DB Front-Rack Squat", u: .barbell, hu: .dumbbellPair, g: 115, hl: 35, inc: 10, hinc: 5,
           cue: "Elbows high, chest tall. Pause 1 s in the hole in week 13–14."),
        ex("trapdl", "Trap-Bar Deadlift", "DB B-Stance RDL (kickstand)", u: .barbell, hu: .dumbbellPair, g: 205, hl: 45, inc: 10, hinc: 5,
           cue: "Push the floor away, finish with glutes, no lean-back."),
        ex("rdl", "Romanian Deadlift", "DB Romanian Deadlift", u: .barbell, hu: .dumbbellPair, g: 135, hl: 40, inc: 10, hinc: 5,
           cue: "Soft knees, hips back, bar on legs. Stop when hamstrings stop you."),
        ex("bss", "Bulgarian Split Squat", u: .dumbbellPair, g: 30, hl: 30, inc: 5, hinc: 5, reps2: "/leg",
           cue: "Front shin vertical-ish, drive through mid-foot. Stride-strength for skating."),
        ex("latlunge", "Lateral Lunge (goblet)", u: .dumbbell, g: 35, hl: 35, inc: 5, hinc: 5, reps2: "/side",
           cue: "Sit into the hip, keep the trail leg straight. Adductor and groin armor."),
        ex("slrdl", "Single-Leg RDL", u: .dumbbell, g: 40, hl: 40, inc: 5, hinc: 5, reps2: "/leg",
           cue: "Weight in opposite hand, square hips, reach long. Golf hip stability."),
        ex("hipthrust", "Barbell Hip Thrust", "Single-Leg Hip Thrust", u: .barbell, hu: .dumbbell, g: 185, hl: 25, inc: 10, hinc: 5,
           cue: "Chin tucked, ribs down, 1 s squeeze at top."),
        ex("nordic", "Nordic Curl (eccentric)", "Slider Hamstring Curl", u: .bodyweight, reps: "3–6",
           cue: "Block 1: 3 reps, add 1 a block. Lower as slow as you can. Hotel: towel under heels on a hard floor."),
        ex("copen", "Copenhagen Plank", "Copenhagen Plank (bench)", u: .time, reps: "20–30 s/side",
           cue: "Top leg on bench, hips stacked. Short lever (knee) in Block 1. #1 groin-strain prevention drill."),
        ex("boxjump", "Box Jump", "Squat Jump", u: .bodyweight, reps: "4",
           cue: "Max intent, step down. Full reset between reps."),
        ex("skater", "Skater Bound (stick 2 s)", u: .bodyweight, reps: "4/side",
           cue: "Push long and lateral, land soft on one leg, hold."),
        ex("broadjump", "Broad Jump", u: .bodyweight, reps: "3",
           cue: "Arm swing, explode, stick the landing."),
        ex("dbbench", "DB Bench Press", u: .dumbbellPair, g: 55, hl: 45, inc: 5, hinc: 5,
           cue: "Shoulder blades pinned, 2 s lower."),
        ex("incdb", "Incline DB Press", u: .dumbbellPair, g: 45, hl: 40, inc: 5, hinc: 5,
           cue: "30° bench, elbows ~45°."),
        ex("landmine", "Half-Kneeling Landmine Press", "Half-Kneeling 1-Arm DB Press", u: .landmine, hu: .dumbbell, g: 25, hl: 35, inc: 5, hinc: 5, reps2: "/arm",
           cue: "Squeeze down-side glute, press up and in. Shoulder-friendly for hockey."),
        ex("pushup", "Tempo Push-up (3-1-1)", u: .bodyweight,
           cue: "Plank body, 3 s down, 1 s pause just off floor."),
        ex("pullup", "Neutral-Grip Pull-up", "Pull-up or Inverted Row", u: .bodyweight,
           cue: "Dead hang to chin over. Add load (belt/DB) once you hit the top of the range."),
        ex("pulldown", "Lat Pulldown", "Pull-up or Inverted Row (under a sturdy table or Smith bar)", u: .cable, hu: .bodyweight, g: 130, hl: 40, inc: 10, hinc: 5,
           cue: "Drive elbows to back pockets, no swing."),
        ex("csrow", "Chest-Supported DB Row", "Incline-Bench DB Row", u: .dumbbellPair, g: 45, hl: 45, inc: 5, hinc: 5,
           cue: "Chest stays on pad, pull to hip, 1 s squeeze."),
        ex("cablerow", "1-Arm Cable Row + Rotation", "1-Arm DB Row", u: .cable, hu: .dumbbell, g: 60, hl: 50, inc: 5, hinc: 5, reps2: "/arm",
           cue: "Reach long, row and rotate through the T-spine."),
        ex("facepull", "Cable Face Pull", "Prone Y-T-W (light DBs)", u: .cable, hu: .dumbbellPair, g: 40, hl: 8, inc: 5, hinc: 2.5,
           cue: "Pull to forehead, thumbs back. Shoulder health for the season."),
        ex("pallof", "Cable Pallof Press", "Plank DB Pull-Through", u: .cable, hu: .dumbbell, g: 30, hl: 20, inc: 5, hinc: 5, reps: "10/side",
           cue: "Resist rotation. Ribs down, 2 s hold at lockout. Hotel: in a high plank, drag the DB across under your body without letting the hips twist."),
        ex("chop", "Cable High-Low Woodchop", "DB Woodchop", u: .cable, hu: .dumbbell, g: 35, hl: 20, inc: 5, hinc: 5, reps: "8/side",
           cue: "Rotate from hips and T-spine, arms are just hooks."),
        ex("lift", "Cable Low-High Lift", "Half-Kneeling DB Lift", u: .cable, hu: .dumbbell, g: 30, hl: 15, inc: 5, hinc: 5, reps: "8/side",
           cue: "Same pattern as a golf finish. Control the return."),
        ex("mbtoss", "Med-Ball Rotational Scoop Toss", "Med-Ball Toss or Speed DB Chop", u: .medBall, hu: .dumbbell, g: 8, hl: 10, inc: 2, hinc: 5, reps: "5/side",
           cue: "Load back hip, throw through the wall. Clubhead speed and shot power."),
        ex("mbslam", "Med-Ball Slam", "Burpee to Broad Jump", u: .medBall, hu: .bodyweight, g: 15, inc: 5, reps: "6",
           cue: "Full extension, slam through the floor."),
        ex("deadbug", "Dead Bug (DB overhead)", u: .dumbbell, g: 15, hl: 15, inc: 5, hinc: 5, reps: "8/side",
           cue: "Low back glued down, exhale fully on each rep."),
        ex("sideplank", "Side Plank with Reach-Through", u: .time, reps: "30 s/side",
           cue: "Stack hips, reach under and rotate."),
        ex("carry", "Suitcase Carry", u: .dumbbell, g: 70, hl: 50, inc: 5, hinc: 5, reps: "40 m/side",
           cue: "Stand tall, don't lean. Anti-lateral-flexion."),
        ex("bike", "Bike Intervals (Assault/Echo)", "Bike / Treadmill Incline Intervals", u: .time, reps: "6 × 30 s hard / 45 s easy",
           cue: "Shift-length efforts. Skip on weeks with 2+ hockey games; do D5 Zone 2 on hockey-free weeks. RPE 9 on the work, true easy on recovery."),
        ex("z2", "Zone 2 Cardio", "Zone 2 Cardio (bike/incline walk)", u: .time, reps: "25 min @ HR 125–140",
           cue: "Nasal breathing pace. Watch: Workout → Indoor Cycle, heart-rate zone 2 alert."),
        ex("hipir", "90/90 Hip IR Lift-off", u: .time, reps: "5 × 5 s/side",
           cue: "Sit 90/90, torso tall, lift the back knee and foot off the floor by internally rotating the back hip. Hold 5 s. Lead-hip IR for the golf downswing; hockey hips lose IR first."),
        ex("mobflow", "Mobility Flow", u: .time, reps: "5 min",
           cue: "Couch stretch, 90/90, T-spine open-books, thread the needle."),
    ]

    public static let byID: [String: Exercise] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static subscript(id: String) -> Exercise? { byID[id] }
}
