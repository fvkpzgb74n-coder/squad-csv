// swift-tools-version: 5.9

// This package is a Swift Playgrounds app: open Lineup.swiftpm in Swift Playgrounds
// on iPad or Mac (or in Xcode) to run it. SquadCSV.xcodeproj builds the same sources.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Lineup",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Lineup",
            targets: ["AppModule"],
            bundleIdentifier: "com.example.SquadCSV",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .asset("AccentColor"),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources"
        )
    ]
)
