//
//  StormAdaptyIntegration.swift
//  StormSDKCore
//
//  Created by Vadzim Ivanchanka on 12/4/25.
//

import Foundation
import HubIntegrationCore

public final class HubAdaptyIntegration: StormDependencyIntegration, AwaitableIntegration {
    public static var name: String { "Adapty" }
    public var provider: HubSDKAdaptyProviding { adapty }
    
    private let config: StormSDKAdaptyConfiguration
    private let adapty = HubSDKAdapty()
    
    public private(set) var isReady: Bool = false
    public var onReady: (() -> Void)?
    
    public init(config: StormSDKAdaptyConfiguration) {
        self.config = config
    }
    
    public func start() {
        Task {
            do {
                try await adapty.start(config: config)
                markAsReady()
            } catch {
                markAsReady()
            }
        }
    }
    
    private func markAsReady() {
        guard !isReady else { return }
        isReady = true
        onReady?()
    }
}
