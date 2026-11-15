import SwiftUI
import SwiftData

@main
struct BlueLineApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @Environment(\.scenePhase) private var phase

    init() {
        let c = Store.makeContainer()
        container = c
        _model = State(initialValue: AppModel(container: c))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await Reminders.requestAuthorization() }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await model.refreshHealth() } }
                }
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "sun.max") }
            NavigationStack { CurrentSessionView() }.tabItem { Label("Session", systemImage: "dumbbell") }
            ProgramView().tabItem { Label("Program", systemImage: "calendar") }
            FuelView().tabItem { Label("Fuel", systemImage: "fork.knife") }
            BodyView().tabItem { Label("Body", systemImage: "scalemass") }
        }
        .tint(Theme.blue)
    }
}

/// The Session tab always opens the next session for this week.
struct CurrentSessionView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let n = model.nextSession(band: model.readiness(model.metrics())?.band ?? .none)
        SessionView(week: n.week, day: n.day).id("\(n.week)-\(n.day)")
    }
}
