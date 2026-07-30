import Foundation

/// The strings bundle, resolved for BOTH deployment shapes. SwiftPM's
/// generated `Bundle.module` probes only (a) the app-bundle ROOT and
/// (b) an absolute `.build/...` path baked into the binary at compile
/// time — NEITHER exists on a user's machine once make-app.sh places
/// the bundle in Contents/Resources (the codesign-safe location), and
/// `.module` fatalErrors when its probes miss: the app would launch on
/// the build machine (via the baked path) and crash everywhere else.
/// So probe Contents/Resources ourselves first; fall back to `.module`
/// for `swift run` / `swift test`, where it resolves correctly.
private let stringsBundle: Bundle = {
    if let url = Bundle.main.resourceURL?.appendingPathComponent("birth_BirthUI.bundle"),
       let bundle = Bundle(url: url) {
        return bundle
    }
    return .module
}()

/// Localized string lookup against THIS target's resource bundle, by
/// semantic key ("advanced.empty.noMatch"). SwiftUI's implicit `Text`
/// lookup only searches Bundle.main, which never contains an SPM
/// library's strings — every user-visible string in BirthUI goes through
/// `L()` instead. zh-Hans is the source-of-truth table; a completeness
/// test pins the en table to the same key set so neither can drift.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: stringsBundle, comment: "")
}

/// Formatted variant — the table value carries classic %@/%lld
/// specifiers (positional %1$@ where the languages reorder arguments).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

/// BirthUI's strings bundle by name — tests can't say `Bundle.module`:
/// under @testable import of BOTH targets the two generated accessors
/// are ambiguous.
var uiStringsBundle: Bundle { stringsBundle }
