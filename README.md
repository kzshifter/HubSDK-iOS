# HubSDK-iOS

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-orange.svg" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-15.0+-blue.svg" alt="iOS 15.0+">
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg" alt="SPM Compatible">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey.svg" alt="MIT License">
</p>

**HubSDK** — модульный Swift SDK для iOS, объединяющий популярные сервисы аналитики, рекламы и монетизации под единым API.

---

## 📦 Модули

| Модуль | Описание |
|--------|----------|
| `HubSDKCore` | Ядро SDK — регистрация и управление интеграциями |
| `HubSDKAdapty` | Подписки, Paywall, Onboarding, Remote Config (Adapty) |
| `HubGoogleAds` | Реклама: Interstitial, Rewarded, Banner, AppOpen |
| `HubAppsflyer` | Атрибуция установок (AppsFlyer) |
| `HubSkarb` | Аналитика (Skarb) |
| `HubFacebook` | Facebook SDK интеграция |
| `HubFirebase` | Firebase Analytics |
| `HubAnalytics` | Универсальный трекер событий |
| `HubIntegrationCore` | Event Bus для межмодульной коммуникации |

---

## 📲 Установка

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/kzshifter/HubSDK-iOS", branch: "main")
]
```

Подключите нужные модули:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "HubSDKCore",
        "HubSDKAdapty",
        "HubGoogleAds",
        "HubAppsflyer",
        "HubSkarb",
        "HubFacebook",
        "HubAnalytics"
    ]
)
```

---

## 🚀 Quick Start

### 1. Инициализация SDK

```swift
import HubSDKCore
import HubSDKAdapty
import HubGoogleAds
import HubAppsflyer
import HubSkarb
import HubFacebook

final class ApplicationDependency {
    static let shared = ApplicationDependency()

    var adaptyCore: HubSDKAdaptyProviding?
    var googleAdsCore: HubGoogleAdsProviding?
    var appsflyerCore: HubAppsflyerProviding?

    func start(completion: @escaping () -> Void) {
        Task {
            // 1️⃣ Регистрируем интеграции
            await HubSDKCore.shared.register(
                HubAdaptyIntegration(config: .init(
                    apiKey: "public_live_xxxxx",
                    placementIdentifers: ["main_placement", "settings_placement"],
                    accessLevels: [.premium]
                )),
                awaitReady: true
            )

            await HubSDKCore.shared.register(
                HubGoogleAdsIntegration(config: .init(
                    interstitialKey: "ca-app-pub-xxx/xxx",
                    appOpenKey: "ca-app-pub-xxx/xxx",
                    awaitAdTypes: .appOpen
                )),
                awaitReady: true
            )

            await HubSDKCore.shared.register(
                HubAppsflyerIntegration(config: .init(
                    devkey: "YOUR_AF_DEV_KEY",
                    appId: "YOUR_APPLE_ID"
                ))
            )

            await HubSDKCore.shared.register(
                HubSkarbIntegration(config: .init(clientId: "your_client"))
            )

            await HubSDKCore.shared.register(
                HubFacebookIntegration(config: .init())
            )

            // 2️⃣ Запускаем
            await HubSDKCore.shared.run(with: UIApplication.shared)

            // 3️⃣ Ждём готовности
            await HubSDKCore.shared.waitUntilReady()

            // 4️⃣ Сохраняем провайдеры
            self.adaptyCore = await HubSDKCore.shared.adapty
            self.googleAdsCore = await HubSDKCore.shared.googleAds
            self.appsflyerCore = await HubSDKCore.shared.appsflyer

            completion()
        }
    }
}
```

### 2. Настройка Paywall координатора

После инициализации SDK зарегистрируйте зависимости для `HubPaywallCoordinator`:

```swift
// В completion start() или после waitUntilReady()
if let adapty = ApplicationDependency.shared.adaptyCore {
    HubPaywallCoordinator.resolve(
        sdk: adapty,
        localPaywallProvider: AppLocalPaywallProvider() // опционально
    )
}
```

