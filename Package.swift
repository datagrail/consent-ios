// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "DataGrailConsent",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "DataGrailConsent",
            targets: ["DataGrailConsent"]
        ),
    ],
    targets: [
        .target(
            name: "DataGrailConsent",
            dependencies: [],
            path: "Sources/DataGrailConsent"
        ),
        .testTarget(
            name: "DataGrailConsentTests",
            dependencies: ["DataGrailConsent"],
            path: "Tests/DataGrailConsentTests",
            resources: [
                .copy("Resources/test-config.json"),
                .copy("Resources/config-bys.json"),
            ]
        ),
    ]
)
