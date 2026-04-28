import Adapty
import AdaptyUI
import Foundation
import HubIntegrationCore
import UIKit

// MARK: - HubPaywallCoordinatorDelegate

/// A delegate for receiving paywall lifecycle and transaction events.
public protocol HubPaywallCoordinatorDelegate: AnyObject {
    
    /// Called when the paywall coordinator dispatches an action.
    ///
    /// All paywall events (close, purchase, restore, errors) flow through this single method.
    /// Use `switch action` to handle specific cases.
    func paywallCoordinator(_ coordinator: HubPaywallCoordinator, didPerformAction action: HubPaywallCoordinator.Action)
}

// MARK: - HubPaywallCoordinator

/// A unified coordinator for fetching, presenting, and managing Adapty paywalls.
///
/// Uses a hybrid approach: static `resolve()` for dependency injection at app launch,
/// while each `show()` call creates a new isolated instance with its own lifecycle.
///
/// ## Setup (once at app launch)
///
/// ```swift
/// HubPaywallCoordinator.resolve(
///     sdk: adaptyCore,
///     localPaywallProvider: MyLocalPaywallProvider()
/// )
/// ```
///
/// ## Usage — fire and forget
///
/// ```swift
/// try await HubPaywallCoordinator.show(
///     placementId: "premium",
///     from: viewController,
///     config: .init(presentType: .present)
/// ) { action in
///     switch action {
///     case .close: print("closed")
///     case .purchase(let r): print("purchased: \(r.isPurchaseSuccess)")
///     case .purchaseFailed(_, let e): print("purchase error: \(e)")
///     case .restore(let e): print("restored: \(e.isActive)")
///     case .restoreFailed(let e): print("restore error: \(e)")
///     }
/// }
/// ```
///
/// ## Usage — with dismiss control
///
/// ```swift
/// let coordinator = try await HubPaywallCoordinator.show(
///     placementId: "premium",
///     from: viewController,
///     config: .init(closeOnSuccess: false)
/// ) { action in
///     // handle actions
/// }
///
/// // Later:
/// coordinator.dismiss()
/// ```
@MainActor
public final class HubPaywallCoordinator {
    
    // MARK: - Action
    
    /// Represents all possible outcomes from a paywall flow.
    public enum Action {
        /// The paywall was dismissed (user tapped close or auto-closed after success).
        case close
        
        /// A purchase completed (check `result.isPurchaseSuccess` for success/cancellation).
        case purchase(result: AdaptyPurchaseResult)
        
        /// A purchase failed with an error.
        case purchaseFailed(product: any AdaptyPaywallProduct, error: Error)
        
        /// A restore completed.
        case restore(entry: AccessEntry)
        
        /// A restore failed with an error.
        case restoreFailed(error: Error)
    }
    
    public typealias ActionHandler = (Action) -> Void
    
    // MARK: - Static Dependencies
    
    private static var _sdk: (any HubSDKAdaptyProviding & Sendable)?
    private static var _localPaywallProvider: (any HubLocalPaywallProvider)?
    
    /// Registers SDK dependencies for all future paywall presentations.
    ///
    /// Call this once during app initialization (e.g., in `AppDelegate` or your DI setup).
    ///
    /// - Parameters:
    ///   - sdk: The HubSDK instance for Adapty operations.
    ///   - localPaywallProvider: Optional provider for local (non-builder) paywall view controllers.
    public static func resolve(
        sdk: any HubSDKAdaptyProviding & Sendable,
        localPaywallProvider: (any HubLocalPaywallProvider)? = nil
    ) {
        _sdk = sdk
        _localPaywallProvider = localPaywallProvider
    }
    
    // MARK: - Static Show
    
    /// Fetches and presents a paywall, returning the coordinator instance for optional lifecycle control.
    ///
    /// Each call creates a new isolated coordinator with its own state.
    /// The coordinator retains itself while the paywall is presented and auto-releases on dispose.
    ///
    /// - Parameters:
    ///   - placementId: The placement identifier from the Adapty Dashboard.
    ///   - viewController: The view controller to present from.
    ///   - config: Presentation and behavior configuration.
    ///   - onAction: Optional closure called for each paywall action.
    /// - Returns: The coordinator instance. Retain it only if you need external dismiss control.
    /// - Throws: `HubSDKError.notInitialized` if `resolve()` has not been called.
    /// - Throws: `HubSDKError.placementNotFound` if placement does not exist.
    @discardableResult
    public static func show(
        placementId: String,
        from viewController: UIViewController,
        config: HubPaywallPresentConfiguration = .init(),
        userInfo: [String: Any] = [:],
        onAction: ActionHandler? = nil
    ) async throws -> HubPaywallCoordinator {
        guard let sdk = _sdk else {
            throw HubSDKError.notInitialized
        }

        let coordinator = HubPaywallCoordinator(
            sdk: sdk,
            localPaywallProvider: _localPaywallProvider
        )

        try await coordinator.performShow(
            placementId: placementId,
            from: viewController,
            config: config,
            userInfo: userInfo,
            onAction: onAction
        )

        return coordinator
    }
    
