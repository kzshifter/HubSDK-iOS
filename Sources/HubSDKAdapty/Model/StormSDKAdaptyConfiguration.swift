import Adapty
import Foundation

// MARK: - HubSDKAdaptyConfiguration

/// The configuration object used to initialize the HubSDK Adapty wrapper.
///
/// This structure contains all required and optional parameters for SDK initialization,
/// including API credentials, placement identifiers, and behavior customization options.
///
/// ## Example Usage
///
/// ```swift
/// let config = HubSDKAdaptyConfiguration(
///     apiKey: "public_live_xxxxx",
///     placementIdentifers: ["onboarding_placement", "settings_placement"],
///     accessLevels: [.premium]
/// )
///
/// try await sdk.start(config: config)
/// ```
public struct HubSDKAdaptyConfiguration: Sendable {

    /// The public API key from the Adapty dashboard.
    ///
    /// Obtain this key from your Adapty project settings.
    /// Use the appropriate key for your environment (live or test).
    let apiKey: String

    /// The list of placement identifiers to preload during initialization.
    ///
    /// Placements define where paywalls appear in your app.
    /// Preloading ensures instant access via synchronous methods.
    let placementIdentifers: [String]

    /// The access levels to monitor for subscription status.
    ///
    /// The SDK evaluates these levels when determining `isActiveSubscription`
    /// and during validation operations.
    let accessLevels: [AccessLevel]

    /// The logging verbosity level for Adapty operations.
    ///
    /// Use `.verbose` during development and `.error` in production.
    /// Defaults to `nil` (Adapty default).
    let logLevel: AdaptyLog.Level?

    /// A Boolean value indicating whether to use China-specific servers.
    ///
    /// When `true`, the SDK automatically selects the China cluster
    /// if the device region is set to CN. Defaults to `true`.
    let chinaClusterEnable: Bool

    /// The name of the fallback JSON file in the app bundle.
    ///
    /// Provide a fallback file to ensure paywalls display even when
    /// network requests fail. The file should be exported from the Adapty dashboard.
    /// Pass `nil` to disable fallback support.
    let fallbackName: String?

    /// The language code used for remote config localization.
    ///
    /// This value determines which localized strings are returned
    /// from remote configuration data. Defaults to `"en"`.
    let languageCode: String

    /// Creates a new SDK configuration.
    ///
    /// - Parameters:
    ///   - apiKey: The public API key from the Adapty dashboard.
    ///   - placementIdentifers: The placement identifiers to preload.
    ///   - accessLevels: The access levels to monitor for subscription status.
    ///   - logLevel: The logging verbosity level. Defaults to `nil`.
    ///   - chinaClusterEnable: Whether to enable China cluster selection. Defaults to `true`.
    ///   - fallbackName: The fallback JSON filename, or `nil` to disable.
    ///   - languageCode: The language code for localization. Defaults to `"en"`.
    public init(
        apiKey: String,
        placementIdentifers: [String],
        accessLevels: [AccessLevel],
        logLevel: AdaptyLog.Level? = nil,
        chinaClusterEnable: Bool = true,
        fallbackName: String? = nil,
        languageCode: String = Locale.current.languageCode ?? "en"
    ) {
        self.apiKey = apiKey
        self.placementIdentifers = placementIdentifers
        self.accessLevels = accessLevels
        self.chinaClusterEnable = chinaClusterEnable
        self.logLevel = logLevel
        self.fallbackName = fallbackName
        self.languageCode = languageCode
    }
}

@available(*, deprecated, renamed: "HubSDKAdaptyConfiguration")
public typealias StormSDKAdaptyConfiguration = HubSDKAdaptyConfiguration
