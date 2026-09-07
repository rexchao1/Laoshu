// swift-tools-version: 6.2
import PackageDescription

// Every rule Laoshu has lives in this package: the word catalogue, the review
// log, and the session engine. It imports no UIKit and no SwiftUI, so it builds
// and tests with `swift test` on any Mac, with or without Xcode. The app target
// is a thin shell over it.
let package = Package(
    name: "LaoshuKit",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "LaoshuKit", targets: ["LaoshuKit"]),
        .executable(name: "laoshu-build-db", targets: ["laoshu-build-db"]),
    ],
    targets: [
        .target(name: "LaoshuKit"),
        .executableTarget(
            name: "laoshu-build-db",
            dependencies: ["LaoshuKit"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "LaoshuKitTests", dependencies: ["LaoshuKit"]),
    ]
)
