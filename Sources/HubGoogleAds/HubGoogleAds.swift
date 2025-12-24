//
//  StormGoogleAds.swift
//  HubSDKCore
//
//  Created by Vadzim Ivanchanka on 12/17/25.
//

import Foundation
import GoogleMobileAds
import HubIntegrationCore
import HubSDKCore

public extension HubSDKCore {
    var googleAds: HubGoogleAdsProviding? {
        integration(ofType: HubGoogleAdsIntegration.self)?.provider
    }
}

public struct AdType: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let interstitial = AdType(rawValue: 1 << 0)
    public static let rewarded = AdType(rawValue: 1 << 1)
    public static let appOpen = AdType(rawValue: 1 << 2)
    
    public static let all: AdType = [.interstitial, .rewarded, .appOpen]
    public static let none: AdType = []
}

@MainActor
public protocol HubGoogleAdsProviding: Sendable {
    var isInterstitialReady: Bool { get }
    var isRewardedReady: Bool { get }
    var isAppOpenReady: Bool { get }
    
    func showInterstitial(from viewController: UIViewController?) async
    func showRewarded(from viewController: UIViewController?) async -> Bool
    func showAppOpen(from viewController: UIViewController?) async
    
    func showInterstitial(from viewController: UIViewController?, completion: (() -> Void)?)
    func showRewarded(from viewController: UIViewController?, completion: ((_ rewarded: Bool) -> Void)?)
    func showAppOpen(from viewController: UIViewController?, completion: (() -> Void)?)
    
    func createBanner(in viewController: UIViewController, size: AdSize) -> BannerView
}

// MARK: - Default Parameters

public extension HubGoogleAdsProviding {
    func showInterstitial(from viewController: UIViewController? = nil) async {
        await showInterstitial(from: viewController)
    }
    
    func showRewarded(from viewController: UIViewController? = nil) async -> Bool {
        await showRewarded(from: viewController)
    }
    
    func showAppOpen(from viewController: UIViewController? = nil) async {
        await showAppOpen(from: viewController)
    }
    
    // Callback с опциональным viewController (дефолт nil)
    func showInterstitial(from viewController: UIViewController? = nil, completion: (() -> Void)? = nil) {
        showInterstitial(from: viewController, completion: completion)
    }
    
    func showRewarded(from viewController: UIViewController? = nil, completion: ((_ rewarded: Bool) -> Void)? = nil) {
        showRewarded(from: viewController, completion: completion)
    }
    
    func showAppOpen(from viewController: UIViewController? = nil, completion: (() -> Void)? = nil) {
        showAppOpen(from: viewController, completion: completion)
    }
}

// MARK: - Configuration

public struct HubGoogleAdsConfiguration: Sendable {
    public let interstitialKey: String
    public let rewardedKey: String
    public let bannerKey: String
    public let appOpenKey: String
    public let maxRetryAttempts: Int
    public let awaitAdTypes: AdType
    public let awaitTimeout: TimeInterval
    public let debug: Bool
    
    public init(
        interstitialKey: String = "",
        rewardedKey: String = "",
        bannerKey: String = "",
        appOpenKey: String = "",
        maxRetryAttempts: Int = 2,
        awaitAdTypes: AdType = .none,
        awaitTimeout: TimeInterval = 10,
        debug: Bool = false
    ) {
        if debug {
            self.interstitialKey = "ca-app-pub-3940256099942544/1033173712"
            self.rewardedKey = "ca-app-pub-3940256099942544/5224354917"
            self.bannerKey = "ca-app-pub-3940256099942544/2934735716"
            self.appOpenKey = "ca-app-pub-3940256099942544/9257395921"
        } else {
            self.interstitialKey = interstitialKey
            self.rewardedKey = rewardedKey
            self.bannerKey = bannerKey
            self.appOpenKey = appOpenKey
        }
        self.maxRetryAttempts = maxRetryAttempts
        self.awaitAdTypes = awaitAdTypes
        self.awaitTimeout = awaitTimeout
        self.debug = debug
    }
}

// MARK: - Integration

public final class HubGoogleAdsIntegration: HubDependencyIntegration, AwaitableIntegration {
    public static var name: String { "GoogleAds" }
    
    public var provider: HubGoogleAdsProviding { googleAds }
    
    public private(set) var isReady: Bool = false
    public var onReady: (() -> Void)?
    
    private let googleAds: HubGoogleAds
    private let config: HubGoogleAdsConfiguration
    
    public init(config: HubGoogleAdsConfiguration) {
        self.config = config
        self.googleAds = HubGoogleAds(config: config)
    }
    
