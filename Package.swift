// swift-tools-version: 6.0

import PackageDescription

let package = Package(
	name: "Background",
	platforms: [
		.macOS(.v11),
		.iOS(.v14),
		.tvOS(.v14),
		.watchOS(.v7),
		.macCatalyst(.v14),
	],
	products: [
		.library(name: "Background", targets: ["Background"]),
	],
	targets: [
		.target(name: "Background"),
		.testTarget(name: "BackgroundTests", dependencies: ["Background"]),
	]
)
