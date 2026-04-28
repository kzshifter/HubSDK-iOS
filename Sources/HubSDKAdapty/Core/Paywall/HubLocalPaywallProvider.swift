import Adapty
import UIKit

// MARK: - HubLocalPaywallDelegate

/// A delegate for handling user interactions within a local paywall.
///
/// The local paywall (ViewModel, ViewController, or Presenter) uses this delegate
/// to **request** actions. The coordinator performs the actual purchase/restore
/// operations and reports results back via `HubLocalPaywallStateDelegate`.
///
/// This separation ensures that all purchase logic is centralized in the coordinator,
/// while the local paywall only manages its UI.
public protocol HubLocalPaywallDelegate: AnyObject {

    /// Called when the user taps a purchase button.
    ///
    /// The coordinator will execute the purchase and report the result
    /// back via `HubLocalPaywallStateDelegate`.
    ///
    /// - Parameter product: The product the user wants to purchase.
    func localPaywallDidRequestPurchase(product: AdaptyPaywallProduct)

    /// Called when the user taps the restore button.
    ///
    /// The coordinator will execute the restore and report the result
    /// back via `HubLocalPaywallStateDelegate`.
    func localPaywallDidRequestRestore()

    /// Called when the user taps close or swipes to dismiss.
    func localPaywallDidRequestClose()
}

// MARK: - HubLocalPaywallStateDelegate

/// A delegate the coordinator uses to report operation results back to the local paywall.
///
/// Implement this on the object that manages paywall state — a ViewModel, Presenter,
/// Coordinator, or the ViewController itself. The object does NOT have to be a UIViewController.
public protocol HubLocalPaywallStateDelegate: AnyObject {

    /// Called when a purchase completes.
    ///
    /// Use this to update UI based on the result. If `closeOnSuccess` is enabled,
    /// the coordinator will dismiss the paywall automatically after this call.
    ///
    /// - Parameter result: The purchase result (check `isPurchaseSuccess`).
    func localPaywallDidFinishPurchase(result: AdaptyPurchaseResult)

    /// Called when a purchase fails.
    ///
    /// - Parameter error: The error that occurred.
    func localPaywallDidFailPurchase(error: Error)

    /// Called when a restore completes.
    ///
    /// - Parameter entry: The access entry with the restored subscription status.
    func localPaywallDidFinishRestore(entry: AccessEntry)

    /// Called when a restore fails.
    ///
    /// - Parameter error: The error that occurred.
    func localPaywallDidFailRestore(error: Error)
}

// MARK: - Default Implementations

public extension HubLocalPaywallStateDelegate {
    func localPaywallDidFinishPurchase(result: AdaptyPurchaseResult) {}
    func localPaywallDidFailPurchase(error: Error) {}
    func localPaywallDidFinishRestore(entry: AccessEntry) {}
    func localPaywallDidFailRestore(error: Error) {}
}

// MARK: - HubLocalPaywallProvider

/// A protocol for providing local paywall scenes.
///
/// Implement this protocol in your app to supply custom paywall implementations
/// for placements that use local (non-builder) paywalls.
///
/// Returns a `HubLocalPaywallHandle` that separates the view controller from the
/// state delegate, allowing any architecture (MVC, MVVM, Coordinator, VIPER).
///
/// ## MVVM / SwiftUI Example
///
/// ```swift
/// final class AppPaywallProvider: HubLocalPaywallProvider {
///
///     func makePaywall(
///         for identifier: String,
///         placementId: String,
///         products: [AdaptyPaywallProduct],
///         delegate: HubLocalPaywallDelegate,
///         configuration: HubPaywallPresentConfiguration,
///         userInfo: [String: Any]
///     ) -> HubLocalPaywallHandle? {
///         let vm = PaywallViewModel(products: products, delegate: delegate)
///         vm.isCanPopBack = userInfo["isCanPopBack"] as? Bool ?? false
///         let vc = UIHostingController(rootView: PaywallView(viewModel: vm))
///         return HubLocalPaywallHandle(viewController: vc, stateDelegate: vm)
///     }
/// }
/// ```
///
/// ## Coordinator Example
///
/// ```swift
/// final class AppPaywallProvider: HubLocalPaywallProvider {
///
///     func makePaywall(
///         for identifier: String,
///         placementId: String,
///         products: [AdaptyPaywallProduct],
///         delegate: HubLocalPaywallDelegate,
///         configuration: HubPaywallPresentConfiguration,
///         userInfo: [String: Any]
///     ) -> HubLocalPaywallHandle? {
///         let coordinator = PaywallCoordinator(products: products, delegate: delegate)
///         let handle = HubLocalPaywallHandle(
///             viewController: coordinator.viewController,
///             stateDelegate: coordinator.viewModel
///         )
///         handle.onDismiss = { [weak coordinator] in coordinator?.finish() }
///         return handle
///     }
/// }
/// ```
public protocol HubLocalPaywallProvider: AnyObject {

    /// Creates a local paywall scene for the specified identifier.
    ///
    /// - Parameters:
    ///   - identifier: The paywall identifier from remote configuration.
    ///   - placementId: The placement identifier from the Adapty Dashboard.
    ///   - products: The products available for purchase.
    ///   - delegate: The delegate for requesting actions (purchase, restore, close).
    ///   - configuration: The presentation configuration (present type, dismiss policy, etc.).
    ///   - userInfo: Arbitrary app-specific data passed from the `show()` call site.
    /// - Returns: A handle containing the view controller and optional state delegate,
    ///   or `nil` if the identifier is not recognized.
    func makePaywall(
        for identifier: String,
        placementId: String,
        products: [AdaptyPaywallProduct],
        delegate: HubLocalPaywallDelegate,
        configuration: HubPaywallPresentConfiguration,
        userInfo: [String: Any]
    ) -> HubLocalPaywallHandle?
}
