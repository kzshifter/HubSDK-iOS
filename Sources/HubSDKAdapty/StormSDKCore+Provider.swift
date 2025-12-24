import Foundation
import StormSDKCore

public extension StormSDKCore {
    var adapty: HubSDKAdaptyProviding? {
        integration(ofType: HubAdaptyIntegration.self)?.provider
    }
}
