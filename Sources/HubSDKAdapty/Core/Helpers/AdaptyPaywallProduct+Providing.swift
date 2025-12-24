import Foundation
import Adapty

fileprivate enum Period {
    case week, month, year, day
    
    func description(isAdaptiveName: Bool, periodValue: Int) -> String {
        switch self {
        case .week:
            return isAdaptiveName ? "weekly" : "week"
        case .month:
            return isAdaptiveName ? "monthly" : "month"
        case .year:
            return isAdaptiveName ? "yearly" : "year"
        case .day:
            if periodValue % 7 == 0 {
                return isAdaptiveName ? "weekly" : "week"
            } else {
                return isAdaptiveName ? "day" : "day"
            }
        }
    }
}

extension Decimal {
    var doubleValue:Double {
        return NSDecimalNumber(decimal:self).doubleValue
    }
}

// MARK: - AdaptyPaywallProduct + Formatting

extension AdaptyPaywallProduct {
    
    /// Replaces placeholder tokens in the given text with product-specific values.
    ///
    /// This method substitutes predefined placeholders with formatted price and period
    /// information derived from the product. Custom placeholders can be provided
    /// to extend the replacement behavior.
    ///
    /// The following placeholders are supported by default:
    /// - `%subscriptionPrice%`: The formatted product price.
    /// - `%subscriptionPeriod%`: The subscription period description.
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// let text = "Subscribe for %subscriptionPrice% per %subscriptionPeriod%"
    /// let formatted = product.replacingPlaceholders(in: text)
    /// // Result: "Subscribe for $9.99 per month"
    /// ```
    ///
    /// - Parameters:
    ///   - text: The string containing placeholder tokens.
    ///   - multiplicatorValue: A multiplier applied to the price. Defaults to `1.0`.
    ///   - additionalPlaceholders: Custom placeholder-value pairs to include in replacement.
    /// - Returns: The text with all recognized placeholders replaced.
    public func replacingPlaceholders(
        in text: String,
        multiplicatorValue: Double = 1.0,
        additionalPlaceholders: [String: String] = [:]
    ) -> String {
        var result = text
        
        let defaultPlaceholders: [String: String] = [
            "%subscriptionPrice%": descriptionPrice(multiplicatorValue: multiplicatorValue),
            "%subscriptionPeriod%": descriptionPeriod()
        ]
        
        let placeholders = defaultPlaceholders.merging(additionalPlaceholders) { _, new in new }
        
        for (key, value) in placeholders {
            result = result.replacingOccurrences(of: key, with: value)
        }
        
        return result
    }
    
    /// Returns a formatted price string for the product.
    ///
    /// The price is formatted with the product's locale currency symbol
    /// and two decimal places.
    ///
    /// - Parameter multiplicatorValue: A multiplier applied to the base price.
    ///   Use this to calculate weekly or daily rates from monthly prices. Defaults to `1.0`.
    /// - Returns: A formatted price string (e.g., "$9.99").
    public func descriptionPrice(multiplicatorValue: Double = 1.0) -> String {
        let currencySymbol = priceLocale.currencySymbol ?? ""
        let price: Double
        
        if let sk1Product {
            price = sk1Product.price.doubleValue
        } else if let sk2Product {
            price = sk2Product.price.doubleValue
        } else {
            price = 0
        }
        
        return String(format: "\(currencySymbol)%.2f", price * multiplicatorValue)
    }
    
    /// Returns a human-readable description of the subscription period.
    ///
    /// The period is derived from the underlying StoreKit product and formatted
    /// according to the specified style.
    ///
    /// - Parameter isAdaptiveName: When `true`, returns a contextually adaptive
    ///   period name based on the unit count. Defaults to `false`.
    /// - Returns: A period description string (e.g., "month", "year").
    public func descriptionPeriod(isAdaptiveName: Bool = false) -> String {
        if sk1Product != nil {
            return sk1Period(for: self, isAdaptiveName: isAdaptiveName)
        }
        return sk2Period(for: self, isAdaptiveName: isAdaptiveName)
    }
    
    // MARK: - Private Methods
    
    private func sk1Period(for product: AdaptyPaywallProduct, isAdaptiveName: Bool = false) -> String {
        guard let period = product.sk1Product?.subscriptionPeriod else {
            return ""
        }
        
        let periodValue = period.numberOfUnits
        
        return switch period.unit {
        case .day:
            Period.day.description(isAdaptiveName: isAdaptiveName, periodValue: periodValue)
        case .week:
            Period.week.description(isAdaptiveName: isAdaptiveName, periodValue: periodValue)
        case .month:
            Period.month.description(isAdaptiveName: isAdaptiveName, periodValue: periodValue)
        case .year:
            Period.year.description(isAdaptiveName: isAdaptiveName, periodValue: periodValue)
        @unknown default:
            Period.day.description(isAdaptiveName: isAdaptiveName, periodValue: periodValue)
        }
    }
    
    private func sk2Period(for product: AdaptyPaywallProduct, isAdaptiveName: Bool = false) -> String {
        guard let subscription = product.sk2Product?.subscription else {
            return ""
        }
        
        let period = subscription.subscriptionPeriod
        
        return switch period.unit {
        case .day:
            Period.day.description(isAdaptiveName: isAdaptiveName, periodValue: period.value)
        case .week:
            Period.week.description(isAdaptiveName: isAdaptiveName, periodValue: period.value)
        case .month:
            Period.month.description(isAdaptiveName: isAdaptiveName, periodValue: period.value)
        case .year:
            Period.year.description(isAdaptiveName: isAdaptiveName, periodValue: period.value)
        @unknown default:
            Period.day.description(isAdaptiveName: isAdaptiveName, periodValue: period.value)
        }
    }
}