> `resolve()` вызывается **один раз** при старте. После этого `HubPaywallCoordinator.show(...)` готов к использованию в любом месте приложения.

---

## 💰 Подписки и Paywall (HubSDKAdapty)

### Интерфейс `HubSDKAdaptyProviding`

```swift
let adapty = ApplicationDependency.shared.adaptyCore

// Быстрая проверка подписки (кэш)
adapty?.hasActiveSubscription  // Bool

// Полная валидация с сервером
let access = await adapty?.validateSubscription()
access?.isActive      // Bool
access?.isRenewable   // Bool

// Получение placement
let entry = adapty?.placementEntry(with: "main_placement")
entry?.products      // [AdaptyPaywallProduct]
entry?.paywall       // AdaptyPaywall
entry?.identifier    // .builder или .local("identifier")

// Remote Config
struct MyConfig: Codable { ... }
let config: MyConfig? = adapty?.remoteConfig(for: "main_placement")

// Покупка
let result = try await adapty?.purchase(with: product)
result?.isPurchaseSuccess  // Bool

// Восстановление покупок
let restored = try await adapty?.restore(for: [.premium])
// или с дефолтными accessLevels из конфигурации:
let restored = try await adapty?.restore()
```

### Ленивая загрузка плейсментов

```swift
// Загрузить плейсменты после инициализации
let entries = try await adapty?.loadPlacements(["promo_placement"])

// Получить плейсмент с автозагрузкой если не кэширован
let entry = try await adapty?.placementEntry(for: "promo", loadIfNeeded: true)

// Проверить, загружен ли плейсмент
let isLoaded = adapty?.isPlacementLoaded("promo") ?? false
```

---

### 🎯 Показ Paywall — `HubPaywallCoordinator`

Координатор управляет полным циклом paywall: загрузка, показ, покупка, восстановление, закрытие.

#### Fire-and-forget

```swift
try await HubPaywallCoordinator.show(
    placementId: "premium",
    from: viewController
) { action in
    switch action {
    case .close:
        print("Paywall закрыт")
    case .purchase(let result):
        if result.isPurchaseSuccess {
            self.unlockPremium()
        }
    case .purchaseFailed(_, let error):
        print("Ошибка покупки: \(error)")
    case .restore(let entry):
        if entry.isActive {
            self.unlockPremium()
        }
    case .restoreFailed(let error):
        print("Ошибка восстановления: \(error)")
    }
}
```

#### С контролем dismiss

```swift
let coordinator = try await HubPaywallCoordinator.show(
    placementId: "premium",
    from: viewController,
    config: .init(closeOnSuccess: false)
) { action in
    // обработка событий
}

// Закрыть вручную позже:
coordinator.dismiss()
```

#### Через делегат

```swift
let coordinator = try await HubPaywallCoordinator.show(
    placementId: "premium",
    from: viewController
)
coordinator.delegate = self

// Реализуйте HubPaywallCoordinatorDelegate:
extension MyController: HubPaywallCoordinatorDelegate {
    func paywallCoordinator(
        _ coordinator: HubPaywallCoordinator,
        didPerformAction action: HubPaywallCoordinator.Action
    ) {
        switch action {
        case .close: ...
        case .purchase(let result): ...
        case .purchaseFailed(_, let error): ...
        case .restore(let entry): ...
        case .restoreFailed(let error): ...
        }
    }
}
```

### Конфигурация Paywall

```swift
HubPaywallPresentConfiguration(
    presentType: .present,    // .present (модально) или .push (в navigation)
    animationEnable: true,    // Анимация перехода
    dismissEnable: true,      // Разрешить закрытие по кнопке
    closeOnSuccess: true      // Автоматически закрыть после успешной покупки/восстановления
)
```

---

### 🖌 Локальные Paywall

