import Foundation
import SkarbSDK
import HubIntegrationCore

// MARK: - Protocol

public protocol HubSkarbProviding {
    func sendSource(broker: SKBroker, features: [String: String], brokerUserID: String)
}

// MARK: - Configuration

public struct HubSkarbConfiguration: Sendable {
    public let clientId: String
    public let observerMode: Bool
    
    public init(clientId: String, observerMode: Bool = true) {
        self.clientId = clientId
        self.observerMode = observerMode
    }
}

// MARK: - Integration (Facade)

public final class HubSkarbIntegration: StormDependencyIntegration, AwaitableIntegration {
    public static var name: String { "Skarb" }
    
    public var provider: HubSkarbProviding { skarb }
    
    public private(set) var isReady: Bool = false
    public var onReady: (() -> Void)?
    
    private let skarb: HubSkarb
    
    public init(config: HubSkarbConfiguration) {
        self.skarb = HubSkarb(config: config)
    }
    
    public func start() {
        skarb.start()
        markAsReady()
    }
    
    private func markAsReady() {
        guard !isReady else { return }
        isReady = true
        onReady?()
    }
}

// MARK: - Implementation

internal final class HubSkarb: NSObject, HubSkarbProviding, StormEventListener {
    
    private let config: HubSkarbConfiguration
    
    init(config: HubSkarbConfiguration) {
        self.config = config
        super.init()
    }
    
    deinit {
        StormEventBus.shared.unsubscribe(self)
    }
    
    func start() {
        SkarbSDK.initialize(clientId: config.clientId, isObservable: config.observerMode)
        StormEventBus.shared.subscribe(self)
    }
    
    // MARK: - Public API
    
    func sendSource(broker: SKBroker, features: [String: String], brokerUserID: String = "") {
        SkarbSDK.sendSource(broker: broker, features: features, brokerUserID: brokerUserID)
    }
    
    // MARK: - StormEventListener
    
    nonisolated func handle(event: StormEvent) {
        if case let .conversionDataReceived(conversionInfo) = event {
            SkarbSDK.sendSource(broker: .appsflyer, features: conversionInfo, brokerUserID: "")
        }
    }
}
