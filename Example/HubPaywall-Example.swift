import Adapty
import AdaptyUI
import Foundation
import HubSDKAdapty
import UIKit

// ============================================================================
// MARK: - Setup (AppDelegate / DI)
// ============================================================================

/// Call once at app launch after Adapty SDK is initialized.
func setupPaywallCoordinator() {
    HubPaywallCoordinator.resolve(
        sdk: AppDependency.shared.adaptyCore!,
        localPaywallProvider: AppLocalPaywallProvider()
    )
}


// ============================================================================
// MARK: 1. Fire & Forget — самый частый кейс
// ============================================================================

/// Из любого места: кнопка "Get Premium", баннер, ограничение фичи.
/// Координатор сам себя удержит и отпустит после dismiss.
func showPremiumPaywall(from vc: UIViewController) {
    Task { @MainActor in
        try await HubPaywallCoordinator.show(
            placementId: "premium",
            from: vc,
            config: .init(presentType: .present, closeOnSuccess: true)
        ) { action in
            switch action {
            case .close:
                print("Closed")
            case .purchase(let result):
                if result.isPurchaseSuccess {
                    NotificationCenter.default.post(name: .premiumActivated, object: nil)
                }
            case .purchaseFailed(_, let error):
                print("Purchase error: \(error)")
            case .restore(let entry):
                if entry.isActive {
                    NotificationCenter.default.post(name: .premiumActivated, object: nil)
                }
            case .restoreFailed(let error):
                print("Restore error: \(error)")
            }
        }
    }
}


// ============================================================================
// MARK: 2. С контролем dismiss — когда нужно закрыть снаружи
// ============================================================================

@MainActor
final class FeatureGateViewController: UIViewController {

    private var paywallCoordinator: HubPaywallCoordinator?

    func showPaywall() {
        Task {
            paywallCoordinator = try await HubPaywallCoordinator.show(
                placementId: "feature_gate",
                from: self,
                config: .init(closeOnSuccess: false)  // сами контролируем dismiss
            ) { [weak self] action in
                self?.handleAction(action)
            }
        }
    }

    private func handleAction(_ action: HubPaywallCoordinator.Action) {
        switch action {
        case .purchase(let result) where result.isPurchaseSuccess:
            // Анимация успеха → потом dismiss
            showSuccessAnimation {
                self.paywallCoordinator?.dismiss()
                self.paywallCoordinator = nil
                self.unlockFeature()
            }
        case .close:
            paywallCoordinator = nil
        case .purchaseFailed(_, let error):
            showAlert(error: error)
        case .restoreFailed(let error):
            showAlert(error: error)
        default:
            break
        }
    }

    private func showSuccessAnimation(completion: @escaping () -> Void) { /* ... */ }
    private func unlockFeature() { /* ... */ }
    private func showAlert(error: Error) { /* ... */ }
}


// ============================================================================
// MARK: 3. С делегатом — для сложных VC с множеством пейволлов
// ============================================================================

@MainActor
final class SettingsViewController: UIViewController {

    private var paywallCoordinator: HubPaywallCoordinator?

    func showPremium() {
        Task {
            let coordinator = try await HubPaywallCoordinator.show(
                placementId: "settings_premium",
                from: self,
                config: .init(presentType: .present)
            )
            coordinator.delegate = self
            self.paywallCoordinator = coordinator
        }
    }

    func showProPlan() {
        Task {
            let coordinator = try await HubPaywallCoordinator.show(
                placementId: "settings_pro",
                from: self,
                config: .init(presentType: .push)
            )
            coordinator.delegate = self
            self.paywallCoordinator = coordinator
        }
    }
}

extension SettingsViewController: HubPaywallCoordinatorDelegate {
    func paywallCoordinator(
        _ coordinator: HubPaywallCoordinator,
        didPerformAction action: HubPaywallCoordinator.Action
    ) {
        switch action {
        case .close:
            paywallCoordinator = nil
        case .purchase(let result) where result.isPurchaseSuccess:
            refreshPremiumUI()
            paywallCoordinator = nil
        case .restore(let entry) where entry.isActive:
            refreshPremiumUI()
            paywallCoordinator = nil
        case .purchaseFailed(_, let error):
            showError(error)
        case .restoreFailed(let error):
            showError(error)
        default:
            break
        }
    }

    private func refreshPremiumUI() { /* ... */ }
    private func showError(_ error: Error) { /* ... */ }
}


// ============================================================================
// MARK: 4. Минимальный вызов — дефолты делают всё за тебя
// ============================================================================

/// closeOnSuccess: true (default), presentType: .present (default)
/// Координатор сам закроется после покупки/рестора. Просто вызови и забудь.
func quickShow(from vc: UIViewController) {
    Task { @MainActor in
        try await HubPaywallCoordinator.show(placementId: "premium", from: vc)
    }
}


// ============================================================================
// MARK: 5. Custom Assets — видео, изображения для builder пейволлов
// ============================================================================

/// Передай assetsResolver в show() для кастомных медиа-ресурсов в builder пейволлах.
func showPaywallWithCustomAssets(from vc: UIViewController) {
    Task { @MainActor in
        var assets: [String: AdaptyCustomAsset] = [:]

        if let videoURL = Bundle.main.url(forResource: "hero_video", withExtension: "mp4"),
           let preview = UIImage(named: "hero_video") {
            assets["hero_video"] = .video(.file(url: videoURL, preview: .uiImage(value: preview)))
        }

        try await HubPaywallCoordinator.show(
            placementId: "premium",
            from: vc,
            assetsResolver: assets.isEmpty ? nil : assets
        ) { action in
            switch action {
            case .purchase(let result) where result.isPurchaseSuccess:
                print("Purchased!")
            case .close:
                print("Closed")
            default:
                break
            }
        }
    }
}


