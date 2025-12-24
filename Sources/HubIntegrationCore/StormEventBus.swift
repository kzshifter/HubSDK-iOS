import Foundation

public enum StormEvent {
    case conversionDataReceived([String: String])
    case successPurchase
}

public protocol StormEventListener: AnyObject {
    func handle(event: StormEvent)
}

public final class StormEventBus: @unchecked Sendable {
    public static let shared = StormEventBus()
    
    private var listeners = NSHashTable<AnyObject>.weakObjects()
    private let lock = NSLock()
    
    private init() {}
    
    public func subscribe(_ listener: StormEventListener) {
        lock.lock()
        defer { lock.unlock() }
        listeners.add(listener)
    }
    
    public func unsubscribe(_ listener: StormEventListener) {
        lock.lock()
        defer { lock.unlock() }
        listeners.remove(listener)
    }
    
    public func publish(_ event: StormEvent) {
        lock.lock()
        let currentListeners = listeners.allObjects.compactMap { $0 as? StormEventListener }
        lock.unlock()
        
        currentListeners.forEach { $0.handle(event: event) }
    }
}
