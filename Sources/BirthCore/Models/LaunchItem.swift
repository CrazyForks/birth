import Foundation

/// A single startup item, unified across launchd domains and BTM login items.
public struct LaunchItem: Identifiable, Hashable, Sendable {
    /// Where the item lives and which mechanism manages it.
    public enum Domain: String, CaseIterable, Codable, Sendable {
        /// `~/Library/LaunchAgents` — per-user agents, no privileges needed.
        case userAgent
        /// `/Library/LaunchAgents` — agents loaded into every user's session.
        case globalAgent
        /// `/Library/LaunchDaemons` — system daemons, root-owned.
        case globalDaemon
        /// Background Task Management login items (System Settings > Login Items).
        case loginItem

        /// Case order doubles as the presentation order (sidebar, 类型
        /// column sort): user things first, system things later.
        public var sortRank: Int {
            Self.allCases.firstIndex(of: self) ?? 0
        }
    }

    /// Whether the item is allowed to launch.
    public enum EnablementState: Hashable, Sendable {
        case enabled
        case disabled
        /// BTM items whose state we can read but not change.
        case managedBySystem(enabled: Bool)
        case unknown

        public var isEnabled: Bool? {
            switch self {
            case .enabled: true
            case .disabled: false
            case .managedBySystem(let enabled): enabled
            case .unknown: nil
            }
        }

        /// Sort weight for the 启用 column: on first, off second,
        /// unknown last — same effective-state grouping the filter uses.
        public var sortRank: Int {
            switch isEnabled {
            case true?: 0
            case false?: 1
            case nil: 2
            }
        }
    }

    public var id: String
    public var label: String
    public var displayName: String
    public var domain: Domain
    public var plistURL: URL?
    public var executablePath: String?
    public var enablement: EnablementState
    /// PID if the job is currently running, nil if not running or unknown.
    public var pid: Int?
    /// True when we positively know the job is loaded but idle (pid == nil).
    public var isLoaded: Bool
    /// True when the runtime query for the item's domain failed outright —
    /// "we don't know" as opposed to "known not loaded". Drives
    /// `RunState.unknown` so the UI never files ignorance under 未加载.
    public var runtimeUnknown: Bool
    public var runAtLoad: Bool
    public var keepAlive: Bool
    /// Human-readable schedule summary ("Every 3600s", "Calendar schedule"), if any.
    public var schedule: String?
    public var signature: SignatureInfo?
    /// BTM-only: item type description from the BTM database ("app", "login item"...).
    public var btmTypeDescription: String?

    /// The label claims Apple's namespace. A claim, not proof: any plist
    /// author can write a com.apple.* label, so this only stands in for
    /// "Apple" until a signature check confirms or disproves it.
    /// Static so call sites without a built item (the BTM bridge) share
    /// the one namespace definition instead of re-typing the prefix.
    public static func claimsAppleLabel(_ label: String) -> Bool {
        label.hasPrefix("com.apple.")
    }

    public var claimsAppleLabel: Bool {
        Self.claimsAppleLabel(label)
    }

    /// The label claims Apple but the verified signature says otherwise —
    /// the classic disguise for malicious launchd persistence. nil
    /// signature means "not verified yet", which is not an accusation.
    public func isMasquerading(signature: SignatureInfo?) -> Bool {
        guard let signature, claimsAppleLabel else { return false }
        return !signature.isVerifiedApple
    }

    /// BTM login items are macOS-managed: Birth can neither toggle nor
    /// remove them, only point at System Settings. Single source for
    /// every "offer removal?" decision in the UI.
    public var isUserRemovable: Bool {
        domain != .loginItem
    }

    /// Coarse runtime state, derived once from pid/isLoaded — the single
    /// classification behind the 状态 column, the detail pane's runtime
    /// suffix, and the run-state filter, so the three can never drift.
    /// BTM login items carry no launchd runtime state and always land in
    /// `notLoaded` — factually right: they are not launchd jobs.
    public enum RunState: Hashable, Sendable {
        case running(pid: Int)
        case loadedIdle
        case notLoaded
        /// The runtime query itself failed — not the same as notLoaded.
        case unknown

        /// Sort weight for the 状态 column: most alive first, ignorance last.
        public var sortRank: Int {
            switch self {
            case .running: 0
            case .loadedIdle: 1
            case .notLoaded: 2
            case .unknown: 3
            }
        }
    }

