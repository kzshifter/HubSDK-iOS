//
//  AwaitableIntegration.swift
//  HubSDKCore
//
//  Created by Vadzim Ivanchanka on 12/3/25.
//

import Foundation

@MainActor
public protocol AwaitableIntegration {
    /// Flag
    var isReady: Bool { get }
    
    /// Callback
    var onReady: (() -> Void)? { get set }
}
