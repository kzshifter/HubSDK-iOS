import Adapty
import AdaptyUI
import Foundation
import UIKit

// MARK: - HubSDKAdaptyProviding

/// A protocol that defines the interface for subscription management and paywall operations.
///
/// Use this protocol to validate subscriptions, retrieve placements and remote configurations,
/// process purchases, restore previous transactions, and present onboardings.
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

    /// Retrieves the placement entry for the specified identifier.
    ///
    /// Unlike the synchronous variant, this method throws detailed errors
    /// when the SDK is not ready or the placement is not found.
    ///
    /// - Parameter placementId: The unique identifier of the placement.
    /// - Returns: The placement entry.
    /// - Throws: `HubSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `HubSDKError.placementNotFound` if the placement does not exist.
    func placementEntryAsync(with placementId: String) async throws -> PlacementEntry
    
    /// Decodes and returns the remote configuration for the specified placement.
    ///
    /// Unlike the synchronous variant, this method throws detailed errors
    /// for debugging and error handling purposes.
    ///
    /// - Parameter placementId: The unique identifier of the placement.
    /// - Returns: The decoded configuration.
    /// - Throws: `HubSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `HubSDKError.remoteConfigNotAvailable` if configuration is missing.
    /// - Throws: `HubSDKError.configDecodingFailed` if decoding fails.
    func remoteConfigAsync<T: Sendable>(for placementId: String) async throws -> T where T: Decodable
    
    // MARK: Purchase Operations
    
    /// Initiates a purchase for the specified product.
    ///
    /// This method handles the complete purchase flow including StoreKit interaction
    /// and receipt validation with Adapty servers.
    ///
    /// - Parameters:
    ///   - product: The product to purchase.
    ///   - trackEvent: If `true`, publishes a `successPurchase` event to `HubEventBus`.
    ///     Set to `false` when the caller handles event tracking independently (e.g., `HubPaywallCoordinator`).
    /// - Returns: The purchase result containing transaction details.
    /// - Throws: `HubSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `HubSDKError.purchaseFailed` if the purchase fails.
    func purchase(with product: any AdaptyPaywallProduct, trackEvent: Bool) async throws -> AdaptyPurchaseResult
    
    /// Restores previously purchased subscriptions.
    ///
    /// Use this method to restore purchases when the user reinstalls the app
    /// or switches devices.
    ///
    /// - Parameter accessLevels: The access levels to check after restoration.
    /// - Returns: An `AccessEntry` containing the restored subscription status.
    /// - Throws: `HubSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `HubSDKError.restoreFailed` if restoration fails.
    func restore(for accessLevels: [AccessLevel]) async throws -> AccessEntry
    
    func restore() async throws -> AccessEntry
    
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
    
    // MARK: Onboarding (Async)
    
    /// Fetches an onboarding and its UI configuration for the given placement.
    ///
    /// Performs two sequential calls:
    /// 1. `Adapty.getOnboarding(placementId:)` to fetch the onboarding data.
    /// 2. `AdaptyUI.getOnboardingConfiguration(forOnboarding:)` to prepare the UI config.
    ///
    /// For best performance, call this early to give images time to download.
    ///
    /// - Parameters:
    ///   - placementId: The placement identifier from the Adapty Dashboard.
    ///   - locale: Optional locale code (e.g., `"en"`, `"pt-br"`). Defaults to SDK config's `languageCode`.
    /// - Returns: An `OnboardingEntry` containing the onboarding and its configuration.
    /// - Throws: `HubSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `HubSDKError.onboardingFetchFailed` if fetching fails.
    /// - Throws: `HubSDKError.onboardingConfigurationFailed` if UI config creation fails.
    func onboardingEntry(
        for placementId: String,
        locale: String?
    ) async throws -> OnboardingEntry
    
    /// Fetches an onboarding for the default audience (All Users).
    ///
    /// Use this for faster loading when personalization is not needed.
    /// See Adapty docs for limitations of `getOnboardingForDefaultAudience`:
    /// - May create backward-compatibility issues across app versions.
    /// - No personalization — only shows content for "All Users" audience.
    ///
    /// - Parameters:
    ///   - placementId: The placement identifier.
    ///   - locale: Optional locale code. Defaults to SDK config's `languageCode`.
    /// - Returns: An `OnboardingEntry` for the default audience.
    /// - Throws: `HubSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `HubSDKError.onboardingFetchFailed` if fetching fails.
    func onboardingEntryForDefaultAudience(
        for placementId: String,
        locale: String?
    ) async throws -> OnboardingEntry
    
    // MARK: Onboarding Presentation (UIKit)
    
    /// Creates an `AdaptyOnboardingController` ready for presentation.
    ///
    /// This is a convenience method that combines fetching and controller creation.
    ///
    /// - Parameters:
    ///   - placementId: The placement identifier.
    ///   - delegate: The delegate to receive onboarding events.
    ///   - locale: Optional locale code.
    /// - Returns: A configured `AdaptyOnboardingController`.
    /// - Throws: `HubSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `HubSDKError.onboardingFetchFailed` if fetching fails.
    /// - Throws: `HubSDKError.onboardingConfigurationFailed` if UI config creation fails.
    @MainActor
    func onboardingController(
        for placementId: String,
        delegate: AdaptyOnboardingControllerDelegate,
        locale: String?
    ) async throws -> AdaptyOnboardingController
    
    /// Creates an `AdaptyOnboardingController` with a closure-based action handler.
    ///
    /// Uses `OnboardingDelegateProxy` internally for simplified event handling.
    /// **Important:** Retain the returned proxy — it acts as the delegate.
    ///
    /// - Parameters:
    ///   - placementId: The placement identifier.
    ///   - locale: Optional locale code.
    ///   - placeholder: Optional closure providing a loading placeholder view.
    ///   - onAction: Closure called for each onboarding action.
    /// - Returns: A tuple of the controller and its delegate proxy.
    /// - Throws: `HubSDKError.notInitialized` if SDK is not ready.
    /// - Throws: `HubSDKError.onboardingFetchFailed` if fetching fails.
    /// - Throws: `HubSDKError.onboardingConfigurationFailed` if UI config creation fails.
    @MainActor
    func onboardingController(
        for placementId: String,
        locale: String?,
        placeholder: (@MainActor @Sendable () -> UIView?)?,
        onAction: @MainActor @Sendable @escaping (OnboardingAction) -> Void
    ) async throws -> (AdaptyOnboardingController, OnboardingDelegateProxy)
    
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
    
    func restore(
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
    
    /// Fetches an onboarding entry with a completion handler.
    ///
    /// This method provides callback-based API access for cases
    /// where async/await is not available.
    ///
    /// - Parameters:
    ///   - placementId: The placement identifier.
    ///   - locale: Optional locale code. Defaults to SDK config's `languageCode`.
    ///   - completion: A closure called on the main thread with the result.
    func onboardingEntry(
        for placementId: String,
        locale: String?,
        completion: @MainActor @Sendable @escaping (Result<OnboardingEntry, Error>) -> Void
    )
}

