# HubSDK-iOS

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-orange.svg" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-15.0+-blue.svg" alt="iOS 15.0+">
  <img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg" alt="SPM Compatible">
  <img src="https://img.shields.io/badge/License-MIT-lightgrey.svg" alt="MIT License">
</p>

**HubSDK** — модульный Swift SDK, объединяющий популярные сервисы мобильной аналитики, рекламы и монетизации под единым API. Подключайте только то, что нужно.

## ✨ Возможности

- 🔌 **Модульная архитектура** — каждая интеграция в отдельном модуле
- ⏳ **Awaitable паттерн** — ожидание готовности SDK перед стартом приложения
- 📡 **Event Bus** — автоматическая синхронизация данных между модулями
- 🎯 **Swift 6 Concurrency** — современный async/await API
- 🛡️ **Type-safe** — строгая типизация конфигураций и ошибок

## 📦 Модули

| Модуль | Описание | Зависимость |
|--------|----------|-------------|
| `HubSDKCore` | Ядро SDK, регистрация интеграций | — |
| `HubIntegrationCore` | Базовые протоколы и Event Bus | — |
| `HubAppsflyer` | Атрибуция установок | [AppsFlyer](https://github.com/AppsFlyerSDK/AppsFlyerFramework) |
| `HubGoogleAds` | Реклама (Interstitial, Rewarded, Banner, AppOpen) | [Google Mobile Ads](https://github.com/googleads/swift-package-manager-google-mobile-ads) |
| `HubSDKAdapty` | Подписки и Paywall | [Adapty](https://github.com/adaptyteam/AdaptySDK-iOS) |
| `HubSkarb` | Аналитика Skarb | [SkarbSDK](https://github.com/bitlica/SkarbSDK-iOS) |

## 📲 Установка

### Swift Package Manager

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/kzshifter/HubSDK-iOS", branch: "main")
]
```

Или в Xcode: **File → Add Package Dependencies** → вставить URL репозитория.

### Подключение модулей

```swift
// Подключите только нужные модули
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "HubSDKCore", package: "HubSDK-iOS"),
        .product(name: "HubAppsflyer", package: "HubSDK-iOS"),
        .product(name: "HubSDKAdapty", package: "HubSDK-iOS"),
        .product(name: "HubGoogleAds", package: "HubSDK-iOS"),
        .product(name: "HubSkarb", package: "HubSDK-iOS"),
    ]
)
```

---

## 🚀 Quick Start

### Инициализация в AppDelegate

```swift
import UIKit
import HubSDKCore
import HubAppsflyer
import HubSDKAdapty
import HubGoogleAds
import HubSkarb

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        Task { @MainActor in
            await setupSDK(application: application)
        }
        
        return true
    }
    
    @MainActor
    private func setupSDK(application: UIApplication) async {
        // 1️⃣ Регистрируем интеграции
        
        // AppsFlyer — атрибуция
        HubSDKCore.shared.register(
            HubAppsflyerIntegration(config: .init(
                devkey: "YOUR_APPSFLYER_DEV_KEY",
                appId: "YOUR_APPLE_APP_ID"
            )),
            awaitReady: true  // Ждём conversion data
        )
        
        // Adapty — подписки
        HubSDKCore.shared.register(
            HubAdaptyIntegration(config: .init(
                apiKey: "public_live_XXXXXX",
                placementIdentifers: ["onboarding", "settings"],
                accessLevels: [.premium]
            )),
            awaitReady: true
        )
        
        // Google Ads — реклама
        HubSDKCore.shared.register(
            HubGoogleAdsIntegration(config: .init(
                interstitialKey: "ca-app-pub-xxx/xxx",
                rewardedKey: "ca-app-pub-xxx/xxx",
                appOpenKey: "ca-app-pub-xxx/xxx",
                awaitAdTypes: [.interstitial]
            )),
            awaitReady: true
        )
        
        // Skarb — аналитика (автоматически получит conversion data)
        HubSDKCore.shared.register(
            HubSkarbIntegration(config: .init(
                clientId: "YOUR_SKARB_CLIENT_ID"
            ))
        )
        
        // 2️⃣ Запускаем все интеграции
        HubSDKCore.shared.run(with: application)
        
        // 3️⃣ Ждём готовности
        await HubSDKCore.shared.waitUntilReady(timeout: 10)
        
        // 4️⃣ SDK готов к работе!
        print("✅ HubSDK initialized")
    }
}
```

---

## 📖 Документация модулей

### HubSDKCore

Центральный модуль для управления интеграциями.

```swift
@MainActor
public class HubSDKCore {
    static let shared: HubSDKCore
    
