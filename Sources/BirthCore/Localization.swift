import Foundation

/// The strings bundle, resolved for BOTH deployment shapes — same
/// contract and same rationale as BirthUI's copy: SwiftPM's generated
/// `Bundle.module` never probes Contents/Resources (where make-app.sh
/// puts the bundle) and fatalErrors on a user's machine where its baked
/// `.build` path doesn't exist. Probe Contents/Resources first; fall
/// back to `.module` for `swift run` / `swift test`.
private let stringsBundle: Bundle = {
    if let url = Bundle.main.resourceURL?.appendingPathComponent("birth_BirthCore.bundle"),
       let bundle = Bundle(url: url) {
        return bundle
    }
    return .module
}()

/// Localized string lookup for BirthCore's user-facing error text, by
/// semantic key. zh-Hans is the source-of-truth table; en is pinned to
/// the same key set by a completeness test.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: stringsBundle, comment: "")
}

/// Formatted variant — table values carry classic %@/%lld specifiers.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
