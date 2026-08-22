// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SimctlBuddy",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "simbuddy", targets: ["SimctlBuddyCLI"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
  ],
  targets: [
    .target(name: "SimctlBuddyCore"),
    .executableTarget(
      name: "SimctlBuddyCLI",
      dependencies: [
        "SimctlBuddyCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(
      name: "SimctlBuddyCoreTests",
      dependencies: ["SimctlBuddyCore"]
    ),
  ]
)