`HubLocalPaywallHandle` разделяет view controller и state delegate, позволяя использовать любую архитектуру (MVC, MVVM, Coordinator, VIPER).

**1. `HubLocalPaywallProvider`** — фабрика paywall-сцен:

```swift
// MVVM / SwiftUI
final class AppLocalPaywallProvider: HubLocalPaywallProvider {

    func makePaywall(
        for identifier: String,
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
            let vm = SpecialViewModel(products: products, delegate: delegate)
            let vc = UIHostingController(rootView: SpecialView(viewModel: vm))
            return HubLocalPaywallHandle(viewController: vc, stateDelegate: vm)
        default:
            return nil
        }
    }
}

// MVC — ViewController сам является stateDelegate
let vc = PaywallViewController(products: products, delegate: delegate)
return HubLocalPaywallHandle(viewController: vc, stateDelegate: vc)

// Coordinator — кастомный dismiss
let handle = HubLocalPaywallHandle(viewController: vc, stateDelegate: vm)
handle.onDismiss = { [weak coordinator] in coordinator?.finish() }
return handle
```

**2. `HubLocalPaywallDelegate`** — запросы действий (purchase, restore, close):

```swift
// ViewModel или VC запрашивает действия через delegate
delegate.localPaywallDidRequestPurchase(product: product)
delegate.localPaywallDidRequestRestore()
delegate.localPaywallDidRequestClose()
```

**3. `HubLocalPaywallStateDelegate`** — координатор сообщает результаты:

```swift
// Реализуйте на любом объекте: ViewModel, VC, Presenter, Coordinator
class MainPaywallViewModel: ObservableObject, HubLocalPaywallStateDelegate {

    func localPaywallDidFinishPurchase(result: AdaptyPurchaseResult) {
        // Обновить UI после покупки
    }

    func localPaywallDidFailPurchase(error: Error) {
        // Показать ошибку
    }

    func localPaywallDidFinishRestore(entry: AccessEntry) {
        // Обновить UI после восстановления
    }

    func localPaywallDidFailRestore(error: Error) {
        // Показать ошибку
    }
}
```

> **Архитектура:** `stateDelegate` может быть любым объектом — ViewModel, ViewController, Presenter, Coordinator. Если `stateDelegate = nil`, результаты приходят только через `HubPaywallCoordinator.Action`. Если задан `onDismiss`, координатор вызовет его вместо стандартного dismiss.

---

### Хелперы для продуктов

```swift
// Форматирование цены
product.descriptionPrice()                           // "$9.99"
product.descriptionPrice(multiplicatorValue: 0.25)   // "$2.50"

// Период подписки
product.descriptionPeriod()                          // "month"
product.descriptionPeriod(isAdaptiveName: true)      // "monthly"

// Замена плейсхолдеров
let text = "Subscribe for %subscriptionPrice% per %subscriptionPeriod%"
product.replacingPlaceholders(in: text)
// → "Subscribe for $9.99 per month"

// Кастомные плейсхолдеры
product.replacingPlaceholders(
    in: "Get %feature% for %subscriptionPrice%",
    additionalPlaceholders: ["%feature%": "Premium"]
)
```

---

## 🎓 Onboarding (HubSDKAdapty)

SDK предоставляет интеграцию с Adapty Onboarding — визуальный конструктор онбординга.

### Closure-based API (рекомендуется)

```swift
let adapty = ApplicationDependency.shared.adaptyCore!

let (controller, proxy) = try await adapty.onboardingController(
    for: "onboarding_placement"
) { action in
    switch action {
    case .close:
        self.dismiss(animated: true)
        self.showMainScreen()

    case .openPaywall(let paywallAction):
        try? await HubPaywallCoordinator.show(
            placementId: paywallAction.actionId,
            from: self,
            config: .init(dismissEnable: false)
        )

    case .custom(let customAction):
        print("Custom action: \(customAction.actionId)")

    case .stateUpdated(let state):
        print("User input: \(state)")

    case .didFinishLoading:
        print("Onboarding loaded")

    case .analytics(let event):
        print("Analytics: \(event)")

    case .error(let error):
        print("Error: \(error)")
    }
}

// ⚠️ Важно: сохраните proxy — он выступает делегатом контроллера
self.onboardingProxy = proxy
present(controller, animated: true)
```

