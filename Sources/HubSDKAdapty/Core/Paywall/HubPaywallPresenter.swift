import Foundation
import UIKit
import Adapty
import AdaptyUI
import HubIntegrationCore

// MARK: - PaywallCoordinatorDelegate

/// A delegate for receiving paywall lifecycle and transaction events.
public protocol HubPaywallCoordinatorDelegate: AnyObject {
    
    /// Called when a purchase completes successfully.
    func paywallCoordinator(_ coordinator: HubPaywallPresenter, didFinishPurchaseWith result: AdaptyPurchaseResult)
    
    /// Called when purchase restoration completes.
    func paywallCoordinator(_ coordinator: HubPaywallPresenter, didFinishRestoreWith entry: AccessEntry)
    
    /// Called when the paywall is dismissed.
    func paywallCoordinatorDidClose(_ coordinator: HubPaywallPresenter)
}

// MARK: - Default Implementation

public extension HubPaywallCoordinatorDelegate {
    func paywallCoordinator(_ coordinator: HubPaywallPresenter, didFinishPurchaseWith result: AdaptyPurchaseResult) {}
    func paywallCoordinator(_ coordinator: HubPaywallPresenter, didFinishRestoreWith entry: AccessEntry) {}
    func paywallCoordinatorDidClose(_ coordinator: HubPaywallPresenter) {}
}

@MainActor
final public class HubPaywallPresenter {
    
    private let sdk: (any HubSDKAdaptyProviding & Sendable)
    private var localPaywallProvider: HubLocalPaywallProvider?
    private var presentedViewController: UIViewController?
    private var currentEntry: PlacementEntry?
    private var currentConfig: HubPaywallPresentConfiguration?
    
    public var delegate: HubPaywallCoordinatorDelegate?
    
    /// Creates a new paywall coordinator.
    ///
    /// - Parameters:
    ///   - sdk: The Storm SDK instance for Adapty operations.
    ///   - localPaywallProvider: The provider for local paywall view controllers.
    public init(
        sdk: (any HubSDKAdaptyProviding & Sendable),
        localPaywallProvider: HubLocalPaywallProvider? = nil
    ) {
        self.sdk = sdk
        self.localPaywallProvider = localPaywallProvider
    }
    
    // MARK: - Public Methods
    
    /// Presents the appropriate paywall for the specified placement.
    ///
    /// This method determines whether to show a builder or local paywall
    /// based on the placement configuration and presents it modally.
    ///
    /// - Parameters:
    ///   - placementId: The placement identifier.
    ///   - viewController: The view controller to present from.
    ///   - config: The configuration for present paywall
    /// - Throws: `HubSDKError` if the placement is not found or paywall cannot be displayed.
    public func showPaywall(
        placementId: String,
        from viewController: UIViewController,
        config: HubPaywallPresentConfiguration
    ) async throws {
        let sdk = self.sdk
        
        let entry = try await sdk.placementEntryAsync(with: placementId)
        currentEntry = entry
        currentConfig = config
        
        switch entry.identifier {
        case .builder:
            try await showBuilderPaywall(
                entry: entry,
                from: viewController,
                config: config
            )
        case .local(let identifier):
            await sdk.logPaywall(with: entry.paywall)
            try await showLocalPaywall(
                identifier: identifier,
                entry: entry,
                from: viewController,
                config: config
            )
        }
    }
    
    /// Dismisses the currently presented paywall.
      ///
      /// - Parameter animated: Whether to animate the dismissal.
      public func dismiss() async {
          if currentConfig?.dissmissEnable ?? true {
              let animationEnable = currentConfig?.animationEnable ?? false
              if currentConfig?.presentType == .present {
                  presentedViewController?.dismiss(animated: animationEnable)
              } else {
                  presentedViewController?
                  .navigationController?
                  .popViewController(animated: animationEnable)
              }
          }
      }
      
      // MARK: - Private Methods
      
      private func showBuilderPaywall(
          entry: PlacementEntry,
          from viewController: UIViewController,
          config: HubPaywallPresentConfiguration
      ) async throws {
          let configuration = try await AdaptyUI.getPaywallConfiguration(forPaywall: entry.paywall)
       
          let adaptyController = try AdaptyUI.paywallController(with: configuration,
                                                                delegate: self)
          presentedViewController = adaptyController
          
          self.presentPaywall(from: viewController,
                              paywall: adaptyController,
                              type: config.presentType,
                              withAnimation: config.animationEnable)
      }
      
