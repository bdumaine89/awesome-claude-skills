import SwiftUI
import BlueLineCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Program") {
                    DatePicker("Start date", selection: Binding(
                        get: { model.profile.start.dayDate },
                        set: { model.profile.start = DayKey.from($0) }), displayedComponents: .date)
                    Text("Current week: \(model.week) of 16").foregroundStyle(.secondary)
                    Picker("Location", selection: $model.profile.loc) {
                        Text("Work gym").tag(Location.gym)
                        Text("Hotel").tag(Location.hotel)
                    }
                    Stepper("Hotel DB max: \(fmtNum(model.profile.hotelMax)) lb", value: $model.profile.hotelMax, in: 20...120, step: 5)
                }
                Section("Body") {
                    Stepper("Age: \(model.profile.age)", value: $model.profile.age, in: 18...90)
                    Stepper("Height: \(fmtNum(model.profile.heightCm)) cm", value: $model.profile.heightCm, in: 140...210, step: 0.5)
                    Stepper("Start: \(fmtNum(model.profile.startLb)) lb", value: $model.profile.startLb, in: 100...400)
                    Stepper("Goal: \(fmtNum(model.profile.goalLb)) lb", value: $model.profile.goalLb, in: 100...400)
                }
                Section {
                    Stepper("Deficit: \(Int(model.profile.deficit)) kcal", value: $model.profile.deficit, in: 0...1000, step: 50)
                    Stepper("Protein: \(Int(model.profile.protein)) g", value: $model.profile.protein, in: 100...250, step: 5)
                    Stepper("Fat: \(Int(model.profile.fat)) g", value: $model.profile.fat, in: 40...120, step: 5)
                } header: { Text("Targets") } footer: {
                    Text("Calories never go below 1,800 kcal/day.")
                }
                Section("Reminders") {
                    reminder("Daily training", $model.trainingReminder, defaultHour: 6)
                    reminder("Protein check-in", $model.proteinReminder, defaultHour: 15)
                }
                Section("Apple Health") {
                    Button("Connect / refresh Apple Health") { Task { await model.connectHealth() } }
                    Text("Reads energy, HRV, resting HR, weight, body fat, sleep, steps and workouts. Writes strength workouts and logged meals.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func reminder(_ title: String, _ time: Binding<Date?>, defaultHour: Int) -> some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: Binding(
                get: { time.wrappedValue != nil },
                set: { on in
                    time.wrappedValue = on ? Calendar.current.date(bySettingHour: defaultHour, minute: 0, second: 0, of: .now) : nil
                }))
            if let t = time.wrappedValue {
                DatePicker("Time", selection: Binding(get: { t }, set: { time.wrappedValue = $0 }), displayedComponents: .hourAndMinute)
            }
        }
    }
}
