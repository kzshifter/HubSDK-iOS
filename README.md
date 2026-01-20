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
| `HubSDKAdapty` | Подписки, Paywall, Remote Config (Adapty) |
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

### Инициализация SDK

```swift
import HubSDKCore
import HubSDKAdapty
import HubGoogleAds
import HubAppsflyer
import HubSkarb
import HubFacebook

final class ApplicationDependency {
    static let shared = ApplicationDependency()
    
    // Провайдеры для доступа к интерфейсам
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
                    accessLevels: [.premium],
                    storeKitVersion: .v2
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

---

## 💰 Подписки и Paywall (HubSDKAdapty)

### Интерфейс `HubSDKAdaptyProviding`

```swift
// Быстрая проверка подписки (кэш)
adaptyCore.hasActiveSubscription  // Bool

// Полная валидация с сервером
let access = await adaptyCore.validateSubscription()
access.isActive      // Bool
access.isRenewable   // Bool

// Получение placement
let entry = adaptyCore.placementEntry(with: "main_placement")
entry?.products      // [AdaptyPaywallProduct]
entry?.paywall       // AdaptyPaywall
entry?.identifier    // .builder или .local("identifier")

// Remote Config
struct MyConfig: Codable { ... }
let config: MyConfig? = adaptyCore.remoteConfig(for: "main_placement")

// Покупка
let result = try await adaptyCore.purchase(with: product)
result.isPurchaseSuccess  // Bool

// Восстановление покупок
let restored = try await adaptyCore.restore(for: [.premium])
```

### Показ Paywall

Рекомендуемый паттерн — создать координатор:

```swift
// AppPaywallCoordinator.swift
@MainActor
final class AppPaywallCoordinator {
    
    enum Action {
        case close
        case finishPurchase(status: AdaptyPurchaseResult)
        case finishRestore(status: AccessEntry)
    }
    
    typealias ActionHandler = (Action) -> Void
    
    private var presenter: HubPaywallPresenter?
    private var actionHandler: ActionHandler = { _ in }
    
    static func build() -> AppPaywallCoordinator {
        AppPaywallCoordinator(
            core: ApplicationDependency.shared.adaptyCore,
            localProvider: AppLocalPaywallCoordinator()
        )
    }
    
    private init(core: HubSDKAdaptyProviding?, localProvider: HubLocalPaywallProvider) {
        guard let core else { return }
        self.presenter = HubPaywallPresenter(sdk: core, localPaywallProvider: localProvider)
        self.presenter?.delegate = self
    }
    
    @discardableResult
    func actionHandler(_ handler: @escaping ActionHandler) -> Self {
        self.actionHandler = handler
        return self
    }
    
    func show(placementId: String,
              from viewController: UIViewController? = nil,
              config: HubPaywallPresentConfiguration) {
        Task {
            try await presenter?.showPaywall(
                placementId: placementId,
                from: viewController ?? rootViewController!,
                config: config
            )
        }
    }
}

extension AppPaywallCoordinator: HubPaywallCoordinatorDelegate {
    func paywallCoordinatorDidClose(_ coordinator: HubPaywallPresenter) {
        actionHandler(.close)
    }
    
    func paywallCoordinator(_ coordinator: HubPaywallPresenter, 
                            didFinishPurchaseWith result: AdaptyPurchaseResult) {
        actionHandler(.finishPurchase(status: result))
    }
    
    func paywallCoordinator(_ coordinator: HubPaywallPresenter, 
                            didFinishRestoreWith entry: AccessEntry) {
        actionHandler(.finishRestore(status: entry))
    }
}
```

**Использование:**

```swift
AppPaywallCoordinator
    .build()
    .actionHandler { action in
        switch action {
        case .close:
            self.startMain()
        case .finishPurchase(let result):
            if result.isPurchaseSuccess {
                self.unlockPremium()
            }
        case .finishRestore(let entry):
            if entry.isActive {
                self.unlockPremium()
            }
        }
    }
    .show(placementId: "main_placement", config: .init(dissmissEnable: false))
```

### Конфигурация Paywall

```swift
HubPaywallPresentConfiguration(
    presentType: .present,    // .present (модально) или .push (в navigation)
    animationEnable: true,    // Анимация перехода
    dissmissEnable: true      // Разрешить закрытие по кнопке
)
```

### Локальные Paywall

Для кастомных UI реализуйте `HubLocalPaywallProvider`:

```swift
final class AppLocalPaywallCoordinator: HubLocalPaywallProvider {
    
    func paywallViewController(
        for identifier: String,
        products: [AdaptyPaywallProduct],
        delegate: HubLocalPaywallDelegate
    ) -> UIViewController? {
        
        switch identifier {
        case "main":
            return MainPaywallViewController(products: products, delegate: delegate)
        case "special":
            return SpecialOfferViewController(products: products, delegate: delegate)
        default:
            return nil
        }
    }
}
```

В вашем ViewController вызывайте делегат:

```swift
// При покупке
delegate.purchaseLocalPaywallFinish(result, product: product)

