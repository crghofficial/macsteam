import Foundation

#if SWIFT_PACKAGE
// A packaged app must find its embedded bundle even when the original build
// tree no longer exists. Fail rather than silently using a developer path.
extension Bundle {
    static var module: Bundle { fatalError("Unexpected SwiftPM build-tree fallback") }
}
#endif

@main
struct LocalizationBundleCheck {
    static func main() {
        let language = CommandLine.arguments.last!
        let resources = L10n.resources.bundleURL.resolvingSymlinksInPath().path
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        precondition(resources.hasPrefix(app), "Resources escaped app: \(resources), app: \(app)")
        precondition(L10n.text("Cancel") == (language == "en" ? "Cancel" : "取消"))
        precondition(L10n.count("Imported %ld games", 1)
                     == (language == "en" ? "Imported 1 game" : "已导入 1 个游戏"))
        print("PASS: Relocatable app resources and per-app language (\(language))")
    }
}
