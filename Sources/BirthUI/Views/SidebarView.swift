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
            if state.loginItemsError != nil {
                FullDiskAccessHint()
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

/// Always-on breadcrumb for the one permission-gated slice: reachable
/// even when the user never visits 登录项 or clicks refresh. Kept by
/// product decision — the in-place guidance covers active discovery,
/// this covers passive.
private struct FullDiskAccessHint: View {
    private var state: AppState { .shared }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("sidebar.fda.title"), systemImage: "lock.shield")
                .font(.callout.weight(.semibold))
            Text(L("sidebar.fda.body"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(L("common.openPrivacySettings")) {
                state.openFullDiskAccessSettings()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
