import SwiftUI
import SwiftData
import BlueLineCore

/// Meal log with manual macros, and the day's totals against target. Meals are also written to Apple Health.
struct FuelView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \MealRecord.time) private var meals: [MealRecord]
    @Query private var days: [DayRecord]
    @State private var date = Date()
    @State private var adding = false

    /// Swap in a real implementation to enable photo estimates (see MealEstimator.swift).
    static var estimator: any MealEstimator = UnconfiguredMealEstimator()

    var body: some View {
        let key = DayKey.from(date)
        let todays = meals.filter { $0.day == key }
        let t = EnergyModel(profile: model.profile, days: Store.metrics(days: days, meals: meals), today: model.today).targets(for: key)
        let sum = todays.reduce(into: (k: 0.0, p: 0.0, c: 0.0, f: 0.0)) { $0.k += $1.kcal; $0.p += $1.protein; $0.c += $1.carbs; $0.f += $1.fat }
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                    MacroBar(label: "Calories", value: sum.k, target: t.kcal, unit: "kcal")
                    MacroBar(label: "Protein", value: sum.p, target: t.protein, unit: "g")
                    MacroBar(label: "Carbs", value: sum.c, target: t.carbs, unit: "g")
                    MacroBar(label: "Fat", value: sum.f, target: t.fat, unit: "g")
                    if t.sportAdjust != 0 {
                        Text("Includes \(Int(t.sportAdjust)) kcal sport adjustment (hockey/golf).").font(.caption).foregroundStyle(.secondary)
                    }
                    if sum.p < t.protein && key == model.today {
                        Text("\(Int(t.protein - sum.p)) g protein to go. Aim for 35–50 g per feeding.")
                            .font(.footnote)
                    }
                }
                Section("Meals") {
                    if todays.isEmpty {
                        Text("No meals logged for this day.").foregroundStyle(.secondary)
                    }
                    ForEach(todays) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(m.name).font(.headline)
                                Spacer()
                                Text("\(Int(m.kcal)) kcal").monospacedDigit()
                            }
                            Text("\(m.time.formatted(date: .omitted, time: .shortened)) · P \(Int(m.protein)) · C \(Int(m.carbs)) · F \(Int(m.fat))"
                                 + (m.inHealth ? " · in Health" : ""))
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { idx in idx.map { todays[$0] }.forEach(model.deleteMeal) }
                }
            }
            .navigationTitle("Fuel")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add meal")
                }
            }
            .sheet(isPresented: $adding) { MealEditor(day: date) }
        }
    }
}

struct MealEditor: View {
    let day: Date
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var time = Date()
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    var body: some View {
        NavigationStack {
            Form {
                TextField("What did you eat?", text: $name)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                Section("Macros") {
                    field("Calories", $kcal, "kcal")
                    field("Protein", $protein, "g")
                    field("Carbs", $carbs, "g")
                    field("Fat", $fat, "g")
                    if let k = kcal, let p = protein, let c = carbs, let f = fat {
                        let calc = p * 4 + c * 4 + f * 9
                        if abs(calc - k) > 0.15 * max(k, 1) {
                            Text("Macros add up to \(Int(calc)) kcal; check the numbers.").font(.caption).foregroundStyle(Theme.warn)
                        }
                    }
                }
                Section {
                    Button { } label: { Label("Estimate from photo", systemImage: "camera") }
                        .disabled(!FuelView.estimator.isAvailable)
                } footer: {
                    Text("Photo estimates are a future feature (MealEstimator hook). For now, enter macros by hand or ask Claude in chat.")
                }
            }
            .navigationTitle("Log meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.addMeal(MealRecord(time: combined, name: name.isEmpty ? "Meal" : name, kcal: kcal ?? 0,
                                                 protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0))
                        dismiss()
                    }
                    .disabled(kcal == nil)
                }
            }
        }
    }

    /// The selected day with the chosen clock time.
    private var combined: Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    private func field(_ label: String, _ value: Binding<Double?>, _ unit: String) -> some View {
        HStack {
            Text(label)
            TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
