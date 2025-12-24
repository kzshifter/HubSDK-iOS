import Adapty
import Foundation

// MARK: - PlacementBag

/// A thread-safe container for preloaded paywall placements.
///
/// This actor manages the lifecycle of placement entries, including fetching
/// paywalls and their associated products from Adapty during initialization.
/// Once loaded, entries are accessible via synchronous iteration or lookup.
///
/// ## Example Usage
///
/// ```swift
/// let bag = try await PlacementBag(["onboarding_placement", "settings_placement"], locale: "en_US")
///
/// if let entry = bag.entry(for: "onboarding_placement") {
///     // Use the placement entry
/// }
/// ```
actor PlacementBag {
    
    // MARK: - Properties
    
    /// The list of placement identifiers managed by this bag.
    private(set) var placementIdentifiers: [String] = []
    
    /// The loaded placement entries.
    private(set) var entries: [PlacementEntry] = []
    nonisolated(unsafe) private var cachedEntries: [PlacementEntry] = []
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
    init(_ identifiers: [String], locale: String) async throws {
        self.placementIdentifiers = identifiers
        
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
            
            entries.append(entry)
        }
        
        cachedEntries = entries
    }
    
    // MARK: - Lookup
    
    /// Returns the placement entry for the specified identifier.
    ///
    /// This method provides synchronous access to cached placement data.
    ///
    /// - Parameter placementId: The unique identifier of the placement.
    /// - Returns: The matching placement entry, or `nil` if not found.
    nonisolated public func entry(for placementId: String) -> PlacementEntry? {
        cachedEntries.first(where: { $0.placementId == placementId })
    }
}

// MARK: - Sequence Conformance

extension PlacementBag: @preconcurrency Sequence {
    
    func makeIterator() -> PlacementBagIterator {
        PlacementBagIterator(entries: entries)
    }
}

// MARK: - PlacementBagIterator

struct PlacementBagIterator: IteratorProtocol {
    
    private var entries: [PlacementEntry]
    private var currentIndex: Int = 0
    
    init(entries: [PlacementEntry]) {
        self.entries = entries
        
    }
    
    mutating func next() -> PlacementEntry? {
        guard currentIndex < entries.count else {
            return nil
        }
        
        let entry = entries[currentIndex]
        currentIndex += 1
        return entry
    }
}