    // MARK: - Instance Properties
    
    private let sdk: any HubSDKAdaptyProviding & Sendable
    private let localPaywallProvider: (any HubLocalPaywallProvider)?
    
    private var presentedViewController: UIViewController?
    private var currentEntry: PlacementEntry?
    private var currentPresentConfig: HubPaywallPresentConfiguration?
    private var actionHandler: ActionHandler?
    
    /// Reference to the local paywall for reporting purchase/restore results back to its UI.
    private weak var localPaywallStateDelegate: HubLocalPaywallStateDelegate?

    /// Custom dismiss handler provided by the local paywall handle.
    private var localPaywallOnDismiss: (() -> Void)?
    
    /// Self-retention to keep the coordinator alive while the paywall is on screen.
    /// Released in `dispose()` when the paywall is dismissed.
    private var retainedSelf: HubPaywallCoordinator?
    
    /// Optional delegate for receiving paywall events.
    /// Can be used alongside the closure-based `onAction`.
    public weak var delegate: HubPaywallCoordinatorDelegate?
    
    // MARK: - Init
    
    private init(
        sdk: any HubSDKAdaptyProviding & Sendable,
        localPaywallProvider: (any HubLocalPaywallProvider)?
    ) {
        self.sdk = sdk
        self.localPaywallProvider = localPaywallProvider
    }
    
    // MARK: - Dismiss
    
    /// Dismisses the currently presented paywall.
    ///
    /// Respects the `dismissEnable` flag from the presentation configuration.
    /// Dispatches `.close` and releases all resources.
    public func dismiss() {
        guard currentPresentConfig?.dismissEnable ?? true else { return }
        
        performDismiss()
        dispatch(.close)
        dispose()
    }
    
    // MARK: - Private: Show Flow
    
    private func performShow(
        placementId: String,
        from viewController: UIViewController,
        config: HubPaywallPresentConfiguration,
        userInfo: [String: Any],
        onAction: ActionHandler?
    ) async throws {
        self.actionHandler = onAction
        self.currentPresentConfig = config
        self.retainedSelf = self

        let entry = try await sdk.placementEntryAsync(with: placementId)
        self.currentEntry = entry

        switch entry.identifier {
        case .builder:
            try await showBuilderPaywall(entry: entry, from: viewController, config: config)
        case .local(let identifier):
            await sdk.logPaywall(with: entry.paywall)
            try showLocalPaywall(identifier: identifier, entry: entry, from: viewController, config: config, userInfo: userInfo)
        }
    }
    
    // MARK: - Private: Presentation
    
    private func showBuilderPaywall(
        entry: PlacementEntry,
        from viewController: UIViewController,
        config: HubPaywallPresentConfiguration
    ) async throws {
        let paywallConfig = try await AdaptyUI.getPaywallConfiguration(forPaywall: entry.paywall)
        let controller = try AdaptyUI.paywallController(with: paywallConfig, delegate: self)
        
        presentedViewController = controller
        presentViewController(controller, from: viewController, config: config)
    }
    
    private func showLocalPaywall(
        identifier: String,
        entry: PlacementEntry,
        from viewController: UIViewController,
        config: HubPaywallPresentConfiguration,
        userInfo: [String: Any]
    ) throws {
        guard let provider = localPaywallProvider else {
            throw HubSDKError.localPaywallProviderNotSet
        }

        guard let handle = provider.makePaywall(
            for: identifier,
            placementId: entry.placementId,
            products: entry.products,
            delegate: self,
            configuration: config,
            userInfo: userInfo
        ) else {
            throw HubSDKError.localPaywallNotFound(identifier)
        }

        localPaywallStateDelegate = handle.stateDelegate
        localPaywallOnDismiss = handle.onDismiss

        presentedViewController = handle.viewController
        presentViewController(handle.viewController, from: viewController, config: config)
    }
    
    private func presentViewController(
        _ child: UIViewController,
        from presenter: UIViewController,
        config: HubPaywallPresentConfiguration
    ) {
        switch config.presentType {
        case .present:
            child.modalPresentationStyle = .fullScreen
            presenter.present(child, animated: config.animationEnable)
            
        case .push:
            if let nav = presenter as? UINavigationController {
                nav.pushViewController(child, animated: config.animationEnable)
            } else if let nav = presenter.navigationController {
                nav.pushViewController(child, animated: config.animationEnable)
            } else {
                assertionFailure("[HubSDK] Push requested but no UINavigationController available")
                child.modalPresentationStyle = .fullScreen
                presenter.present(child, animated: config.animationEnable)
            }
        }
    }
    
    // MARK: - Private: Dismiss & Cleanup
    
    private func performDismiss() {
        guard currentPresentConfig?.dismissEnable ?? true else { return }

        if let onDismiss = localPaywallOnDismiss {
            onDismiss()
            return
        }

        let animated = currentPresentConfig?.animationEnable ?? false

        switch currentPresentConfig?.presentType {
        case .present, .none:
            presentedViewController?.dismiss(animated: animated)
        case .push:
            presentedViewController?.navigationController?.popViewController(animated: animated)
        }
    }
    
