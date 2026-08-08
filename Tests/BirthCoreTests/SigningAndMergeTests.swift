import Foundation
import Testing
@testable import BirthCore

@Suite("Signature summary parsing")
struct SigningTests {
    @Test func extractsDeveloperIDName() {
        #expect(CodeSignInspector.developerName(from: "Developer ID Application: Docker Inc (9BNSXJN65R)") == "Docker Inc")
        #expect(CodeSignInspector.developerName(from: "Apple Development: dev@example.com (ABC123)") == "dev@example.com")
        #expect(CodeSignInspector.developerName(from: "Some Plain Name") == "Some Plain Name")
        #expect(CodeSignInspector.developerName(from: nil) == nil)
    }

    @Test func inspectsRealAppleBinary() {
        // /bin/ls ships with macOS and is always Apple-signed — a stable
        // integration point for the Security-framework path.
        let signature = CodeSignInspector.inspect(path: "/bin/ls")
        #expect(signature?.kind == .apple)
    }

    @Test func inspectsAppleStoreDistributedApp() throws {
        // Xcode is Apple's own app on the App Store signing chain — the
        // exact shape the masquerade exemption exists for. Sentinel only
        // on machines that have it; quietly passes elsewhere.
        let path = "/Applications/Xcode.app"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let signature = try #require(CodeSignInspector.inspect(path: path))
        #expect(signature.kind == .appStore)
        #expect(signature.signingIdentifier?.hasPrefix("com.apple.") == true)
        #expect(signature.developerName == "Apple")
    }

    @Test func missingPathReturnsNil() {
        #expect(CodeSignInspector.inspect(path: "/nonexistent/binary") == nil)
    }
}

@Suite("Snapshot merge logic")
struct MergeTests {
    let service = StartupItemService()

    func makeItem(_ enablement: LaunchItem.EnablementState = .unknown) -> LaunchItem {
        LaunchItem(
            id: "/tmp/test.plist",
            label: "com.example.test",
            displayName: "test",
            domain: .userAgent,
            enablement: enablement
        )
    }

    @Test func overrideBeatsPlistState() {
        let merged = service.merge(
            item: makeItem(.disabled),
            overrides: ["com.example.test": false],
            runtime: [:]
        )
        #expect(merged.enablement == .enabled)
    }

    @Test func plistDisabledHoldsWithoutOverride() {
        let merged = service.merge(item: makeItem(.disabled), overrides: [:], runtime: [:])
        #expect(merged.enablement == .disabled)
    }

    @Test func defaultsToEnabledWhenNothingSaysOtherwise() {
        let merged = service.merge(item: makeItem(.unknown), overrides: [:], runtime: [:])
        #expect(merged.enablement == .enabled)
    }

    @Test func runtimeFillsPIDAndLoadedFlag() {
        let merged = service.merge(
            item: makeItem(),
            overrides: [:],
            runtime: ["com.example.test": JobRuntime(pid: 4242)]
        )
        #expect(merged.isLoaded)
        #expect(merged.pid == 4242)
    }

    /// A failed runtime query (nil) is "we don't know"; an empty result
    /// ([:]) is "known not loaded". The two must produce different states —
    /// filing ignorance under 未加载 would let a broken query masquerade
    /// as an idle system.
    @Test func failedRuntimeQueryYieldsUnknownNotNotLoaded() {
        let unknown = service.merge(item: makeItem(), overrides: [:], runtime: nil)
        #expect(unknown.runtimeUnknown)
        #expect(unknown.runState == .unknown)

        let absent = service.merge(item: makeItem(), overrides: [:], runtime: [:])
        #expect(!absent.runtimeUnknown)
        #expect(absent.runState == .notLoaded)
    }
}

