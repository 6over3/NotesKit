// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "NotesKit",
  platforms: [
    .macOS(.v13),
    .iOS(.v16),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "NotesKit",
      targets: ["NotesKit"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.32.0"),
    .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.4"),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "NotesKit",
      dependencies: [
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .product(name: "SQLite", package: "SQLite.swift"),
      ]
    ),
    .testTarget(
      name: "NotesKitTests",
      dependencies: ["NotesKit"]
    ),
  ]
)
