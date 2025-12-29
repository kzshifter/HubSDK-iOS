// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HubSDKCore",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "HubSDKCore", targets: ["HubSDKCore"]),
        .library(name: "HubAppsflyer", targets: ["HubAppsflyer"]),
        .library(name: "HubSkarb", targets: ["HubSkarb"]),
        .library(name: "HubSDKAdapty", targets: ["HubSDKAdapty"]),
        .library(name: "HubGoogleAds", targets: ["HubGoogleAds"]),
        .library(name: "HubFacebook", targets: ["HubFacebook"]),
        .library(name: "HubFirebase", targets: ["HubFirebase"]),
        .library(name: "HubAnalytics", targets: ["HubAnalytics"]),
        .library(name: "HubIntegrationCore", targets: ["HubIntegrationCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/gixdev/AdaptySDK-SK1", branch: "master"),
        .package(url: "https://github.com/bitlica/SkarbSDK-iOS", branch: "master"),
        .package(url: "https://github.com/AppsFlyerSDK/AppsFlyerFramework", from: "6.15.0"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", from: "12.14.0"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", from: "18.0.1"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.4.0")
    ],
    targets: [
        .target(
            name: "HubSDKCore",
            dependencies: [
                .target(name: "HubIntegrationCore")
            ]),
        
            .target(
                name: "HubAppsflyer",
                dependencies: [
                    .product(name: "AppsFlyerLib", package: "AppsFlyerFramework"),
                    .target(name: "HubIntegrationCore"),
                    .target(name: "HubSDKCore")
                ]
            ),
        
            .target(
                name: "HubSDKAdapty",
                dependencies: [
                    .product(name: "Adapty", package: "AdaptySDK-SK1"),
                    .product(name: "AdaptyUI", package: "AdaptySDK-SK1"),
                    .target(name: "HubIntegrationCore"),
                    .target(name: "HubSDKCore")
                ]
            ),
        
            .target(
                name: "HubSkarb",
                dependencies: [
                    .product(name: "SkarbSDK", package: "SkarbSDK-iOS"),
                    .target(name: "HubIntegrationCore"),
                    .target(name: "HubSDKCore")
                ]
            ),
        
            .target(
                name: "HubGoogleAds",
                dependencies: [
                    .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                    .target(name: "HubIntegrationCore"),
                    .target(name: "HubSDKCore")
                ]
            ),
        
            .target(
                name: "HubFacebook",
                dependencies: [
                    .product(name: "FacebookCore", package: "facebook-ios-sdk"),
                    .target(name: "HubIntegrationCore")
                ]
            ),
        
            .target(
                name: "HubFirebase",
                dependencies: [
                    .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                    .target(name: "HubIntegrationCore")
                ]
            ),
        
            .target(
                name: "HubAnalytics",
                dependencies: [
                    .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                    .target(name: "HubIntegrationCore")
                ]
            ),
        
            .target(name: "HubIntegrationCore")
    ]
)