@Suite("Sort keys")
struct SortKeyTests {
    /// Apple identity arrives two ways — codesign (developerName "Apple")
    /// and BTM conversion (kind only) — and both must land in ONE sort
    /// bucket, or 开发者-sorting the 全部 scope shears Apple items apart.
    @Test func appleSortsToOneBucketRegardlessOfSource() {
        let codesigned = LaunchItem(
            id: "a", label: "com.apple.x", displayName: "x", domain: .globalDaemon,
            signature: SignatureInfo(kind: .apple, developerName: "Apple")
        )
        let btm = LaunchItem(
            id: "b", label: "com.apple.y", displayName: "y", domain: .loginItem,
            signature: SignatureInfo(kind: .apple)
        )
        #expect(codesigned.developerSortName == "Apple")
        #expect(btm.developerSortName == "Apple")
        #expect(LaunchItem(id: "c", label: "c", displayName: "c", domain: .userAgent)
            .developerSortName.isEmpty)
    }

    /// Inside 登录项 every row's domain is .loginItem — the BTM subtype
    /// must break the tie or the 类型 header sorts nothing there.
    @Test func kindSortKeyBreaksTiesByBTMSubtype() {
        let app = LaunchItem(
            id: "a", label: "a", displayName: "a", domain: .loginItem, btmTypeDescription: "app"
        )
        let daemon = LaunchItem(
            id: "d", label: "d", displayName: "d", domain: .loginItem, btmTypeDescription: "daemon"
        )
        let agent = LaunchItem(id: "g", label: "g", displayName: "g", domain: .userAgent)
        #expect(app.kindSortKey != daemon.kindSortKey)
        #expect(app.kindSortKey < daemon.kindSortKey)
        // Domain grouping stays primary across the whole table.
        #expect(agent.kindSortKey < app.kindSortKey)
    }
}

@Suite("Masquerade detection")
struct MasqueradeTests {
    private func item(label: String) -> LaunchItem {
        LaunchItem(id: "t", label: label, displayName: label, domain: .userAgent)
    }

    @Test func appleLabelWithNonAppleSignatureIsMasquerading() {
        let fake = item(label: "com.apple.totally.legit")
        #expect(fake.isMasquerading(signature: SignatureInfo(kind: .unsigned)))
        #expect(fake.isMasquerading(signature: SignatureInfo(kind: .untrusted)))
        #expect(fake.isMasquerading(signature: SignatureInfo(kind: .developerID)))
    }

    @Test func appleLabelWithAppleSignatureIsGenuine() {
        #expect(!item(label: "com.apple.Finder").isMasquerading(signature: SignatureInfo(kind: .apple)))
    }

    /// Xcode's shape: App Store chain + store-controlled com.apple.*
    /// signing identifier. Genuine Apple, must not be flagged.
    @Test func appleStoreAppWithAppleIdentifierIsGenuine() {
        let xcode = SignatureInfo(
            kind: .appStore, developerName: "Apple", signingIdentifier: "com.apple.dt.Xcode"
        )
        #expect(!item(label: "com.apple.dt.Xcode").isMasquerading(signature: xcode))
    }

    /// A third-party store app claiming a com.apple.* label is the real
    /// masquerade; so is a store chain with no identifier captured — the
    /// exemption requires positive proof, not absence of evidence.
    @Test func appleLabelOnForeignStoreAppStillMasquerades() {
        let fake = item(label: "com.apple.fake")
        #expect(fake.isMasquerading(
            signature: SignatureInfo(kind: .appStore, signingIdentifier: "com.vendor.tool")
        ))
        #expect(fake.isMasquerading(signature: SignatureInfo(kind: .appStore)))
    }

    @Test func unverifiedSignatureIsNotAnAccusation() {
        #expect(!item(label: "com.apple.pending").isMasquerading(signature: nil))
        #expect(!item(label: "com.vendor.tool").isMasquerading(signature: SignatureInfo(kind: .unsigned)))
    }
}

@Suite("BTM signature pre-fill")
struct BTMPreFillTests {
    private func btm(bundleID: String, team: String?) -> BTMItem {
        BTMItem(
            uuid: "test-uuid",
            name: "Test",
            teamIdentifier: team,
            typeDescription: "app",
            isEnabled: true,
            executablePath: "/Applications/Test.app",
            bundleIdentifier: bundleID
        )
    }

    /// A com.apple.* label must never receive a pre-filled verdict,
    /// in either direction — real check or nothing. Full rationale
    /// lives on the pre-fill logic in `LaunchItem(btmItem:)`.
    @Test func appleLabelDefersToRealCheckRegardlessOfTeam() {
        let withTeam = LaunchItem(btmItem: btm(bundleID: "com.apple.dt.Xcode", team: "59GAB85EFG"))
        #expect(withTeam.signature == nil)
        #expect(!withTeam.isMasquerading(signature: withTeam.signature))

        let withoutTeam = LaunchItem(btmItem: btm(bundleID: "com.apple.Safari", team: nil))
        #expect(withoutTeam.signature == nil)
        #expect(!withoutTeam.isMasquerading(signature: withoutTeam.signature))
    }

    @Test func thirdPartyTeamStillPreFillsDeveloperID() {
        let item = LaunchItem(btmItem: btm(bundleID: "com.example.browser", team: "TEAM123456"))
        #expect(item.signature?.kind == .developerID)
        #expect(item.signature?.teamID == "TEAM123456")
    }
}
