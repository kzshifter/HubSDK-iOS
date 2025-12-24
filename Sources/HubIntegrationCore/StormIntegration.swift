//
//  StormIntegration.swift
//  HubSDKCore
//
//  Created by Vadzim Ivanchanka on 10/31/25.
//

import Foundation

@MainActor
public protocol StormDependencyIntegration {
    associatedtype Provider
    
    static var name: String { get }
    var provider: Provider { get }
    func start()
}