### Delegate-based API

```swift
let controller = try await adapty.onboardingController(
    for: "onboarding_placement",
    delegate: self  // AdaptyOnboardingControllerDelegate
)
present(controller, animated: true)
```

### Ручная загрузка

```swift
// Загрузить onboarding data + конфигурацию
let entry = try await adapty.onboardingEntry(for: "onboarding_placement")

// Для ускорения (без персонализации):
let entry = try await adapty.onboardingEntryForDefaultAudience(for: "onboarding_placement")

// Создать контроллер из entry
let controller = try AdaptyUI.onboardingController(
    with: entry.configuration,
    delegate: self
)
```

### Placeholder при загрузке

```swift
let (controller, proxy) = try await adapty.onboardingController(
    for: "onboarding_placement",
    locale: "en",
    placeholder: {
        let view = UIView()
        view.backgroundColor = .black
        return view
    },
    onAction: { action in ... }
)
```

---

## 📺 Реклама (HubGoogleAds)

### Info.plist

> ⚠️ **Обязательно** добавьте в `Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX</string>
```

Также рекомендуется для iOS 14+:

```xml
<key>SKAdNetworkItems</key>
<array>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>cstr6suwn9.skadnetwork</string>
    </dict>
    <!-- Добавьте остальные SKAdNetwork ID от Google -->
</array>
```

### Показ рекламы

```swift
let ads = ApplicationDependency.shared.googleAdsCore

// Проверка готовности
ads?.isInterstitialReady  // Bool
ads?.isRewardedReady      // Bool
ads?.isAppOpenReady       // Bool
```

**Interstitial:**
```swift
await ads?.showInterstitial(from: viewController)

// Или с callback:
ads?.showInterstitial(from: viewController) {
    self.continueFlow()
}
```

**Rewarded:**
```swift
// Возвращает RewardedResult? с данными о выручке (revenue, currencyCode, precision).
// nil — если объявление не показано или пользователь не досмотрел.
if let result = await ads?.showRewarded(from: viewController) {
    self.giveReward()
    print("Revenue: \(result.revenue) \(result.currencyCode)")
}

// Или с callback:
ads?.showRewarded(from: viewController) { result in
    if result != nil { self.giveReward() }
}
```

**App Open:**
```swift
await ads?.showAppOpen(from: viewController)
```

**Banner:**
```swift
let banner = ads?.createBanner(in: viewController, size: AdSizeBanner)
view.addSubview(banner!)
```

### Конфигурация

```swift
HubGoogleAdsConfiguration(
    interstitialKey: "ca-app-pub-xxx/xxx",
    rewardedKey: "ca-app-pub-xxx/xxx",
    bannerKey: "ca-app-pub-xxx/xxx",
    appOpenKey: "ca-app-pub-xxx/xxx",
    maxRetryAttempts: 2,         // Повторы при ошибке загрузки
    awaitAdTypes: .appOpen,      // Ждать загрузки перед стартом
    awaitTimeout: 6,             // Таймаут ожидания (секунды)
    debug: false                 // true = тестовые ключи Google
)
```

**Типы рекламы для ожидания:**
```swift
.interstitial
.rewarded
.appOpen
.all        // Все типы
.none       // Не ждать (по умолчанию)
```

---

## 📊 AppsFlyer (HubAppsflyer)

```swift
let appsflyer = ApplicationDependency.shared.appsflyerCore

let data = appsflyer?.conversionData
let mediaSource = data?["media_source"] as? String ?? "organic"
let campaign = data?["campaign"] as? String
```

