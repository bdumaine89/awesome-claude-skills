import SwiftUI
import SwiftData
import BlueLineCore

/// One session: supersets with per-set checklist rows (done, load, reps), last-set RPE,
/// rest timer with haptics, gym/hotel toggle and a "Watch demo" link per exercise.
struct SessionView: View {
    let week: Int
    let day: Int
    @Environment(AppModel.self) private var model
    @Query private var records: [SessionRecord]
    @State private var log: SessionLog
    @State private var loaded = false
    @State private var timer = RestTimer()

    init(week: Int, day: Int) {
        self.week = week
        self.day = day
        _log = State(initialValue: SessionLog(week: week, day: day, location: .gym))
    }

    private static let rpeOptions: [Double] = [6, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    var body: some View {
        let logs = records.map(\.log).filter { $0.key != log.key }
        let band = model.readiness(model.metrics())?.band ?? .none
        let items = log.items
        let plan = Program.dayPlan(week: week, day: day)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Week \(week) · \(day == Program.recoveryDayIndex ? "Recovery" : "Day \(day)")"
                         + (Program.isDeload(week) ? " · Deload" : "") + (Program.isTest(week) ? " · Test week" : ""))
                        .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                    Text(plan.name).font(.title2.weight(.bold))
                    Text("Block \(Program.blockIndex(week: week) + 1): \(Program.block(week: week).name)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Picker("Location", selection: locationBinding) {
                    Text("Work gym").tag(Location.gym)
                    Text("Hotel").tag(Location.hotel)
                }
                .pickerStyle(.segmented)
                if band == .yellow || band == .red {
                    Label(band.advice, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.color(band))
                }
                if Program.isTest(week) {
                    Label("Test week: last set of each main lift is AMRAP at the week-1 load.", systemImage: "flag.checkered")
                        .font(.footnote)
                }
            }
            ForEach(["W", "A", "B", "C"], id: \.self) { tag in
                let group = items.filter { $0.tag == tag }
                if !group.isEmpty {
                    Section(tag == "W" ? "Warm-up" : "Superset \(tag)") {
                        ForEach(group) { it in
                            exerciseRow(it, band: band, logs: logs, isLastInGroup: it == group.last)
                        }
                    }
                }
            }
            Section {
                let p = log.progress
                HStack {
                    Text("\(p.done) of \(p.total) done")
                    Spacer()
                    if log.completedAt != nil { Label("Complete", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.go) }
                }
                Button { model.pushPlanToWatch() } label: { Label("Send to Apple Watch", systemImage: "applewatch") }
                Button { timer.start(60) } label: { Label("Start 60 s rest", systemImage: "timer") }
            }
        }
        .navigationTitle("W\(week) D\(day)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { if timer.isRunning { RestBar(timer: timer) } }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            guard !loaded else { return }
            log = model.log(week: week, day: day)
            loaded = true
        }
        .onChange(of: log) { _, new in if loaded { model.save(new) } }
        .onDisappear { timer.stop() }
    }

    private var locationBinding: Binding<Location> {
        Binding(get: { log.loc }, set: { log.loc = $0; model.profile.loc = $0 })
    }

    // MARK: Rows

    @ViewBuilder
    private func exerciseRow(_ it: SessionItem, band: ReadinessBand, logs: [SessionLog], isLastInGroup: Bool) -> some View {
        let e = it.info
        let rx = Program.adjusted(Program.prescription(week: week, day: day, item: it), item: it, week: week, day: day, band: band)
        let sg = model.engine.suggest(week: week, day: day, item: it, location: log.loc, logs: logs)
        let entry = log.ex[it.exercise]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if !it.slot.isEmpty { Text(it.slot).font(.headline).foregroundStyle(Theme.red) }
                Text(e.name(at: log.loc)).font(.headline).strikethrough(entry?.done == true, color: Theme.go)
                Spacer()
                if entry?.done == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.go) }
            }
            HStack(spacing: 10) {
                Text(it.role == .warm ? rx.reps : "\(rx.sets) × \(rx.reps)")
                if !rx.rpe.isEmpty && rx.rpe != "—" { Text("RPE \(rx.rpe)") }
                if !rx.rest.isEmpty && rx.rest != "—" { Text("Rest \(rx.rest)") }
                if !sg.text.isEmpty {
                    Text(sg.text).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 6).background(Theme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            if !sg.why.isEmpty && sg.why != "plan" { Text(sg.why).font(.caption).foregroundStyle(.secondary) }
            if let cap = sg.cap { Text(cap).font(.caption).foregroundStyle(Theme.warn) }
            if let orig = it.original, let o = ExerciseLibrary[orig] { Text("Swapped from \(o.name)").font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Cue") { Text(e.cue).font(.footnote) }.font(.footnote)

            if it.role == .warm || sg.unit == .time {
                Toggle(isOn: Binding(get: { entry?.done == true }, set: { log.setDone(it.exercise, $0, count: rx.sets) })) {
                    Text(rx.sets > 1 ? "All \(rx.sets) rounds done" : "Done")
                }
            } else {
                ForEach(0..<rx.sets, id: \.self) { i in
                    setRow(it, index: i, rx: rx, sg: sg, restAfter: isLastInGroup || it.slot.hasSuffix("2"))
                }
                Picker("Last set RPE", selection: Binding(get: { entry?.rpe }, set: { log.setRPE(it.exercise, $0) })) {
                    Text("–").tag(Double?.none)
                    ForEach(Self.rpeOptions, id: \.self) { Text(fmtNum($0)).tag(Double?.some($0)) }
                }
                .pickerStyle(.menu)
            }
            Link(destination: e.demoURL(at: log.loc)) { Label("Watch demo", systemImage: "play.rectangle") }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private func setRow(_ it: SessionItem, index i: Int, rx: Prescription, sg: Suggestion, restAfter: Bool) -> some View {
        let s = setBinding(it.exercise, i, rx.sets)
        let hasLoad = !sg.unit.isUnloaded
        let amrap = rx.amrapLastSet && i == rx.sets - 1
        return HStack(spacing: 10) {
            Text(amrap ? "AMRAP" : "Set \(i + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Button {
                var v = s.wrappedValue
                v.done.toggle()
                if v.done {
                    if hasLoad && v.load == nil { v.load = amrap ? (sg.amrapLoad ?? sg.lb) : sg.lb }
                    if v.reps == nil { v.reps = rx.targetReps }
                }
                s.wrappedValue = v
                if v.done && restAfter && i < rx.sets - 1 { timer.start(rx.restSeconds, next: "Back to it: set \(i + 2).") }
            } label: {
                Image(systemName: s.wrappedValue.done ? "checkmark.square.fill" : "square")
                    .font(.title2).foregroundStyle(s.wrappedValue.done ? Theme.go : .secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Set \(i + 1) done")
            .sensoryFeedback(.success, trigger: s.wrappedValue.done) { _, new in new }
            if hasLoad {
                TextField(fmtNum(amrap ? (sg.amrapLoad ?? sg.lb) : sg.lb), value: s.load, format: .number)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Set \(i + 1) load in pounds")
                Text("lb").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("BW").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField(rx.targetReps.map { String($0) } ?? "reps", value: s.reps, format: .number)
                .keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 64)
                .accessibilityLabel("Set \(i + 1) reps")
        }
    }

    private func setBinding(_ ex: String, _ i: Int, _ n: Int) -> Binding<SetEntry> {
        Binding(get: { log.ex[ex]?.sets[safe: i] ?? SetEntry() },
                set: { v in log.setSet(ex, index: i, count: n) { $0 = v } })
    }
}

struct RestBar: View {
    let timer: RestTimer
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
            Text(String(format: "%d:%02d", timer.remaining / 60, timer.remaining % 60))
                .font(.system(.title2, design: .monospaced).weight(.semibold))
            ProgressView(value: timer.progress)
            Button("+15") { timer.add(15) }.buttonStyle(.bordered)
            Button("Skip") { timer.stop() }.buttonStyle(.borderedProminent).tint(Theme.red)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer, \(timer.remaining) seconds left")
    }
}
