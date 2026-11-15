import SwiftUI
import BlueLineCore

@main
struct BlueLineWatchApp: App {
    @State private var model = WatchModel()
    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchHomeView() }.environment(model)
        }
    }
}

struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        if model.workout.isRunning {
            WatchSessionView()
        } else if let plan = model.plan {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("W\(plan.week) · \(plan.day == 5 ? "Recovery" : "Day \(plan.day)")").font(.caption).foregroundStyle(.secondary)
                    Text(plan.title).font(.headline)
                    Text("\(plan.steps.count) sets · \(plan.location == .hotel ? "Hotel" : "Gym")").font(.caption2)
                    if plan.trimmed { Text("Yellow readiness: last round dropped, RPE ≤ 7").font(.caption2).foregroundStyle(.yellow) }
                    if let msg = model.saveMessage { Text(msg).font(.caption2).foregroundStyle(.secondary) }
                    Button { Task { await model.start() } } label: { Label("Start", systemImage: "play.fill") }
                        .tint(.green)
                        .disabled(plan.steps.isEmpty)
                }
            }
            .navigationTitle("Blue Line")
        } else {
            Text("Open Blue Line on your iPhone to send today's session.")
                .multilineTextAlignment(.center)
                .navigationTitle("Blue Line")
        }
    }
}

struct WatchSessionView: View {
    @Environment(WatchModel.self) private var model
    @State private var reps: Double = 0
    @State private var askRPE = false

    var body: some View {
        Group {
            if model.isResting {
                VStack(spacing: 6) {
                    Text("REST").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%d:%02d", model.restRemaining / 60, model.restRemaining % 60))
                        .font(.system(size: 44, weight: .semibold, design: .monospaced))
                    if let n = model.step { Text("Next: \(n.slot) \(n.name)").font(.caption2).lineLimit(2) }
                    Button("Skip rest") { model.skipRest() }
                }
            } else if let s = model.step {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.slot.isEmpty ? "Warm-up" : s.slot).font(.caption.bold()).foregroundStyle(.red)
                            Spacer()
                            Label("\(Int(model.workout.heartRate))", systemImage: "heart.fill")
                                .font(.caption.monospacedDigit()).foregroundStyle(.pink)
                        }
                        Text(s.name).font(.headline).lineLimit(2).minimumScaleFactor(0.7)
                        Text(s.of > 1 ? "Set \(s.round) of \(s.of) · \(s.reps)" : s.reps).font(.caption2)
                        if !s.loadText.isEmpty {
                            Text(s.loadText).font(.system(.title3, design: .monospaced).weight(.semibold))
                        }
                        if s.cap != nil { Text("Hotel cap: 4 s lowering").font(.caption2).foregroundStyle(.yellow) }
                        if !s.isWarmup && s.unit != .time {
                            Text("Reps: \(Int(reps))  (turn crown)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Button { done(s) } label: { Label("Done", systemImage: "checkmark") }.tint(.green)
                        HStack {
                            Button("Skip") { model.skipSet() }
                            Button("End", role: .destructive) { model.end() }
                        }
                        .font(.caption2)
                    }
                }
                .focusable()
                .digitalCrownRotation($reps, from: 0, through: 60, by: 1, sensitivity: .low)
                .onAppear { reps = Double(Int(s.reps.prefix { $0.isNumber }) ?? 0) }
                .onChange(of: s.id) { _, _ in reps = Double(Int(s.reps.prefix { $0.isNumber }) ?? 0) }
            } else {
                Text(model.finished ? "Session done. Saving…" : "No sets left.")
            }
        }
        .sheet(isPresented: $askRPE) {
            RPEPicker { rpe in
                askRPE = false
                model.completeSet(reps: reps > 0 ? Int(reps) : nil, rpe: rpe)
            }
        }
    }

    private func done(_ s: GuidedStep) {
        // Last set of a loaded exercise: ask for RPE, which drives next session's load.
        if s.isLastSet && !s.isWarmup && !s.unit.isUnloaded && s.rpe != "—" {
            askRPE = true
        } else {
            model.completeSet(reps: s.isWarmup || s.unit == .time || reps <= 0 ? nil : Int(reps), rpe: nil)
        }
    }
}

struct RPEPicker: View {
    let pick: (Double?) -> Void
    private let options: [Double] = [6, 7, 7.5, 8, 8.5, 9, 9.5, 10]
    var body: some View {
        List {
            Section("Last set RPE") {
                ForEach(options, id: \.self) { v in Button(fmtNum(v)) { pick(v) } }
                Button("Skip") { pick(nil) }
            }
        }
    }
}
