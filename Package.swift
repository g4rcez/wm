// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "wm",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "wm", targets: ["Cli"]),
        .executable(name: "wmd", targets: ["App"]),
    ],
    targets: [
        // Vendored Lua 5.4.9 (MIT). Library sources only: lua.c and luac.c are left out.
        .target(name: "CLua", cSettings: [.define("LUA_USE_MACOSX")]),
        .target(name: "Common"),
        .target(name: "Core"),
        .target(name: "PrivateApi"),
        .target(name: "Platform", dependencies: ["Core", "PrivateApi"]),
        .target(name: "Scripting", dependencies: ["CLua", "Common", "Core"]),
        .target(name: "Cheatsheet", dependencies: ["Common", "Scripting"]),
        .executableTarget(name: "App", dependencies: ["Cheatsheet", "Common", "Core", "Platform", "Scripting"]),
        .executableTarget(name: "Cli", dependencies: ["Cheatsheet", "Common", "Scripting"]),
        .testTarget(name: "CheatsheetTests", dependencies: ["Cheatsheet", "Scripting"]),
        .testTarget(name: "CommonTests", dependencies: ["Common"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ScriptingTests", dependencies: ["Scripting", "Core", "Common"]),
    ]
)

// A compiler warning is an error, in the sources and in the tests. Vendored Lua is not ours to change.
for target in package.targets where target.name != "CLua" {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
    target.cSettings = (target.cSettings ?? []) + [.treatAllWarnings(as: .error)]
}
