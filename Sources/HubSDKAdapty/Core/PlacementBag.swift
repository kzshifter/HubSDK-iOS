import Adapty
import Foundation

// MARK: - PlacementBag

/// A thread-safe container for paywall placements with lazy loading support.
public final class PlacementBag: @unchecked Sendable {
    
    // MARK: - Properties
    
    private let lock = NSLock()
    private var entries: [PlacementEntry] = []
    private var loadedIds: Set<String> = []
    private let locale: String
    
    // MARK: - Initialization
    
    public init(_ identifiers: [String], locale: String) async throws {
        self.locale = locale
        
        guard !identifiers.isEmpty else { return }
        
        let loaded = try await Self.fetchEntries(for: identifiers, locale: locale)
        
        addEntries(loaded, ids: identifiers)
    }
    
    // MARK: - Loading
    
    @discardableResult
    public func load(_ identifiers: [String]) async throws -> [PlacementEntry] {
        let newIds = filterNewIds(identifiers)
        guard !newIds.isEmpty else { return [] }
        
        let loaded = try await Self.fetchEntries(for: newIds, locale: locale)
        
        addEntries(loaded, ids: newIds)
        
        return loaded
    }
    
    public func loadIfNeeded(_ identifier: String) async throws -> PlacementEntry {
        if let existing = entry(for: identifier) {
            return existing
        }
        
        let loaded = try await load([identifier])
        
        guard let entry = loaded.first else {
            throw HubSDKError.placementNotFound(identifier)
        }
        
        return entry
    }
    
    // MARK: - Sync Access (Thread-Safe)
    
    public func isLoaded(_ identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadedIds.contains(identifier)
    }
    
    public func entry(for placementId: String) -> PlacementEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first { $0.placementId == placementId }
    }
    
    public var allEntries: [PlacementEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
    
    public var placementIdentifiers: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(loadedIds)
    }
    
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
    
    public var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries.isEmpty
    }
    
    // MARK: - Private Sync Helpers
    
    private func filterNewIds(_ identifiers: [String]) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return identifiers.filter { !loadedIds.contains($0) }
    }
    
    private func addEntries(_ newEntries: [PlacementEntry], ids: [String]) {
        lock.lock()
        entries.append(contentsOf: newEntries)
        loadedIds.formUnion(ids)
        lock.unlock()
    }
    
    // MARK: - Static Fetch (No Lock)
    
    private static func fetchEntries(for identifiers: [String], locale: String) async throws -> [PlacementEntry] {
        var result: [PlacementEntry] = []
        result.reserveCapacity(identifiers.count)
        
        for id in identifiers {
            let paywall = try await Adapty.getPaywall(placementId: id, locale: locale)
            let products = try await Adapty.getPaywallProducts(paywall: paywall)
            let remoteConfigData = paywall.remoteConfig?.jsonString.data(using: .utf8)
            
            let viewType: AdaptyPaywallViewType = {
                if paywall.hasViewConfiguration {
                    return .builder
                }
                
                let identifier = (paywall.remoteConfig?.dictionary?["identifier"] as? String)
                    ?? paywall.name.components(separatedBy: "-").first?.lowercased()
                    ?? ""
                
                return .local(identifier)
            }()
            
            let entry = PlacementEntry(
                placementId: id,
                identifier: viewType,
                paywall: paywall,
                products: products,
                remoteConfigData: remoteConfigData
            )
            
            result.append(entry)
        }
        
        return result
    }
}

// MARK: - Sequence Conformance

extension PlacementBag: Sequence {
    public func makeIterator() -> IndexingIterator<[PlacementEntry]> {
        allEntries.makeIterator()
    }
}

// MARK: - Collection Convenience

extension PlacementBag {
    
    public subscript(placementId: String) -> PlacementEntry? {
        entry(for: placementId)
    }
    
    public func entries(where predicate: (PlacementEntry) -> Bool) -> [PlacementEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter(predicate)
    }
    
    public var builderEntries: [PlacementEntry] {
        entries(where: { $0.identifier == .builder })
    }
    
    public var localEntries: [PlacementEntry] {
        entries(where: {
            if case .local = $0.identifier { return true }
            return false
        })
    }
}
