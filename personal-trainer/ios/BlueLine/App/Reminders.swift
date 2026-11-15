import Foundation
import UserNotifications

/// Local notifications: daily training reminder, protein check-in, and rest-timer end (for when the app is backgrounded).
enum Reminders {
    static let trainingID = "bl.training", proteinID = "bl.protein", restID = "bl.rest"
    private static var center: UNUserNotificationCenter { .current() }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replace both daily reminders. A nil time turns that reminder off.
    static func schedule(training: Date?, protein: Date?, proteinTarget: Double) {
        center.removePendingNotificationRequests(withIdentifiers: [trainingID, proteinID])
        if let training {
            add(trainingID, at: training, title: "Training time",
                body: "30 minutes. Open Blue Line for today's session and loads.")
        }
        if let protein {
            add(proteinID, at: protein, title: "Protein check-in",
                body: "Target \(Int(proteinTarget)) g. Log what you've eaten and plan the next 35–50 g feeding.")
        }
    }

    private static func add(_ id: String, at time: Date, title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
    }

    static func scheduleRestEnd(in seconds: Int, next: String) {
        guard seconds > 0 else { return }
        let c = UNMutableNotificationContent()
        c.title = "Rest done"
        c.body = next
        c.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: restID, content: c, trigger: trigger))
    }

    static func cancelRestEnd() { center.removePendingNotificationRequests(withIdentifiers: [restID]) }
}
