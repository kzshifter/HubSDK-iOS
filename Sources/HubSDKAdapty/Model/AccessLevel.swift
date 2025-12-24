import Foundation
import Adapty

public enum AccessLevel: RawRepresentable, Sendable {
    public var rawValue: String {
        if case let AccessLevel.custom(level) = self {
            level
        } else {
            "premium"
        }
    }
    
    public init?(rawValue: String) {
        if rawValue == "premium" {
            self = .premium
        } else {
            self = .custom(rawValue)
        }
    }
    
    case premium
    case custom(String)
}

public struct AccessEntry: Sendable {
    public let isActive: Bool
    public let isRenewable: Bool
}
