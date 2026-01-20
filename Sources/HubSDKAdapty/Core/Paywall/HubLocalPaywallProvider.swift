import Adapty
import UIKit

// MARK: - LocalPaywallDelegate

/// A delegate for handling user interactions within a local paywall.
///
/// Implement this protocol to receive callbacks when the user interacts
/// with purchase controls, restoration, or dismissal actions.
public protocol HubLocalPaywallDelegate: AnyObject {
    
    /// Called when the user finish a purchase.
    ///
    /// - Parameter product: The product to purchase.
    func purchaseLocalPaywallFinish(_ result: AdaptyPurchaseResult, product: AdaptyPaywallProduct)
    
    /// Called when the user requests purchase restoration.
    func restoreLocalPaywallFinish(_ profile: AdaptyProfile)
    
    /// Called when the user dismisses the paywall.
    func closeLocalPaywallAction()
}

// MARK: - LocalPaywallProvider

/// A protocol for providing local paywall view controllers.
///
/// Implement this protocol in your app to supply custom paywall implementations
/// for placements that use local (non-builder) paywalls.
///
/// ## Example Implementation
///
/// ```swift
/// final class AppPaywallProvider: LocalPaywallProvider {
///
///     func paywallViewController(
///         for identifier: String,
///         products: [AdaptyPaywallProduct],
///         delegate: LocalPaywallDelegate
///     ) -> UIViewController? {
///         switch identifier {
///         case "main":
///             return OnboardingPaywallViewController(
///                 products: products,
///                 delegate: delegate
///             )
///         case "settings":
///             return SettingsPaywallViewController(
///                 products: products,
///                 delegate: delegate
///             )
///         default:
///             return nil
///         }
///     }
/// }
/// ```
public protocol HubLocalPaywallProvider: AnyObject {
    
    /// Creates a view controller for the specified local paywall.
    ///
    /// - Parameters:
    ///   - identifier: The paywall identifier from remote configuration.
    ///   - products: The products available for purchase.
    ///   - delegate: The delegate for handling paywall events.
    /// - Returns: A configured view controller, or `nil` if the identifier is not recognized.
    func paywallViewController(
        for identifier: String,
        products: [AdaptyPaywallProduct],
        delegate: HubLocalPaywallDelegate
    ) -> UIViewController?
}
