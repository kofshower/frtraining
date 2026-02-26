import Foundation

enum NutritionFoodSearchProvider: String, CaseIterable, Identifiable {
    case usdaFDC
    case openFoodFacts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .usdaFDC:
            return "USDA FDC"
        case .openFoodFacts:
            return "OpenFoodFacts"
        }
    }

    var sourceTag: String {
        switch self {
        case .usdaFDC:
            return "USDA"
        case .openFoodFacts:
            return "OFF"
        }
    }
}

enum NutritionFoodSearchError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid food search URL."
        case let .requestFailed(code, body):
            return "Food search request failed (\(code)): \(body)"
        case .invalidResponse:
            return "Food search response is invalid."
        }
    }
}

struct NutritionFoodSearchHit: Identifiable, Hashable {
    let id: String
    let provider: NutritionFoodSearchProvider
    let food: FoodLibraryItem
    let brand: String?
    let barcode: String?
    let sourceDescription: String

    init(
        provider: NutritionFoodSearchProvider,
        food: FoodLibraryItem,
        brand: String? = nil,
        barcode: String? = nil,
        sourceDescription: String
    ) {
        self.provider = provider
        self.food = food
        self.brand = brand
        self.barcode = barcode
        self.sourceDescription = sourceDescription
        self.id = "\(provider.rawValue)::\(food.code)"
    }
}

