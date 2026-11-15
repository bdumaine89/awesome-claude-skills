import Foundation
import HealthKit
import Observation

/// Strength workout on the Watch: HKWorkoutSession + HKLiveWorkoutBuilder for live heart rate and energy,
/// saved to Health as Traditional Strength Training when the session ends. UNTESTED on device.
@Observable @MainActor final class WorkoutManager: NSObject {
    let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private(set) var heartRate: Double = 0
    private(set) var activeKcal: Double = 0
    private(set) var isRunning = false
    private(set) var startDate: Date?
    /// Called on the main actor with `true` once the workout is saved to Health.
    var onFinished: ((Bool) -> Void)?

    func requestAuthorization() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start(title: String) async throws {
        guard !isRunning else { return }
        await requestAuthorization()
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let s = try HKWorkoutSession(healthStore: store, configuration: config)
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        s.delegate = self
        b.delegate = self
        session = s
        builder = b
        let start = Date()
        s.startActivity(with: start)
        try await b.beginCollection(at: start)
        try? await b.addMetadata([HKMetadataKeyWorkoutBrandName: "Blue Line Training", "BLSession": title])
        startDate = start
        isRunning = true
    }

    /// Ends the session; the workout is finished and saved in the state-change delegate.
    func end() {
        guard isRunning else { onFinished?(false); return }
        session?.end()
    }

    private func finish(at date: Date) async {
        var ok = false
        if let b = builder {
            do {
                try await b.endCollection(at: date)
                ok = try await b.finishWorkout() != nil
            } catch { ok = false }
        }
        isRunning = false
        session = nil
        builder = nil
        heartRate = 0
        onFinished?(ok)
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in await self.finish(at: date) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in await self.finish(at: Date()) }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: bpm)
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in
            if let hr { self.heartRate = hr }
            if let kcal { self.activeKcal = kcal }
        }
    }
}
