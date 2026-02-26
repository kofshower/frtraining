import Foundation

enum OpenAICoachError: Error, LocalizedError {
    case missingAPIKey
    case badResponse
    case requestFailed(Int, String)
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing."
        case .badResponse:
            return "OpenAI returned an invalid response."
        case let .requestFailed(code, body):
            return "OpenAI request failed (\(code)): \(body)"
        case .malformedPayload:
            return "OpenAI returned malformed coach payload."
        }
    }
}

struct GPTCoachInput: Encodable {
    struct Summary: Encodable {
        let weeklyTSS: Int
        let monthlyDistanceKm: Double
        let ctl: Double
        let atl: Double
        let tsb: Double
    }

    struct ProfileContext: Encodable {
        let athleteAgeYears: Int
        let athleteWeightKg: Double
        let cyclingFTPWatts: Int
        let runningFTPWatts: Int
        let swimmingFTPWatts: Int
        let strengthFTPWatts: Int
        let cyclingThresholdHeartRate: Int
        let runningThresholdHeartRate: Int
        let swimmingThresholdHeartRate: Int
        let strengthThresholdHeartRate: Int
        let hrvBaseline: Double
        let hrvToday: Double
        let goalRaceDate: String?
    }

    struct LoadPoint: Encodable {
        let date: String
        let tss: Double
        let ctl: Double
        let atl: Double
        let tsb: Double
    }

    struct ActivityPoint: Encodable {
        let date: String
        let sport: String
        let durationMinutes: Int
        let distanceKm: Double
        let tss: Int
        let normalizedPower: Int?
        let avgHeartRate: Int?
        let notes: String
    }

    struct PlannedWorkoutPoint: Encodable {
        let date: String
        let sport: String
        let name: String
        let totalMinutes: Int
        let segmentCount: Int
    }

    let now: String
    let summary: Summary
    let profile: ProfileContext
    let recentLoad: [LoadPoint]
    let recentActivities: [ActivityPoint]
    let upcomingWorkouts: [PlannedWorkoutPoint]
}

struct ActivityMetricInsightInput: Encodable {
    let date: String
    let sport: String
    let durationMinutes: Int
    let distanceKm: Double
    let tss: Int
    let normalizedPower: Int?
    let avgHeartRate: Int?
    let ftp: Int
    let thresholdHeartRate: Int
    let intensityFactor: Double?
    let tssPerHour: Double
    let ctl: Double?
    let atl: Double?
    let tsb: Double?
    let aerobicTISS: Double?
    let anaerobicTISS: Double?
    let notes: String
}

struct ActivityMetricInsightPayload: Codable {
    let summary: String
    let keyFindings: [String]
    let actions: [String]
}

struct NutritionMealTargetInput: Encodable {
    let slot: String
    let calories: Int
    let protein: Double
    let carbs: Double
    let fat: Double
}

struct NutritionFoodAvailabilityInput: Encodable {
    let name: String
    let servings: Double
    let caloriesPerServing: Int?
    let proteinPerServing: Double?
    let carbsPerServing: Double?
    let fatPerServing: Double?
}

struct DailyNutritionPlannerInput: Encodable {
    let date: String
    let athleteName: String
    let sportFocus: String
    let athleteWeightKg: Double?
    let basalMetabolicRateKcal: Int?
    let nutritionActivityFactor: Double?
    let estimatedMaintenanceCalories: Int?
    let nutritionGoalProfile: String
    let goalGuidance: String
    let dailyCalorieTarget: Int
    let hydrationTargetLiters: Double
    let mealTargets: [NutritionMealTargetInput]
    let fridgeFoods: [NutritionFoodAvailabilityInput]
    let notes: String
}

struct NutritionMealSuggestionPayload: Codable {
    let slot: String
    let foods: [String]
    let calories: Int?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let rationale: String?
}

struct DailyNutritionPlanPayload: Codable {
    let summary: String
    let meals: [NutritionMealSuggestionPayload]
    let notes: [String]
}

final class OpenAICoachClient {
    private let apiKey: String
    private let session: URLSession
    private let model: String

    init(apiKey: String, model: String = "gpt-4o-mini", session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
        self.session = session
    }

    func recommend(input: GPTCoachInput) async throws -> AIRecommendation {
        guard !apiKey.isEmpty else {
            throw OpenAICoachError.missingAPIKey
        }

        let encodedInput = try JSONEncoder().encode(input)
        guard let inputJSON = String(data: encodedInput, encoding: .utf8) else {
            throw OpenAICoachError.malformedPayload
        }

        let systemPrompt = """
        You are an elite endurance coach. Use the athlete context and return strict JSON only.
        JSON schema:
        {
          "readinessScore": 1-100 integer,
          "phase": "short string",
          "todayFocus": "single sentence",
          "weeklyFocus": ["3-5 bullets"],
          "cautions": ["0-4 bullets"]
        }
        Keep guidance practical and conservative when fatigue risk is high.
        """

        let userPrompt = """
        Athlete context (JSON):
        \(inputJSON)
        """

        let content = try await completeJSON(systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: 0.25)

        return try parseRecommendation(from: content)
    }

