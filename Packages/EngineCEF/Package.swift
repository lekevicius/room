// swift-tools-version: 6.2
import PackageDescription

// CEF is not a package dependency: `scripts/bootstrap-cef.sh` downloads the
// pinned binary distribution and builds libcef_dll_wrapper into Engine/cef/dist.
// The framework itself is dlopen'ed at runtime (CefScopedLibraryLoader) and is
// copied into the app bundle by a build phase in project.yml.
let cefDist = Context.packageDirectory + "/../../Engine/cef/dist"
let cefRoot = cefDist + "/current"
let cefWrapperDir = cefDist + "/build/libcef_dll_wrapper"

// Must match how libcef_dll_wrapper was compiled (see bootstrap-cef.sh).
let cefCXXSettings: [CXXSetting] = [
    .define("CEF_API_VERSION", to: "15400"),
    .define("CEF_USE_SANDBOX"),
    .define("__STDC_CONSTANT_MACROS"),
    .define("__STDC_FORMAT_MACROS"),
    .unsafeFlags(["-I", cefRoot, "-fobjc-arc"]),
]
let cefLinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-L", cefWrapperDir, "-lcef_dll_wrapper"]),
    .linkedLibrary("c++"),
]

let package = Package(
    name: "EngineCEF",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EngineCEF", targets: ["EngineCEF"]),
        .library(name: "CEFHelper", targets: ["CEFHelper"]),
    ],
    dependencies: [.package(path: "../Engine")],
    targets: [
        .target(
            name: "CEFBridge",
            cxxSettings: cefCXXSettings,
            linkerSettings: cefLinkerSettings + [.linkedFramework("AppKit")]
        ),
        .target(
            name: "CEFHelper",
            cxxSettings: cefCXXSettings,
            linkerSettings: cefLinkerSettings
        ),
        .target(
            name: "EngineCEF",
            dependencies: ["CEFBridge", "Engine"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ],
    cxxLanguageStandard: .cxx20
)
