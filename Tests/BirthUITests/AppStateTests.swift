import Foundation
import Testing
@testable import BirthCore
@testable import BirthUI

/// Policy-layer tests for AppState. Each test gets a scratch UserDefaults
/// suite so nothing touches the user's real preferences.
@MainActor
private struct StateBox {
    let state: AppState
    let defaults: UserDefaults
    private let suite: String

    init() {
        suite = "dev.birth.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        state = AppState(forTesting: defaults)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        // removePersistentDomain empties the domain but can leave the
        // plist shell behind — delete it so test runs don't litter
        // ~/Library/Preferences.
        let plist = NSHomeDirectory() + "/Library/Preferences/\(suite).plist"
        try? FileManager.default.removeItem(atPath: plist)
    }
}

private func makeItem(
    id: String = "t",
    label: String,
    displayName: String? = nil,
    domain: LaunchItem.Domain = .userAgent,
    executablePath: String? = nil,
    pid: Int? = nil,
    isLoaded: Bool = false,
    runtimeUnknown: Bool = false
) -> LaunchItem {
    LaunchItem(
        id: id,
        label: label,
        displayName: displayName ?? label,
        domain: domain,
        executablePath: executablePath,
        pid: pid,
        isLoaded: isLoaded,
        runtimeUnknown: runtimeUnknown
    )
}

@MainActor
@Suite("AppState policy")
struct AppStateTests {
    @Test func sidebarSectionStorageRoundtrips() {
        let sections: [AppState.SidebarSection] = [
            .loginApps, .recentlyRemoved, .all,
            .domain(.userAgent), .domain(.globalAgent), .domain(.globalDaemon), .domain(.loginItem),
        ]
        for section in sections {
            #expect(AppState.SidebarSection(storageValue: section.storageValue) == section)
        }
        #expect(AppState.SidebarSection(storageValue: "garbage") == nil)
        #expect(AppState.SidebarSection(storageValue: "domain.garbage") == nil)
    }

    @Test func selectionPersistsAcrossInstances() {
        let box = StateBox()
        defer { box.cleanUp() }
        box.state.selection = .domain(.globalDaemon)
        let revived = AppState(forTesting: box.defaults)
        #expect(revived.selection == .domain(.globalDaemon))
    }

    /// The security property behind the 伪装系统项 fix: a com.apple.* label
    /// hides an item only until a signature verdict exists; a non-Apple
    /// verdict MUST surface the item in the third-party view.
    @Test func appleClaimStopsHidingOnceSignatureDisproves() {
        let box = StateBox()
        defer { box.cleanUp() }
        let fake = makeItem(label: "com.apple.totally.legit", executablePath: "/tmp/fake-bin")
        box.state.items = [fake]
        box.state.selection = .all
        box.state.showAppleItems = false

        // No signature yet: the claim provisionally hides it.
        #expect(box.state.visibleItems.isEmpty)
        #expect(!box.state.isMasquerading(fake))

        // Non-Apple signature arrives: the item must appear, flagged.
        box.state.signatures["/tmp/fake-bin"] = SignatureInfo(kind: .developerID, developerName: "Evil Corp")
        #expect(box.state.visibleItems.count == 1)
        #expect(box.state.isMasquerading(fake))

        // Genuine Apple signature: hidden again, not an accusation.
        box.state.signatures["/tmp/fake-bin"] = SignatureInfo(kind: .apple)
        #expect(box.state.visibleItems.isEmpty)
        #expect(!box.state.isMasquerading(fake))
    }

    @Test func sidebarCountsRespectAppleFilter() {
        let box = StateBox()
        defer { box.cleanUp() }
        box.state.items = [
            makeItem(id: "a", label: "com.vendor.tool", domain: .userAgent),
            makeItem(id: "b", label: "com.apple.service", domain: .globalDaemon),
        ]
        #expect(box.state.count(for: .all) == 1)
        #expect(box.state.count(for: .domain(.userAgent)) == 1)
        #expect(box.state.count(for: .domain(.globalDaemon)) == 0)

        box.state.showAppleItems = true
        #expect(box.state.count(for: .all) == 2)
        #expect(box.state.count(for: .domain(.globalDaemon)) == 1)
    }

