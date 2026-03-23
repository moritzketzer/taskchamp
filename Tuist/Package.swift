// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [
        "MarkdownUI": .staticFramework,
        "SoulverCore": .staticFramework
    ]
)
#endif

let package = Package(
    name: "taskchamp",
    dependencies: [
        // Add your own dependencies here:
        Package.Dependency.package(url: "https://github.com/soulverteam/SoulverCore", from: "2.6.3"),
        Package.Dependency.package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        Package.Dependency.package(
            name: "TaskchampionBridge",
            path: "../../bridge"
        )
    ]
)
