import Foundation
import HubSDKCore

public extension HubSDKCore {
    var adapty: HubSDKAdaptyProviding? {
        integration(ofType: HubAdaptyIntegration.self)?.provider
    }
}
