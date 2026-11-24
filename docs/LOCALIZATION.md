# Localization

macSteam Config supports English (the development language) and Simplified
Chinese (`zh-Hans`). macOS selects a supported language using the user's
preferred language list or the per-app language setting in System Settings.
The application's identity, release version, and Sparkle update feed are unchanged.

## Resources and formatting

Translations live in `macsteam-app/Sources/MacsteamApp/Resources/<language>.lproj`:

- `Localizable.strings`: complete user-facing messages. The English text is
  also the fallback key; new, untranslated messages remain readable in English.
- `Localizable.stringsdict`: English singular/plural and Chinese count messages.
- `InfoPlist.strings`: localized Finder/application display names.

Use `L10n.text("English message")` for fixed text and
`L10n.format("Message for %1$@", value)` for interpolated values.
Indexed `%1$@`, `%2$@`, … placeholders may be reordered in translations.
Keep their indexes and number of occurrences unchanged. The formatting helper
converts values to strings; filenames and error details are not used as lookup
keys and are not interpreted as format strings.

Use `L10n.count("%ld depot keys", count)` and a `.stringsdict` entry when the
English message changes with its count. Do not build plural messages by adding
an English `"s"` suffix.

Do not translate selectors, symbol names, URL/protocol fields, configuration
keys, Lua syntax, or filesystem paths. External diagnostic output and names
supplied by files or Steam remain verbatim.

## Build integration

SwiftPM processes the resources and declares English as the default language.
`make_app.sh` embeds the generated resource bundle under `Contents/Resources`;
`L10n` finds this embedded bundle before falling back to SwiftPM's build-tree
accessor, so a copied application does not depend on the developer's checkout.
The display-name localizations are also copied into the main app bundle.

The checked-in Xcode project contains localized variant groups and the new
source file. `project.yml` discovers these resources under the existing source
directory and advertises both supported languages.

## Validation

```bash
bash scripts/test_localization.sh
swift build --package-path macsteam-app -c release
```

The first command runs without XCTest or a Steam installation and checks key
coverage, formatting, English fallback, plural rules, and Chinese configuration
round-trips. Build and package with the existing `make` / `make_app.sh` workflow.
Check both English and Simplified Chinese in macOS's per-app language settings,
including after moving the `.app` outside the build folder.

Localization does not change the Steam integration, updater configuration,
supported platforms, license, app icon, or release numbering.
