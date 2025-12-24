import Adapty
import Foundation

// MARK: - PlacementBag

/// A thread-safe container for preloaded paywall placements.
///
/// This class manages immutable placement entries loaded during initialization.
/// All data is write-once, making it inherently thread-safe without locks.
///
/// ## Example Usage
///
/// ```swift
/// let bag = try await PlacementBag(["onboarding", "settings"], locale: "en_US")
///
/// if let entry = bag.entry(for: "onboarding") {
///     // Use the placement entry
/// }
/// ```
public final class PlacementBag: Sendable {
    
    // MARK: - Properties
    
    /// The list of placement identifiers managed by this bag.
    public let placementIdentifiers: [String]
    
    /// The loaded placement entries (immutable after init).
    private let entries: [PlacementEntry]
    
    // MARK: - Initialization
    
    /// Creates a new placement bag by fetching paywalls for the specified identifiers.
    ///
    /// This initializer performs network requests to load each placement's paywall
    /// and associated products. All placements are loaded before the initializer returns.
    ///
    /// - Parameters:
    ///   - identifiers: The placement identifiers to load.
    ///   - locale: The locale identifier for paywall localization.
    /// - Throws: An error if any paywall or product fetch fails.
    public init(_ identifiers: [String], locale: String) async throws {
        self.placementIdentifiers = identifiers
        
        var loadedEntries: [PlacementEntry] = []
        loadedEntries.reserveCapacity(identifiers.count)
        
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
            
            loadedEntries.append(entry)
        }
        
        self.entries = loadedEntries
    }
    
    // MARK: - Lookup
    
    /// Returns the placement entry for the specified identifier.
    ///
    /// - Parameter placementId: The unique identifier of the placement.
    /// - Returns: The matching placement entry, or `nil` if not found.
    public func entry(for placementId: String) -> PlacementEntry? {
        entries.first { $0.placementId == placementId }
    }
    
    /// Returns all loaded entries.
    public var allEntries: [PlacementEntry] {
        entries
    }
    
    /// The number of loaded placements.
    public var count: Int {
        entries.count
    }
    
    /// Whether the bag contains any placements.
    public var isEmpty: Bool {
        entries.isEmpty
    }
}

// MARK: - Sequence Conformance

extension PlacementBag: Sequence {
    public func makeIterator() -> IndexingIterator<[PlacementEntry]> {
        entries.makeIterator()
    }
}

// MARK: - Collection Convenience

extension PlacementBag {
    /// Subscript access by placement ID.
    public subscript(placementId: String) -> PlacementEntry? {
        entry(for: placementId)
    }
    
    /// Returns entries matching the given predicate.
    public func entries(where predicate: (PlacementEntry) -> Bool) -> [PlacementEntry] {
        entries.filter(predicate)
    }
    
    /// Returns all builder (remote) paywalls.
    public var builderEntries: [PlacementEntry] {
        entries.filter { $0.identifier == .builder }
    }
    
    /// Returns all local paywalls.
    public var localEntries: [PlacementEntry] {
        entries.filter {
            if case .local = $0.identifier { return true }
            return false
        }
    }
}