    @Test func searchMatchesNameAndDeveloper() {
        let box = StateBox()
        defer { box.cleanUp() }
        let item = makeItem(label: "com.docker.helper", displayName: "Docker Helper", executablePath: "/tmp/docker")
        box.state.items = [item]
        box.state.selection = .all
        box.state.signatures["/tmp/docker"] = SignatureInfo(kind: .developerID, developerName: "Docker Inc")

        box.state.searchText = "docker"
        #expect(box.state.visibleItems.count == 1)
        box.state.searchText = "Docker Inc"
        #expect(box.state.visibleItems.count == 1)
        box.state.searchText = "nonexistent"
        #expect(box.state.visibleItems.isEmpty)
    }

    /// Issue #2: a numeric query finds "which item spawned process N" —
    /// exact PID match only, so short numbers don't sweep in unrelated
    /// PIDs, while text fields keep their substring behavior.
    @Test func numericSearchMatchesPIDExactlyNotBySubstring() {
        let box = StateBox()
        defer { box.cleanUp() }
        box.state.items = [
            makeItem(id: "a", label: "com.vendor.alpha", pid: 1234),
            makeItem(id: "b", label: "com.vendor.beta", pid: 987),
        ]
        box.state.selection = .all

        box.state.searchText = "1234"
        #expect(box.state.visibleItems.map(\.id) == ["a"])

        // A PID prefix is not a hit…
        box.state.searchText = "12"
        #expect(box.state.visibleItems.isEmpty)

        // …but the same digits still hit text fields by substring.
        box.state.items.append(makeItem(id: "c", label: "com.vendor.tool12"))
        #expect(box.state.visibleItems.map(\.id) == ["c"])
    }

    @Test func runStateFilterSlicesByRuntime() {
        let box = StateBox()
        defer { box.cleanUp() }
        box.state.items = [
            makeItem(id: "run", label: "com.vendor.running", pid: 42),
            makeItem(id: "idle", label: "com.vendor.idle", isLoaded: true),
            makeItem(id: "off", label: "com.vendor.off"),
            makeItem(id: "mystery", label: "com.vendor.mystery", runtimeUnknown: true),
        ]
        box.state.selection = .all

        #expect(box.state.visibleItems.count == 4)
        box.state.runStateFilter = .running
        #expect(box.state.visibleItems.map(\.id) == ["run"])
        box.state.runStateFilter = .loadedIdle
        #expect(box.state.visibleItems.map(\.id) == ["idle"])
        // A failed runtime query must NOT be filed under 未加载 — the
        // unknown item matches no specific slice, only 全部状态.
        box.state.runStateFilter = .notLoaded
        #expect(box.state.visibleItems.map(\.id) == ["off"])

        // Sidebar badges show category totals — the filter, like the
        // search text, must not shrink them.
        #expect(box.state.count(for: .all) == 4)
    }

    @Test func runStateFilterCombinesWithSearch() {
        let box = StateBox()
        defer { box.cleanUp() }
        box.state.items = [
            makeItem(id: "a", label: "com.docker.helper", pid: 7),
            makeItem(id: "b", label: "com.docker.updater"),
        ]
        box.state.selection = .all
        box.state.runStateFilter = .running

        box.state.searchText = "docker"
        #expect(box.state.visibleItems.map(\.id) == ["a"])
        box.state.searchText = "updater"
        #expect(box.state.visibleItems.isEmpty)
    }

    /// An all-Apple category under the 第三方 scope is hidden, not empty —
    /// the empty state must be able to tell the two apart.
    @Test func scopeEmptyStateDetectsHiddenAppleItems() {
        let box = StateBox()
        defer { box.cleanUp() }
        box.state.selection = .all
        box.state.items = [makeItem(id: "sys", label: "com.apple.service")]
        #expect(box.state.visibleItems.isEmpty)
        #expect(box.state.scopeHidesAllItems)

        // Scope switched to 全部: nothing is hidden by scope anymore.
        box.state.showAppleItems = true
        #expect(!box.state.scopeHidesAllItems)

        // The hidden item must be in the SELECTED category to count.
        box.state.showAppleItems = false
        box.state.selection = .domain(.userAgent)
        box.state.items = [makeItem(id: "sys", label: "com.apple.service", domain: .globalDaemon)]
        #expect(!box.state.scopeHidesAllItems)

        // A genuinely empty category stays "empty", not "hidden".
        box.state.items = []
        box.state.selection = .all
        #expect(!box.state.scopeHidesAllItems)
    }

