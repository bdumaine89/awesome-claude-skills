import Foundation
import Observation
import UIKit

/// Rest countdown with haptics: light taps at 3-2-1, success buzz at zero.
/// A local notification covers the case where the app is in the background.
@Observable @MainActor final class RestTimer {
    private(set) var total = 0
    private(set) var remaining = 0
    private var endsAt: Date?
    private var task: Task<Void, Never>?

    var isRunning: Bool { endsAt != nil }
    var progress: Double { total > 0 ? Double(total - remaining) / Double(total) : 0 }

    func start(_ seconds: Int, next: String = "Next set.") {
        guard seconds > 0 else { return }
        stop()
        total = seconds
        remaining = seconds
        endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        Reminders.scheduleRestEnd(in: seconds, next: next)
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.tick()
            }
        }
    }

    func add(_ seconds: Int) {
        guard let e = endsAt else { return }
        endsAt = e.addingTimeInterval(TimeInterval(seconds))
        total += seconds
        Reminders.cancelRestEnd()
        Reminders.scheduleRestEnd(in: Int(endsAt!.timeIntervalSinceNow.rounded(.up)), next: "Next set.")
        tick()
    }

    func stop() {
        task?.cancel()
        task = nil
        endsAt = nil
        remaining = 0
        Reminders.cancelRestEnd()
    }

    private func tick() {
        guard let e = endsAt else { return }
        let left = max(0, Int(e.timeIntervalSinceNow.rounded(.up)))
        if left != remaining, (1...3).contains(left) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        remaining = left
        if left == 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            stop()
        }
    }
}
