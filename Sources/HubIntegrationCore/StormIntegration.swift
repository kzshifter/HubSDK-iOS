import Foundation

@MainActor
public protocol HubDependencyIntegration {
    associatedtype Provider
    
    static var name: String { get }
    var provider: Provider { get }
    func start()
}
