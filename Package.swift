// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TailGui",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TailGui",
            path: "Sources/TailGui"
        )
    ]
)
