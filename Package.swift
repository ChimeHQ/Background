// swift-tools-version: 5.8

import PackageDescription

let package = Package(
	name: "Background",
	platforms: [
		.macOS(.v11),
		.iOS(.v13),
		.tvOS(.v13),
		.watchOS(.v6),
		.macCatalyst(.v13),
	],
	products: [
		.library(name: "Background", targets: ["Background"]),
	],
	targets: [
		.target(name: "Background"),
		.testTarget(name: "BackgroundTests", dependencies: ["Background"]),
	]
)

let swiftSettings: [SwiftSetting] = [
	.enableExperimentalFeature("StrictConcurrency")
]

for target in package.targets {
	var settings = target.swiftSettings ?? []
	settings.append(contentsOf: swiftSettings)
	target.swiftSettings = settings
}