    /// Регистрирует интеграцию
    /// - Parameters:
    ///   - integration: Экземпляр интеграции
    ///   - awaitReady: Если true, waitUntilReady() будет ждать эту интеграцию
    func register(_ integration: any StormDependencyIntegration, awaitReady: Bool = false)
    
    /// Запускает все зарегистрированные интеграции
    func run(with application: UIApplication)
    
    /// Ожидает готовности всех awaitable интеграций
    func waitUntilReady(timeout: TimeInterval = 10) async
    
    /// Получает интеграцию по типу
    func integration<T: StormDependencyIntegration>(ofType type: T.Type) -> T?
}
```

---

### HubAppsflyer

Интеграция с AppsFlyer для атрибуции установок.

#### Конфигурация

```swift
HubAppsflyerConfiguration(
    devkey: String,              // AppsFlyer Dev Key
    appId: String,               // Apple App ID (без "id" префикса)
    waitForATT: Double = 60.0,   // Ожидание ATT диалога (секунды)
    debug: Bool = false          // Включить debug логи
)
```

#### Использование

```swift
// Получение conversion data
if let appsflyer = HubSDKCore.shared.appsflyer {
    let data = appsflyer.conversionData
    
    let mediaSource = data["media_source"] as? String ?? "organic"
    let campaign = data["campaign"] as? String
    
    print("Install source: \(mediaSource)")
}
```

#### События

Conversion data автоматически публикуется через Event Bus:

```swift
// В других модулях (например, Skarb) данные получаются автоматически
StormEvent.conversionDataReceived([String: String])
```

---

### HubGoogleAds

Интеграция с Google Mobile Ads.

#### Конфигурация

```swift
HubGoogleAdsConfiguration(
    interstitialKey: String = "",      // Ad Unit ID
    rewardedKey: String = "",          // Ad Unit ID
    bannerKey: String = "",            // Ad Unit ID
    appOpenKey: String = "",           // Ad Unit ID
    maxRetryAttempts: Int = 2,         // Повторные попытки загрузки
    awaitAdTypes: AdType = .none,      // Типы рекламы для ожидания
    awaitTimeout: TimeInterval = 10,   // Таймаут ожидания загрузки
    debug: Bool = false                // Использовать тестовые ключи
)
```

#### Типы рекламы

```swift
struct AdType: OptionSet {
    static let interstitial  // Полноэкранная реклама
    static let rewarded      // Реклама с наградой
    static let appOpen       // Реклама при открытии приложения
    static let all           // Все типы
    static let none          // Ничего не ждать
}
```

#### Показ рекламы

```swift
guard let ads = HubSDKCore.shared.googleAds else { return }

// Interstitial
if ads.isInterstitialReady {
    await ads.showInterstitial(from: viewController)
}

// Rewarded
if ads.isRewardedReady {
    let rewarded = await ads.showRewarded(from: viewController)
    if rewarded {
        // Выдать награду пользователю
        giveReward()
    }
}

// App Open (обычно в sceneDidBecomeActive)
if ads.isAppOpenReady {
    await ads.showAppOpen()
}

// Banner
let banner = ads.createBanner(in: viewController, size: AdSizeBanner)
view.addSubview(banner)
```

#### Callback API

```swift
// Если нужен callback вместо async/await
ads.showRewarded(from: viewController) { rewarded in
    if rewarded {
        self.giveReward()
    }
}
```

---

### HubSDKAdapty

Интеграция с Adapty для управления подписками и paywall.

#### Конфигурация

```swift
StormSDKAdaptyConfiguration(
    apiKey: String,                           // Public API Key из Adapty Dashboard
    placementIdentifers: [String],            // ID плейсментов для предзагрузки
    accessLevels: [AccessLevel],              // Уровни доступа для проверки
    storeKitVersion: StoreKitVersion = .v1,   // Версия StoreKit
    logLevel: AdaptyLog.Level = .verbose,     // Уровень логирования
    chinaClusterEnable: Bool = true,          // Китайский кластер
    fallbackName: String? = nil,              // Имя fallback JSON файла
    languageCode: String = Locale.current.identifier
)
```

#### Уровни доступа

```swift
enum AccessLevel {
    case premium                    // Стандартный "premium"
    case custom(String)             // Кастомный уровень
}
```

#### Проверка подписки

```swift
guard let adapty = HubSDKCore.shared.adapty else { return }

// Быстрая проверка (кэшированное значение)
if adapty.hasActiveSubscription {
    showPremiumContent()
}