    /// The pane opens on selection and closes on deselection, but a manual
    /// close (toolbar toggle) must stick without clearing the selection —
    /// visibility derived purely from the selection was undismissable when
    /// the table left no blank space to click.
    @Test func inspectorFollowsSelectionButClosesIndependently() {
        let box = StateBox()
        defer { box.cleanUp() }
        #expect(!box.state.inspectorPresented)

        box.state.selectedItemID = "a"
        #expect(box.state.inspectorPresented)

        // Toolbar toggle: pane closes, row stays selected.
        box.state.inspectorPresented = false
        #expect(box.state.selectedItemID == "a")

        // Clicking blank space (deselect) keeps the pane closed.
        box.state.selectedItemID = nil
        #expect(!box.state.inspectorPresented)
    }

    /// 点一次打开、再点一次收起, judged against the pre-click selection
    /// snapshot: a click whose mouse-down found the row already selected
    /// is a repeat click and toggles; the click that did the selecting
    /// leaves the pane open.
    @Test func repeatRowClickTogglesInspector() {
        let box = StateBox()
        defer { box.cleanUp() }

        // Click 1 on "a": snapshot (nothing selected) → table selects → tap.
        box.state.noteMouseDown()
        box.state.selectedItemID = "a"
        box.state.rowTapped("a")
        #expect(box.state.inspectorPresented)

        // Click 2, same row: snapshot says already selected → toggles shut,
        // row stays selected.
        box.state.noteMouseDown()
        box.state.rowTapped("a")
        #expect(!box.state.inspectorPresented)
        #expect(box.state.selectedItemID == "a")

        // Click 3 reopens.
        box.state.noteMouseDown()
        box.state.rowTapped("a")
        #expect(box.state.inspectorPresented)

        // Moving to another row is a plain selection, never a toggle.
        box.state.noteMouseDown()
        box.state.selectedItemID = "b"
        box.state.rowTapped("b")
        #expect(box.state.inspectorPresented)
    }

    /// The reported bug: clicking the gesture-free 启用 column's blank
    /// area selects the row (pane opens) but produces no tap. The NEXT
    /// click on any other column must close the pane immediately — the
    /// old flag-pairing design swallowed it.
    @Test func gestureFreeColumnClickDoesNotSwallowNextRepeatClick() {
        let box = StateBox()
        defer { box.cleanUp() }

        // Click on the 启用 column blank area: selection, no tap.
        box.state.noteMouseDown()
        box.state.selectedItemID = "a"
        #expect(box.state.inspectorPresented)

        // Next click on a gesture column of the same row: closes at once.
        box.state.noteMouseDown()
        box.state.rowTapped("a")
        #expect(!box.state.inspectorPresented)
    }

    /// If the tap ever outruns the table's own selection, it must do both
    /// halves itself: select first, toggle only on a genuine repeat.
    @Test func rowTapAloneSelectsThenToggles() {
        let box = StateBox()
        defer { box.cleanUp() }

        box.state.noteMouseDown()
        box.state.rowTapped("a")
        #expect(box.state.selectedItemID == "a")
        #expect(box.state.inspectorPresented)

        box.state.noteMouseDown()
        box.state.rowTapped("a")
        #expect(!box.state.inspectorPresented)
    }

    /// Restorable rows require the app to still exist on disk and to be
    /// absent from the live list.
    @Test func restorableRemovedFiltersDeadAndReaddedApps() {
        let box = StateBox()
        defer { box.cleanUp() }
        let calc = LoginApp(name: "计算器", path: "/System/Applications/Calculator.app")
        let ghost = LoginApp(name: "Ghost", path: "/nonexistent/Ghost.app")

        box.state.recentlyRemovedLoginApps = [calc, ghost]
        #expect(box.state.restorableRemovedLoginApps == [calc])

        // Back in the live list -> no longer restorable.
        box.state.loginApps = [calc]
        box.state.recentlyRemovedLoginApps = [calc, ghost]
        #expect(box.state.restorableRemovedLoginApps.isEmpty)
    }

