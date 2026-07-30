import BirthCore
import SwiftUI
import UniformTypeIdentifiers

/// The everyday view: manage the "Open at Login" app list, with the extra
/// transparency (developer identity, related background pieces) that
/// System Settings never shows.
struct SimpleLoginAppsView: View {
    private var state: AppState { .shared }
    @State private var showingAppPicker = false
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var state = state
        Group {
            if let error = state.loginAppsError {
                automationErrorView(error)
            } else if state.loginApps.isEmpty && state.isLoadingLoginApps {
                ProgressView(L("loginApps.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.loginApps.isEmpty && state.appLikeAgents.isEmpty {
                emptyState
            } else if state.visibleLoginApps.isEmpty && state.visibleAppLikeAgents.isEmpty {
                ContentUnavailableView(
                    L("empty.noResults"),
                    systemImage: "magnifyingglass",
                    description: Text(L("loginApps.empty.noMatch", state.loginSearchText))
                )
            } else {
                appList
            }
        }
        .navigationTitle(L("sidebar.loginApps"))
        .navigationSubtitle(L("common.itemCount", state.visibleLoginApps.count + state.visibleAppLikeAgents.count))
        .searchable(text: $state.loginSearchText, placement: .toolbar, prompt: Text(L("loginApps.searchPrompt")))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAppPicker = true
                } label: {
                    Label(L("loginApps.add"), systemImage: "plus")
                }
                .help(L("loginApps.addHelp"))

                RefreshToolbarButton()
            }
        }
        .fileImporter(
            isPresented: $showingAppPicker,
            allowedContentTypes: [.application]
        ) { result in
            if case .success(let url) = result {
                state.addLoginApp(url: url)
            }
        }
        .fileDialogDefaultDirectory(URL(filePath: "/Applications", directoryHint: .isDirectory))
        // Drag an .app from Finder anywhere onto the view to add it.
        .dropDestination(for: URL.self) { urls, _ in
            let apps = urls.filter { $0.pathExtension == "app" }
            guard !apps.isEmpty else { return false }
            for url in apps {
                state.addLoginApp(url: url)
            }
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if isDropTargeted {
                dropHighlight
            }
        }
        .task { await state.loadLoginApps() }
    }

    private var appList: some View {
        List {
            if !state.visibleLoginApps.isEmpty {
                Section {
                    ForEach(state.visibleLoginApps) { app in
                        LoginAppRow(app: app)
                    }
                } header: {
                    if !state.visibleAppLikeAgents.isEmpty {
                        Text(L("loginApps.openAtLogin"))
                    }
                } footer: {
                    Text(L("loginApps.openAtLoginFooter"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
            if !state.visibleAppLikeAgents.isEmpty {
                Section {
                    ForEach(state.visibleAppLikeAgents) { item in
                        AgentAppRow(item: item)
                    }
                } header: {
                    Text(L("loginApps.otherWays"))
                } footer: {
                    Text(L("loginApps.otherWaysFooter"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L("loginApps.empty.title"), systemImage: "sunrise")
        } description: {
            Text(L("loginApps.empty.body"))
        } actions: {
            Button(L("loginApps.addEllipsis")) { showingAppPicker = true }
        }
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                Label(L("loginApps.dropHint"), systemImage: "plus.app")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(12)
            .allowsHitTesting(false)
    }

    private func automationErrorView(_ error: LoginItemsClient.LoginItemsError) -> some View {
        let isDenied = if case .automationDenied = error { true } else { false }
        return ContentUnavailableView {
            Label(
                isDenied ? L("loginApps.authNeeded") : L("loginApps.cantRead"),
                systemImage: "lock.shield"
            )
        } description: {
            Text(error.localizedDescription + (isDenied ? "\n" + L("loginApps.authNote") : ""))
        } actions: {
            if isDenied {
                Button(L("loginApps.openAutomation")) {
                    state.openAutomationSettings()
                }
            }
            Button(L("loginApps.backToList")) {
                state.loginAppsError = nil
                Task { await state.loadLoginApps() }
            }
        }
    }
}

private struct LoginAppRow: View {
    private var state: AppState { .shared }
    let app: LoginApp

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIconCache.icon(forPath: app.path))
                .resizable()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    developerText
                    if !relatedItems.isEmpty {
                        relatedBadge
                    }
                }
            }

            Spacer()

            MutationButton(title: L("loginApps.remove"), isBusy: isBusy) {
                state.removeLoginApp(app)
            }
            .help(L("loginApps.removeHelp"))
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(L("common.revealInFinder")) {
                state.revealInFinder(URL(filePath: app.path))
            }
            if !relatedItems.isEmpty {
                Button(L("loginApps.viewBackground")) {
                    showRelatedInAdvanced()
                }
            }
        }
    }

    private var relatedItems: [LaunchItem] {
        state.relatedBackgroundItems(for: app)
    }

    private var isBusy: Bool {
        state.busyLoginAppPaths.contains(app.path)
    }

    @ViewBuilder
    private var developerText: some View {
        if let signature = state.signature(forAppPath: app.path) {
            HStack(spacing: 3) {
                if !signature.isTrustworthy {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                Text(signature.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(app.path)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// Clickable: jumps to the advanced view filtered to this app's
    /// background pieces — the fastest answer to "what else did it install?".
    private var relatedBadge: some View {
        Button {
            showRelatedInAdvanced()
        } label: {
            Text(L("loginApps.relatedBadge", relatedItems.count))
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(L("loginApps.relatedHelp") + "\n" + relatedItems.map(\.displayName).joined(separator: "\n"))
    }

    private func showRelatedInAdvanced() {
        state.searchText = app.name
        state.selection = .all
    }
}

/// A launch agent that opens a real app at login — icon and name come
/// from the .app it launches; the switch is the item's launchd
/// enablement (user-session domains, so no password).
private struct AgentAppRow: View {
    private var state: AppState { .shared }
    let item: LaunchItem

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIconCache.icon(forPath: item.launchedAppBundlePath ?? ""))
                .resizable()
                .frame(width: 36, height: 36)
                .opacity(item.enablement.isEnabled == false ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.launchedAppName ?? item.displayName)
                    .font(.body.weight(.medium))
                HStack(spacing: 3) {
                    if let signature = state.signature(for: item), !signature.isTrustworthy {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            EnablementToggle(item: item)
                .help(L("loginApps.toggleHelp"))
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let bundle = item.launchedAppBundlePath {
                Button(L("common.revealInFinder")) {
                    state.revealInFinder(URL(filePath: bundle))
                }
            }
            Button(L("loginApps.showInAdvanced")) {
                state.searchText = item.launchedAppName ?? item.displayName
                state.selection = .all
            }
            if item.isUserRemovable {
                Divider()
                Button(L("common.remove"), role: .destructive) {
                    state.itemPendingRemoval = item
                }
            }
        }
    }

    private var subtitle: String {
        let mechanism = item.domain.displayName
        if let signature = state.signature(for: item) {
            return signature.shortDescription + " · " + mechanism
        }
        return mechanism
    }
}

