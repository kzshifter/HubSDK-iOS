# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HubSDK is a modular Swift SDK for iOS that unifies analytics, advertising, and monetization services under a single API. Documentation and comments are in a mix of Russian and English.

- **Language:** Swift 6.0 (strict concurrency)
- **Platform:** iOS 15.0+
- **Distribution:** Swift Package Manager only (no CocoaPods/Carthage)
- **Adapty fork:** Uses a custom fork `superteamstrm/AdaptySDK-iOS` (forked from official `adaptyteam/AdaptySDK-iOS` 3.15.7+, StoreKit 2)

## Build & Test Commands

```bash
# Build (iOS SDK required — plain `swift build` fails for iOS-only targets)
xcodebuild build -scheme HubSDKCore -destination 'generic/platform=iOS'

# Resolve dependencies (first time or after Package.swift changes)
swift package resolve

# Run all tests
swift test

# Run a single test target
swift test --filter HubEventBusTests
swift test --filter HubSDKCoreTests
```

Test targets: `HubIntegrationCoreTests`, `HubSDKCoreTests`. No linting configured.

## Architecture

### Module Dependency Graph

```
HubIntegrationCore  (foundation — Event Bus + protocols, no external deps)
    ├── HubSDKCore          (registration engine, depends on HubIntegrationCore)
    ├── HubFacebook         (Facebook SDK)
    ├── HubFirebase         (Firebase Analytics)
    └── HubAnalytics        (universal event tracker via Firebase)

HubSDKCore + HubIntegrationCore
    ├── HubSDKAdapty        (subscriptions, paywalls, onboarding via Adapty)
    ├── HubGoogleAds        (interstitial, rewarded, banner, app-open ads)
    ├── HubAppsflyer        (install attribution)
    └── HubSkarb            (Skarb analytics)
```

### Core Patterns

**Integration registration (`HubSDKCore`):** Singleton `HubSDKCore.shared` acts as a registry. Integrations are registered via `register(_:awaitReady:)`, then started together with `run(with:)`. Access a registered integration's provider via `integration(ofType:)` or typed convenience properties (e.g., `.adapty`, `.googleAds`) defined in extension files like `HubSDKCore+Provider.swift`.

**`HubDependencyIntegration` protocol** (`HubIntegrationCore/StormIntegration.swift`): Every integration module conforms to this. It requires an associated `Provider` type, a static `name`, and a `start()` method. The provider protocol (e.g., `HubSDKAdaptyProviding`, `HubGoogleAdsProviding`) defines the public API that consumers use.

**`AwaitableIntegration` protocol:** Integrations that need async initialization (Adapty, GoogleAds, Appsflyer, Skarb) also conform to this. They expose `isReady` and `onReady` callback. `HubSDKCore.waitUntilReady()` suspends until all awaited integrations signal readiness (or timeout).

**Event Bus (`HubIntegrationCore/EventBus/`):** `HubEventBus.shared` enables decoupled inter-module communication. Modules publish `HubEvent` cases (`.conversionDataReceived`, `.successPurchase`, `.event`) and any `HubEventListener` subscriber receives them. Uses `NSHashTable.weakObjects()` for automatic cleanup, `NSLock` for thread safety.

**Event flow:** AppsFlyer → `.conversionDataReceived` → Skarb listens. Adapty/PaywallCoordinator → `.successPurchase` → Facebook, Firebase listen. HubAnalytics → `.event` → Facebook, Firebase listen.

### HubSDKAdapty Internals

The most complex module. Key architectural details:

- **Internal `actor HubSDKAdapty`** with a state machine: `.notInitialized` → `.initializing(Task)` → `.ready(config, placementBag)` / `.failed(Error)`. Prevents duplicate initialization.
- **`PlacementBag`:** Thread-safe (`NSLock`, `@unchecked Sendable`) lazy-loading container for placements. Supports sync access (`entry()`, `isLoaded()`) and async loading (`load()`, `loadIfNeeded()`).
- **`cachedSnapshot`:** `nonisolated(unsafe)` `StateSnapshot` for fast synchronous reads from `@MainActor` context without awaiting the actor.
- **`HubPaywallCoordinator`:** Static `resolve()` for DI setup (called once), then `show()` creates isolated instances per presentation. Self-retains via `retainedSelf` while presented, auto-releases on dismiss. Supports both Adapty Builder paywalls and local (custom UI) paywalls via `HubLocalPaywallProvider`.
- **`HubSDKError`:** Structured error enum with code ranges (100s: init, 200s: config/fallback, 300s: placement, 400s: purchase, 500s: restore, 600s: network, 700s: profile, 900s: paywall, 1000s: onboarding). Implements `LocalizedError` with `isRetryable`, `isUserFacing`, `userFriendlyMessage`.
- **Legacy naming:** The Adapty config struct is `StormSDKAdaptyConfiguration` (not `Hub*`), reflecting the project's original name.

### Concurrency Model

All integration protocols and `HubSDKCore` are `@MainActor`-isolated. Public APIs provide both `async` and completion-handler variants. `CheckedContinuation` is used throughout for bridging callback-based SDK APIs to async/await. `NSLock` is used for synchronous thread-safe access in `PlacementBag`, `HubEventBus`, and `HubAppsflyer`.