// MARK: - Default Parameter Values

public extension HubSDKAdaptyProviding {

    // Purchase convenience overload with default trackEvent

    func purchase(with product: any AdaptyPaywallProduct) async throws -> AdaptyPurchaseResult {
        try await purchase(with: product, trackEvent: true)
    }

    // Onboarding convenience overloads with default locale
    
    func onboardingEntry(for placementId: String) async throws -> OnboardingEntry {
        try await onboardingEntry(for: placementId, locale: nil)
    }
    
    func onboardingEntryForDefaultAudience(for placementId: String) async throws -> OnboardingEntry {
        try await onboardingEntryForDefaultAudience(for: placementId, locale: nil)
    }
    
    @MainActor
    func onboardingController(
        for placementId: String,
        delegate: AdaptyOnboardingControllerDelegate
    ) async throws -> AdaptyOnboardingController {
        try await onboardingController(for: placementId, delegate: delegate, locale: nil)
    }
    
    @MainActor
    func onboardingController(
        for placementId: String,
        onAction: @MainActor @Sendable @escaping (OnboardingAction) -> Void
    ) async throws -> (AdaptyOnboardingController, OnboardingDelegateProxy) {
        try await onboardingController(for: placementId, locale: nil, placeholder: nil, onAction: onAction)
    }
    
    func onboardingEntry(
        for placementId: String,
        completion: @MainActor @Sendable @escaping (Result<OnboardingEntry, Error>) -> Void
    ) {
        onboardingEntry(for: placementId, locale: nil, completion: completion)
    }
}
