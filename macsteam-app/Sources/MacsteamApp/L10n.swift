import Foundation

/// Shared localization for SwiftPM executables and the native Xcode app target.
enum L10n {
    static let resources: Bundle = {
        #if SWIFT_PACKAGE
        // SwiftPM's generated accessor knows the build tree, but not the app's
        // Contents/Resources directory. Prefer the embedded, relocatable bundle.
        if let url = Bundle.main.resourceURL?
            .appendingPathComponent("MacsteamApp_MacsteamApp.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }()

    static func text(_ key: String, bundle: Bundle = resources) -> String {
        bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func locale(for bundle: Bundle = resources) -> Locale {
        let language = bundle.bundleURL.pathExtension == "lproj"
            ? bundle.bundleURL.deletingPathExtension().lastPathComponent
            : (bundle.preferredLocalizations.first ?? bundle.developmentLocalization ?? "en")
        return Locale(identifier: language)
    }

    /// Values are strings so translators can reorder indexed %@ placeholders.
    /// Runtime values (including filenames and error messages) never become keys.
    static func format(_ key: String, _ values: Any..., bundle: Bundle = resources) -> String {
        let arguments: [CVarArg] = values.map { String(describing: $0) }
        return String(format: text(key, bundle: bundle), arguments: arguments)
    }

    /// Let Apple's plural rules choose the English singular/plural or Chinese form.
    static func count(_ key: String, _ value: Int, bundle: Bundle = resources) -> String {
        // The app's chosen language can differ from the system locale.
        String(format: text(key, bundle: bundle), locale: locale(for: bundle), arguments: [value])
    }
}