final class NutritionFoodSearchService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        query: String,
        provider: NutritionFoodSearchProvider,
        usdaAPIKey: String?
    ) async throws -> [NutritionFoodSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        switch provider {
        case .usdaFDC:
            return try await searchUSDA(query: trimmed, apiKey: normalizedUSDAKey(usdaAPIKey))
        case .openFoodFacts:
            return try await searchOpenFoodFacts(query: trimmed)
        }
    }

    func lookupBarcode(
        _ barcode: String,
        usdaAPIKey: String?
    ) async throws -> [NutritionFoodSearchHit] {
        let normalized = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var results: [NutritionFoodSearchHit] = []
        if let off = try await lookupOpenFoodFactsBarcode(normalized) {
            results.append(off)
        }
        let usda = try await searchUSDA(query: normalized, apiKey: normalizedUSDAKey(usdaAPIKey), pageSize: 8)
            .filter { hit in
                let hitBarcode = hit.barcode?.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
                let queryBarcode = normalized.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
                return hitBarcode == queryBarcode || hit.food.searchableText.contains(queryBarcode.lowercased())
            }
        results.append(contentsOf: usda)
        return dedupe(results)
    }

    private func normalizedUSDAKey(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "DEMO_KEY" : trimmed
    }

    private func dedupe(_ rows: [NutritionFoodSearchHit]) -> [NutritionFoodSearchHit] {
        var seen: Set<String> = []
        var result: [NutritionFoodSearchHit] = []
        for row in rows {
            let key = [row.provider.rawValue, row.barcode ?? "", row.food.displayName.lowercased(), row.brand?.lowercased() ?? ""].joined(separator: "|")
            if seen.insert(key).inserted {
                result.append(row)
            }
        }
        return result
    }

    private func searchUSDA(query: String, apiKey: String, pageSize: Int = 20) async throws -> [NutritionFoodSearchHit] {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(min(max(pageSize, 1), 50)))
        ]
        guard let url = components?.url else { throw NutritionFoodSearchError.invalidURL }

        let response: USDAFoodSearchResponse = try await requestJSON(url: url)
        return response.foods.prefix(20).compactMap { food in
            let parsed = parseUSDANutrients(food.foodNutrients)
            let servingText = usdaServingLabel(for: food)
            let foodItem = FoodLibraryItem(
                code: "usda_\(food.fdcId)",
                category: categorizeFood(
                    name: food.description,
                    protein: parsed.protein,
                    carbs: parsed.carbs,
                    fat: parsed.fat
                ),
                nameZH: food.description,
                nameEN: food.description,
                servingLabelZH: servingText,
                servingLabelEN: servingText,
                calories: Int((parsed.calories ?? 0).rounded()),
                protein: parsed.protein ?? 0,
                carbs: parsed.carbs ?? 0,
                fat: parsed.fat ?? 0,
                keywords: [food.brandOwner ?? "", food.brandName ?? "", food.dataType ?? "USDA", food.foodCategory ?? ""]
                    .filter { !$0.isEmpty }
            )
            return NutritionFoodSearchHit(
                provider: .usdaFDC,
                food: foodItem,
                brand: firstNonEmpty(food.brandName, food.brandOwner),
                barcode: food.gtinUpc,
                sourceDescription: ["USDA", food.dataType, food.foodCategory].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            )
        }
    }

    private func lookupOpenFoodFactsBarcode(_ barcode: String) async throws -> NutritionFoodSearchHit? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v0/product/\(barcode).json?fields=code,product_name,brands,serving_size,quantity,nutriments") else {
            throw NutritionFoodSearchError.invalidURL
        }
        let response: OpenFoodFactsProductResponse = try await requestJSON(url: url)
        guard response.status == 1, let product = response.product else { return nil }
        return makeOpenFoodFactsHit(product: product)
    }

    private func searchOpenFoodFacts(query: String) async throws -> [NutritionFoodSearchHit] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,serving_size,quantity,nutriments")
        ]
        guard let url = components?.url else { throw NutritionFoodSearchError.invalidURL }
        let response: OpenFoodFactsSearchResponse = try await requestJSON(url: url)
        return response.products.compactMap { makeOpenFoodFactsHit(product: $0) }
    }

    private func makeOpenFoodFactsHit(product: OpenFoodFactsProduct) -> NutritionFoodSearchHit? {
        let name = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }

        let nutriments = product.nutriments
        let calories = nutriments?.energyKcalServing ?? nutriments?.energyKcal100g ?? 0
        let protein = nutriments?.proteinsServing ?? nutriments?.proteins100g ?? 0
        let carbs = nutriments?.carbohydratesServing ?? nutriments?.carbohydrates100g ?? 0
        let fat = nutriments?.fatServing ?? nutriments?.fat100g ?? 0
        let serving = product.servingSize ?? product.quantity ?? "100g"
        let food = FoodLibraryItem(
            code: "off_\(product.code ?? UUID().uuidString)",
            category: categorizeFood(name: name, protein: protein, carbs: carbs, fat: fat),
            nameZH: name,
            nameEN: name,
            servingLabelZH: serving,
            servingLabelEN: serving,
            calories: Int(calories.rounded()),
            protein: protein,
            carbs: carbs,
            fat: fat,
            keywords: [product.brands ?? "", "OpenFoodFacts"]
        )
        return NutritionFoodSearchHit(
            provider: .openFoodFacts,
            food: food,
            brand: product.brands,
            barcode: product.code,
            sourceDescription: "OpenFoodFacts"
        )
    }

    private func usdaServingLabel(for food: USDAFoodSearchItem) -> String {
        if let full = food.householdServingFullText?.trimmingCharacters(in: .whitespacesAndNewlines), !full.isEmpty {
            if let servingSize = food.servingSize, let unit = food.servingSizeUnit, !unit.isEmpty {
                return "\(full) (~\(trimZero(servingSize)) \(unit))"
            }
            return full
        }
        if let servingSize = food.servingSize, let unit = food.servingSizeUnit, !unit.isEmpty {
            return "\(trimZero(servingSize)) \(unit)"
        }
        return "100g"
    }

    private func trimZero(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }

    private func categorizeFood(name: String, protein: Double?, carbs: Double?, fat: Double?) -> FoodLibraryCategory {
        let lower = name.lowercased()
        if ["milk", "yogurt", "cheese", "kefir"].contains(where: lower.contains) { return .dairy }
        if ["drink", "juice", "beverage", "soda"].contains(where: lower.contains) { return .beverage }
        if ["broccoli", "lettuce", "spinach", "tomato", "cucumber", "pepper", "mushroom", "carrot"].contains(where: lower.contains) { return .vegetable }
        if ["apple", "banana", "orange", "berry", "fruit"].contains(where: lower.contains) { return .fruit }
        if ["oil", "butter", "avocado", "almond", "walnut", "peanut"].contains(where: lower.contains) { return .fat }
        if ["rice", "bread", "oat", "pasta", "noodle", "potato", "wrap", "quinoa"].contains(where: lower.contains) { return .carb }
        let p = protein ?? 0
        let c = carbs ?? 0
        let f = fat ?? 0
        if p >= max(c, f) + 3 { return .protein }
        if c >= max(p, f) + 3 { return .carb }
        if f >= max(p, c) + 3 { return .fat }
        return .snack
    }

    private func parseUSDANutrients(_ rows: [USDAFoodNutrient]?) -> (calories: Double?, protein: Double?, carbs: Double?, fat: Double?) {
        guard let rows else { return (nil, nil, nil, nil) }
        func firstValue(_ matcher: (USDAFoodNutrient) -> Bool) -> Double? {
            rows.first(where: matcher)?.value
        }
        let calories = firstValue {
            let name = ($0.nutrientName ?? "").lowercased()
            return $0.nutrientNumber == "208" || name.contains("energy")
        }
        let protein = firstValue {
            $0.nutrientNumber == "203" || ($0.nutrientName ?? "").lowercased() == "protein"
        }
        let fat = firstValue {
            $0.nutrientNumber == "204" || ($0.nutrientName ?? "").lowercased().contains("total lipid") || ($0.nutrientName ?? "").lowercased() == "fat"
        }
        let carbs = firstValue {
            let n = ($0.nutrientName ?? "").lowercased()
            return $0.nutrientNumber == "205" || n.contains("carbohydrate")
        }
        return (calories, protein, carbs, fat)
    }

    private func firstNonEmpty(_ lhs: String?, _ rhs: String?) -> String? {
        let a = lhs?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a, !a.isEmpty { return a }
        let b = rhs?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let b, !b.isEmpty { return b }
        return nil
    }

    private func requestJSON<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Fricu/1.0 (+nutrition-search)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NutritionFoodSearchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw NutritionFoodSearchError.requestFailed(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NutritionFoodSearchError.invalidResponse
        }
    }
}

