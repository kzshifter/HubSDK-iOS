import UIKit
import HubIntegrationCore

@MainActor
open class HubSDKCore {
    public static let shared = HubSDKCore()
    
    private var integrations: [any HubDependencyIntegration] = []
    private var awaitState = AwaitState()
    
    public init() {}
    
    /// Registers an integration with the SDK.
    /// - Parameters:
    ///   - integration: The integration instance to register.
    ///   - awaitReady: If `true`, `waitUntilReady()` will wait for this integration to signal readiness.
    public func register(_ integration: any HubDependencyIntegration, awaitReady: Bool = false) {
        integrations.append(integration)
        
        if awaitReady {
            awaitState.addAwaited(type(of: integration).name)
        }
    }
    
    /// Starts all registered integrations.
    public func run(with application: UIApplication) {
        for integration in integrations {
            configureAwaitableIfNeeded(integration)
            integration.start()
        }
    }
    
    /// Returns a registered integration of the specified type.
    public func integration<T: HubDependencyIntegration>(ofType type: T.Type) -> T? {
        integrations.first { $0 is T } as? T
    }
}

// MARK: - Awaitable Support

private extension HubSDKCore {
    
    struct AwaitState {
        var awaited: Set<String> = []
        var ready: Set<String> = []
        var continuation: CheckedContinuation<Void, Never>?
        
        var isComplete: Bool {
            awaited.isEmpty || ready.isSuperset(of: awaited)
        }
        
        mutating func addAwaited(_ name: String) {
            awaited.insert(name)
        }
        
        mutating func markReady(_ name: String) -> Bool {
            guard awaited.contains(name) else { return false }
            ready.insert(name)
            return isComplete
        }
        
        mutating func resume() {
            continuation?.resume()
            continuation = nil
        }
    }
    
    func configureAwaitableIfNeeded(_ integration: any HubDependencyIntegration) {
        guard var awaitable = integration as? AwaitableIntegration else { return }
        
        let name = type(of: integration).name
        
        awaitable.onReady = { [weak self] in
            Task { @MainActor in
                self?.markReady(name)
            }
        }
        
        if awaitable.isReady {
            markReady(name)
        }
    }
    
    func markReady(_ name: String) {
        if awaitState.markReady(name) {
            awaitState.resume()
        }
    }
}

// MARK: - Wait Until Ready

public extension HubSDKCore {
    
    /// Suspends until all awaited integrations are ready or timeout occurs.
    /// - Parameter timeout: Maximum time to wait in seconds.
    func waitUntilReady(timeout: TimeInterval = 10) async {
        if awaitState.isComplete { return }
        
        await withCheckedContinuation { cont in
            awaitState.continuation = cont
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                awaitState.resume()
            }
        }
    }
    
    /// Completion-based variant of `waitUntilReady`.
    nonisolated func waitUntilReady(timeout: TimeInterval = 10, completion: @escaping @MainActor () -> Void) {
        Task {
            await waitUntilReady(timeout: timeout)
            await MainActor.run { completion() }
        }
    }
}