// При восстановлении
delegate.restoreLocalPaywallFinish(profile)

// При закрытии
delegate.closeLocalPaywallAction()
```

### Хелперы для продуктов

```swift
// Форматирование цены
product.descriptionPrice()                    // "$9.99"
product.descriptionPrice(multiplicatorValue: 0.25)  // "$2.50" (недельная цена от месячной)

// Период подписки
product.descriptionPeriod()                   // "month"
product.descriptionPeriod(isAdaptiveName: true)  // "monthly"

// Замена плейсхолдеров в тексте
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

## 📺 Реклама (HubGoogleAds)

### Info.plist

> ⚠️ **Обязательно** добавьте в `Info.plist` вашего приложения:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX</string>
```

Также рекомендуется добавить для iOS 14+:

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

### Интерфейс `HubGoogleAdsProviding`

```swift
let ads = ApplicationDependency.shared.googleAdsCore

// Проверка готовности
ads?.isInterstitialReady  // Bool
ads?.isRewardedReady      // Bool
ads?.isAppOpenReady       // Bool
```

### Показ рекламы

**Interstitial:**
```swift
// Async
await ads?.showInterstitial(from: viewController)

// Callback
ads?.showInterstitial(from: viewController) {
    // Реклама закрыта
    self.continueFlow()
}
```

**Rewarded:**
```swift
// Async
let rewarded = await ads?.showRewarded(from: viewController)
if rewarded == true {
    self.giveReward()
}

// Callback
ads?.showRewarded(from: viewController) { rewarded in
    if rewarded {
        self.giveReward()
    }
}
```

**App Open:**
```swift
// В SceneDelegate или при возврате в приложение
await ads?.showAppOpen(from: viewController)

// Или с callback
ads?.showAppOpen { 
    self.continueLoading()
}
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
.none       // Не ждать
```

---

## 📊 AppsFlyer (HubAppsflyer)

### Интерфейс `HubAppsflyerProviding`

```swift
let appsflyer = ApplicationDependency.shared.appsflyerCore

// Получение conversion data
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

Универсальный трекер событий, который отправляет в **все** подключённые сервисы (AppsFlyer, Facebook, Firebase).

```swift
// Трек события
HubAnalytics.trackEvent(name: "button_clicked")
HubAnalytics.trackEvent(name: "level_complete", params: ["level": 5])

// Трек покупки (автоматически отправляется во все сервисы)
HubAnalytics.trackSuccessPurchase(amount: 9.99, currency: "USD")
```

---

## 📱 Facebook (HubFacebook)

### Info.plist

> ⚠️ **Обязательно** добавьте в `Info.plist` вашего приложения:

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

Facebook автоматически получает события покупок и кастомные события через Event Bus.

---

## 📡 Skarb (HubSkarb)

### Интерфейс `HubSkarbProviding`

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

> **Note:** Skarb автоматически получает conversion data от AppsFlyer через Event Bus.

---

## 🔄 Event Bus

Модули автоматически обмениваются данными. Вы можете подписаться на события:

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
        case .conversionDataReceived(let data):
            print("Attribution: \(data)")
        case .successPurchase(let amount, let currency):
            print("Purchase: \(amount) \(currency)")
        case .event(let name, let params):
            print("Event: \(name)")
        }
    }
}
```

---

## ⚙️ Конфигурации

### StormSDKAdaptyConfiguration

```swift
StormSDKAdaptyConfiguration(
    apiKey: String,                    // Adapty Public API Key
    placementIdentifers: [String],     // ID плейсментов для предзагрузки
    accessLevels: [AccessLevel],       // [.premium] или [.custom("vip")]
    storeKitVersion: .v1 | .v2,        // Версия StoreKit
    logLevel: .verbose | .error,       // Уровень логов
    chinaClusterEnable: true,          // Китайский кластер
    fallbackName: "fallback",          // Имя fallback JSON (опционально)
    languageCode: "en"                 // Код языка для локализации
)
```

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
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        ApplicationDependency.shared.start {
            // SDK готов
            self.showOnboarding()
        }
        
        return true
    }
}

// OnboardingViewController.swift
class OnboardingViewController: UIViewController {
    
    func showPaywall() {
        AppPaywallCoordinator
            .build()
            .actionHandler { [weak self] action in
                switch action {
                case .close:
                    self?.goToMain()
                case .finishPurchase(let result):
                    if result.isPurchaseSuccess {
                        self?.goToMain()
                    }
                default:
                    break
                }
            }
            .show(placementId: "onboarding_placement", config: .init(dissmissEnable: false))
    }
}

// SettingsViewController.swift  
class SettingsViewController: UIViewController {
    
    @IBAction func restoreTapped() {
        Task {
            let entry = try? await ApplicationDependency.shared.adaptyCore?.restore(for: [.premium])
            if entry?.isActive == true {
                showAlert("Purchases restored!")
            }
        }
    }
    
    @IBAction func watchAdTapped() {
        ApplicationDependency.shared.googleAdsCore?.showRewarded(from: self) { rewarded in
            if rewarded {
                self.giveBonus()
            }
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
