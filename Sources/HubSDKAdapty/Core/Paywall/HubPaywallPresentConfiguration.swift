import Foundation

public struct HubPaywallPresentConfiguration: Sendable {
    let presentType: PresentType
    let animationEnable: Bool
    let dissmissEnable: Bool
    
    public init(presentType: PresentType = .push,
                animationEnable: Bool = true,
                dissmissEnable: Bool = true) {
        self.presentType = presentType
        self.animationEnable = animationEnable
        self.dissmissEnable = dissmissEnable
    }
    
    //MARK: Types
    
    public enum PresentType: Sendable {
        case push
        case present
    }
}
