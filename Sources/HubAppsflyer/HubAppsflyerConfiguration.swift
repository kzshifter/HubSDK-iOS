//
//  HubAppsflyerConfiguration.swift
//  HubSDKCore
//
//  Created by Vadzim Ivanchanka on 12/19/25.
//

import Foundation

public struct HubAppsflyerConfiguration: Sendable {
    public let devkey: String
    public let appId: String
    public let waitForATT: Double
    public let debug: Bool
    
    public init(devkey: String, appId: String, waitForATT: Double = 60.0, debug: Bool = false) {
        self.devkey = devkey
        self.appId = appId
        self.waitForATT = waitForATT
        self.debug = debug
    }
}
