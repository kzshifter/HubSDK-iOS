import Foundation
import Adapty

// MARK: - HubSDKAdaptyProviding

/// A protocol that defines the interface for subscription management and paywall operations.
///
/// Use this protocol to validate subscriptions, retrieve placements and remote configurations,
/// process purchases, and restore previous transactions.
public protocol HubSDKAdaptyProviding: Sendable {
    
    // MARK: State
    
    /// A Boolean value indicating whether the SDK has completed initialization.
    ///
    /// This property returns `true` only after a successful call to `start(config:)`.
    /// Attempting to use subscription-related methods before initialization results
    /// in errors or `nil` return values.
    var isInitialized: Bool { get }
    
    /// A Boolean value indicating whether the user has an active subscription.
    ///
    /// This property is cached and updates automatically when:
    /// - `validateSubscription(for:)` completes
    /// - A purchase succeeds via `purchase(with:)`
    /// - A restore completes via `restore(for:)`
    /// - The Adapty profile updates
    ///
    /// Returns `false` if the SDK is not initialized.
    var hasActiveSubscription: Bool { get }
    
    // MARK: Subscription Validation
    
    /// Validates the subscription status for the specified access levels.
    ///
    /// This method checks the user's profile against the provided access levels
    /// and returns the first active subscription found.
    ///
    /// - Parameter accessLevels: An array of access levels to validate against.
    /// - Returns: An `AccessEntry` containing the subscription status.
    func validateSubscription(for accessLevels: [AccessLevel]) async -> AccessEntry
    
    /// Validates the subscription status for the default premium access level.
    ///
    /// This is a convenience method that checks only the `.premium` access level.
    /// Use this when your app has a single subscription tier.
    ///
    /// - Returns: An `AccessEntry` containing the subscription status.
    func validateSubscription() async -> AccessEntry
    
    // MARK: Placement Access (Synchronous)

    /// Returns the placement entry for the specified identifier.
    ///
    /// This method provides synchronous access to cached placement data.
    /// Use this when you need immediate access without suspension.
    ///
    /// - Parameter placementId: The unique identifier of the placement.
    /// - Returns: The placement entry, or `nil` if not found or SDK is not initialized.
    func placementEntry(with placementId: String) -> PlacementEntry?

    /// Decodes and returns the remote configuration for the specified placement.
    ///
    /// This method provides synchronous access to cached remote configuration data.
    /// The configuration is automatically localized based on the SDK configuration.
    ///
    /// - Parameter placementId: The unique identifier of the placement.
    /// - Returns: The decoded configuration, or `nil` if unavailable or decoding fails.
    func remoteConfig<T: Sendable>(for placementId: String) -> T? where T: Decodable

    /// Checks whether a placement is already loaded.
    ///
    /// Use this to determine if synchronous access via `placementEntry(with:)`
    /// will return a value, or if async loading is required.
    ///
    /// - Parameter identifier: The placement identifier to check.
    /// - Returns: `true` if the placement is cached and available.
    func isPlacementLoaded(_ identifier: String) -> Bool

    // MARK: Placement Access (Asynchronous)

    /// Loads additional placements into the existing bag.
    ///
    /// Use this method to load placements on-demand after SDK initialization.
    /// Already loaded placements are skipped automatically.
    ///
    /// - Parameter identifiers: The placement identifiers to load.
    /// - Returns: Array of newly loaded entries (excludes already cached).
    /// - Throws: `HubSDKError.notInitialized` if SDK is not initialized.
    func loadPlacements(_ identifiers: [String]) async throws -> [PlacementEntry]

    /// Retrieves a placement with optional lazy loading.
    ///
    /// When `loadIfNeeded` is `true`, fetches the placement from network
    /// if not already cached. Otherwise returns only from cache.
    ///
    /// - Parameters:
    ///   - identifier: The placement identifier.
    ///   - loadIfNeeded: If `true`, loads the placement if not cached.
    /// - Returns: The placement entry.
    /// - Throws: `HubSDKError.notInitialized` if SDK is not initialized.
    /// - Throws: `HubSDKError.placementNotFound` if not found and loading is disabled.
    func placementEntry(for identifier: String, loadIfNeeded: Bool) async throws -> PlacementEntry
    
    // MARK: Placement Access (Asynchronous)
    
