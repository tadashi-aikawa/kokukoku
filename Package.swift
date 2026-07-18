// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kokukoku",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Command Line Tools のみの環境には Swift Testing の内部モジュールが同梱されないため依存で供給
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "0.12.0"),
        // 設定ファイル(~/.kokukoku/config.toml)のパース用
        .package(url: "https://github.com/LebJe/TOMLKit.git", exact: "0.6.0"),
    ],
    targets: [
        // 純粋ロジック層(Foundation のみ。ユニットテストの主戦場)
        .target(
            name: "KokukokuCore",
            dependencies: ["TOMLKit"],
            path: "Sources/KokukokuCore"
        ),
        // 実行ターゲット(メニューバー常駐アプリ)
        .executableTarget(
            name: "Kokukoku",
            dependencies: ["KokukokuCore"],
            path: "Sources/Kokukoku",
            resources: [.copy("Resources/kokukoku.webp")]
        ),
        .testTarget(
            name: "KokukokuCoreTests",
            dependencies: [
                "KokukokuCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/KokukokuCoreTests"
        ),
    ]
)
