import BirthCore
import SwiftUI

/// The 最近移除 section's own page: everything removed from 启动应用,
/// one click from coming back. Reachable from the sidebar whenever the
/// record is non-empty.
struct RecentlyRemovedView: View {
    private var state: AppState { .shared }
    @State private var confirmingClear = false

    var body: some View {
        Group {
            if state.restorableRemovedLoginApps.isEmpty {
                ContentUnavailableView {
                    Label(L("removed.empty.title"), systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(L("removed.empty.body"))
                }
            } else {
                List {
                    Section {
                        ForEach(state.restorableRemovedLoginApps) { app in
                            RemovedLoginAppRow(app: app)
                        }
                    } footer: {
                        Text(L("removed.footer"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(L("sidebar.recentlyRemoved"))
        .navigationSubtitle(L("common.itemCount", state.restorableRemovedLoginApps.count))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("removed.clear")) {
                    confirmingClear = true
                }
                .disabled(state.restorableRemovedLoginApps.isEmpty)
            }
        }
        .confirmationDialog(
            L("removed.clearConfirm"),
            isPresented: $confirmingClear
        ) {
            Button(L("removed.clearAction"), role: .destructive) {
                state.clearRemovedLoginAppRecords()
            }
        } message: {
            Text(L("removed.clearBody"))
        }
        // The restorable filter needs the live list to hide re-added apps.
        .task { await state.loadLoginApps() }
    }
}

/// A row in 最近移除: dimmed, with one obvious way back.
struct RemovedLoginAppRow: View {
    private var state: AppState { .shared }
    let app: LoginApp

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIconCache.icon(forPath: app.path))
                .resizable()
                .frame(width: 28, height: 28)
                .opacity(0.55)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .foregroundStyle(.secondary)
                Text(L("removed.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            MutationButton(title: L("removed.reenable"), isBusy: state.busyLoginAppPaths.contains(app.path)) {
                state.reenableLoginApp(app)
            }
            .help(L("removed.reenableHelp"))
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(L("common.revealInFinder")) {
                state.revealInFinder(URL(filePath: app.path))
            }
            Button(L("removed.forget")) {
                state.forgetRemovedLoginApp(app)
            }
        }
    }
}
