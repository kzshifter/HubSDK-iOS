import Foundation

public enum HubEvent {
    case conversionDataReceived([String: String])
    case successPurchase
}

public protocol HubEventListener: AnyObject {
    func handle(event: HubEvent)
}

public final class HubEventBus: @unchecked Sendable {
    public static let shared = HubEventBus()
    
    private var listeners = NSHashTable<AnyObject>.weakObjects()
    private let lock = NSLock()
    
    private init() {}
    
    public func subscribe(_ listener: HubEventListener) {
        lock.lock()
        defer { lock.unlock() }
        listeners.add(listener)
    }
    
    public func unsubscribe(_ listener: HubEventListener) {
        lock.lock()
        defer { lock.unlock() }
        listeners.remove(listener)
    }
    
    public func publish(_ event: HubEvent) {
        lock.lock()
        let currentListeners = listeners.allObjects.compactMap { $0 as? HubEventListener }
        lock.unlock()
        
        currentListeners.forEach { $0.handle(event: event) }
    }
}
