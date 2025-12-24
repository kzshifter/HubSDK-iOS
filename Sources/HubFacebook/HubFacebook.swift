import Foundation
import FBSDKCoreKit
import HubIntegrationCore

final class HubFacebook: HubFacebookProviding, @unchecked Sendable {
    
    private let config: HubFacebookConfiguration
    
    init(config: HubFacebookConfiguration) {
        self.config = config
    }
    
    func start() {
        Settings.shared.isAdvertiserIDCollectionEnabled = config.advertiserIDCollectionEnabled
        Settings.shared.isAutoLogAppEventsEnabled = config.autoLogAppEventsEnabled
        
        ApplicationDelegate.shared.initializeSDK()
        AppEvents.shared.activateApp()
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity) {
        ApplicationDelegate.shared.application(application, continue: userActivity)
    }
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
        ApplicationDelegate.shared.application(application, open: url, options: options)
    }
}
