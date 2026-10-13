// swift-tools-version:5.9
//
// Unit tests for the app's Core logic (Feather/Backend/Core): pure Swift with no app dependencies,
// compiled here exactly as the app compiles it. Sources/AccretionCore is filled by run.sh with
// copies of those files (it's git-ignored), so the tests always check the app's own code.
//
//   CoreTests/run.sh        (macOS with Xcode or a Swift toolchain)

import PackageDescription

let package = Package(
	name: "CoreTests",
	platforms: [.macOS(.v13)],
	targets: [
		.target(name: "AccretionCore", path: "Sources/AccretionCore"),
		.testTarget(name: "AccretionCoreTests", dependencies: ["AccretionCore"], path: "Tests/AccretionCoreTests"),
	]
)
