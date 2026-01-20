import Foundation
import HubIntegrationCore

public protocol HubAnalyticsProviding {
    static func trackEvent(name: String, params: [String: Any])
    static func trackSuccessPurchase(amount: Double, currency: String)
}

extension HubAnalyticsProviding {
    static func trackEvent(name: String) {
        trackEvent(name: name, params: [:])
    }
}

final public class HubAnalytics: HubAnalyticsProviding {
    
    public static func trackSuccessPurchase(amount: Double, currency: String) {
        HubEventBus.shared.publish(.successPurchase(amount: amount, currency: currency))
    }
    
    public static func trackEvent(name: String, params: [String: Any]) {
        HubEventBus.shared.publish(.event(name: name, params: params))
    }
}
