import SwiftUI

private enum NutritionBarcodeScanTarget: String, Identifiable {
    case lookup
    case customFood

    var id: String { rawValue }
}

private struct MealIntakeLogTarget: Identifiable {
    let mealIndex: Int
    var id: Int { mealIndex }
}

struct NutritionPlannerCard: View {
    @EnvironmentObject private var store: AppStore
    private let foodSearchService = NutritionFoodSearchService()
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var draft: DailyMealPlan = DailyMealPlan.defaultTemplate(
        date: Calendar.current.startOfDay(for: Date()),
        athleteName: nil
    )
    @State private var feedback: String?
    @State private var gptSummary: String?
    @State private var foodSearchText = ""
    @AppStorage("nutrition.usda.apiKey") private var usdaAPIKey: String = ""
    @State private var externalProvider: NutritionFoodSearchProvider = .openFoodFacts
    @State private var externalSearchQuery = ""
    @State private var barcodeQuery = ""
    @State private var externalSearchResults: [NutritionFoodSearchHit] = []
    @State private var isSearchingExternalFoods = false
    @State private var isBarcodeLookupRunning = false
    @State private var customFoodName = ""
    @State private var customFoodServing = "100g"
    @State private var customFoodCalories = ""
    @State private var customFoodProtein = ""
    @State private var customFoodCarbs = ""
    @State private var customFoodFat = ""
    @State private var customFoodBarcode = ""
    @State private var customFoodCategory: FoodLibraryCategory = .snack
    @State private var editingCustomFoodID: UUID?
    @State private var activeBarcodeScannerTarget: NutritionBarcodeScanTarget?
    @State private var mealIntakeLogTarget: MealIntakeLogTarget?
    @State private var mealIntakeSearchText = ""
    @State private var mealIntakeServings: Double = 1.0
    @State private var isGeneratingGPTPlan = false

    private var canEdit: Bool {
        !store.isAllAthletesSelected
    }

    private var selectedAthleteProfile: AthleteProfile {
        store.profileForAthlete(named: store.selectedAthleteNameForWrite)
    }

    private var plannedTotals: MealNutritionTotals {
        draft.plannedTotals
    }

    private var actualTotals: MealNutritionTotals {
        draft.actualTotals
    }

    private var hydrationProgress: Double {
        let target = max(0.1, draft.hydrationTargetLiters)
        return min(max(draft.hydrationActualLiters / target, 0), 1.5)
    }

    private var filteredFoodLibrary: [FoodLibraryItem] {
        let query = foodSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let merged = store.allNutritionFoodLibraryItems
        guard !query.isEmpty else { return merged }
        return merged.filter { $0.searchableText.contains(query) }
    }

    private var builtInLibraryCount: Int {
        FoodLibraryItem.commonLibrary.count
    }

    private var customLibraryCount: Int {
        store.customFoodLibrary.count
    }

    private var allSelectableFoodsByCode: [String: FoodLibraryItem] {
        Dictionary(
            uniqueKeysWithValues: (store.allNutritionFoodLibraryItems + externalSearchResults.map { $0.food }).map { ($0.code, $0) }
        )
    }

    private var mealIntakeFilteredLibrary: [FoodLibraryItem] {
        let query = mealIntakeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let merged = store.allNutritionFoodLibraryItems
        guard !query.isEmpty else { return Array(merged.prefix(80)) }
        return Array(merged.filter { $0.searchableText.contains(query) }.prefix(120))
    }

    private var totalMainMealTargetCalories: Int {
        draft.mainMealTargets.reduce(0) { $0 + max(0, $1.calories) }
    }

    private func normalizedDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func estimatedTrainingCaloriesForSelectedAthlete(on day: Date) -> Int {
        let calendar = Calendar.current
        let rows = store.activitiesForAthlete(named: store.selectedAthleteNameForWrite)
            .filter { calendar.isDate($0.date, inSameDayAs: day) }

        let total = rows.reduce(0) { partial, activity in
            if activity.tss > 0 {
                return partial + Int((Double(activity.tss) * 8.0).rounded())
            }
            let hours = Double(max(0, activity.durationSec)) / 3600.0
            let fallbackPerHour: Double
            switch activity.sport {
            case .cycling: fallbackPerHour = 450
            case .running: fallbackPerHour = 650
            case .swimming: fallbackPerHour = 550
            case .strength: fallbackPerHour = 300
            }
            return partial + Int((hours * fallbackPerHour).rounded())
        }
        return max(0, min(4000, total))
    }

    private func profileBasedHydrationTargetLiters(extraTrainingCalories: Int) -> Double {
        let baseline = max(1.5, min(6.0, selectedAthleteProfile.athleteWeightKg * 0.035))
        let trainingExtra = Double(extraTrainingCalories) / 1000.0 * 0.6
        let raw = baseline + trainingExtra
        return (raw * 10.0).rounded() / 10.0
    }

    private func makeProfileDrivenTemplate(
        date: Date,
        goalProfile: NutritionGoalProfile
    ) -> DailyMealPlan {
        let day = normalizedDay(date)
        let extraTrainingCalories = estimatedTrainingCaloriesForSelectedAthlete(on: day)
        let profile = selectedAthleteProfile
        var plan = DailyMealPlan.defaultTemplate(date: day, athleteName: store.selectedAthleteNameForWrite)
        plan.goalProfile = goalProfile
        plan.mealTargets = profile.recommendedMainMealTargets(
            goalProfile: goalProfile,
            extraTrainingCalories: extraTrainingCalories
        )
        plan.hydrationTargetLiters = profileBasedHydrationTargetLiters(extraTrainingCalories: extraTrainingCalories)
        return plan
    }

    private func applyAthleteProfileTargetsToDraft() {
        let extraTrainingCalories = estimatedTrainingCaloriesForSelectedAthlete(on: normalizedDay(selectedDate))
        draft.mealTargets = selectedAthleteProfile.recommendedMainMealTargets(
            goalProfile: draft.goalProfile,
            extraTrainingCalories: extraTrainingCalories
        )
        draft.hydrationTargetLiters = profileBasedHydrationTargetLiters(extraTrainingCalories: extraTrainingCalories)
        applyMainMealTargetsToPlanMacros()
        feedback = L10n.choose(
            simplifiedChinese: "已按 Athlete Profile（BMR/活动系数）重算三餐目标与饮水目标（未保存）",
            english: "Recomputed meal + hydration targets from athlete profile (BMR/activity factor) (not saved)."
        )
    }

