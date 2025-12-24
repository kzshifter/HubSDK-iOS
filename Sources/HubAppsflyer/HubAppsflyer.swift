import Foundation
import AppsFlyerLib
import HubIntegrationCore
import HubSDKCore

public extension HubSDKCore {
    var appsflyer: HubAppsflyerProviding? {
        integration(ofType: HubAppsflyerIntegration.self)?.provider
    }
}

public protocol HubAppsflyerProviding {
    var conversionData: [AnyHashable: Any] { get }
}

// MARK: - Integration (Facade)

public final class HubAppsflyerIntegration: HubDependencyIntegration, AwaitableIntegration {
    public static var name: String { "AppsflyerLib" }
    
    public var provider: HubAppsflyerProviding { appsflyer }
    
    public private(set) var isReady: Bool = false
    public var onReady: (() -> Void)?
    
    private let appsflyer: HubAppsflyer
    
    public init(config: HubAppsflyerConfiguration) {
        self.appsflyer = HubAppsflyer(config: config)
        self.appsflyer.onReady = { [weak self] in
            self?.markAsReady()
        }
    }
    
    public func start() {
        appsflyer.start()
    }
    
    private func markAsReady() {
        guard !isReady else { return }
        isReady = true
        onReady?()
    }
}

// MARK: - Implementation

internal final class HubAppsflyer: NSObject, HubAppsflyerProviding {
    
    private let config: HubAppsflyerConfiguration
    
    var onReady: (() -> Void)?
    
    private(set) var conversionData: [AnyHashable: Any] = [:]
    
    init(config: HubAppsflyerConfiguration) {
        self.config = config
    }
    
    func start() {
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().appsFlyerDevKey = config.devkey
        AppsFlyerLib.shared().appleAppID = config.appId
        AppsFlyerLib.shared().isDebug = config.debug
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: config.waitForATT)
        AppsFlyerLib.shared().start()
    }
}

extension HubAppsflyer: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        conversionData = conversionInfo
        
        let sendableData = conversionInfo.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        
        HubEventBus.shared.publish(.conversionDataReceived(sendableData))
        onReady?()
    }
    
    func onConversionDataFail(_ error: any Error) {
        onReady?()
    }
}
