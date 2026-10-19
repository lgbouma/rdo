// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PhoneList",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PhoneListCore", targets: ["PhoneListCore"]),
        .library(name: "PhoneListUI", targets: ["PhoneListUI"]),
    ],
    targets: [
        // Pure-Swift model, parser, rewrap, three-way merge, Dropbox client.
        // No UI imports; tested with `swift test` on macOS.
        .target(name: "PhoneListCore"),
        // SwiftUI views and the observable store. Compiles on macOS so that
        // `swift build` type-checks it without Xcode; iOS-only API is guarded.
        .target(name: "PhoneListUI", dependencies: ["PhoneListCore"]),
        .testTarget(name: "PhoneListCoreTests", dependencies: ["PhoneListCore"]),
    ],
    swiftLanguageModes: [.v5]
)
