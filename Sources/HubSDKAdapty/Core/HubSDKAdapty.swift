import Adapty
import AdaptyUI
import Foundation
import HubIntegrationCore

// MARK: - StormSDKAdapty

/// The main implementation of the Storm SDK Adapty wrapper.
///
/// This actor provides thread-safe access to Adapty functionality with
/// automatic state management and caching for synchronous access patterns.
///
/// ## Usage
///
/// ```swift
/// let sdk = StormSDKAdapty()
///
/// // Initialize
/// try await sdk.start(config: configuration)
///
/// // Check subscription
/// let entry = await sdk.validateSubscription(for: [.premium])
/// ```
internal actor HubSDKAdapty {
    
    // MARK: - Types
    
    private enum State {
        case notInitialized
        case initializing(Task<Void, Error>)
        case ready(config: StormSDKAdaptyConfiguration, placementBag: PlacementBag)
        case failed(Error)
    }
    
    private struct StateSnapshot: Sendable {
        let isReady: Bool
        let hasActiveSubscription: Bool
        let isReviewMode: Bool
        let config: StormSDKAdaptyConfiguration?
        let placementBag: PlacementBag?
        
        static let initial = StateSnapshot(
            isReady: false,
            hasActiveSubscription: false,
            isReviewMode: true,
            config: nil,
            placementBag: nil
        )
    }
    
    // MARK: - Properties
    
    private var state: State = .notInitialized
    private var subscriptionActive: Bool = false
    private var isReviewMode: Bool = false
    
    nonisolated(unsafe) private var cachedSnapshot: StateSnapshot = .initial
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Configuration
    
    /// Initializes the SDK with the provided configuration.
    ///
    /// This method activates Adapty, loads placements, and begins observing
    /// profile updates. Subsequent calls with the same configuration return
    /// immediately. Calls with different configurations throw an error.
    ///
    /// - Parameter config: The SDK configuration.
    /// - Throws: `StormSDKError.initializationFailed` if activation fails.
    /// - Throws: `StormSDKError.configurationMismatch` if already initialized with different config.
    public func start(config: StormSDKAdaptyConfiguration) async throws {
        switch state {
        case .notInitialized:
            let task = Task {
                try await performInitialization(config: config)
            }
            state = .initializing(task)
            
            do {
                try await task.value
            } catch {
                state = .failed(error)
                updateSnapshot()
                throw HubSDKError.initializationFailed(error)
            }
            
        case .initializing(let existingTask):
            try await existingTask.value
            
        case .ready(let existingConfig, _):
            guard existingConfig.apiKey == config.apiKey else {
                throw HubSDKError.configurationMismatch(
                    expected: existingConfig.apiKey,
                    provided: config.apiKey
                )
            }
            
        case .failed:
            state = .notInitialized
            updateSnapshot()
        }
    }
    
    /// Resets the SDK to its uninitialized state.
    ///
    /// Call this method to allow reinitialization with a different configuration.
    public func invalidate() async {
        state = .notInitialized
        subscriptionActive = false
        updateSnapshot()
    }
    
    // MARK: - Private Methods
    
    private func performInitialization(config: StormSDKAdaptyConfiguration) async throws {
        let serverCluster: AdaptyConfiguration.ServerCluster = {
            if config.chinaClusterEnable && Locale.current.regionCode == "CN" {
                return .cn
            }
            return .default
        }()
        
        let adaptyConfig = AdaptyConfiguration
            .builder(withAPIKey: config.apiKey)
            .with(storeKitVersion: config.storeKitVersion)
            .with(serverCluster: serverCluster)
            .build()
        
        do {
            try await Adapty.activate(with: adaptyConfig)
            try await AdaptyUI.activate()
            Adapty.logLevel = config.logLevel
            
            await setFallback(config.fallbackName)
            
            let placementBag = try await PlacementBag(
                config.placementIdentifers,
                locale: config.languageCode
            )
            
            state = .ready(config: config, placementBag: placementBag)
            
            await refreshSubscriptionStatus(for: config.accessLevels)

            updateSnapshot()
            
        } catch {
            throw HubSDKError.activateAdapty(error)
        }
    }
    
    /// Loads and installs the fallback configuration from the app bundle.
        ///
        /// Searches for a JSON file with the specified name in the main bundle
        /// and registers it with Adapty as the fallback data source.
        /// Errors are logged but do not propagate.
        ///
        /// - Parameter fallbackName: The name of the JSON file without extension,
        ///   or `nil` to skip fallback installation.
    private func setFallback(_ fallbackName: String?) async {
        guard let fallbackName,
              let fallbackURL = Bundle.main.url(forResource: fallbackName, withExtension: "json") else {
            return
        }
        
        do {
            try await Adapty.setFallback(fileURL: fallbackURL)
        } catch {
            HubSDKError.fallbackInstallError(error).log()
        }
    }
    
    /// Validates that the SDK is in ready state and returns the configuration.
        ///
        /// Use this method before performing operations that require an initialized SDK.
        ///
        /// - Returns: A tuple containing the current configuration and placement bag.
        /// - Throws: `StormSDKError.notInitialized` if SDK has not been started.
        /// - Throws: `StormSDKError.initializationInProgress` if initialization is ongoing.
        /// - Throws: `StormSDKError.initializationFailed` if previous initialization failed
    private func ensureReady() throws -> (StormSDKAdaptyConfiguration, PlacementBag) {
        switch state {
        case .ready(let config, let placementBag):
            return (config, placementBag)
        case .notInitialized:
            throw HubSDKError.notInitialized
        case .initializing:
            throw HubSDKError.initializationInProgress
        case .failed(let error):
            throw HubSDKError.initializationFailed(error)
        }
    }
    
    /// Synchronizes the cached snapshot with the current actor state.
        ///
        /// Call this method after any state mutation to ensure that
        /// nonisolated properties reflect the latest values.
    private func updateSnapshot() {
        switch state {
        case .ready(let config, let placementBag):
            cachedSnapshot = StateSnapshot(
                isReady: true,
                hasActiveSubscription: subscriptionActive,
                isReviewMode: true,
                config: config,
                placementBag: placementBag
            )
        default:
            cachedSnapshot = StateSnapshot(
                isReady: false,
                hasActiveSubscription: false,
                isReviewMode: true,
                config: nil,
                placementBag: nil
            )
        }
    }
    
//    // MARK: - Subscription Status Management
    
    /// Fetches the current profile from Adapty and updates the local subscription status.
       ///
       /// Performs a network request to retrieve the latest profile data and
       /// synchronizes the internal subscription state based on the specified access levels.
       /// Errors during fetch are logged but do not throw.
       ///
       /// - Parameter accessLevels: The access levels to evaluate for active subscriptions.
    private func refreshSubscriptionStatus(for accessLevels: [AccessLevel]) async {
        do {
            let profile = try await Adapty.getProfile()
            updateSubscriptionStatus(from: profile, for: accessLevels)
        } catch {
            HubSDKError.profileFetchFailed(error).log()
        }
    }
    
    /// Evaluates the profile and updates the local subscription status.
        ///
        /// Checks whether any of the specified access levels are active in the profile.
        /// Updates the internal state and triggers a snapshot refresh if the status changes.
        ///
        /// - Parameters:
        ///   - profile: The Adapty profile containing current access level information.
        ///   - accessLevels: The access levels to evaluate.
    private func updateSubscriptionStatus(from profile: AdaptyProfile, for accessLevels: [AccessLevel]) {
        let isActive = accessLevels.contains { level in
            profile.accessLevels[level.rawValue]?.isActive == true
        }
        
        if subscriptionActive != isActive {
            subscriptionActive = isActive
            updateSnapshot()
        }
    }
}

