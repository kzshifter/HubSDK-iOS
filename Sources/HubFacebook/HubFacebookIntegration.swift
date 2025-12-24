import Foundation
import HubIntegrationCore
import UIKit

public protocol HubFacebookProviding: Sendable {
    func application(_ application: UIApplication, continue userActivity: NSUserActivity)
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any])
}

public extension HubFacebookProviding {
    func application(_ application: UIApplication, open url: URL) {
        self.application(application, open: url, options: [:])
    }
}

public final class HubFacebookIntegration: HubDependencyIntegration {
    public static var name: String { "Facebook" }
    public var provider: HubFacebookProviding { facebook }
    
    private let facebook: HubFacebook
    
    public init(config: HubFacebookConfiguration) {
        facebook = HubFacebook(config: config)
    }
    
    public func start() {
        facebook.start()
    }
}
