import Foundation

// This runner requires only Command Line Tools, not XCTest or a Steam install.
@main
struct LocalizationChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let en = Bundle(url: root.appendingPathComponent("en.lproj"))!
        let zh = Bundle(url: root.appendingPathComponent("zh-Hans.lproj"))!

        let english = try table(root, language: "en")
        let chinese = try table(root, language: "zh-Hans")
        precondition(Set(english.keys) == Set(chinese.keys), "Translation keys differ")
        for (key, value) in chinese {
            precondition(!value.isEmpty, "Empty translation: \(key)")
            precondition(placeholders(key) == placeholders(value), "Changed placeholders: \(key)")
        }
        print("PASS: \(english.count) matching English/Chinese keys and placeholder sets")

        precondition(L10n.text("Cancel", bundle: en) == "Cancel")
        precondition(L10n.text("Cancel", bundle: zh) == "取消")
        precondition(L10n.text("Missing English fallback", bundle: zh) == "Missing English fallback")
        precondition(L10n.format("Remove %1$@ and %2$@ DLC", "中文 100% %@", 2, bundle: en)
                     == "Remove 中文 100% %@ and 2 DLC")
        precondition(L10n.format("Remove %1$@ and %2$@ DLC", "中文 100% %@", 2, bundle: zh)
                     == "移除 中文 100% %@ 及其 2 个 DLC")
        precondition(L10n.format("%2$@ / %1$@", "first", "second", bundle: en) == "second / first")
        print("PASS: Language lookup, fallback, interpolation, and argument reordering")

        for count in [0, 1, 2, 10] {
            precondition(L10n.count("%ld depot keys", count, bundle: en)
                         == "\(count) depot key\(count == 1 ? "" : "s")")
            precondition(L10n.count("%ld depot keys", count, bundle: zh) == "\(count) 个内容库密钥")
            precondition(L10n.count("Imported %ld games", count, bundle: en)
                         == "Imported \(count) game\(count == 1 ? "" : "s")")
            precondition(L10n.count("Imported %ld games", count, bundle: zh) == "已导入 \(count) 个游戏")
        }
        print("PASS: English/Chinese plural rules for 0, 1, 2, and 10")

        var config = MacsteamConfig()
        config.apps = [100, 101]
        config.appNames = [100: "中文测试游戏", 101: "扩展内容"]
        config.appParents = [101: 100]
        config.hideWhatsNew = true
        config.packageIds = [200]
        config.upsertDepotKey(appID: 100, depotID: 102, key: "012345abcdef")
        let serialized = config.serialize()
        precondition(serialized.contains("Apps:"))
        precondition(serialized.contains("PackageIds:"))
        precondition(serialized.contains("DepotKeys:"))
        precondition(serialized.contains("HideWhatsNew: yes"))
        precondition(MacsteamConfig.parse(serialized) == config)
        print("PASS: Chinese names round-trip without localizing configuration keys")
    }

    static func table(_ root: URL, language: String) throws -> [String: String] {
        let url = root.appendingPathComponent("\(language).lproj/Localizable.strings")
        let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return value as! [String: String]
    }

    static func placeholders(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%\d+\$@"#)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }.sorted()
    }
}