// MARK: - StormSDKAdaptyProviding

extension HubSDKAdapty: HubSDKAdaptyProviding {
    
    // MARK: State
    
    nonisolated public var isInitialized: Bool {
        cachedSnapshot.isReady
    }
    
    nonisolated public var hasActiveSubscription: Bool {
        cachedSnapshot.hasActiveSubscription
    }
    
    // MARK: Subscription Validation
    
    public func validateSubscription(for accessLevels: [AccessLevel]) async -> AccessEntry {
        guard cachedSnapshot.isReady else {
            HubSDKError.notInitialized.log()
            return AccessEntry(isActive: false, isRenewable: false)
        }
        
        do {
            let profile = try await Adapty.getProfile()
            
            for accessLevel in accessLevels {
                if let level = profile.accessLevels[accessLevel.rawValue], level.isActive {
                    let entry = AccessEntry(isActive: true, isRenewable: level.willRenew)
                    updateSubscriptionStatus(from: profile, for: accessLevels)
                    return entry
                }
            }
            
            updateSubscriptionStatus(from: profile, for: accessLevels)
            return AccessEntry(isActive: false, isRenewable: false)
            
        } catch {
            HubSDKError.profileFetchFailed(error).log()
            return AccessEntry(isActive: false, isRenewable: false)
        }
    }
    