### Конфигурация

```swift
HubAppsflyerConfiguration(
    devkey: "YOUR_APPSFLYER_DEV_KEY",
    appId: "YOUR_APPLE_APP_ID",      // Без префикса "id"
    waitForATT: 60.0,                // Ожидание ATT диалога
    debug: false
)
```

---

## 📈 Аналитика (HubAnalytics)

Универсальный трекер — отправляет во **все** подключённые сервисы (AppsFlyer, Facebook, Firebase).

```swift
HubAnalytics.trackEvent(name: "button_clicked")
HubAnalytics.trackEvent(name: "level_complete", params: ["level": 5])

HubAnalytics.trackSuccessPurchase(amount: 9.99, currency: "USD")
```

---

## 📱 Facebook (HubFacebook)

### Info.plist

> ⚠️ **Обязательно** добавьте в `Info.plist`:

```xml
<key>FacebookClientToken</key>
<string>YOUR_CLIENT_TOKEN</string>
<key>FacebookAppID</key>
<string>YOUR_APP_ID</string>
<key>FacebookDisplayName</key>
<string>YOUR_APP_NAME</string>
```

### Конфигурация

```swift
HubFacebookConfiguration(
    advertiserIDCollectionEnabled: true,
    autoLogAppEventsEnabled: true
)
```

> Facebook автоматически получает события покупок и кастомные события через Event Bus.

---

## 📡 Skarb (HubSkarb)

```swift
let skarb = HubSDKCore.shared.integration(ofType: HubSkarbIntegration.self)?.provider

// Ручная отправка source (обычно не нужно — автоматически из AppsFlyer)
skarb?.sendSource(
    broker: .appsflyer,
    features: ["campaign": "summer"],
    brokerUserID: ""
)
```

### Конфигурация

```swift
HubSkarbConfiguration(
    clientId: "your_skarb_client_id",
    observerMode: true
)
```

> Skarb автоматически получает conversion data от AppsFlyer через Event Bus.

---

## 🔄 Event Bus

Модули обмениваются данными через `HubEventBus`. Подписаться на события:

```swift
class MyListener: HubEventListener {
    init() {
        HubEventBus.shared.subscribe(self)
    }

    deinit {
        HubEventBus.shared.unsubscribe(self)
    }

    func handle(event: HubEvent) {
        switch event {
        case .conversionDataReceived(let appsflyerId, let data):
            // Данные атрибуции от AppsFlyer
            print("Attribution from \(appsflyerId): \(data)")

        case .successPurchase(let amount, let currency):
            // Успешная покупка (отправляется автоматически)
            print("Purchase: \(amount) \(currency)")

        case .event(let name, let params):
            // Кастомное событие
            print("Event: \(name)")
        }
    }
}
```

**Какие модули публикуют события:**

| Событие | Источник |
|---------|----------|
| `.conversionDataReceived` | `HubAppsflyer` — после получения conversion data |
| `.successPurchase` | `HubSDKAdapty` — после успешной покупки, `HubPaywallCoordinator` — после покупки через paywall |
| `.event` | `HubAnalytics` — при вызове `trackEvent` |

**Какие модули слушают события:**

| Модуль | Реагирует на |
|--------|-------------|
| `HubSkarb` | `.conversionDataReceived` — отправляет source данные с `brokerUserID = appsflyerId` |
| `HubSDKAdapty` | `.conversionDataReceived` — синхронизирует AppsFlyer ID и атрибуцию через `Adapty.setIntegrationIdentifier` / `Adapty.updateAttribution` |
| `HubAppsflyer` | `.successPurchase`, `.event` — трекает в AppsFlyer |
| `HubFacebook` | `.successPurchase`, `.event` — трекает в Facebook |
| `HubFirebase` | `.successPurchase`, `.event` — трекает в Firebase |

---

## ⚙️ Конфигурации

