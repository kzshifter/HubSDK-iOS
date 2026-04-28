import Adapty
import AdaptyUI
import UIKit
import HubIntegrationCore

// MARK: - HubSDKAdaptyProviding

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
    
    public func purchase(with product: any AdaptyPaywallProduct, trackEvent: Bool) async throws -> AdaptyPurchaseResult {
        let (config, _) = try ensureReady()

        do {
            let result = try await Adapty.makePurchase(product: product)

            if result.isPurchaseSuccess {
                await refreshSubscriptionStatus(for: config.accessLevels)

                if trackEvent {
                    let amount = product.price
                    let currencyCode = product.currencyCode ?? ""
                    HubEventBus.shared.publish(.successPurchase(amount: amount.doubleValue, currency: currencyCode))
                }
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
    
    public func restore() async throws -> AccessEntry {
        let accessLevels = try self.ensureReady().0.accessLevels
        return try await self.restore(for: accessLevels)
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
        completion: @MainActor @Sendable @escaping (AccessEntry) -> Void
    ) {
        Task {
            let result = await validateSubscription(for: accessLevels)
            await MainActor.run { completion(result) }
        }
    }
    
    nonisolated public func validateSubscription(
        completion: @MainActor @Sendable @escaping (AccessEntry) -> Void
    ) {
        guard let accessLevels = cachedSnapshot.config?.accessLevels else {
            Task { @MainActor in
                completion(.init(isActive: false, isRenewable: false))
            }
            return
        }
        validateSubscription(for: accessLevels, completion: completion)
    }
    
    nonisolated public func purchase(
        with product: any AdaptyPaywallProduct,
        completion: @MainActor @Sendable @escaping (Result<AdaptyPurchaseResult, Error>) -> Void
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
        completion: @MainActor @Sendable @escaping (Result<AccessEntry, Error>) -> Void
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
    
    nonisolated
    func restore(completion: @escaping @MainActor (Result<AccessEntry, any Error>) -> Void) {
        Task {
            let accessLevels = try await self.ensureReady().0.accessLevels
            restore(for: accessLevels, completion: completion)
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
    /// - Throws: `HubSDKError` if restoration fails.
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