    public func validateSubscription() async -> AccessEntry {
        guard let accessLevels = cachedSnapshot.config?.accessLevels else { return .init(isActive: false, isRenewable: false)}
        return await validateSubscription(for: accessLevels)
    }
    
    // MARK: Placement Access (Sync)
    
    nonisolated public func placementEntry(with placementId: String) -> PlacementEntry? {
        guard cachedSnapshot.isReady,
              let placementBag = cachedSnapshot.placementBag else {
            return nil
        }
        return placementBag.entry(for: placementId)
    }
    
    nonisolated public func remoteConfig<T: Sendable>(for placementId: String) -> T? where T: Decodable {
        guard cachedSnapshot.isReady,
              let config = cachedSnapshot.config,
              let placementBag = cachedSnapshot.placementBag,
              let remoteConfigData = placementBag.entry(for: placementId)?.remoteConfigData else {
            return nil
        }
        
        let localizer = JSONLocalizer(languageCode: config.languageCode)
        return try? localizer.decode(from: remoteConfigData)
    }
    
    // MARK: Placement Access (Async)
    
    public func placementEntryAsync(with placementId: String) async throws -> PlacementEntry {
        let (_, placementBag) = try ensureReady()
        
        guard let entry = placementBag.entry(for: placementId) else {
            throw HubSDKError.placementNotFound(placementId)
        }
        
        return entry
    }
    
    public func remoteConfigAsync<T: Sendable>(for placementId: String) async throws -> T where T: Decodable {
        let (config, placementBag) = try ensureReady()
        
        guard let remoteConfigData = placementBag.entry(for: placementId)?.remoteConfigData else {
            throw HubSDKError.remoteConfigNotAvailable(placementId)
        }
        
        let localizer = JSONLocalizer(languageCode: config.languageCode)
        
        do {
            return try localizer.decode(from: remoteConfigData)
        } catch {
            throw HubSDKError.configDecodingFailed(error)
        }
    }
    
    // MARK: Purchase Operations
    
    public func purchase(with product: any AdaptyPaywallProduct) async throws -> AdaptyPurchaseResult {
        let (config, _) = try ensureReady()
        
        do {
            let result = try await Adapty.makePurchase(product: product)
            
            if result.isPurchaseSuccess {
                await refreshSubscriptionStatus(for: config.accessLevels)
                
                let amount = product.price
                let currencyCode = product.currencyCode ?? ""
                HubEventBus.shared.publish(.successPurchase(amount: amount.doubleValue, currency: currencyCode))
            }
            
            return result
            
        } catch {
            throw HubSDKError.purchaseFailed(error)
        }
    }
    
    public func restore(for accessLevels: [AccessLevel]) async throws -> AccessEntry {
        _ = try ensureReady()
        
        do {
            let profile = try await Adapty.restorePurchases()
            
            for accessLevel in accessLevels {
                if let level = profile.accessLevels[accessLevel.rawValue], level.isActive {
                    updateSubscriptionStatus(from: profile, for: accessLevels)
                    return AccessEntry(isActive: true, isRenewable: level.willRenew)
                }
            }
            
            updateSubscriptionStatus(from: profile, for: accessLevels)
            return AccessEntry(isActive: false, isRenewable: false)
            
        } catch {
            throw HubSDKError.restoreFailed(error.localizedDescription)
        }
    }
    
