import BirthCore
import SwiftUI

struct SidebarView: View {
    private var state: AppState { .shared }
    var body: some View {
        @Bindable var state = state
        List(selection: $state.selection) {
            Section(L("sidebar.loginApps")) {
                // Row reads 全部 inside its group; the window title still
                // carries the section name (displayTitle = 启动应用).
                row(.loginApps, overrideTitle: L("common.all"))
                if state.count(for: .recentlyRemoved) > 0 {
                    row(.recentlyRemoved)
                }
            }
            Section(L("sidebar.advanced")) {
                row(.all)
                ForEach(LaunchItem.Domain.allCases, id: \.self) { domain in
                    row(.domain(domain))
                }
            }
        }
        .safeAreaInset(edge: .top) {
            // Brand header: with Finder-style window titles (title = where
            // you are), this is where the product identity lives.
            HStack {
                Text(BirthInfo.name)
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom) {
            if let error = state.loginItemsError {
                LoginItemsUnavailableHint(error: error)
                    .padding(10)
            }
        }
    }

    private func row(_ section: AppState.SidebarSection, overrideTitle: String? = nil) -> some View {
        Label {
            Text(overrideTitle ?? section.displayTitle)
                .badge(state.count(for: section))
        } icon: {
            Image(systemName: section.systemImage)
        }
        .tag(section)
    }
}

/// Compact breadcrumb for the unavailable BTM slice. Recovery details stay
/// in the main pane; the sidebar keeps one concise action.
private struct LoginItemsUnavailableHint: View {
    private var state: AppState { .shared }
    let error: BTMReader.BTMError

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("sidebar.fda.title"), systemImage: "lock.shield")
                .font(.callout.weight(.semibold))
            Text(error.requiresFullDiskAccess ? L("sidebar.fda.body") : L("sidebar.btm.body"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if error.requiresFullDiskAccess {
                Button(L("common.openPrivacySettings")) {
                    state.openFullDiskAccessSettings()
                }
                .controlSize(.small)
            } else {
                Button(L("sidebar.btm.details")) {
                    state.selection = .domain(.loginItem)
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