### HubSDKAdaptyConfiguration

```swift
HubSDKAdaptyConfiguration(
    apiKey: String,                    // Adapty Public API Key
    placementIdentifers: [String],     // ID плейсментов для предзагрузки
    accessLevels: [AccessLevel],       // [.premium] или [.custom("vip")]
    logLevel: .verbose | .error,       // Уровень логов (опционально, по умолчанию — Adapty default)
    chinaClusterEnable: true,          // Китайский кластер
    fallbackName: "fallback",          // Имя fallback JSON (опционально)
    languageCode: "en"                 // Код языка для локализации (по умолчанию — из Locale)
)
```

> Старое имя `StormSDKAdaptyConfiguration` оставлено как `@available(*, deprecated, renamed: "HubSDKAdaptyConfiguration") public typealias` — существующий код продолжит работать с warning.
>
> Используется StoreKit 2 (Adapty fork [`superteamstrm/AdaptySDK-iOS`](https://github.com/superteamstrm/AdaptySDK-iOS)). Параметр `storeKitVersion` удалён из конфига.

### AccessLevel

```swift
enum AccessLevel {
    case premium              // Стандартный "premium"
    case custom(String)       // Кастомный: .custom("vip")
}
```

---

## 📋 Полный пример интеграции

```swift
// AppDelegate.swift
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        ApplicationDependency.shared.start {
            // Настраиваем Paywall координатор
            if let adapty = ApplicationDependency.shared.adaptyCore {
                HubPaywallCoordinator.resolve(
                    sdk: adapty,
                    localPaywallProvider: AppLocalPaywallProvider()
                )
            }
            self.showOnboarding()
        }
        return true
    }
}

// OnboardingViewController.swift
class OnboardingViewController: UIViewController {
    private var onboardingProxy: OnboardingDelegateProxy?

    func showOnboarding() {
        guard let adapty = ApplicationDependency.shared.adaptyCore else { return }

        Task {
            let (controller, proxy) = try await adapty.onboardingController(
                for: "onboarding_placement"
            ) { [weak self] action in
                switch action {
                case .close:
                    self?.dismiss(animated: true)
                    self?.goToMain()
                case .openPaywall(let paywallAction):
                    guard let self else { return }
                    try? await HubPaywallCoordinator.show(
                        placementId: paywallAction.actionId,
                        from: self,
                        config: .init(dismissEnable: false)
                    ) { action in
                        if case .purchase(let result) = action, result.isPurchaseSuccess {
                            self.goToMain()
                        }
                    }
                default:
                    break
                }
            }

            self.onboardingProxy = proxy
            present(controller, animated: true)
        }
    }

    func showPaywall() {
        Task {
            try await HubPaywallCoordinator.show(
                placementId: "main_placement",
                from: self,
                config: .init(dismissEnable: false)
            ) { [weak self] action in
                switch action {
                case .close:
                    self?.goToMain()
                case .purchase(let result):
                    if result.isPurchaseSuccess { self?.goToMain() }
                default:
                    break
                }
            }
        }
    }
}

// SettingsViewController.swift
class SettingsViewController: UIViewController {

    @IBAction func restoreTapped() {
        Task {
            let entry = try? await ApplicationDependency.shared.adaptyCore?.restore()
            if entry?.isActive == true {
                showAlert("Purchases restored!")
            }
        }
    }

    @IBAction func upgradeTapped() {
        Task {
            try await HubPaywallCoordinator.show(
                placementId: "settings_placement",
                from: self
            )
        }
    }

    @IBAction func watchAdTapped() {
        ApplicationDependency.shared.googleAdsCore?.showRewarded(from: self) { result in
            if result != nil { self.giveBonus() }
        }
    }
}
```

---

## 📄 Требования

- iOS 15.0+
- Swift 6.0+
- Xcode 16.0+

---

## 📄 Лицензия

MIT License. См. [LICENSE](LICENSE).