    private var nutritionProfileReferenceText: String {
        let profile = selectedAthleteProfile
        let extra = estimatedTrainingCaloriesForSelectedAthlete(on: normalizedDay(selectedDate))
        let target = profile.recommendedDailyNutritionTargetKcal(
            goalProfile: draft.goalProfile,
            extraTrainingCalories: extra
        )
        let factorText = String(format: "%.2f", profile.nutritionActivityFactor)
        return L10n.choose(
            simplifiedChinese: "BMR \(profile.basalMetabolicRateKcal) · 系数 \(factorText) · 维持约 \(profile.estimatedDailyMaintenanceCalories) kcal · 当日训练估算 +\(extra) kcal · 建议目标 \(target) kcal",
            english: "BMR \(profile.basalMetabolicRateKcal) · factor \(factorText) · maintenance ~\(profile.estimatedDailyMaintenanceCalories) kcal · training +\(extra) kcal · suggested \(target) kcal"
        )
    }

    private func reloadDraft() {
        let day = normalizedDay(selectedDate)
        selectedDate = day
        if let existing = store.dailyMealPlanForSelectedAthlete(on: day) {
            draft = existing
        } else {
            draft = makeProfileDrivenTemplate(date: day, goalProfile: .balanced)
            applyMainMealTargetsToPlanMacros()
        }
        feedback = nil
        gptSummary = nil
    }

    private func saveDraft() {
        var saving = draft
        saving.date = normalizedDay(selectedDate)
        saving.athleteName = store.selectedAthleteNameForWrite
        store.saveDailyMealPlanForSelectedAthlete(saving)
        feedback = L10n.choose(simplifiedChinese: "已保存当日饮食记录", english: "Daily meal record saved.")
        reloadDraft()
    }

    private func copyFromYesterday() {
        let day = normalizedDay(selectedDate)
        guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else { return }
        if let copied = store.copyDailyMealPlanTemplateForSelectedAthlete(from: previous, to: day) {
            draft = copied
            feedback = L10n.choose(simplifiedChinese: "已套用昨日模板", english: "Copied yesterday template.")
        } else {
            feedback = L10n.choose(simplifiedChinese: "昨日无可用模板", english: "No template available for yesterday.")
        }
    }

    private func resetToTemplate() {
        draft = makeProfileDrivenTemplate(date: normalizedDay(selectedDate), goalProfile: draft.goalProfile)
        applyMainMealTargetsToPlanMacros()
        feedback = L10n.choose(simplifiedChinese: "已重置为默认模板（未保存）", english: "Reset to default template (not saved).")
        gptSummary = nil
    }

    private func applyPlannedToActualForAll() {
        draft.applyPlannedToActualForAllItems()
        feedback = L10n.choose(simplifiedChinese: "已按计划填充实际摄入（未保存）", english: "Filled actual intake from plan (not saved).")
    }

    private func applyMainMealTargetsToPlanMacros() {
        let targetsBySlot = Dictionary(uniqueKeysWithValues: draft.mainMealTargets.map { ($0.slot, $0) })
        for index in draft.items.indices {
            guard let target = targetsBySlot[draft.items[index].slot] else { continue }
            draft.items[index].plannedCalories = max(0, target.calories)
            draft.items[index].plannedProtein = max(0, target.protein)
            draft.items[index].plannedCarbs = max(0, target.carbs)
            draft.items[index].plannedFat = max(0, target.fat)
        }
        feedback = L10n.choose(simplifiedChinese: "已将三餐目标同步到计划宏量（未保存）", english: "Applied meal targets to planned macros (not saved).")
    }

    private func addFoodToFridge(_ food: FoodLibraryItem) {
        if let idx = draft.fridgeItems.firstIndex(where: { $0.foodCode == food.code }) {
            draft.fridgeItems[idx].servings += 1
        } else {
            let source: String
            if food.code.hasPrefix("off_") {
                source = "OpenFoodFacts"
            } else if food.code.hasPrefix("usda_") {
                source = "USDA"
            } else if UUID(uuidString: food.code) != nil {
                source = L10n.choose(simplifiedChinese: "自定义", english: "Custom")
            } else {
                source = L10n.choose(simplifiedChinese: "内置", english: "Built-in")
            }
            draft.fridgeItems.append(
                FridgeFoodEntry(
                    foodCode: food.code,
                    foodName: food.displayName,
                    servings: 1,
                    servingLabel: food.servingLabel,
                    caloriesPerServing: food.calories,
                    proteinPerServing: food.protein,
                    carbsPerServing: food.carbs,
                    fatPerServing: food.fat,
                    source: source
                )
            )
        }
    }

    private func addFoodToFridgeFromDrop(_ token: String) {
        if let item = allSelectableFoodsByCode[token] ?? FoodLibraryItem.lookup(code: token) {
            addFoodToFridge(item)
            return
        }
        let fallbackName = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackName.isEmpty else { return }
        if let idx = draft.fridgeItems.firstIndex(where: { $0.foodName == fallbackName }) {
            draft.fridgeItems[idx].servings += 1
        } else {
            draft.fridgeItems.append(FridgeFoodEntry(foodCode: fallbackName, foodName: fallbackName, servings: 1))
        }
    }

    private func removeFridgeItem(id: UUID) {
        draft.fridgeItems.removeAll { $0.id == id }
    }

    private func clearFridge() {
        draft.fridgeItems.removeAll()
        feedback = L10n.choose(simplifiedChinese: "已清空冰箱（未保存）", english: "Fridge cleared (not saved).")
    }