    public func start() {
        googleAds.start { [weak self] in
            guard let self else { return }
            
            if self.config.awaitAdTypes == .none {
                self.markAsReady()
            } else {
                Task { @MainActor in
                    await self.googleAds.waitUntilReady(
                        self.config.awaitAdTypes,
                        timeout: self.config.awaitTimeout
                    )
                    self.markAsReady()
                }
            }
        }
    }
    
    private func markAsReady() {
        guard !isReady else { return }
        isReady = true
        onReady?()
    }
}

// MARK: - Implementation

@MainActor
internal final class HubGoogleAds: NSObject, HubGoogleAdsProviding {
    
    // MARK: - Properties
    
    private let config: HubGoogleAdsConfiguration
    
    private var interstitialAd: InterstitialAd?
    private var rewardedAd: RewardedAd?
    private var appOpenAd: AppOpenAd?
    private var appOpenLoadTime: Date?
    
    private var retryCount: [AdType: Int] = [:]
    private var presentationContinuation: CheckedContinuation<Bool, Never>?
    
    // MARK: - Wait State
    
    private var awaitedTypes: AdType = .none
    private var readyTypes: AdType = .none
    private var waitContinuation: CheckedContinuation<Void, Never>?
    
    // MARK: - Init
    
    init(config: HubGoogleAdsConfiguration) {
        self.config = config
        super.init()
    }
    
    // MARK: - Start
    
    func start(completion: @escaping () -> Void) {
        MobileAds.shared.start { [weak self] _ in
            guard let self else { return }
            self.loadInterstitial()
            self.loadRewarded()
            self.loadAppOpen()
            completion()
        }
    }
    
    // MARK: - Ready State
    
    var isInterstitialReady: Bool { interstitialAd != nil }
    var isRewardedReady: Bool { rewardedAd != nil }
    
    var isAppOpenReady: Bool {
        guard let loadTime = appOpenLoadTime, appOpenAd != nil else { return false }
        return Date().timeIntervalSince(loadTime) < 4 * 3600
    }
    
    // MARK: - Wait Until Ready
    
    func waitUntilReady(_ types: AdType, timeout: TimeInterval) async {
        var effectiveTypes: AdType = []
        if types.contains(.interstitial) && !config.interstitialKey.isEmpty {
            effectiveTypes.insert(.interstitial)
        }
        if types.contains(.rewarded) && !config.rewardedKey.isEmpty {
            effectiveTypes.insert(.rewarded)
        }
        if types.contains(.appOpen) && !config.appOpenKey.isEmpty {
            effectiveTypes.insert(.appOpen)
        }
        
        guard !effectiveTypes.isEmpty else { return }
        
        if isTypesReady(effectiveTypes) { return }
        
        awaitedTypes = effectiveTypes
        
        await withCheckedContinuation { continuation in
            waitContinuation = continuation
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                completeWait()
            }
        }
    }
    
    private func isTypesReady(_ types: AdType) -> Bool {
        var ready = true
        if types.contains(.interstitial) { ready = ready && isInterstitialReady }
        if types.contains(.rewarded) { ready = ready && isRewardedReady }
        if types.contains(.appOpen) { ready = ready && isAppOpenReady }
        return ready
    }
    
    private func markTypeReady(_ type: AdType) {
        readyTypes.insert(type)
        checkWaitCompletion()
    }
    
    private func checkWaitCompletion() {
        guard !awaitedTypes.isEmpty else { return }
        if awaitedTypes.isSubset(of: readyTypes) {
            completeWait()
        }
    }
    
    private func completeWait() {
        waitContinuation?.resume()
        waitContinuation = nil
        awaitedTypes = .none
    }
    
    // MARK: - Show Ads
    
    func showInterstitial(from viewController: UIViewController?) async {
        guard let ad = interstitialAd else {
            loadInterstitial()
            return
        }
        
        guard let vc = viewController ?? rootViewController else { return }
        
        _ = await withCheckedContinuation { continuation in
            self.presentationContinuation = continuation
            ad.present(from: vc)
        }
    }
    
    func showRewarded(from viewController: UIViewController?) async -> Bool {
        guard let ad = rewardedAd else {
            loadRewarded()
            return false
        }
        
        guard let vc = viewController ?? rootViewController else { return false }
        
        var rewarded = false
        
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.presentationContinuation = continuation
            ad.present(from: vc) {
                rewarded = true
            }
        }
        
        return rewarded
    }
    
    func showAppOpen(from viewController: UIViewController?) async {
        guard isAppOpenReady, let ad = appOpenAd else { return }
        guard let vc = viewController ?? rootViewController else { return }
        
        _ = await withCheckedContinuation { continuation in
            self.presentationContinuation = continuation
            ad.present(from: vc)
        }
    }
    
    // MARK: - Callback API
    
    func showInterstitial(from viewController: UIViewController?, completion: (() -> Void)?) {
        Task {
            await showInterstitial(from: viewController)
            completion?()
        }
    }
    
    func showRewarded(from viewController: UIViewController?, completion: ((_ rewarded: Bool) -> Void)?) {
        Task {
            let rewarded = await showRewarded(from: viewController)
            completion?(rewarded)
        }
    }
    
    func showAppOpen(from viewController: UIViewController?, completion: (() -> Void)?) {
        Task {
            await showAppOpen(from: viewController)
            completion?()
        }
    }
    
    // MARK: - Banner
    
    func createBanner(in viewController: UIViewController, size: AdSize = AdSizeBanner) -> BannerView {
        let banner = BannerView(adSize: size)
        banner.adUnitID = config.bannerKey
        banner.rootViewController = viewController
        banner.load(Request())
        return banner
    }
    
    // MARK: - Root ViewController
    
    private var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

