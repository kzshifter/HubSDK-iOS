import Foundation

public enum HubSDKError: Error {
    // Initialization errors
    case notInitialized
    case alreadyInitialized
    case initializationInProgress
    case initializationFailed(Error)
    case activateAdapty(Error)
    case logPaywallFailed(Error)
    
    // Fallback errors
    case fallbackFileNotFound(String?)
    case fallbackInstallError(Error)
    
    // Placement errors
    case buildPlacementEntryFailed(Error)
    case placementNotFound(String)
    case placementBagEmpty
    
    // Configuration errors
    case configDecodingFailed(Error)
    case invalidConfiguration(String)
    case remoteConfigNotAvailable(String)
    case configurationMismatch(expected: String, provided: String)
    
    // Purchase errors
    case purchaseFailed(Error)
    case purchaseCancelled
    case productNotFound(String)
    
    // Restore errors
    case restoreFailed(String)
    case noActiveSubscription([AccessLevel])
    
    // Network errors
    case networkError(Error)
    case apiError(statusCode: Int, message: String)
    
    // Profile errors
    case profileFetchFailed(Error)
    case profileCacheExpired
    
    // General errors
    case unknownError(Error)
    case invalidState(current: String, expected: String)
    
    // Paywall erros
    case localPaywallProviderNotSet
    case localPaywallNotFound(String)
}

// MARK: - LocalizedError

extension HubSDKError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        // Initialization
        case .notInitialized:
            return "SDK is not initialized. Call start(config:) first."
            
        case .alreadyInitialized:
            return "SDK is already initialized. Cannot initialize twice."
            
        case .initializationInProgress:
            return "SDK initialization is in progress. Please wait for completion."
            
        case .initializationFailed(let error):
            return "SDK initialization failed: \(error.localizedDescription)"
            
        case .activateAdapty(let error):
            return "Adapty activation failed: \(error.localizedDescription)"
            
        case .logPaywallFailed(let error):
            return "SDK can't log paywall with error: \(error.localizedDescription)"
            
        // Fallback
        case .fallbackFileNotFound(let fileName):
            if let name = fileName {
                return "Fallback file '\(name).json' not found in bundle."
            }
            return "Fallback file not found in bundle."
            
        case .fallbackInstallError(let error):
            return "Failed to install fallback: \(error.localizedDescription)"
            
        // Placement
        case .buildPlacementEntryFailed(let error):
            return "Failed to build placement entry: \(error.localizedDescription)"
            
        case .placementNotFound(let placementId):
            return "Placement with id '\(placementId)' not found."
            
        case .placementBagEmpty:
            return "Placement bag is empty. SDK may not be properly initialized."
            
        // Configuration
        case .configDecodingFailed(let error):
            return "Failed to decode remote config: \(error.localizedDescription)"
            
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
            
        case .remoteConfigNotAvailable(let placementId):
            return "Remote config not available for placement '\(placementId)'."
        
        case .configurationMismatch(let expected, let provided):
            return "Configuration missmatch with api keys: Expected: \(expected) and Provided: \(provided)."
        // Purchase
        case .purchaseFailed(let error):
            return "Purchase failed: \(error.localizedDescription)"
            
        case .purchaseCancelled:
            return "Purchase was cancelled by user."
            
        case .productNotFound(let productId):
            return "Product '\(productId)' not found."
            
        // Restore
        case .restoreFailed(let message):
            return "Restore failed: \(message)"
            
        case .noActiveSubscription(let levels):
            let levelNames = levels.map { $0.rawValue }.joined(separator: ", ")
            return "No active subscription found for access levels: \(levelNames)"
            
        // Network
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
            
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
            
        // Profile
        case .profileFetchFailed(let error):
            return "Failed to fetch user profile: \(error.localizedDescription)"
            
        case .profileCacheExpired:
            return "Profile cache expired. Please refresh."
            
        // General
        case .unknownError(let error):
            return "Unknown error occurred: \(error.localizedDescription)"
            
        case .invalidState(let current, let expected):
            return "Invalid SDK state. Current: \(current), Expected: \(expected)"
            
        // Paywalls
        case .localPaywallProviderNotSet:
            return "Local paywall is not set"
        case .localPaywallNotFound(let id):
            return "Local paywall is not found with id: \(id)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .notInitialized:
            return "The SDK start(config:) method was not called."
            
        case .initializationFailed(let error):
            return "Underlying error: \(error)"
            
        case .purchaseCancelled:
            return "User cancelled the purchase flow."
            
        case .noActiveSubscription:
            return "User does not have any active subscriptions."
            
        default:
            return nil
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .notInitialized:
            return "Initialize SDK by calling: await sdk.start(config: yourConfig)"
            
        case .alreadyInitialized:
            return "SDK can only be initialized once. Use existing instance."
            
        case .placementNotFound(let id):
            return "Check if '\(id)' is included in placementIdentifiers array in your configuration."
            
        case .fallbackFileNotFound(let name):
            if let name = name {
                return "Ensure '\(name).json' file is added to your app bundle."
            }
            return "Add fallback JSON file to your app bundle."
            
        case .purchaseCancelled:
            return "User can retry the purchase when ready."
            
        case .restoreFailed:
            return "Ask user to check their internet connection and try again."
            
        case .networkError:
            return "Check internet connection and try again."
            
        default:
            return nil
        }
    }
}

