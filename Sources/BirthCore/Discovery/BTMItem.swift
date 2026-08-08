import Foundation

/// One record from the Background Task Management database
/// (what System Settings > General > Login Items shows).
public struct BTMItem: Hashable, Sendable {
    public var uuid: String
    public var name: String?
    public var developerName: String?
    public var teamIdentifier: String?
    /// Normalized to one of the modern item kinds Birth displays.
    public var typeDescription: String
    public var isEnabled: Bool?
    public var identifier: String?
    public var urlString: String?
    public var executablePath: String?
    public var bundleIdentifier: String?
    public var parentIdentifier: String?
    public var embeddedItemIdentifiers: [String] = []
}

extension LaunchItem {
    /// Bridge a BTM record into the unified item model.
    public init(btmItem: BTMItem) {
        let name = btmItem.name
            ?? btmItem.bundleIdentifier
            ?? btmItem.identifier
            ?? btmItem.uuid
        let label = btmItem.bundleIdentifier ?? btmItem.identifier ?? name

        var executable = btmItem.executablePath
        if executable == nil,
           let urlString = btmItem.urlString,
           let url = URL(string: urlString), url.isFileURL {
            executable = url.path
        }

        // BTM records carry the developer identity directly; trust it
        // for display instead of re-verifying the binary — but never for
        // a com.apple.* label, where identity is precisely what the
        // masquerade check must adjudicate from the real binary. A
        // pre-filled verdict is permanent (the signature pipeline's
        // `== nil` guards never re-check one), and both directions burn:
        // .developerID brands Apple's own App Store apps (Xcode…)
        // masqueraders, while trusting the label as .apple would let any
        // bundle that names itself com.apple.* hide among system items.
        // Items with no executable path stay unverified — which the UI
        // treats as "no accusation", not as proof of anything.
        var signature: SignatureInfo?
        if let team = btmItem.teamIdentifier, !LaunchItem.claimsAppleLabel(label) {
            signature = SignatureInfo(
                kind: .developerID,
                developerName: btmItem.developerName,
                teamID: team
            )
        }

        self.init(
            id: "btm:\(btmItem.uuid)",
            label: label,
            displayName: name,
            domain: .loginItem,
            plistURL: nil,
            executablePath: executable,
            enablement: .managedBySystem(enabled: btmItem.isEnabled ?? true),
            signature: signature,
            btmTypeDescription: btmItem.typeDescription
        )
    }
}