// ============================================================================
// MARK: 6. Local Paywall Provider — MVVM / SwiftUI
// ============================================================================

/// ViewModel получает products и delegate типизированно.
/// stateDelegate указывает на ViewModel — он получает результаты purchase/restore.
@MainActor
final class AppLocalPaywallProvider: HubLocalPaywallProvider {

    func makePaywall(
        for identifier: String,
        placementId: String,
        products: [AdaptyPaywallProduct],
        delegate: HubLocalPaywallDelegate,
        configuration: HubPaywallPresentConfiguration,
        userInfo: [String: Any]
    ) -> HubLocalPaywallHandle? {
        switch identifier {
        case "main":
            let vm = MainPaywallViewModel(products: products, delegate: delegate)
            vm.isCanPopBack = userInfo["isCanPopBack"] as? Bool ?? false
            let vc = UIHostingController(rootView: MainPaywallView(viewModel: vm))
            return HubLocalPaywallHandle(viewController: vc, stateDelegate: vm)

        case "special":
            let vm = SpecialPaywallViewModel(products: products, delegate: delegate)
            let vc = UIHostingController(rootView: SpecialPaywallView(viewModel: vm))
            return HubLocalPaywallHandle(viewController: vc, stateDelegate: vm)

        default:
            return nil
        }
    }
}

/// ViewModel: запрашивает действия через delegate, получает результаты через HubLocalPaywallStateDelegate.
@MainActor
final class MainPaywallViewModel: ObservableObject, HubLocalPaywallStateDelegate {

    let products: [AdaptyPaywallProduct]
    private let delegate: HubLocalPaywallDelegate

    @Published var isPurchasing = false
    @Published var purchaseSuccess = false
    var isCanPopBack = false

    init(products: [AdaptyPaywallProduct], delegate: HubLocalPaywallDelegate) {
        self.products = products
        self.delegate = delegate
    }

    // MARK: - User Actions → delegate запросы

    func purchase(_ product: AdaptyPaywallProduct) {
        isPurchasing = true
        delegate.localPaywallDidRequestPurchase(product: product)
    }

    func restore() {
        isPurchasing = true
        delegate.localPaywallDidRequestRestore()
    }

    func close() {
        delegate.localPaywallDidRequestClose()
    }

    // MARK: - HubLocalPaywallStateDelegate — результаты от координатора

    func localPaywallDidFinishPurchase(result: AdaptyPurchaseResult) {
        isPurchasing = false
        purchaseSuccess = result.isPurchaseSuccess
    }

    func localPaywallDidFailPurchase(error: Error) {
        isPurchasing = false
    }

    func localPaywallDidFinishRestore(entry: AccessEntry) {
        isPurchasing = false
        purchaseSuccess = entry.isActive
    }

    func localPaywallDidFailRestore(error: Error) {
        isPurchasing = false
    }
}


// ============================================================================
// MARK: 7. Local Paywall Provider — MVC
// ============================================================================

/// В MVC ViewController сам является stateDelegate.
@MainActor
final class MVCLocalPaywallProvider: HubLocalPaywallProvider {

    func makePaywall(
        for identifier: String,
        placementId: String,
        products: [AdaptyPaywallProduct],
        delegate: HubLocalPaywallDelegate,
        configuration: HubPaywallPresentConfiguration,
        userInfo: [String: Any]
    ) -> HubLocalPaywallHandle? {
        let vc = SimplePaywallViewController(products: products, delegate: delegate)
        return HubLocalPaywallHandle(viewController: vc, stateDelegate: vc)
    }
}


// ============================================================================
// MARK: 8. Local Paywall Provider — Coordinator
// ============================================================================

/// Координатор создаёт VC, управляет dismiss через onDismiss.
@MainActor
final class CoordinatorLocalPaywallProvider: HubLocalPaywallProvider {

    weak var navigationController: UINavigationController?

    func makePaywall(
        for identifier: String,
        placementId: String,
        products: [AdaptyPaywallProduct],
        delegate: HubLocalPaywallDelegate,
        configuration: HubPaywallPresentConfiguration,
        userInfo: [String: Any]
    ) -> HubLocalPaywallHandle? {
        let vm = MainPaywallViewModel(products: products, delegate: delegate)
        let vc = UIHostingController(rootView: MainPaywallView(viewModel: vm))

        let handle = HubLocalPaywallHandle(viewController: vc, stateDelegate: vm)

        // Кастомный dismiss — координатор сам управляет навигацией
        handle.onDismiss = { [weak navigationController] in
            navigationController?.popViewController(animated: true)
        }

        return handle
    }
}


// MARK: - Helpers

extension Notification.Name {
    static let premiumActivated = Notification.Name("premiumActivated")
}

// MARK: - Stubs (для компиляции примеров)

import SwiftUI

private struct MainPaywallView: View {
    @ObservedObject var viewModel: MainPaywallViewModel
    var body: some View { EmptyView() }
}
private struct SpecialPaywallView: View {
    @ObservedObject var viewModel: SpecialPaywallViewModel
    var body: some View { EmptyView() }
}
@MainActor
private final class SpecialPaywallViewModel: ObservableObject, HubLocalPaywallStateDelegate {
    init(products: [AdaptyPaywallProduct], delegate: HubLocalPaywallDelegate) {}
}
private final class SimplePaywallViewController: UIViewController, HubLocalPaywallStateDelegate {
    init(products: [AdaptyPaywallProduct], delegate: HubLocalPaywallDelegate) { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
}
