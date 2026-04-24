import Foundation

struct PricingRate {
    let inputPerM: Double
    let outputPerM: Double
    let cacheCreatePerM: Double
    let cacheReadPerM: Double
}

enum ModelPricing {
    static let opus   = PricingRate(inputPerM: 15,   outputPerM: 75,   cacheCreatePerM: 18.75, cacheReadPerM: 1.50)
    static let sonnet = PricingRate(inputPerM: 3,    outputPerM: 15,   cacheCreatePerM: 3.75,  cacheReadPerM: 0.30)
    static let haiku  = PricingRate(inputPerM: 0.25, outputPerM: 1.25, cacheCreatePerM: 0.30,  cacheReadPerM: 0.03)

    static func rate(for model: String) -> PricingRate {
        let lower = model.lowercased()
        if lower.contains("opus")  { return opus }
        if lower.contains("haiku") { return haiku }
        return sonnet
    }

    static func cost(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        let rate = rate(for: model)
        let m = 1_000_000.0
        return Double(inputTokens)          / m * rate.inputPerM
             + Double(outputTokens)         / m * rate.outputPerM
             + Double(cacheCreationTokens)  / m * rate.cacheCreatePerM
             + Double(cacheReadTokens)      / m * rate.cacheReadPerM
    }
}

// MARK: - Plan

enum PlanType: String, CaseIterable, Identifiable {
    case pro    = "Pro"
    case max5   = "Max5"
    case max20  = "Max20"
    case custom = "Custom"

    var id: String { rawValue }

    var limits: PlanLimits {
        switch self {
        case .pro:    return PlanLimits(costPerBlock: 18,  messagesPerBlock: 250)
        case .max5:   return PlanLimits(costPerBlock: 35,  messagesPerBlock: 1_000)
        case .max20:  return PlanLimits(costPerBlock: 140, messagesPerBlock: 2_000)
        case .custom: return PlanLimits(costPerBlock: 50,  messagesPerBlock: 250)
        }
    }
}

struct PlanLimits {
    let costPerBlock: Double
    let messagesPerBlock: Int
}