    @Test func emptyingRecordsSnapsSelectionBack() {
        let box = StateBox()
        defer { box.cleanUp() }
        let calc = LoginApp(name: "计算器", path: "/System/Applications/Calculator.app")
        box.state.recentlyRemovedLoginApps = [calc]
        box.state.selection = .recentlyRemoved

        box.state.clearRemovedLoginAppRecords()
        #expect(box.state.selection == .loginApps)
    }

    @Test func recentlyRemovedRecordPersistsAcrossInstances() throws {
        let box = StateBox()
        defer { box.cleanUp() }
        let calc = LoginApp(name: "计算器", path: "/System/Applications/Calculator.app")
        box.state.recentlyRemovedLoginApps = [calc]

        let revived = AppState(forTesting: box.defaults)
        #expect(revived.recentlyRemovedLoginApps == [calc])
        #expect(revived.restorableRemovedLoginApps == [calc])
    }
}

@MainActor
@Suite("Launched-app agent detection")
struct LaunchedAppAgentTests {
    private func agent(
        path: String?,
        domain: LaunchItem.Domain = .userAgent,
        runAtLoad: Bool = true,
        keepAlive: Bool = false
    ) -> LaunchItem {
        LaunchItem(
            id: "t", label: "t", displayName: "t", domain: domain,
            executablePath: path, runAtLoad: runAtLoad, keepAlive: keepAlive
        )
    }

    /// The 闪电说 shape: a user agent whose executable is the main binary
    /// of an app in /Applications.
    @Test func detectsDIYOpenAtLoginAgents() {
        let item = agent(path: "/Applications/闪电说.app/Contents/MacOS/shandianshuo")
        #expect(item.launchedAppBundlePath == "/Applications/闪电说.app")
        #expect(item.launchedAppName == "闪电说")
    }

    @Test func keepAliveCountsAsLaunching() {
        let item = agent(path: "/Applications/X.app/Contents/MacOS/X", runAtLoad: false, keepAlive: true)
        #expect(item.launchedAppBundlePath != nil)
    }

    @Test func rejectsNonAppShapes() {
        // Embedded login-item helper (double bundle).
        #expect(agent(path: "/Applications/Lemon.app/Contents/Library/LoginItems/M.app/Contents/MacOS/M").launchedAppBundlePath == nil)
        // Non-main binaries inside the bundle.
        #expect(agent(path: "/Applications/S.app/Contents/Resources/monitor").launchedAppBundlePath == nil)
        #expect(agent(path: "/Applications/B.app/Contents/Frameworks/service").launchedAppBundlePath == nil)
        // Updater bundles living in Application Support.
        #expect(agent(path: NSHomeDirectory() + "/Library/Application Support/G/U.app/Contents/MacOS/U").launchedAppBundlePath == nil)
        // Subdirectory under MacOS.
        #expect(agent(path: "/Applications/A.app/Contents/MacOS/sub/bin").launchedAppBundlePath == nil)
        // Daemons and not-at-boot jobs are out of scope.
        #expect(agent(path: "/Applications/D.app/Contents/MacOS/D", domain: .globalDaemon).launchedAppBundlePath == nil)
        #expect(agent(path: "/Applications/N.app/Contents/MacOS/N", runAtLoad: false).launchedAppBundlePath == nil)
        // No executable at all.
        #expect(agent(path: nil).launchedAppBundlePath == nil)
    }

    @Test func aggregatedSidebarCountIncludesAgents() {
        let box = StateBox()
        defer { box.cleanUp() }
        box.state.loginApps = [LoginApp(name: "Paste", path: "/Applications/Paste.app")]
        box.state.items = [
            agent(path: "/Applications/闪电说.app/Contents/MacOS/shandianshuo"),
            agent(path: "/Applications/S.app/Contents/Resources/monitor"),
        ]
        #expect(box.state.count(for: .loginApps) == 2)
        #expect(box.state.appLikeAgents.count == 1)
    }
}
