import Adapty
import AdaptyUI
import Foundation
import HubIntegrationCore
import UIKit

// MARK: - HubSDKAdapty

/// The main implementation of the Hub SDK Adapty wrapper.
///
/// This actor provides thread-safe access to Adapty functionality with
/// automatic state management and caching for synchronous access patterns.
///
/// ## Usage
///
/// ```swift
/// let sdk = HubSDKAdapty()
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
        case ready(config: HubSDKAdaptyConfiguration, placementBag: PlacementBag)
        case failed(Error)
    }

    internal struct StateSnapshot: Sendable {
        let isReady: Bool
        let hasActiveSubscription: Bool
        let isReviewMode: Bool
        let config: HubSDKAdaptyConfiguration?
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

    nonisolated(unsafe) internal var cachedSnapshot: StateSnapshot = .initial

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
    /// - Throws: `HubSDKError.initializationFailed` if activation fails.
    /// - Throws: `HubSDKError.configurationMismatch` if already initialized with different config.
    public func start(config: HubSDKAdaptyConfiguration) async throws {
        switch state {
        case .notInitialized:
            HubEventBus.shared.subscribe(self)
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

    private func performInitialization(config: HubSDKAdaptyConfiguration) async throws {
        let serverCluster: AdaptyServerCluster = {
            if config.chinaClusterEnable && Locale.current.regionCode == "CN" {
                return .cn
            }
            return .default
        }()

        var builder = AdaptyConfiguration
            .builder(withAPIKey: config.apiKey)
            .with(serverCluster: serverCluster)

        if let logLevel = config.logLevel {
            builder = builder.with(logLevel: logLevel)
        }

        let adaptyConfig = builder.build()

        do {
            try await Adapty.activate(with: adaptyConfig)
            try await AdaptyUI.activate()

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
        /// - Throws: `HubSDKError.notInitialized` if SDK has not been started.
        /// - Throws: `HubSDKError.initializationInProgress` if initialization is ongoing.
        /// - Throws: `HubSDKError.initializationFailed` if previous initialization failed
    internal func ensureReady() throws -> (HubSDKAdaptyConfiguration, PlacementBag) {
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
    internal func updateSnapshot() {
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
    internal func refreshSubscriptionStatus(for accessLevels: [AccessLevel]) async {
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
    internal func updateSubscriptionStatus(from profile: AdaptyProfile, for accessLevels: [AccessLevel]) {
        let isActive = accessLevels.contains { level in
            profile.accessLevels[level.rawValue]?.isActive == true
        }

        if subscriptionActive != isActive {
            subscriptionActive = isActive
            updateSnapshot()
        }
    }
}

extension HubSDKAdapty: HubEventListener {
    nonisolated func handle(event: HubEvent) {
        switch event {
        case .conversionDataReceived(let id, let conversionData):
            Task {
                try? await Adapty.setIntegrationIdentifier(key: "appsflyer_id", value: id)
                try? await Adapty.updateAttribution(conversionData, source: "appsflyer")
            }
        default:
            break
        }
    }
}
