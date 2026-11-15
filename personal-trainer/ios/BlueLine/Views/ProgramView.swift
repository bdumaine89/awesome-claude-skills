import SwiftUI
import SwiftData
import BlueLineCore

struct SessionRoute: Hashable { let week: Int; let day: Int }

/// 16-week grid: 4 blocks × 4 weeks × (4 lifting days + recovery), with block completion.
struct ProgramView: View {
    @Environment(AppModel.self) private var model
    @Query private var records: [SessionRecord]
    @State private var path: [SessionRoute] = []

    var body: some View {
        let logs = Dictionary(records.map { ($0.key, $0.log) }, uniquingKeysWith: { a, _ in a })
        NavigationStack(path: $path) {
            List {
                ForEach(Program.blocks.indices, id: \.self) { b in
                    let block = Program.blocks[b]
                    let prog = Program.blockProgress(b, logs: logs)
                    Section {
                        Text(block.goal).font(.footnote).foregroundStyle(.secondary)
                        ForEach(Array(block.weeks), id: \.self) { w in weekRow(w, logs: logs) }
                    } header: {
                        HStack {
                            Text("Block \(b + 1) · \(block.name)")
                            Spacer()
                            Text("\(prog.done)/\(prog.total)").monospacedDigit()
                            if prog.done == prog.total { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.go) }
                        }
                    }
                }
            }
            .navigationTitle("Program")
            .navigationDestination(for: SessionRoute.self) { SessionView(week: $0.week, day: $0.day) }
        }
    }

    private func weekRow(_ w: Int, logs: [String: SessionLog]) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading) {
                Text("W\(w)").font(.headline.monospacedDigit())
                Text(Program.isDeload(w) ? "Deload" : (Program.isTest(w) ? "Test" : " "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 52, alignment: .leading)
            ForEach(1...5, id: \.self) { d in
                let L = logs[Program.logKey(week: w, day: d)]
                let p = L?.progress ?? (done: 0, total: Program.items(week: w, day: d).count)
                Button { path.append(SessionRoute(week: w, day: d)) } label: {
                    Text(d == 5 ? "R" : "D\(d)")
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(p.done == p.total ? Theme.go : (p.done > 0 ? Theme.go.opacity(0.3) : Color.secondary.opacity(0.12)),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(p.done == p.total ? Color.white : Color.primary)
                        .overlay {
                            if w == model.week { RoundedRectangle(cornerRadius: 6).stroke(Theme.red, lineWidth: 2) }
                        }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Week \(w) \(d == 5 ? "recovery" : "day \(d)"), \(p.done) of \(p.total) done")
            }
        }
    }
}