// MARK: - Error Code

extension HubSDKError {
    public var errorCode: Int {
        switch self {
        // 100-199: Initialization errors
        case .notInitialized: return 100
        case .alreadyInitialized: return 101
        case .initializationInProgress: return 102
        case .initializationFailed: return 103
        case .activateAdapty: return 104
        case .logPaywallFailed: return 105
            
        // 200-299: Configuration errors
        case .fallbackFileNotFound: return 200
        case .fallbackInstallError: return 201
        case .invalidConfiguration: return 202
        case .configDecodingFailed: return 203
        case .remoteConfigNotAvailable: return 204
        case .configurationMismatch: return 205
            
        // 300-399: Placement errors
        case .buildPlacementEntryFailed: return 300
        case .placementNotFound: return 301
        case .placementBagEmpty: return 302
            
        // 400-499: Purchase errors
        case .purchaseFailed: return 400
        case .purchaseCancelled: return 401
        case .productNotFound: return 402
            
        // 500-599: Restore errors
        case .restoreFailed: return 500
        case .noActiveSubscription: return 501
            
        // 600-699: Network errors
        case .networkError: return 600
        case .apiError: return 601
            
        // 700-799: Profile errors
        case .profileFetchFailed: return 700
        case .profileCacheExpired: return 701
            
        // 900-999: General errors
        case .unknownError: return 900
        case .invalidState: return 901
        case .localPaywallProviderNotSet: return 902
        case .localPaywallNotFound(_): return 903
        }
    }
}

// MARK: - Logging

extension HubSDKError {
    /// Logs error to console with detailed information
    public func log(file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let location = "\(fileName):\(line) \(function)"
        
        var logMessage = """
        ┌─────────────────────────────────────────────────────────────
        │ 🔴 StormSDK Error [\(errorCode)]
        │ Location: \(location)
        │ Description: \(errorDescription ?? "No description")
        """
        
        if let reason = failureReason {
            logMessage += "\n│ Reason: \(reason)"
        }
        
        if let suggestion = recoverySuggestion {
            logMessage += "\n│ 💡 Suggestion: \(suggestion)"
        }
        
        logMessage += "\n└─────────────────────────────────────────────────────────────"
        
        NSLog("%@", logMessage)
    }
    
    /// Static logging method for backward compatibility
    public static func logError(_ error: HubSDKError, file: String = #file, function: String = #function, line: Int = #line) {
        error.log(file: file, function: function, line: line)
    }
    
    /// Log any error as StormSDKError
    public static func logError(key: HubSDKError, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        if let error = error {
            HubSDKError.unknownError(error).log(file: file, function: function, line: line)
        } else {
            key.log(file: file, function: function, line: line)
        }
    }
}

// MARK: - CustomNSError (for Objective-C interop)

extension HubSDKError: CustomNSError {
    public static var errorDomain: String {
        return "com.stormsdk.error"
    }
    
    public var errorUserInfo: [String: Any] {
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: errorDescription ?? "",
            "errorCode": errorCode
        ]
        
        if let reason = failureReason {
            userInfo[NSLocalizedFailureReasonErrorKey] = reason
        }
        
        if let suggestion = recoverySuggestion {
            userInfo[NSLocalizedRecoverySuggestionErrorKey] = suggestion
        }
        
        return userInfo
    }
}

// MARK: - Convenience Helpers

extension HubSDKError {
    /// Check if error is retryable
    public var isRetryable: Bool {
        switch self {
        case .networkError, .apiError, .profileFetchFailed, .initializationFailed:
            return true
        case .purchaseCancelled, .notInitialized, .alreadyInitialized:
            return false
        default:
            return false
        }
    }
    
    /// Check if error is user-facing (should be shown to user)
    public var isUserFacing: Bool {
        switch self {
        case .purchaseFailed, .purchaseCancelled, .restoreFailed, .networkError, .noActiveSubscription:
            return true
        default:
            return false
        }
    }
    
    /// Get user-friendly message (simplified for UI)
    public var userFriendlyMessage: String {
        switch self {
        case .purchaseCancelled:
            return "Purchase was cancelled"
        case .purchaseFailed:
            return "Unable to complete purchase. Please try again."
        case .restoreFailed:
            return "Unable to restore purchases. Please try again."
        case .networkError:
            return "Network connection error. Please check your internet."
        case .noActiveSubscription:
            return "No active subscription found"
        default:
            return errorDescription ?? "An error occurred"
        }
    }
}
