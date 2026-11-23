// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "StudyCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "StudyCore",
            targets: ["StudyCore"]
        )
    ],
    targets: [
        .target(
            name: "StudyCore",
            dependencies: []
        ),
        .testTarget(
            name: "StudyCoreTests",
            dependencies: ["StudyCore"]
        )
    ]
)
