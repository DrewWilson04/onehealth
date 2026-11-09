import SwiftUI
import PulseCore
import PulseKit

/// Food with calories + macros, recent foods and saved meals.
struct FoodLogView: View {
    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var meal: MealSlot = .defaultForNow
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var fiber: Double?
    @State private var sugar: Double?
    @State private var sodium: Double?
    @State private var date = Date()
    @State private var showMore = false
    @State private var recents: [FoodEntry] = []
    @State private var saveAsMeal = false
    @State private var mealName = ""
    @State private var info: String?

    private var entry: FoodEntry {
        FoodEntry(name: name.isEmpty ? "Food" : name, date: date, kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0,
                  fat: fat ?? 0, fiber: fiber, sugar: sugar, sodium: sodium, meal: meal)
    }

    var body: some View {
        Form {
            if !settings.mealTemplates.isEmpty {
                Section("Saved meals") {
                    ForEach(settings.mealTemplates) { t in
                        Button {
                            Task { await logTemplate(t) }
                        } label: {
                            LabeledContent(t.name, value: "\(Int(t.totalKcal)) kcal")
                        }
                    }
                    .onDelete { idx in idx.map { settings.mealTemplates[$0].id }.forEach(settings.deleteMealTemplate) }
                }
            }
            if !recents.isEmpty {
                Section("Recent foods") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(recents) { r in
                                Button { fill(r) } label: {
                                    VStack(alignment: .leading) {
                                        Text(r.name).font(.subheadline).lineLimit(1)
                                        Text("\(Int(r.kcal)) kcal").font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(Theme.bluishGreen.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Section {
                TextField("Name", text: $name)
                Picker("Meal", selection: $meal) { ForEach(MealSlot.allCases) { Text($0.title).tag($0) } }
                DatePicker("Time", selection: $date)
            }
            Section {
                numberField("Calories (kcal)", $kcal)
                numberField("Protein (g)", $protein)
                numberField("Carbs (g)", $carbs)
                numberField("Fat (g)", $fat)
                DisclosureGroup("More nutrients", isExpanded: $showMore) {
                    numberField("Fiber (g)", $fiber)
                    numberField("Sugar (g)", $sugar)
                    numberField("Sodium (mg)", $sodium)
                }
            } footer: {
                if let k = kcal, entry.macroKcal > 0, abs(entry.macroKcal - k) / max(k, 1) > 0.25 {
                    Text("Macros add up to about \(Int(entry.macroKcal)) kcal.").foregroundStyle(Theme.orange)
                }
            }
            Section {
                Toggle("Also save as a meal", isOn: $saveAsMeal)
                if saveAsMeal { TextField("Meal name", text: $mealName) }
            } footer: {
                Text("Saved meals sync to your other devices through iCloud as templates. The food you eat is saved to Apple Health.")
            }
        }
        .logForm("Log Food", canSave: (kcal ?? 0) > 0) {
            let e = entry
            let id = try await services.writer.logFood(e)
            try? await services.store.addFoodLog(e, healthKitId: id)
            if saveAsMeal {
                var item = e
                item.id = UUID().uuidString
                settings.saveMealTemplate(MealTemplate(name: mealName.isEmpty ? e.name : mealName, items: [item]))
            }
            await services.didWrite([.dietaryEnergy, .protein, .carbohydrates, .fat])
        }
        .task { recents = (try? await services.store.recentFoods()) ?? [] }
    }

    private func numberField(_ title: String, _ value: Binding<Double?>) -> some View {
        TextField(title, value: value, format: .number).keyboardType(.decimalPad)
    }

    private func fill(_ r: FoodEntry) {
        name = r.name; kcal = r.kcal; protein = r.protein; carbs = r.carbs; fat = r.fat
    }

    private func logTemplate(_ t: MealTemplate) async {
        for var item in t.items {
            item.id = UUID().uuidString
            item.date = date
            item.meal = meal
            if let id = try? await services.writer.logFood(item) {
                try? await services.store.addFoodLog(item, healthKitId: id)
            }
        }
        await services.didWrite([.dietaryEnergy, .protein, .carbohydrates, .fat])
        dismiss()
    }
}

extension MealSlot {
    static var defaultForNow: MealSlot {
        switch Calendar.current.component(.hour, from: Date()) {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}
