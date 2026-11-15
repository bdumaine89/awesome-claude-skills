import SwiftUI
import BlueLineCore

enum Theme {
    static let red = Color(red: 0.776, green: 0.165, blue: 0.212)   // #C62A36
    static let blue = Color(red: 0.122, green: 0.373, blue: 0.659)  // #1F5FA8
    static let go = Color(red: 0.090, green: 0.439, blue: 0.290)    // #17704A
    static let warn = Color(red: 0.878, green: 0.643, blue: 0.231)

    static func color(_ band: ReadinessBand) -> Color {
        switch band {
        case .green: return go
        case .yellow: return warn
        case .red: return red
        case .none: return .secondary
        }
    }
}

/// Progress ring for kcal / protein.
struct Ring: View {
    let value: Double
    let target: Double
    let label: String
    let unit: String
    let color: Color

    var body: some View {
        let p = target > 0 ? value / target : 0
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 10)
                Circle().trim(from: 0, to: min(p, 1))
                    .stroke(p > 1.05 ? Theme.warn : color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(value))").font(.system(.title3, design: .monospaced).weight(.semibold))
                    Text("/ \(Int(target)) \(unit)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)
            Text(label).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int(value)) of \(Int(target)) \(unit)")
    }
}

struct MacroBar: View {
    let label: String
    let value: Double
    let target: Double
    let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value)) / \(Int(target)) \(unit)").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.subheadline)
            ProgressView(value: min(value, target), total: max(target, 1))
                .tint(value > target * 1.05 ? Theme.warn : Theme.blue)
        }
    }
}

extension String {
    /// "2026-11-16" → Date at local midnight (falls back to now).
    var dayDate: Date { DayKey.date(self) ?? .now }
}