    func interpretActivityMetrics(input: ActivityMetricInsightInput) async throws -> ActivityMetricInsightPayload {
        guard !apiKey.isEmpty else {
            throw OpenAICoachError.missingAPIKey
        }

        let encodedInput = try JSONEncoder().encode(input)
        guard let inputJSON = String(data: encodedInput, encoding: .utf8) else {
            throw OpenAICoachError.malformedPayload
        }

        let systemPrompt = """
        You are an elite endurance coach. Interpret one activity using objective training metrics.
        Return strict JSON only:
        {
          "summary": "1-2 sentence concise interpretation",
          "keyFindings": ["3-5 concise findings"],
          "actions": ["2-4 practical next actions"]
        }
        Keep recommendations conservative and evidence-driven.
        """

        let userPrompt = """
        Activity metrics (JSON):
        \(inputJSON)
        """

        let content = try await completeJSON(systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: 0.2)
        let object = try parseJSONObject(from: stripCodeFence(content))
        let summary = (JSONValue.string(object["summary"])?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "该活动训练刺激中等，建议结合近期疲劳与恢复信号安排后续课表。"
        let keyFindings = stringArray(object["keyFindings"]).prefix(5).map { $0 }
        let actions = stringArray(object["actions"]).prefix(5).map { $0 }
        return ActivityMetricInsightPayload(
            summary: summary,
            keyFindings: keyFindings.isEmpty ? ["数据完整度有限，建议补充功率和心率连续采样。"] : keyFindings,
            actions: actions.isEmpty ? ["下一次训练根据 TSB 与主观疲劳调整强度。"] : actions
        )
    }

    func planDailyNutrition(input: DailyNutritionPlannerInput) async throws -> DailyNutritionPlanPayload {
        guard !apiKey.isEmpty else {
            throw OpenAICoachError.missingAPIKey
        }

        let encodedInput = try JSONEncoder().encode(input)
        guard let inputJSON = String(data: encodedInput, encoding: .utf8) else {
            throw OpenAICoachError.malformedPayload
        }

        let systemPrompt = """
        You are a sports nutrition coach and meal planner.
        Use ONLY the available fridge foods as primary ingredients. You may suggest small pantry staples (salt, pepper, water, herbs) but do not rely on unavailable foods.
        Respect the requested nutrition goal profile and meal macro targets for breakfast/lunch/dinner.
        If BMR / maintenance calories are provided, use them as the baseline for calorie reasoning and explain any large deviations in notes.
        Return strict JSON only:
        {
          "summary": "1-2 sentence summary",
          "meals": [
            {
              "slot": "breakfast|lunch|dinner|snackAM|snackPM|postWorkout",
              "foods": ["food 1", "food 2"],
              "calories": 0,
              "protein": 0,
              "carbs": 0,
              "fat": 0,
              "rationale": "short rationale"
            }
          ],
          "notes": ["2-6 practical notes"]
        }
        Ensure breakfast/lunch/dinner are always present.
        """

        let userPrompt = """
        Nutrition planning context (JSON):
        \(inputJSON)
        """

        let content = try await completeJSON(systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: 0.25)
        let object = try parseJSONObject(from: stripCodeFence(content))

        let summary = (JSONValue.string(object["summary"])?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "Prioritize hitting the meal targets with foods already in the fridge."

        let mealRows = (object["meals"] as? [Any]) ?? []
        let meals = mealRows.compactMap { row -> NutritionMealSuggestionPayload? in
            guard let dict = row as? [String: Any] else { return nil }
            let slot = (JSONValue.string(dict["slot"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slot.isEmpty else { return nil }
            return NutritionMealSuggestionPayload(
                slot: slot,
                foods: stringArray(dict["foods"]),
                calories: JSONValue.int(dict["calories"]),
                protein: JSONValue.double(dict["protein"]),
                carbs: JSONValue.double(dict["carbs"]),
                fat: JSONValue.double(dict["fat"]),
                rationale: JSONValue.string(dict["rationale"])
            )
        }

        let notes = stringArray(object["notes"])

        return DailyNutritionPlanPayload(
            summary: summary,
            meals: meals,
            notes: notes
        )
    }

    private func completeJSON(systemPrompt: String, userPrompt: String, temperature: Double) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICoachError.badResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw OpenAICoachError.requestFailed(http.statusCode, errorBody)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = JSONValue.string(message["content"])
        else {
            throw OpenAICoachError.malformedPayload
        }
        return content
    }

    private func parseRecommendation(from content: String) throws -> AIRecommendation {
        let cleaned = stripCodeFence(content)
        let object = try parseJSONObject(from: cleaned)

        let readiness = min(100, max(1, JSONValue.int(object["readinessScore"]) ?? 65))
        let phase = (JSONValue.string(object["phase"])?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "Build"
        let todayFocus = (JSONValue.string(object["todayFocus"])?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "Maintain aerobic consistency and adjust intensity by fatigue signals."

        let weeklyFocus = stringArray(object["weeklyFocus"]).prefix(5).map { $0 }
        let cautions = stringArray(object["cautions"]).prefix(5).map { $0 }

        return AIRecommendation(
            readinessScore: readiness,
            phase: phase,
            todayFocus: todayFocus,
            weeklyFocus: weeklyFocus.isEmpty ? ["Keep load progression smooth and respect recovery signals."] : weeklyFocus,
            cautions: cautions
        )
    }

    private func parseJSONObject(from raw: String) throws -> [String: Any] {
        if let data = raw.data(using: .utf8),
           let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return object
        }

        if let start = raw.firstIndex(of: "{"),
           let end = raw.lastIndex(of: "}")
        {
            let slice = String(raw[start...end])
            if let data = slice.data(using: .utf8),
               let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                return object
            }
        }

        throw OpenAICoachError.malformedPayload
    }

    private func stripCodeFence(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value.replacingOccurrences(of: "```json", with: "")
            value = value.replacingOccurrences(of: "```", with: "")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringArray(_ any: Any?) -> [String] {
        guard let rows = any as? [Any] else { return [] }
        return rows
            .compactMap { JSONValue.string($0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
