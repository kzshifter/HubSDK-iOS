import Foundation

public struct HubFacebookConfiguration: Sendable {
    public let advertiserIDCollectionEnabled: Bool
    public let autoLogAppEventsEnabled: Bool
    
    public init(
        advertiserIDCollectionEnabled: Bool = true,
        autoLogAppEventsEnabled: Bool = false
    ) {
        self.advertiserIDCollectionEnabled = advertiserIDCollectionEnabled
        self.autoLogAppEventsEnabled = autoLogAppEventsEnabled
    }
}
