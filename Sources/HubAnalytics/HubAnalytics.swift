import Foundation
import HubIntegrationCore

public protocol HubAnalyticsProviding {
    func trackEvent(name: String, params: [String: Any])
    func trackSuccessPurchase(amount: Double, currency: String)
}

extension HubAnalyticsProviding {
    func trackEvent(name: String) {
        trackEvent(name: name, params: [:])
    }
}

final class HubAnalytics: HubAnalyticsProviding {
    
    func trackSuccessPurchase(amount: Double, currency: String) {
        HubEventBus.shared.publish(.successPurchase(amount: amount, currency: currency))
    }
    
    func trackEvent(name: String, params: [String: Any]) {
        HubEventBus.shared.publish(.event(name: name, params: params))
    }
}