      private func showLocalPaywall(
          identifier: String,
          entry: PlacementEntry,
          from viewController: UIViewController,
          config: HubPaywallPresentConfiguration
      ) async throws {
          guard let provider = localPaywallProvider else {
              throw HubSDKError.localPaywallProviderNotSet
          }
          
          guard let paywallVC = provider.paywallViewController(
              for: identifier,
              products: entry.products,
              delegate: self
          ) else {
              throw HubSDKError.localPaywallNotFound(identifier)
          }
          
          self.presentedViewController = paywallVC
          self.presentPaywall(from: viewController,
                              paywall: paywallVC,
                              type: config.presentType,
                              withAnimation: config.animationEnable)
      }
    
    private func presentPaywall(from presenter: UIViewController,
                                paywall: UIViewController,
                                type: HubPaywallPresentConfiguration.PresentType,
                                withAnimation status: Bool) {
        switch type {
        case .present:
            paywall.modalPresentationStyle = .fullScreen
            presenter.present(paywall, animated: status)
            
        case .push:
            if let nav = presenter as? UINavigationController {
                nav.pushViewController(paywall, animated: status)
            } else if let nav = presenter.navigationController {
                nav.pushViewController(paywall, animated: status)
            } else {
                assertionFailure("[HubSDK] Push requested but no UINavigationController available")
                paywall.modalPresentationStyle = .fullScreen
                presenter.present(paywall, animated: status)
            }
        }
    }
    
    private func dispose() {
        presentedViewController = nil
        currentEntry = nil
        currentConfig = nil
        localPaywallProvider = nil
        delegate = nil
    }
}

//MARK: Local Paywall Delegate

extension HubPaywallPresenter: @preconcurrency HubLocalPaywallDelegate {
    public func purchaseLocalPaywallFinish(_ result: AdaptyPurchaseResult, product: AdaptyPaywallProduct) {
        self.purchaseValidator(purchaseResult: result, product: product)
    }
    
    public func restoreLocalPaywallFinish(_ profile: AdaptyProfile) {
        self.restoreValidator()
    }
    
    public func closeLocalPaywallAction() {
        Task { @MainActor in
            self.delegate?.paywallCoordinatorDidClose(self)
            await self.dismiss()
            self.dispose()
        }
    }
    
    private func restoreValidator() {
        Task {
            if let access = try? await sdk.validateSubscription() {
                delegate?.paywallCoordinator(self, didFinishRestoreWith: access)
            }
        }
    }
    
    private func purchaseValidator(purchaseResult: AdaptyPurchaseResult, product: AdaptyPaywallProduct) {
        delegate?.paywallCoordinator(self, didFinishPurchaseWith: purchaseResult)
        
        if purchaseResult.isPurchaseSuccess {
            /// Track purchase
            let amount = product.price
            let currencyCode = product.currencyCode ?? ""
            HubEventBus.shared.publish(.successPurchase(amount: amount.doubleValue, currency: currencyCode))
            
            /// Dismiss after success purchase
            Task {
                await self.dismiss()
                self.dispose()
            }
        }
    }
}


//MARK: Builder Paywall Delegate

extension HubPaywallPresenter: AdaptyPaywallControllerDelegate {
    public func paywallController(_ controller: AdaptyPaywallController, didFailRestoreWith error: AdaptyError) {}
    public func paywallController(_ controller: AdaptyPaywallController, didFailPurchase product: any AdaptyPaywallProduct, error: AdaptyError) {}
    
    public func paywallController(_ controller: AdaptyPaywallController, didFinishRestoreWith profile: AdaptyProfile) {
        self.restoreValidator()
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didPerform action: AdaptyUI.Action) {
        switch action {
        case .close:
            Task {
                delegate?.paywallCoordinatorDidClose(self)
                await self.dismiss()
                self.dispose()
            }
        default: break
        }
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didFinishPurchase product: any AdaptyPaywallProduct, purchaseResult: AdaptyPurchaseResult) {
        self.purchaseValidator(purchaseResult: purchaseResult, product: product)
    }
}
