import Foundation
import Observation
import WatchConnectivity
import WatchKit
import BlueLineCore

/// Watch side of WatchConnectivity: receives today's plan, sends each completed set back to the phone.
final class WatchLink: NSObject, WCSessionDelegate {
    var onPlan: ((GuidedPlan) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ set: SetCompletion) {
        guard let data = set.jsonData() else { return }
        WCSession.default.transferUserInfo([WatchKeys.set: data])
    }

    func sendWorkoutSaved(_ key: String) {
        WCSession.default.transferUserInfo([WatchKeys.workoutSaved: key])
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        deliver(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    private func deliver(_ ctx: [String: Any]) {
        guard let plan = GuidedPlan.fromJSON(ctx[WatchKeys.plan]) else { return }
        DispatchQueue.main.async { self.onPlan?(plan) }
    }
}

@Observable @MainActor final class WatchModel {
    private(set) var plan: GuidedPlan?
    private(set) var index = 0
    private(set) var restRemaining = 0
    private(set) var finished = false
    private(set) var saveMessage: String?
    let workout = WorkoutManager()
    private let link = WatchLink()
    private var incoming: GuidedPlan?
    private var restTask: Task<Void, Never>?
    private static let storeKey = "bl.plan"

    init() {
        plan = GuidedPlan.fromJSON(UserDefaults.standard.data(forKey: Self.storeKey))
        link.onPlan = { [weak self] in self?.receive($0) }
        workout.onFinished = { [weak self] ok in self?.workoutFinished(ok) }
    }

    var step: GuidedStep? { plan.flatMap { $0.steps.indices.contains(index) ? $0.steps[index] : nil } }
    var nextStep: GuidedStep? { plan.flatMap { $0.steps.indices.contains(index + 1) ? $0.steps[index + 1] : nil } }
    var isResting: Bool { restRemaining > 0 }

    private func receive(_ p: GuidedPlan) {
        UserDefaults.standard.set(p.jsonData(), forKey: Self.storeKey)
        // The phone re-sends the plan after every set; don't reshuffle a session in progress.
        if workout.isRunning { incoming = p; return }
        plan = p
        index = 0
        finished = false
    }

    func start() async {
        guard let plan else { return }
        index = 0
        finished = false
        saveMessage = nil
        do {
            try await workout.start(title: "W\(plan.week) D\(plan.day) \(plan.title)")
            WKInterfaceDevice.current().play(.start)
        } catch {
            saveMessage = "Couldn't start the workout: \(error.localizedDescription)"
        }
    }

    /// Log the current set and move on, starting rest if the superset round is over.
    func completeSet(reps: Int?, rpe: Double?) {
        guard let plan, let s = step else { return }
        link.send(SetCompletion(step: s, plan: plan, reps: reps, rpe: rpe))
        WKInterfaceDevice.current().play(.success)
        index += 1
        if step == nil { end() } else if s.restAfter > 0 { startRest(s.restAfter) }
    }

    func skipSet() {
        index += 1
        if step == nil { end() }
    }

    func startRest(_ seconds: Int) {
        restTask?.cancel()
        restRemaining = seconds
        restTask = Task { [weak self] in
            while let self, self.restRemaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self.restRemaining -= 1
                if (1...3).contains(self.restRemaining) { WKInterfaceDevice.current().play(.click) }
                if self.restRemaining == 0 { WKInterfaceDevice.current().play(.notification) }
            }
        }
    }

    func skipRest() {
        restTask?.cancel()
        restRemaining = 0
    }

    func end() {
        skipRest()
        finished = true
        workout.end()
    }

    private func workoutFinished(_ ok: Bool) {
        if ok, let plan { link.sendWorkoutSaved(plan.key) }
        saveMessage = ok ? "Saved to Health." : "Workout not saved to Health."
        if let p = incoming { incoming = nil; plan = p; index = 0 }
    }
}