private struct USDAFoodSearchResponse: Decodable {
    let foods: [USDAFoodSearchItem]
}

private struct USDAFoodSearchItem: Decodable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let brandName: String?
    let foodCategory: String?
    let gtinUpc: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let householdServingFullText: String?
    let foodNutrients: [USDAFoodNutrient]?
}

private struct USDAFoodNutrient: Decodable {
    let nutrientName: String?
    let nutrientNumber: String?
    let value: Double?
}

private struct OpenFoodFactsSearchResponse: Decodable {
    let products: [OpenFoodFactsProduct]
}

private struct OpenFoodFactsProductResponse: Decodable {
    let status: Int
    let product: OpenFoodFactsProduct?
}

private struct OpenFoodFactsProduct: Decodable {
    let code: String?
    let productName: String?
    let brands: String?
    let servingSize: String?
    let quantity: String?
    let nutriments: OpenFoodFactsNutriments?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case servingSize = "serving_size"
        case quantity
        case nutriments
    }
}

private struct OpenFoodFactsNutriments: Decodable {
    let energyKcal100g: Double?
    let energyKcalServing: Double?
    let proteins100g: Double?
    let proteinsServing: Double?
    let carbohydrates100g: Double?
    let carbohydratesServing: Double?
    let fat100g: Double?
    let fatServing: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalServing = "energy-kcal_serving"
        case proteins100g = "proteins_100g"
        case proteinsServing = "proteins_serving"
        case carbohydrates100g = "carbohydrates_100g"
        case carbohydratesServing = "carbohydrates_serving"
        case fat100g = "fat_100g"
        case fatServing = "fat_serving"
    }
}