// Полная валидация с сервера
let entry = await adapty.validateSubscription(for: [.premium])
if entry.isActive {
    print("Subscription active, will renew: \(entry.isRenewable)")
}
```

#### Показ Paywall

```swift
// Получение placement
if let entry = adapty.placementEntry(with: "onboarding") {
    switch entry.identifier {
    case .builder:
        // Используется Adapty Paywall Builder
        showBuilderPaywall(entry: entry)
    case .local(let identifier):
        // Локальный paywall
        showLocalPaywall(identifier: identifier, products: entry.products)
    }
}

// Или через HubPaywallPresenter
let presenter = HubPaywallPresenter(
    sdk: adapty,
    localPaywallProvider: myPaywallProvider
)
presenter.delegate = self

try await presenter.showPaywall(
    placementId: "onboarding",
    from: viewController,
    config: HubPaywallPresentConfiguration(
        presentType: .present,
        animationEnable: true,
        dissmissEnable: true
    )
)
```

#### Покупка и восстановление

```swift
// Покупка
do {
    let result = try await adapty.purchase(with: product)
    if result.isPurchaseSuccess {
        print("Purchase successful!")
    }
} catch {
    print("Purchase failed: \(error)")
}

// Восстановление покупок
do {
    let entry = try await adapty.restore(for: [.premium])
    if entry.isActive {
        print("Purchases restored!")
    }
} catch {
    print("Restore failed: \(error)")
}
```

#### Remote Config

```swift
// Типизированный remote config
struct OnboardingConfig: Codable, Sendable {
    let title: String
    let features: [String]
    let showTrial: Bool
}

if let config: OnboardingConfig = adapty.remoteConfig(for: "onboarding") {
    print("Title: \(config.title)")
}
```

---

### HubSkarb

Интеграция со Skarb для аналитики.

#### Конфигурация

```swift
HubSkarbConfiguration(
    clientId: String,           // Skarb Client ID
    observerMode: Bool = true   // Observer mode
)
```

#### Автоматическая интеграция

Skarb автоматически получает conversion data от AppsFlyer через Event Bus — дополнительная настройка не требуется.

#### Ручная отправка данных

```swift
if let skarb = HubSDKCore.shared.integration(ofType: HubSkarbIntegration.self)?.provider {
    skarb.sendSource(
        broker: .appsflyer,
        features: ["campaign": "summer_sale"],
        brokerUserID: "user123"
    )
}
```

---

## 🔄 Event Bus

Модули автоматически обмениваются данными через `StormEventBus`.

### Доступные события

```swift
enum StormEvent {
    case conversionDataReceived([String: String])  // Данные атрибуции
    case successPurchase                            // Успешная покупка
}
```

### Подписка на события

```swift
class MyAnalytics: StormEventListener {
    init() {
        StormEventBus.shared.subscribe(self)
    }
    
    deinit {
        StormEventBus.shared.unsubscribe(self)
    }
    
    func handle(event: StormEvent) {
        switch event {
        case .conversionDataReceived(let data):
            trackInstall(source: data["media_source"])
        case .successPurchase:
            trackPurchase()
        }
    }
}
```

---

## 🏗️ Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                        Your App                              │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                      HubSDKCore                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  register() → run() → waitUntilReady()                 │ │
│  └────────────────────────────────────────────────────────┘ │
└──────────────────────────┬──────────────────────────────────┘
                           │
     ┌─────────────────────┼─────────────────────┐
     │                     │                     │
┌────▼────┐          ┌─────▼─────┐         ┌────▼────┐
│ HubApps │          │ HubGoogle │         │ HubSDK  │
│ flyer   │          │ Ads       │         │ Adapty  │
└────┬────┘          └─────┬─────┘         └────┬────┘
     │                     │                     │
     └──────────┬──────────┴──────────┬──────────┘
                │                     │
         ┌──────▼──────┐       ┌──────▼──────┐
         │ StormEvent  │       │   HubSkarb  │
         │    Bus      │◄──────│             │
         └─────────────┘       └─────────────┘
```

---

## ⚠️ Обработка ошибок

SDK использует типизированные ошибки `HubSDKError`:

```swift
do {
    try await adapty.purchase(with: product)
} catch let error as HubSDKError {
    switch error {
    case .notInitialized:
        print("SDK not ready")
    case .purchaseCancelled:
        print("User cancelled")
    case .purchaseFailed(let underlyingError):
        print("Purchase failed: \(underlyingError)")
    case .networkError:
        print("Check internet connection")
    default:
        print(error.localizedDescription)
    }
    
    // Удобные свойства
    if error.isRetryable {
        // Показать кнопку "Повторить"
    }
    
    if error.isUserFacing {
        showAlert(message: error.userFriendlyMessage)
    }
}
```

---

## 📋 Требования

- iOS 15.0+
- Swift 6.0+
- Xcode 16.0+

---

## 📄 Лицензия

MIT License. См. [LICENSE](LICENSE) для деталей.