    public var runState: RunState {
        // Positive signals win: a pid is a pid even if some other part of
        // the query failed. `unknown` is reserved for "no signal at all,
        // and the query that would have produced one didn't run".
        if let pid { .running(pid: pid) }
        else if isLoaded { .loadedIdle }
        else if runtimeUnknown { .unknown }
        else { .notLoaded }
    }

    /// Sort key for the 开发者 column. Populated by two write-through
    /// points in the UI layer (snapshot landing + the streamed signature
    /// pass). The isVerifiedApple fallback is defense in depth: today
    /// every producer of a verified-Apple signature also sets
    /// developerName "Apple" (CodeSignInspector; the BTM bridge no
    /// longer pre-fills Apple verdicts at all), but any future producer
    /// that forgets the name must still land in the one "Apple" sort
    /// bucket. Unsigned / not-yet-verified items sort together under
    /// the empty string; the column may still DISPLAY a kind label
    /// ("未签名") for them.
    public var developerSortName: String {
        if let name = signature?.developerName { return name }
        if signature?.isVerifiedApple == true { return "Apple" }
        return ""
    }

    /// Sort key for the 类型 column: domain groups first, the BTM subtype
    /// breaks ties inside 登录项 — where every row's domain is .loginItem
    /// yet the cell shows App / 登录项 / 代理 / 守护进程. Raw English
    /// subtype keys cluster correctly even though the cell localizes them.
    public var kindSortKey: String {
        "\(domain.sortRank)|\(btmTypeDescription?.lowercased() ?? "")"
    }

    public init(
        id: String,
        label: String,
        displayName: String,
        domain: Domain,
        plistURL: URL? = nil,
        executablePath: String? = nil,
        enablement: EnablementState = .unknown,
        pid: Int? = nil,
        isLoaded: Bool = false,
        runtimeUnknown: Bool = false,
        runAtLoad: Bool = false,
        keepAlive: Bool = false,
        schedule: String? = nil,
        signature: SignatureInfo? = nil,
        btmTypeDescription: String? = nil
    ) {
        self.id = id
        self.label = label
        self.displayName = displayName
        self.domain = domain
        self.plistURL = plistURL
        self.executablePath = executablePath
        self.enablement = enablement
        self.pid = pid
        self.isLoaded = isLoaded
        self.runtimeUnknown = runtimeUnknown
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.schedule = schedule
        self.signature = signature
        self.btmTypeDescription = btmTypeDescription
    }
}

/// Code-signing identity of the item's executable.
public struct SignatureInfo: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case apple            // Chain anchored at Apple's root (Apple's own binaries)
        case appStore         // Apple-generic anchor, App Store leaf
        case developerID      // Apple-generic anchor, third-party developer leaf
        case adhoc            // Signed without an identity
        case untrusted        // Has certificates, but no Apple anchor (e.g. self-signed)
        case unsigned
        case invalid          // Signature exists but fails validation
    }

    public var kind: Kind
    /// e.g. "Docker Inc" from "Developer ID Application: Docker Inc (9BNSXJN65R)"
    public var developerName: String?
    public var teamID: String?
    /// The identifier baked into the signature (kSecCodeInfoIdentifier).
    /// Populated only for App Store–chain signatures, where Apple's
    /// re-signing pipeline derives it from the store-controlled bundle
    /// ID — so a com.apple.* value proves an Apple-published app.
    /// Deliberately nil for every other chain: a Developer ID or ad-hoc
    /// identifier is author-chosen and must never feed a trust decision.
    public var signingIdentifier: String?

    public init(
        kind: Kind,
        developerName: String? = nil,
        teamID: String? = nil,
        signingIdentifier: String? = nil
    ) {
        self.kind = kind
        self.developerName = developerName
        self.teamID = teamID
        self.signingIdentifier = signingIdentifier
    }

    /// The signature positively proves an Apple-published binary — the
    /// ONE definition consumed by the masquerade check, the inspector's
    /// developer-name choice, and the sort-key fallback, so the rule
    /// cannot drift between layers. Apple's own chain qualifies
    /// outright; the App Store chain qualifies only with a com.apple.*
    /// signing identifier (Apple ships Xcode, TestFlight… through store
    /// re-signing, which never satisfies `anchor apple`, but the
    /// store-controlled identifier namespace is closed to third
    /// parties). No identifier captured, no proof. Future kinds default
    /// to "not proof".
    public var isVerifiedApple: Bool {
        switch kind {
        case .apple: true
        case .appStore: signingIdentifier?.hasPrefix("com.apple.") == true
        default: false
        }
    }
}
