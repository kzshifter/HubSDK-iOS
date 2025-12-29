import Foundation
import FirebaseCore
import HubIntegrationCore
import FirebaseAnalytics

public protocol HubFirebaseProviding: Sendable { }

public class HubFirebaseIntegration: HubDependencyIntegration {
    public static var name: String { "Firebase" }
    private let firebase = HubFirebase()
    public var provider: HubFirebaseProviding { firebase }
    
    public func start() {
        firebase.start()
    }
}

final class HubFirebase: HubFirebaseProviding {
    func start() {
        FirebaseApp.configure()
    }
}

extension HubFirebase: HubEventListener {
    public func handle(event: HubEvent) {
        // track cases custom event and purchase
        switch event {
        case .successPurchase(let amount, let currency):
            Analytics.logEvent(HubEventNames.HUBPurchase, parameters: ["amount": amount, "currency": currency])
        case .event(let name, let params):
            Analytics.logEvent(name, parameters: params)
        default:
            break
        }
    }
}
