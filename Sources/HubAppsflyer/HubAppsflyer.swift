import Foundation
import AppsFlyerLib
import HubIntegrationCore
import HubSDKCore

public extension HubSDKCore {
    var appsflyer: HubAppsflyerProviding? {
        integration(ofType: HubAppsflyerIntegration.self)?.provider
    }
}

public protocol HubAppsflyerProviding: Sendable {
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

internal final class HubAppsflyer: NSObject, HubAppsflyerProviding, @unchecked Sendable {
    
    private let config: HubAppsflyerConfiguration
    private let lock = NSLock()
    
    private var _onReady: (() -> Void)?
    var onReady: (() -> Void)? {
        get { lock.withLock { _onReady } }
        set { lock.withLock { _onReady = newValue } }
    }
    
    private var _conversionData: [AnyHashable: Any] = [:]
    private(set) var conversionData: [AnyHashable: Any] {
        get { lock.withLock { _conversionData } }
        set { lock.withLock { _conversionData = newValue } }
    }
    
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

extension AppsFlyerLib: HubEventListener {
    public func handle(event: HubEvent) {
        // track cases custom event and purchase
        switch event {
        case .successPurchase(let amount, let currency):
            AppsFlyerLib.shared().logEvent(AFEventPurchase, withValues: ["amount": amount, "currency": currency])
            AppsFlyerLib.shared().logEvent(HubEventNames.HUBPurchase, withValues: ["amount": amount, "currency": currency])
        case .event(let name, let params):
            AppsFlyerLib.shared().logEvent(name, withValues: params)
        default:
            break
        }
    }
}