    /// Retrieves the placement entry for the specified identifier.
    ///
    /// Unlike the synchronous variant, this method throws detailed errors
    /// when the SDK is not ready or the placement is not found.
    ///
    /// - Parameter placementId: The unique identifier of the placement.
    /// - Returns: The placement entry.
    /// - Throws: `StormSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `StormSDKError.placementNotFound` if the placement does not exist.
    func placementEntryAsync(with placementId: String) async throws -> PlacementEntry
    
    /// Decodes and returns the remote configuration for the specified placement.
    ///
    /// Unlike the synchronous variant, this method throws detailed errors
    /// for debugging and error handling purposes.
    ///
    /// - Parameter placementId: The unique identifier of the placement.
    /// - Returns: The decoded configuration.
    /// - Throws: `StormSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `StormSDKError.remoteConfigNotAvailable` if configuration is missing.
    /// - Throws: `StormSDKError.configDecodingFailed` if decoding fails.
    func remoteConfigAsync<T: Sendable>(for placementId: String) async throws -> T where T: Decodable
    
    // MARK: Purchase Operations
    
    /// Initiates a purchase for the specified product.
    ///
    /// This method handles the complete purchase flow including StoreKit interaction
    /// and receipt validation with Adapty servers.
    ///
    /// - Parameter product: The product to purchase.
    /// - Returns: The purchase result containing transaction details.
    /// - Throws: `StormSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `StormSDKError.purchaseFailed` if the purchase fails.
    func purchase(with product: any AdaptyPaywallProduct) async throws -> AdaptyPurchaseResult
    
    /// Restores previously purchased subscriptions.
    ///
    /// Use this method to restore purchases when the user reinstalls the app
    /// or switches devices.
    ///
    /// - Parameter accessLevels: The access levels to check after restoration.
    /// - Returns: An `AccessEntry` containing the restored subscription status.
    /// - Throws: `StormSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `StormSDKError.restoreFailed` if restoration fails.
    func restore(for accessLevels: [AccessLevel]) async throws -> AccessEntry
    
    // MARK: Analytics
    
    /// Logs a paywall impression for the specified placement.
    ///
    /// Call this method when displaying a paywall to track conversion metrics.
    ///
    /// - Parameter placementId: The unique identifier of the placement being shown.
    func logPaywall(from placementId: String) async
    
    /// Logs a paywall impression for the specified paywall.
    ///
    /// Use this overload when you have direct access to the paywall object.
    ///
    /// - Parameter paywall: The paywall being shown.
    func logPaywall(with paywall: AdaptyPaywall) async
    
    // MARK: Completion Handler Variants
    
    /// Restores purchases with a completion handler.
    ///
    /// This method provides Objective-C compatibility and callback-based API access.
    ///
    /// - Parameters:
    ///   - accessLevels: The access levels to check after restoration.
    ///   - completion: A closure called on the main thread with the result.
    func restore(
        for accessLevels: [AccessLevel],
        completion: @MainActor @Sendable @escaping (Result<AccessEntry, Error>) -> Void
    )
    
    /// Initiates a purchase with a completion handler.
    ///
    /// This method provides Objective-C compatibility and callback-based API access.
    ///
    /// - Parameters:
    ///   - product: The product to purchase.
    ///   - completion: A closure called on the main thread with the result.
    func purchase(
        with product: any AdaptyPaywallProduct,
        completion: @MainActor @Sendable @escaping (Result<AdaptyPurchaseResult, Error>) -> Void
    )
    
    /// Validates subscription status with a completion handler.
    ///
    /// This method provides Objective-C compatibility and callback-based API access.
    ///
    /// - Parameters:
    ///   - accessLevels: The access levels to validate against.
    ///   - completion: A closure called on the main thread with the access entry.
    func validateSubscription(
        for accessLevels: [AccessLevel],
        completion: @MainActor @Sendable @escaping (AccessEntry) -> Void
    )
    
    /// Validates subscription status for the default premium access level with a completion handler.
    ///
    /// This is a convenience method that checks only the `.premium` access level.
    /// Use this when your app has a single subscription tier.
    ///
    /// - Parameter completion: A closure called on the main thread with the access entry.
    func validateSubscription(
        completion: @MainActor @Sendable @escaping (AccessEntry) -> Void
    )
}