    // MARK: Analytics
    
    public func logPaywall(from placementId: String) async {
        guard let (_, placementBag) = try? ensureReady(),
              let paywall = placementBag.entry(for: placementId)?.paywall else {
            HubSDKError.placementNotFound(placementId).log()
            return
        }
        
        await logPaywall(with: paywall)
    }
    
    public func logPaywall(with paywall: AdaptyPaywall) async {
        do {
            try await Adapty.logShowPaywall(paywall)
        } catch {
            HubSDKError.logPaywallFailed(error).log()
        }
    }
    
    // MARK: Completion Handler Variants
    
    nonisolated public func validateSubscription(
        for accessLevels: [AccessLevel],
        completion: @Sendable @escaping (AccessEntry) -> Void
    ) {
        Task {
            let result = await validateSubscription(for: accessLevels)
            await MainActor.run { completion(result) }
        }
    }
    
    nonisolated public func validateSubscription(completion: @Sendable @escaping (AccessEntry) -> Void) {
        guard let accessLevels = cachedSnapshot.config?.accessLevels else { completion(.init(isActive: false, isRenewable: false)); return}
        validateSubscription(for: accessLevels, completion: completion)
    }
    
    nonisolated public func purchase(
        with product: any AdaptyPaywallProduct,
        completion: @Sendable @escaping (Result<AdaptyPurchaseResult, Error>) -> Void
    ) {
        Task {
            do {
                let result = try await purchase(with: product)
                await MainActor.run { completion(.success(result)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }
    
    nonisolated public func restore(
        for accessLevels: [AccessLevel],
        completion: @Sendable @escaping (Result<AccessEntry, Error>) -> Void
    ) {
        Task {
            do {
                let result = try await restore(for: accessLevels)
                await MainActor.run { completion(.success(result)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }
}

// MARK: - Convenience Methods

extension HubSDKAdapty {
    
    /// Validates subscription status for a single access level.
    ///
    /// - Parameter accessLevel: The access level to validate.
    /// - Returns: An `AccessEntry` containing the subscription status.
    public func validateSubscription(for accessLevel: AccessLevel) async -> AccessEntry {
        await validateSubscription(for: [accessLevel])
    }
    
    /// Restores purchases for a single access level.
    ///
    /// - Parameter accessLevel: The access level to check after restoration.
    /// - Returns: An `AccessEntry` containing the restored subscription status.
    /// - Throws: `StormSDKError` if restoration fails.
    public func restore(for accessLevel: AccessLevel) async throws -> AccessEntry {
        try await restore(for: [accessLevel])
    }
}


extension HubSDKAdapty {
    
    // MARK: - Lazy Loading
    
    /// Loads additional placements into the existing bag.
    ///
    /// Use this method to load placements on-demand after SDK initialization.
    /// Already loaded placements are skipped automatically.
    ///
    /// - Parameter identifiers: The placement identifiers to load.
    /// - Returns: Array of newly loaded entries (excludes already cached).
    /// - Throws: `HubSDKError.notInitialized` if SDK is not initialized.
    public func loadPlacements(_ identifiers: [String]) async throws -> [PlacementEntry] {
        let (_, placementBag) = try ensureReady()
        return try await placementBag.load(identifiers)
    }
    
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
    public func placementEntry(
        for identifier: String,
        loadIfNeeded: Bool
    ) async throws -> PlacementEntry {
        let (_, placementBag) = try ensureReady()
        
        if loadIfNeeded {
            return try await placementBag.loadIfNeeded(identifier)
        } else {
            guard let entry = placementBag.entry(for: identifier) else {
                throw HubSDKError.placementNotFound(identifier)
            }
            return entry
        }
    }
    
    /// Checks whether a placement is already loaded.
    ///
    /// Use this to determine if synchronous access via `placementEntry(with:)`
    /// will return a value, or if async loading is required.
    ///
    /// - Parameter identifier: The placement identifier to check.
    /// - Returns: `true` if the placement is cached and available.
    nonisolated public func isPlacementLoaded(_ identifier: String) -> Bool {
        cachedSnapshot.placementBag?.isLoaded(identifier) ?? false
    }
}
