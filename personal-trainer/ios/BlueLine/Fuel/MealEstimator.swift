import Foundation

/// Result of a meal estimate, shaped like a web-app meal entry.
struct MealEstimate: Sendable {
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// "food (portion)" lines.
    var items: [String]
    /// "low" | "medium" | "high"
    var confidence: String
    /// Biggest uncertainty, e.g. "cooking oil".
    var note: String?
}

// ============================================================================================
// HOOK: future Claude photo estimate.
//
// Implement `MealEstimator` with a type that sends the photo + description to YOUR OWN backend,
// which holds the Anthropic API key and calls the Messages API with the image. Do NOT put an API
// key in this app: anything shipped in the binary can be extracted.
//
// Prompt guidance lives in references/nutrition.md ("Estimating a meal from a photo"):
// itemize foods with portions, assume restaurant cooking fat, size portions as served,
// return a confidence level and the biggest uncertainty.
//
// Then set `FuelView.estimator` to your implementation. Until then the photo button stays disabled.
// ============================================================================================
protocol MealEstimator: Sendable {
    var isAvailable: Bool { get }
    func estimate(photo: Data?, description: String) async throws -> MealEstimate
}

enum MealEstimatorError: LocalizedError {
    case notConfigured
    var errorDescription: String? { "Photo estimates aren't set up yet. Enter the macros by hand." }
}

/// Default: no estimator. Manual entry only.
struct UnconfiguredMealEstimator: MealEstimator {
    var isAvailable: Bool { false }
    func estimate(photo: Data?, description: String) async throws -> MealEstimate {
        throw MealEstimatorError.notConfigured
    }
}
