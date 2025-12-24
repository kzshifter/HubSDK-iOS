import Adapty
import Foundation

public struct PlacementEntry: Sendable {
    public let placementId: String
    public let identifier: AdaptyPaywallViewType
    public let paywall: AdaptyPaywall
    public let products: [AdaptyPaywallProduct]
    public let remoteConfigData: Data?
}

public enum AdaptyPaywallViewType: Sendable, Hashable {
    case builder
    case local(String)
}