    private func mealIntakeNutrients(for entry: FridgeFoodEntry) -> (calories: Int, protein: Double, carbs: Double, fat: Double)? {
        if let calories = entry.caloriesPerServing,
           let protein = entry.proteinPerServing,
           let carbs = entry.carbsPerServing,
           let fat = entry.fatPerServing {
            return (calories, protein, carbs, fat)
        }
        if let food = allSelectableFoodsByCode[entry.foodCode] ?? FoodLibraryItem.lookup(code: entry.foodCode) {
            return (food.calories, food.protein, food.carbs, food.fat)
        }
        return nil
    }

    private func appendActualFoodText(_ text: String, to itemIndex: Int) {
        guard draft.items.indices.contains(itemIndex) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = draft.items[itemIndex].actualFood.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            draft.items[itemIndex].actualFood = trimmed
        } else {
            let separator = L10n.choose(simplifiedChinese: " + ", english: " + ")
            draft.items[itemIndex].actualFood = existing + separator + trimmed
        }
    }

    private func addFoodToActualMeal(itemIndex: Int, food: FoodLibraryItem, servings: Double, displayName: String? = nil) {
        guard draft.items.indices.contains(itemIndex) else { return }
        let s = max(0.1, min(99, servings))
        draft.items[itemIndex].actualCalories += Int((Double(food.calories) * s).rounded())
        draft.items[itemIndex].actualProtein += food.protein * s
        draft.items[itemIndex].actualCarbs += food.carbs * s
        draft.items[itemIndex].actualFat += food.fat * s

        let name = displayName ?? food.displayName
        let suffix = abs(s - 1.0) < 0.05 ? name : "\(name) ×\(String(format: "%.1f", s))"
        appendActualFoodText(suffix, to: itemIndex)
    }

    private func addFridgeEntryToActualMeal(itemIndex: Int, entry: FridgeFoodEntry, servingsOverride: Double? = nil) {
        guard let nutrients = mealIntakeNutrients(for: entry) else {
            appendActualFoodText(entry.foodName, to: itemIndex)
            return
        }
        let s = max(0.1, min(99, servingsOverride ?? entry.servings))
        let proxy = FoodLibraryItem(
            code: entry.foodCode,
            category: .snack,
            nameZH: entry.foodName,
            nameEN: entry.foodName,
            servingLabelZH: entry.servingLabel ?? "1 serving",
            servingLabelEN: entry.servingLabel ?? "1 serving",
            calories: nutrients.calories,
            protein: nutrients.protein,
            carbs: nutrients.carbs,
            fat: nutrients.fat,
            keywords: []
        )
        addFoodToActualMeal(itemIndex: itemIndex, food: proxy, servings: s, displayName: entry.foodName)
    }

    private func clearActualMealIntake(itemIndex: Int) {
        guard draft.items.indices.contains(itemIndex) else { return }
        draft.items[itemIndex].actualFood = ""
        draft.items[itemIndex].actualCalories = 0
        draft.items[itemIndex].actualProtein = 0
        draft.items[itemIndex].actualCarbs = 0
        draft.items[itemIndex].actualFat = 0
    }

    @MainActor
    private func runExternalFoodSearch() async {
        let query = externalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            externalSearchResults = []
            return
        }
        guard !isSearchingExternalFoods else { return }
        isSearchingExternalFoods = true
        defer { isSearchingExternalFoods = false }
        do {
            externalSearchResults = try await foodSearchService.search(
                query: query,
                provider: externalProvider,
                usdaAPIKey: usdaAPIKey
            )
            feedback = L10n.choose(
                simplifiedChinese: "外部食品搜索返回 \(externalSearchResults.count) 条结果（\(externalProvider.label)）",
                english: "External food search returned \(externalSearchResults.count) result(s) (\(externalProvider.label))."
            )
        } catch {
            feedback = L10n.choose(
                simplifiedChinese: "外部食品搜索失败：\(error.localizedDescription)",
                english: "External food search failed: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func lookupBarcode() async {
        let barcode = barcodeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !barcode.isEmpty else { return }
        guard !isBarcodeLookupRunning else { return }
        isBarcodeLookupRunning = true
        defer { isBarcodeLookupRunning = false }
        do {
            if let custom = store.customFoodByBarcode(barcode) {
                let item = custom.asFoodLibraryItem()
                externalSearchResults = [
                    NutritionFoodSearchHit(
                        provider: .openFoodFacts,
                        food: item,
                        brand: nil,
                        barcode: custom.barcode,
                        sourceDescription: L10n.choose(simplifiedChinese: "本地自定义食品", english: "Local custom food")
                    )
                ]
                feedback = L10n.choose(simplifiedChinese: "已命中本地自定义食品条码", english: "Matched local custom-food barcode.")
                return
            }
            externalSearchResults = try await foodSearchService.lookupBarcode(barcode, usdaAPIKey: usdaAPIKey)
            feedback = L10n.choose(
                simplifiedChinese: "条码查询返回 \(externalSearchResults.count) 条结果",
                english: "Barcode lookup returned \(externalSearchResults.count) result(s)."
            )
        } catch {
            feedback = L10n.choose(
                simplifiedChinese: "条码查询失败：\(error.localizedDescription)",
                english: "Barcode lookup failed: \(error.localizedDescription)"
            )
        }
    }

    private func saveCustomFoodFromForm() {
        let name = customFoodName.trimmingCharacters(in: .whitespacesAndNewlines)
        let serving = customFoodServing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !serving.isEmpty else {
            feedback = L10n.choose(simplifiedChinese: "请填写自定义食品名称和份量描述", english: "Enter custom-food name and serving label.")
            return
        }

        let calories = Int(customFoodCalories.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let protein = Double(customFoodProtein.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let carbs = Double(customFoodCarbs.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let fat = Double(customFoodFat.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let existing = editingCustomFoodID.flatMap { id in
            store.customFoodLibrary.first(where: { $0.id == id })
        }

        let item = CustomFoodLibraryItem(
            id: existing?.id ?? UUID(),
            category: customFoodCategory,
            nameZH: name,
            nameEN: name,
            servingLabelZH: serving,
            servingLabelEN: serving,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            barcode: customFoodBarcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customFoodBarcode.trimmingCharacters(in: .whitespacesAndNewlines),
            keywords: [customFoodCategory.rawValue],
            createdAt: existing?.createdAt ?? Date()
        )
        store.upsertCustomNutritionFood(item)
        if existing == nil {
            addFoodToFridge(item.asFoodLibraryItem())
            feedback = L10n.choose(simplifiedChinese: "已保存自定义食品并加入冰箱（未保存餐单）", english: "Custom food saved and added to fridge (meal plan not saved).")
        } else {
            feedback = L10n.choose(simplifiedChinese: "已更新自定义食品（未保存餐单）", english: "Custom food updated (meal plan not saved).")
        }
        clearCustomFoodForm()
    }

    private func clearCustomFoodForm() {
        editingCustomFoodID = nil
        customFoodName = ""
        customFoodServing = "100g"
        customFoodCalories = ""
        customFoodProtein = ""
        customFoodCarbs = ""
        customFoodFat = ""
        customFoodBarcode = ""
        customFoodCategory = .snack
    }

    private func populateCustomFoodForm(_ custom: CustomFoodLibraryItem) {
        editingCustomFoodID = custom.id
        customFoodName = custom.displayName
        customFoodServing = L10n.choose(simplifiedChinese: custom.servingLabelZH, english: custom.servingLabelEN)
        customFoodCalories = custom.calories == 0 ? "" : String(custom.calories)
        customFoodProtein = custom.protein == 0 ? "" : String(format: "%.1f", custom.protein)
        customFoodCarbs = custom.carbs == 0 ? "" : String(format: "%.1f", custom.carbs)
        customFoodFat = custom.fat == 0 ? "" : String(format: "%.1f", custom.fat)
        customFoodBarcode = custom.barcode ?? ""
        customFoodCategory = custom.category
    }

    private func applyScannedBarcode(_ code: String, target: NutritionBarcodeScanTarget) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch target {
        case .lookup:
            barcodeQuery = trimmed
            Task { await lookupBarcode() }
        case .customFood:
            customFoodBarcode = trimmed
            feedback = L10n.choose(simplifiedChinese: "已填入自定义食品条码", english: "Filled custom-food barcode.")
        }
    }

    @MainActor
    private func generateNutritionPlanWithGPT() async {
        guard canEdit else { return }
        guard !isGeneratingGPTPlan else { return }
        isGeneratingGPTPlan = true
        defer { isGeneratingGPTPlan = false }
        feedback = L10n.choose(simplifiedChinese: "正在调用 GPT 生成餐单...", english: "Generating meal plan with GPT...")

        do {
            let (generatedDraft, payload) = try await store.generateNutritionPlanDraftWithGPT(from: draft)
            draft = generatedDraft
            gptSummary = payload.summary
            let noteCount = payload.notes.count
            feedback = noteCount > 0
                ? L10n.choose(simplifiedChinese: "GPT 已生成今日餐单（含 \(noteCount) 条执行建议，未保存）", english: "GPT meal plan generated (\(noteCount) execution notes, not saved).")
                : L10n.choose(simplifiedChinese: "GPT 已生成今日餐单（未保存）", english: "GPT meal plan generated (not saved).")
        } catch {
            feedback = L10n.choose(simplifiedChinese: "GPT 生成失败：\(error.localizedDescription)", english: "GPT generation failed: \(error.localizedDescription)")
        }
    }

    private func intBinding(item index: Int, keyPath: WritableKeyPath<MealPlanItem, Int>) -> Binding<Int> {
        Binding(
            get: {
                guard draft.items.indices.contains(index) else { return 0 }
                return draft.items[index][keyPath: keyPath]
            },
            set: { newValue in
                guard draft.items.indices.contains(index) else { return }
                draft.items[index][keyPath: keyPath] = max(0, newValue)
            }
        )
    }

    private func doubleBinding(item index: Int, keyPath: WritableKeyPath<MealPlanItem, Double>) -> Binding<Double> {
        Binding(
            get: {
                guard draft.items.indices.contains(index) else { return 0 }
                return draft.items[index][keyPath: keyPath]
            },
            set: { newValue in
                guard draft.items.indices.contains(index) else { return }
                draft.items[index][keyPath: keyPath] = max(0, newValue)
            }
        )
    }

    private var hydrationTargetBinding: Binding<Double> {
        Binding(
            get: { draft.hydrationTargetLiters },
            set: { draft.hydrationTargetLiters = max(0.1, $0) }
        )
    }

    private var hydrationActualBinding: Binding<Double> {
        Binding(
            get: { draft.hydrationActualLiters },
            set: { draft.hydrationActualLiters = max(0, $0) }
        )
    }

    private var goalProfileBinding: Binding<NutritionGoalProfile> {
        Binding(
            get: { draft.goalProfile },
            set: { draft.goalProfile = $0 }
        )
    }

    private func mealTargetIntBinding(slot: MealSlot, keyPath: WritableKeyPath<MealMacroTarget, Int>) -> Binding<Int> {
        Binding(
            get: {
                draft.target(for: slot)?[keyPath: keyPath] ?? 0
            },
            set: { newValue in
                var target = draft.target(for: slot) ?? MealMacroTarget(slot: slot)
                target[keyPath: keyPath] = max(0, newValue)
                draft.setTarget(target)
            }
        )
    }

    private func mealTargetDoubleBinding(slot: MealSlot, keyPath: WritableKeyPath<MealMacroTarget, Double>) -> Binding<Double> {
        Binding(
            get: {
                draft.target(for: slot)?[keyPath: keyPath] ?? 0
            },
            set: { newValue in
                var target = draft.target(for: slot) ?? MealMacroTarget(slot: slot)
                target[keyPath: keyPath] = max(0, newValue)
                draft.setTarget(target)
            }
        )
    }

    private func fridgeServingBinding(entryID: UUID) -> Binding<Double> {
        Binding(
            get: {
                draft.fridgeItems.first(where: { $0.id == entryID })?.servings ?? 1
            },
            set: { newValue in
                guard let idx = draft.fridgeItems.firstIndex(where: { $0.id == entryID }) else { return }
                draft.fridgeItems[idx].servings = max(0.1, min(99, newValue))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            if !canEdit {
                Text(
                    L10n.choose(
                        simplifiedChinese: "当前为“全部运动员”视图。请切换到具体运动员后再编辑饮食计划。",
                        english: "You are in 'All Athletes'. Switch to a specific athlete to edit meal plans."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                controlsView
                targetsSection
                foodLibraryAndFridgeSection
                nutritionSummaryChips
                hydrationSection
                mealEditorSection
                notesSection
            }

            if let gptSummary, !gptSummary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.choose(simplifiedChinese: "GPT 今日饮食方案摘要", english: "GPT meal-plan summary"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(gptSummary)
                        .font(.subheadline)
                }
                .padding(10)
                .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { reloadDraft() }
        .onChange(of: selectedDate) { _, _ in reloadDraft() }
        .onChange(of: store.selectedAthletePanelID) { _, _ in reloadDraft() }
        .sheet(item: $activeBarcodeScannerTarget) { target in
            NutritionBarcodeScannerSheet { code in
                applyScannedBarcode(code, target: target)
                activeBarcodeScannerTarget = nil
            } onCancel: {
                activeBarcodeScannerTarget = nil
            }
        }
        .sheet(item: $mealIntakeLogTarget) { target in
            mealIntakeLogSheet(for: target.mealIndex)
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.choose(simplifiedChinese: "饮食计划与打卡", english: "Nutrition Plan & Log"))
                    .font(.title3.bold())
                Text(
                    L10n.choose(
                        simplifiedChinese: "支持三餐目标、常见食品库、冰箱管理，并可用 GPT 基于食材与目标生成今日餐单。",
                        english: "Set meal targets, manage a common food library + fridge, and use GPT to build today's meal plan."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.selectedAthleteTitle)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.background.tertiary, in: Capsule())
        }
    }

    private var controlsView: some View {
        HStack(spacing: 10) {
            DatePicker(
                L10n.choose(simplifiedChinese: "日期", english: "Date"),
                selection: $selectedDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .frame(maxWidth: 180, alignment: .leading)

            Picker(L10n.choose(simplifiedChinese: "饮食目标", english: "Goal profile"), selection: goalProfileBinding) {
                ForEach(NutritionGoalProfile.allCases) { goal in
                    Text(goal.label).tag(goal)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)

            Button(L10n.choose(simplifiedChinese: "套用昨日", english: "Use Yesterday")) { copyFromYesterday() }
                .buttonStyle(.bordered)
            Button(L10n.choose(simplifiedChinese: "默认模板", english: "Reset Template")) { resetToTemplate() }
                .buttonStyle(.bordered)
            Button(L10n.choose(simplifiedChinese: "按计划打卡", english: "Fill Actual")) { applyPlannedToActualForAll() }
                .buttonStyle(.bordered)

            Spacer()

            Button(L10n.choose(simplifiedChinese: "GPT 生成今日餐单", english: "GPT Plan Today")) {
                Task { await generateNutritionPlanWithGPT() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGeneratingGPTPlan)

            Button(L10n.choose(simplifiedChinese: "保存饮食记录", english: "Save Meal Log")) { saveDraft() }
                .buttonStyle(.borderedProminent)
        }
        .overlay(alignment: .bottomLeading) {
            if isGeneratingGPTPlan {
                ProgressView()
                    .controlSize(.small)
                    .offset(y: 22)
            }
        }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.choose(simplifiedChinese: "三餐目标（热量 + 三大营养素）", english: "Three-meal targets (calories + macros)"))
                        .font(.headline)
                    Text(draft.goalProfile.guidanceHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(nutritionProfileReferenceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(totalMainMealTargetCalories) kcal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(L10n.choose(simplifiedChinese: "按 BMR 重算", english: "Recalc from BMR")) {
                    applyAthleteProfileTargetsToDraft()
                }
                .buttonStyle(.bordered)
                Button(L10n.choose(simplifiedChinese: "同步到计划宏量", english: "Apply to Plan")) {
                    applyMainMealTargetsToPlanMacros()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                MealTargetCard(
                    title: MealSlot.breakfast.label,
                    tint: .orange,
                    calories: mealTargetIntBinding(slot: .breakfast, keyPath: \.calories),
                    protein: mealTargetDoubleBinding(slot: .breakfast, keyPath: \.protein),
                    carbs: mealTargetDoubleBinding(slot: .breakfast, keyPath: \.carbs),
                    fat: mealTargetDoubleBinding(slot: .breakfast, keyPath: \.fat)
                )
                MealTargetCard(
                    title: MealSlot.lunch.label,
                    tint: .green,
                    calories: mealTargetIntBinding(slot: .lunch, keyPath: \.calories),
                    protein: mealTargetDoubleBinding(slot: .lunch, keyPath: \.protein),
                    carbs: mealTargetDoubleBinding(slot: .lunch, keyPath: \.carbs),
                    fat: mealTargetDoubleBinding(slot: .lunch, keyPath: \.fat)
                )
                MealTargetCard(
                    title: MealSlot.dinner.label,
                    tint: .blue,
                    calories: mealTargetIntBinding(slot: .dinner, keyPath: \.calories),
                    protein: mealTargetDoubleBinding(slot: .dinner, keyPath: \.protein),
                    carbs: mealTargetDoubleBinding(slot: .dinner, keyPath: \.carbs),
                    fat: mealTargetDoubleBinding(slot: .dinner, keyPath: \.fat)
                )
            }
        }
    }

    private var foodLibraryAndFridgeSection: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.choose(simplifiedChinese: "食品库（内置 + 自定义 + 外部搜索）", english: "Food Library (built-in + custom + external)"))
                        .font(.headline)
                    Spacer()
                    Text("\(filteredFoodLibrary.count) / \(builtInLibraryCount + customLibraryCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(
                    L10n.choose(
                        simplifiedChinese: "内置 \(builtInLibraryCount) 项 · 自定义 \(customLibraryCount) 项。支持拖拽加入冰箱。",
                        english: "Built-in \(builtInLibraryCount) · Custom \(customLibraryCount). Drag items into the fridge."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                TextField(
                    L10n.choose(simplifiedChinese: "搜索食品（名称/类别）", english: "Search foods (name/category)"),
                    text: $foodSearchText
                )
                .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Picker(L10n.choose(simplifiedChinese: "外部库", english: "Provider"), selection: $externalProvider) {
                            ForEach(NutritionFoodSearchProvider.allCases) { provider in
                                Text(provider.label).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 180)

                        TextField(
                            L10n.choose(simplifiedChinese: "外部搜索（USDA / OpenFoodFacts）", english: "External search (USDA / OpenFoodFacts)"),
                            text: $externalSearchQuery
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await runExternalFoodSearch() } }

                        Button(L10n.choose(simplifiedChinese: "搜索", english: "Search")) {
                            Task { await runExternalFoodSearch() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSearchingExternalFoods)
                    }

                    HStack(spacing: 8) {
                        TextField(
                            L10n.choose(simplifiedChinese: "条码（EAN/UPC）", english: "Barcode (EAN/UPC)"),
                            text: $barcodeQuery
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                        .onSubmit { Task { await lookupBarcode() } }

                        Button(L10n.choose(simplifiedChinese: "查条码", english: "Lookup Barcode")) {
                            Task { await lookupBarcode() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBarcodeLookupRunning)

                        #if os(iOS)
                        Button(L10n.choose(simplifiedChinese: "扫码", english: "Scan")) {
                            activeBarcodeScannerTarget = .lookup
                        }
                        .buttonStyle(.bordered)
                        #endif

                        TextField(
                            L10n.choose(simplifiedChinese: "USDA API Key（可选，默认 DEMO_KEY）", english: "USDA API Key (optional, defaults to DEMO_KEY)"),
                            text: $usdaAPIKey
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(8)
                .background(.background.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

                if !externalSearchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.choose(simplifiedChinese: "外部搜索结果", english: "External search results"))
                            .font(.subheadline.weight(.semibold))
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(externalSearchResults) { hit in
                                    FoodSearchResultRow(hit: hit) {
                                        addFoodToFridge(hit.food)
                                    }
                                    .onDrag {
                                        NSItemProvider(object: hit.food.code as NSString)
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 100, maxHeight: 180)
                    }
                    .padding(8)
                    .background(.background.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredFoodLibrary, id: \.id) { food in
                            FoodLibraryRow(food: food, onAdd: { addFoodToFridge(food) })
                                .onDrag {
                                    NSItemProvider(object: food.code as NSString)
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 180, maxHeight: 260)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.choose(simplifiedChinese: "自定义食品录入", english: "Custom food entry"))
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        TextField(L10n.choose(simplifiedChinese: "食品名称", english: "Food name"), text: $customFoodName)
                            .textFieldStyle(.roundedBorder)
                        Picker(L10n.choose(simplifiedChinese: "类别", english: "Category"), selection: $customFoodCategory) {
                            ForEach(FoodLibraryCategory.allCases) { category in
                                Text(category.label).tag(category)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 160)
                    }

                    HStack(spacing: 8) {
                        TextField(L10n.choose(simplifiedChinese: "份量描述（如 100g / 1个）", english: "Serving label (e.g. 100g / 1 piece)"), text: $customFoodServing)
                            .textFieldStyle(.roundedBorder)
                        TextField(L10n.choose(simplifiedChinese: "条码（可选）", english: "Barcode (optional)"), text: $customFoodBarcode)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        #if os(iOS)
                        Button {
                            activeBarcodeScannerTarget = .customFood
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                        }
                        .buttonStyle(.bordered)
                        .help(L10n.choose(simplifiedChinese: "摄像头扫码填入条码", english: "Scan barcode with camera"))
                        #endif
                    }

                    HStack(spacing: 8) {
                        TextField("kcal", text: $customFoodCalories)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        TextField("P", text: $customFoodProtein)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        TextField("C", text: $customFoodCarbs)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        TextField("F", text: $customFoodFat)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Button(L10n.choose(simplifiedChinese: editingCustomFoodID == nil ? "保存自定义食品" : "更新自定义食品", english: editingCustomFoodID == nil ? "Save Custom Food" : "Update Custom Food")) {
                            saveCustomFoodFromForm()
                        }
                        .buttonStyle(.borderedProminent)
                        if editingCustomFoodID != nil {
                            Button(L10n.choose(simplifiedChinese: "取消编辑", english: "Cancel Edit")) {
                                clearCustomFoodForm()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if !store.customFoodLibrary.isEmpty {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(store.customFoodLibrary.prefix(10)) { custom in
                                    CustomFoodLibraryRow(custom: custom, onAdd: {
                                        addFoodToFridge(custom.asFoodLibraryItem())
                                    }, onEdit: {
                                        populateCustomFoodForm(custom)
                                    }, onDelete: {
                                        store.removeCustomNutritionFood(id: custom.id)
                                        if editingCustomFoodID == custom.id {
                                            clearCustomFoodForm()
                                        }
                                    })
                                    .onDrag { NSItemProvider(object: custom.id.uuidString as NSString) }
                                }
                            }
                        }
                        .frame(maxHeight: 140)
                    }
                }
                .padding(8)
                .background(.background.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.background.tertiary.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.choose(simplifiedChinese: "冰箱（把食品拖到这里）", english: "Fridge (drop foods here)"))
                        .font(.headline)
                    Spacer()
                    if !draft.fridgeItems.isEmpty {
                        Button(L10n.choose(simplifiedChinese: "清空", english: "Clear")) {
                            clearFridge()
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if draft.fridgeItems.isEmpty {
                    Text(
                        L10n.choose(
                            simplifiedChinese: "从左侧食品库拖入食物，或点击 + 添加。GPT 会优先使用冰箱中的食材。",
                            english: "Drag foods from the library or tap +. GPT will prioritize ingredients in the fridge."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.background.secondary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(draft.fridgeItems) { entry in
                                FridgeFoodRow(
                                    entry: entry,
                                    libraryItem: allSelectableFoodsByCode[entry.foodCode] ?? FoodLibraryItem.lookup(code: entry.foodCode),
                                    servings: fridgeServingBinding(entryID: entry.id),
                                    onRemove: { removeFridgeItem(id: entry.id) }
                                )
                            }
                        }
                    }
                    .frame(minHeight: 180, maxHeight: 260)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(.mint.opacity(0.35))
            )
            .dropDestination(for: String.self) { items, _ in
                guard !items.isEmpty else { return false }
                for token in items { addFoodToFridgeFromDrop(token) }
                feedback = L10n.choose(simplifiedChinese: "已添加食材到冰箱（未保存）", english: "Added ingredients to fridge (not saved).")
                return true
            }
        }
    }

    private var nutritionSummaryChips: some View {
        HStack(spacing: 10) {
            NutritionProgressChip(
                title: L10n.choose(simplifiedChinese: "热量完成", english: "Calories"),
                planned: Double(plannedTotals.calories),
                actual: Double(actualTotals.calories),
                unit: "kcal",
                tint: .orange
            )
            NutritionProgressChip(
                title: "Protein",
                planned: plannedTotals.protein,
                actual: actualTotals.protein,
                unit: "g",
                tint: .teal
            )
            NutritionProgressChip(
                title: "Carbs",
                planned: plannedTotals.carbs,
                actual: actualTotals.carbs,
                unit: "g",
                tint: .blue
            )
            NutritionProgressChip(
                title: "Fat",
                planned: plannedTotals.fat,
                actual: actualTotals.fat,
                unit: "g",
                tint: .pink
            )
        }
    }

    private var hydrationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.choose(simplifiedChinese: "饮水目标 / 实际", english: "Hydration target / actual"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f / %.1f L", draft.hydrationActualLiters, draft.hydrationTargetLiters))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: hydrationProgress, total: 1.0)
                .tint(.cyan)
            HStack(spacing: 10) {
                TextField(
                    L10n.choose(simplifiedChinese: "目标 L", english: "Target L"),
                    value: hydrationTargetBinding,
                    format: .number.precision(.fractionLength(1))
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)

                TextField(
                    L10n.choose(simplifiedChinese: "实际 L", english: "Actual L"),
                    value: hydrationActualBinding,
                    format: .number.precision(.fractionLength(1))
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
            }
        }
        .padding(10)
        .background(.background.tertiary.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
    }

    private var mealEditorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.choose(simplifiedChinese: "分餐计划与实际记录", english: "Meal plan + actual intake"))
                .font(.headline)

            ForEach(draft.items.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(draft.items[index].slot.label)
                            .font(.headline)
                        Spacer()
                        if let target = draft.target(for: draft.items[index].slot) {
                            Text("Target \(target.calories) kcal · P\(Int(target.protein)) C\(Int(target.carbs)) F\(Int(target.fat))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button(L10n.choose(simplifiedChinese: "按计划", english: "Use Plan")) {
                            draft.items[index].applyPlannedToActual()
                        }
                        .buttonStyle(.borderless)
                        Button(L10n.choose(simplifiedChinese: "录入", english: "Log")) {
                            mealIntakeSearchText = ""
                            mealIntakeServings = 1.0
                            mealIntakeLogTarget = MealIntakeLogTarget(mealIndex: index)
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack(spacing: 8) {
                        TextField(
                            L10n.choose(simplifiedChinese: "计划吃什么", english: "Planned food"),
                            text: $draft.items[index].plannedFood
                        )
                        .textFieldStyle(.roundedBorder)
                        TextField(
                            L10n.choose(simplifiedChinese: "实际吃了什么", english: "Actual food"),
                            text: $draft.items[index].actualFood
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow {
                            Text("kcal").font(.caption.bold())
                            TextField("0", value: intBinding(item: index, keyPath: \.plannedCalories), format: .number)
                                .textFieldStyle(.roundedBorder)
                            TextField("0", value: intBinding(item: index, keyPath: \.actualCalories), format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("P(g)").font(.caption.bold())
                            TextField("0", value: doubleBinding(item: index, keyPath: \.plannedProtein), format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder)
                            TextField("0", value: doubleBinding(item: index, keyPath: \.actualProtein), format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("C(g)").font(.caption.bold())
                            TextField("0", value: doubleBinding(item: index, keyPath: \.plannedCarbs), format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder)
                            TextField("0", value: doubleBinding(item: index, keyPath: \.actualCarbs), format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("F(g)").font(.caption.bold())
                            TextField("0", value: doubleBinding(item: index, keyPath: \.plannedFat), format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder)
                            TextField("0", value: doubleBinding(item: index, keyPath: \.actualFat), format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack {
                        Text(L10n.choose(simplifiedChinese: "计划", english: "Plan"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(L10n.choose(simplifiedChinese: "实际", english: "Actual"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.background.tertiary.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var notesSection: some View {
        TextField(
            L10n.choose(simplifiedChinese: "当天备注（饥饿感、胃肠反应、训练配餐感受）", english: "Daily notes (hunger, GI response, fueling feedback)"),
            text: $draft.notes,
            axis: .vertical
        )
        .textFieldStyle(.roundedBorder)
        .lineLimit(4...8)
    }

    @ViewBuilder
    private func mealIntakeLogSheet(for itemIndex: Int) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                if draft.items.indices.contains(itemIndex) {
                    Text(
                        L10n.choose(
                            simplifiedChinese: "为 \(draft.items[itemIndex].slot.label) 录入实际进食。选择食物后会自动累加到实际热量与三大营养素。",
                            english: "Log actual intake for \(draft.items[itemIndex].slot.label). Selecting foods will add to actual calories + macros."
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TextField(
                        L10n.choose(simplifiedChinese: "搜索食品", english: "Search foods"),
                        text: $mealIntakeSearchText
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        L10n.choose(simplifiedChinese: "份数", english: "Servings"),
                        value: $mealIntakeServings,
                        format: .number.precision(.fractionLength(1))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                }

                if !draft.fridgeItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.choose(simplifiedChinese: "从冰箱录入", english: "Log from Fridge"))
                            .font(.subheadline.weight(.semibold))
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(draft.fridgeItems) { entry in
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.foodName).font(.subheadline.weight(.semibold))
                                            let servingDesc = entry.servingLabel ?? L10n.choose(simplifiedChinese: "每份", english: "per serving")
                                            Text("\(servingDesc) · 冰箱 \(String(format: "%.1f", entry.servings))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button(L10n.choose(simplifiedChinese: "按冰箱份数", english: "Use Fridge Qty")) {
                                            addFridgeEntryToActualMeal(itemIndex: itemIndex, entry: entry)
                                        }
                                        .buttonStyle(.bordered)
                                        Button(L10n.choose(simplifiedChinese: "按录入份数", english: "Use Input Qty")) {
                                            addFridgeEntryToActualMeal(itemIndex: itemIndex, entry: entry, servingsOverride: mealIntakeServings)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding(8)
                                    .background(.background.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.choose(simplifiedChinese: "从食品库录入", english: "Log from Food Library"))
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(mealIntakeFilteredLibrary, id: \.id) { food in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(food.displayName).font(.subheadline.weight(.semibold))
                                        Text("\(food.servingLabel) · \(food.calories) kcal · P\(Int(food.protein.rounded())) C\(Int(food.carbs.rounded())) F\(Int(food.fat.rounded()))")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(L10n.choose(simplifiedChinese: "录入", english: "Add")) {
                                        addFoodToActualMeal(itemIndex: itemIndex, food: food, servings: mealIntakeServings)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .padding(8)
                                .background(.background.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .frame(minHeight: 220, maxHeight: 320)
                }

                if draft.items.indices.contains(itemIndex) {
                    HStack {
                        Text(L10n.choose(simplifiedChinese: "当前实际", english: "Current actual"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        let item = draft.items[itemIndex]
                        Text("\(item.actualCalories) kcal · P\(Int(item.actualProtein.rounded())) C\(Int(item.actualCarbs.rounded())) F\(Int(item.actualFat.rounded()))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .navigationTitle(
                draft.items.indices.contains(itemIndex)
                ? L10n.choose(simplifiedChinese: "\(draft.items[itemIndex].slot.label)录入", english: "\(draft.items[itemIndex].slot.label) Log")
                : L10n.choose(simplifiedChinese: "录入", english: "Log Intake")
            )
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.choose(simplifiedChinese: "关闭", english: "Close")) {
                        mealIntakeLogTarget = nil
                    }
                }
                ToolbarItem {
                    Button(L10n.choose(simplifiedChinese: "清空本餐实际", english: "Clear Meal Actual")) {
                        clearActualMealIntake(itemIndex: itemIndex)
                    }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 560)
    }
}

private struct MealTargetCard: View {
    let title: String
    let tint: Color
    let calories: Binding<Int>
    let protein: Binding<Double>
    let carbs: Binding<Double>
    let fat: Binding<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
            HStack(spacing: 8) {
                targetField("kcal", int: calories)
                targetField("P", double: protein)
                targetField("C", double: carbs)
                targetField("F", double: fat)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private func targetField(_ label: String, int: Binding<Int>? = nil, double: Binding<Double>? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let int {
                TextField("0", value: int, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 60)
            } else if let double {
                TextField("0", value: double, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 60)
            }
        }
    }
}

private struct FoodLibraryRow: View {
    let food: FoodLibraryItem
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(food.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(food.category.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.background.secondary.opacity(0.65), in: Capsule())
                }
                Text(food.servingLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(food.calories) kcal · P\(Int(food.protein.rounded())) C\(Int(food.carbs.rounded())) F\(Int(food.fat.rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .help(L10n.choose(simplifiedChinese: "加入冰箱", english: "Add to fridge"))
        }
        .padding(8)
        .background(.background.secondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FoodSearchResultRow: View {
    let hit: NutritionFoodSearchHit
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(hit.food.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(hit.provider.sourceTag)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.background.secondary.opacity(0.5), in: Capsule())
                    }
                    if let brand = hit.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(hit.food.servingLabel) · \(hit.food.calories) kcal · P\(Int(hit.food.protein.rounded())) C\(Int(hit.food.carbs.rounded())) F\(Int(hit.food.fat.rounded()))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let barcode = hit.barcode, !barcode.isEmpty {
                        Text("Barcode: \(barcode)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.background.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CustomFoodLibraryRow: View {
    let custom: CustomFoodLibraryItem
    let onAdd: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(custom.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.choose(simplifiedChinese: "自定义", english: "Custom"))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.background.secondary.opacity(0.45), in: Capsule())
                }
                Text("\(L10n.choose(simplifiedChinese: custom.servingLabelZH, english: custom.servingLabelEN)) · \(custom.calories) kcal · P\(Int(custom.protein.rounded())) C\(Int(custom.carbs.rounded())) F\(Int(custom.fat.rounded()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let barcode = custom.barcode, !barcode.isEmpty {
                    Text("Barcode: \(barcode)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: onAdd) { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain)
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .buttonStyle(.plain)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.background.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FridgeFoodRow: View {
    let entry: FridgeFoodEntry
    let libraryItem: FoodLibraryItem?
    let servings: Binding<Double>
    let onRemove: () -> Void

    private var kcalText: String {
        if let libraryItem {
            let total = Double(libraryItem.calories) * servings.wrappedValue
            return "≈ \(Int(total.rounded())) kcal"
        }
        if let calories = entry.caloriesPerServing {
            let total = Double(calories) * servings.wrappedValue
            return "≈ \(Int(total.rounded())) kcal"
        }
        return ""
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .font(.subheadline.weight(.semibold))
                if let libraryItem {
                    Text("\(libraryItem.servingLabel) · \(kcalText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let servingLabel = entry.servingLabel, !servingLabel.isEmpty {
                    Text("\(servingLabel)\(kcalText.isEmpty ? "" : " · \(kcalText)")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let source = entry.source, !source.isEmpty {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Text(L10n.choose(simplifiedChinese: "份数", english: "Servings"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "1.0",
                    value: servings,
                    format: .number.precision(.fractionLength(1))
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
            }

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(.background.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct NutritionProgressChip: View {
    let title: String
    let planned: Double
    let actual: Double
    let unit: String
    let tint: Color

    private var ratio: Double {
        min(max(actual / max(planned, 1.0), 0.0), 1.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(actual.rounded())) / \(Int(planned.rounded())) \(unit)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(tint)
            ProgressView(value: ratio, total: 1.0)
                .tint(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}
