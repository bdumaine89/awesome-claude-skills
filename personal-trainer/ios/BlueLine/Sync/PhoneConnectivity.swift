import Foundation
import WatchConnectivity
import BlueLineCore

/// iPhone side of WatchConnectivity.
/// - Phone → Watch: today's `GuidedPlan` as application context (latest value wins).
/// - Watch → Phone: each completed set as `transferUserInfo` (queued, delivered in order, survives the phone being away).
/// UNTESTED on device.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    var onSet: ((SetCompletion) -> Void)?
    var onWorkoutSaved: ((String) -> Void)?
    private var pending: GuidedPlan?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ plan: GuidedPlan) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { pending = plan; return }
        guard s.isPaired, s.isWatchAppInstalled, let data = plan.jsonData() else { return }
        try? s.updateApplicationContext([WatchKeys.plan: data])
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated, let p = pending {
            pending = nil
            DispatchQueue.main.async { self.send(p) }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let set = SetCompletion.fromJSON(userInfo[WatchKeys.set])
        let saved = userInfo[WatchKeys.workoutSaved] as? String
        DispatchQueue.main.async {
            if let set { self.onSet?(set) }
            if let saved { self.onWorkoutSaved?(saved) }
        }
    }
}