    // MARK: - Private: Action Dispatch
    
    /// Single point for dispatching all actions through both closure and delegate.
    private func dispatch(_ action: Action) {
        actionHandler?(action)
        delegate?.paywallCoordinator(self, didPerformAction: action)
    }
    
    /// Handles auto-close logic after successful purchase or restore.
    private func handleSuccessIfNeeded() {
        guard currentPresentConfig?.closeOnSuccess ?? true else { return }
        performDismiss()
        dispatch(.close)
        dispose()
    }
    
    /// Releases all references and breaks the self-retention cycle.
    private func dispose() {
        presentedViewController = nil
        currentEntry = nil
        currentPresentConfig = nil
        actionHandler = nil
        localPaywallStateDelegate = nil
        localPaywallOnDismiss = nil
        retainedSelf = nil
    }
    
    // MARK: - Private: Purchase Handling
    
    /// Processes a successful purchase result.
    /// Notifies local paywall UI, dispatches action, handles auto-close if needed.
    private func handlePurchaseResult(_ result: AdaptyPurchaseResult, product: any AdaptyPaywallProduct) {
        localPaywallStateDelegate?.localPaywallDidFinishPurchase(result: result)
        dispatch(.purchase(result: result))
        
        if result.isPurchaseSuccess {
            let amount = product.price
            let currencyCode = product.currencyCode ?? ""
            HubEventBus.shared.publish(.successPurchase(amount: amount.doubleValue, currency: currencyCode))
            handleSuccessIfNeeded()
        }
    }
    
    /// Processes a purchase failure.
    /// Notifies local paywall UI and dispatches error action.
    private func handlePurchaseFailure(product: any AdaptyPaywallProduct, error: Error) {
        localPaywallStateDelegate?.localPaywallDidFailPurchase(error: error)
        dispatch(.purchaseFailed(product: product, error: error))
    }
    
    // MARK: - Private: Restore Handling
    
    /// Processes a successful restore.
    /// Notifies local paywall UI, dispatches action, handles auto-close if active.
    private func handleRestoreSuccess(entry: AccessEntry) {
        localPaywallStateDelegate?.localPaywallDidFinishRestore(entry: entry)
        dispatch(.restore(entry: entry))
        
        if entry.isActive {
            handleSuccessIfNeeded()
        }
    }
    
    /// Processes a restore failure.
    /// Notifies local paywall UI and dispatches error action.
    private func handleRestoreFailure(error: Error) {
        localPaywallStateDelegate?.localPaywallDidFailRestore(error: error)
        dispatch(.restoreFailed(error: error))
    }
}

// MARK: - AdaptyPaywallControllerDelegate (Builder Paywalls)

extension HubPaywallCoordinator: AdaptyPaywallControllerDelegate {
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didPerform action: AdaptyUI.Action
    ) {
        switch action {
        case .close:
            performDismiss()
            dispatch(.close)
            dispose()
        default:
            break
        }
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishPurchase product: any AdaptyPaywallProduct,
        purchaseResult: AdaptyPurchaseResult
    ) {
        handlePurchaseResult(purchaseResult, product: product)
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishRestoreWith profile: AdaptyProfile
    ) {
        Task {
            let entry = await sdk.validateSubscription()
            handleRestoreSuccess(entry: entry)
        }
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFailPurchase product: any AdaptyPaywallProduct,
        error: AdaptyError
    ) {
        handlePurchaseFailure(product: product, error: error)
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRestoreWith error: AdaptyError
    ) {
        handleRestoreFailure(error: error)
    }
}

// MARK: - HubLocalPaywallDelegate (Local Paywalls)

extension HubPaywallCoordinator: @preconcurrency HubLocalPaywallDelegate {
    
    /// Local paywall requested a purchase — coordinator executes it via SDK
    /// and reports back through `HubLocalPaywallStateDelegate`.
    ///
    /// Lifecycle: sdk.purchase → result/error callback.
    public func localPaywallDidRequestPurchase(product: AdaptyPaywallProduct) {
        
        Task {
            do {
                let result = try await sdk.purchase(with: product, trackEvent: false)
                handlePurchaseResult(result, product: product)
            } catch {
                handlePurchaseFailure(product: product, error: error)
            }
        }
    }
    
    /// Local paywall requested a restore — coordinator executes it via SDK
    /// and reports back through `HubLocalPaywallStateDelegate`.
    ///
    /// Lifecycle: sdk.restore → result/error callback.
    public func localPaywallDidRequestRestore() {
        
        Task {
            do {
                let access = try await sdk.restore()
                handleRestoreSuccess(entry: access)
            } catch {
                handleRestoreFailure(error: error)
            }
        }
    }
    
    /// Local paywall requested close.
    public func localPaywallDidRequestClose() {
        performDismiss()
        dispatch(.close)
        dispose()
    }
}