// MARK: - Loading

private extension HubGoogleAds {
    
    func loadInterstitial() {
        guard !config.interstitialKey.isEmpty else { return }
        
        InterstitialAd.load(with: config.interstitialKey, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            
            if let error {
                print("[HubGoogleAds] Interstitial load failed: \(error.localizedDescription)")
                self.retry(.interstitial) { self.loadInterstitial() }
                return
            }
            
            self.resetRetry(.interstitial)
            self.interstitialAd = ad
            self.interstitialAd?.fullScreenContentDelegate = self
            self.markTypeReady(.interstitial)
        }
    }
    
    func loadRewarded() {
        guard !config.rewardedKey.isEmpty else { return }
        
        RewardedAd.load(with: config.rewardedKey, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            
            if let error {
                print("[HubGoogleAds] Rewarded load failed: \(error.localizedDescription)")
                self.retry(.rewarded) { self.loadRewarded() }
                return
            }
            
            self.resetRetry(.rewarded)
            self.rewardedAd = ad
            self.rewardedAd?.fullScreenContentDelegate = self
            self.markTypeReady(.rewarded)
        }
    }
    
    func loadAppOpen() {
        guard !config.appOpenKey.isEmpty else { return }
        
        AppOpenAd.load(with: config.appOpenKey, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            
            if let error {
                print("[HubGoogleAds] App Open load failed: \(error.localizedDescription)")
                self.retry(.appOpen) { self.loadAppOpen() }
                return
            }
            
            self.resetRetry(.appOpen)
            self.appOpenAd = ad
            self.appOpenAd?.fullScreenContentDelegate = self
            self.appOpenLoadTime = Date()
            self.markTypeReady(.appOpen)
        }
    }
}

// MARK: - Retry

private extension HubGoogleAds {
    
    func retry(_ type: AdType, action: @escaping () -> Void) {
        let count = retryCount[type, default: 0]
        
        guard count < config.maxRetryAttempts else {
            print("[HubGoogleAds] \(type) max retry attempts reached")
            return
        }
        
        retryCount[type] = count + 1
        let delay = min(pow(2.0, Double(count)), 30)
        
        print("[HubGoogleAds] \(type) retry \(count + 1)/\(config.maxRetryAttempts) in \(delay)s")
        
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            action()
        }
    }
    
    func resetRetry(_ type: AdType) {
        retryCount[type] = 0
    }
}

// MARK: - FullScreenContentDelegate

extension HubGoogleAds: FullScreenContentDelegate {
    
    public func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        presentationContinuation?.resume(returning: true)
        presentationContinuation = nil
        
        switch ad {
        case is InterstitialAd:
            interstitialAd = nil
            readyTypes.remove(.interstitial)
            resetRetry(.interstitial)
            loadInterstitial()
            
        case is RewardedAd:
            rewardedAd = nil
            readyTypes.remove(.rewarded)
            resetRetry(.rewarded)
            loadRewarded()
            
        case is AppOpenAd:
            appOpenAd = nil
            readyTypes.remove(.appOpen)
            resetRetry(.appOpen)
            
        default:
            break
        }
    }
    
    public func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("[HubGoogleAds] Failed to present: \(error.localizedDescription)")
        
        presentationContinuation?.resume(returning: false)
        presentationContinuation = nil
        
        switch ad {
        case is InterstitialAd: loadInterstitial()
        case is RewardedAd: loadRewarded()
        default: break
        }
    }
}
