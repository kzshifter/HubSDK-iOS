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

extension HubFacebook: HubEventListener {
    public func handle(event: HubEvent) {
        // track cases custom event and purchase
        switch event {
        case .successPurchase(let amount, let currency):
            AppEvents.shared.logPurchase(amount: amount, currency: currency)
            AppEvents.shared.logEvent(AppEvents.Name(rawValue: HubEventNames.HUBPurchase))
        case .event(let name, let params):
            let convertedParams = params.reduce(into: [AppEvents.ParameterName : Any]()) { partialResult, dictValue in
                partialResult[AppEvents.ParameterName(rawValue: dictValue.key)] = dictValue.value
            }
            AppEvents.shared.logEvent(AppEvents.Name(rawValue: name), parameters: convertedParams)
        default:
            break
        }
    }
}
