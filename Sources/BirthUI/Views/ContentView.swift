import BirthCore
import SwiftUI

/// One unified sidebar layout: "启动应用" (the everyday Open-at-Login
/// manager) on top, "高级启动项" (the full launchd/BTM table) below.
struct ContentView: View {
    private var state: AppState { .shared }
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var state = state
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch state.selection {
                case .loginApps:
                    SimpleLoginAppsView()
                        .transition(.opacity)
                case .recentlyRemoved:
                    RecentlyRemovedView()
                        .transition(.opacity)
                case .all, .domain:
                    AdvancedItemsView()
                        .transition(.opacity)
                }
            }
            // Animate only when crossing between the two sidebar groups —
            // switching within a group should not blink the content.
            .animation(.easeInOut(duration: 0.15), value: isAdvancedSelection)
        }
        .task { await state.refresh() }
        .alert(
            L("error.operationFailed"),
            isPresented: Binding(
                get: { state.lastErrorMessage != nil },
                set: { if !$0 { state.lastErrorMessage = nil } }
            )
        ) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(state.lastErrorMessage ?? "")
        }
        // Root-level: removal can now start from 启动应用 (agent rows) as
        // well as the advanced table, so the dialog must outlive both.
        .confirmationDialog(
            L("remove.confirmTitle", state.itemPendingRemoval?.displayName ?? ""),
            isPresented: Binding(
                get: { state.itemPendingRemoval != nil },
                set: { if !$0 { state.itemPendingRemoval = nil } }
            )
        ) {
            Button(L("remove.moveToTrash"), role: .destructive) {
                state.confirmRemoval()
            }
        } message: {
            Text(L("remove.confirmBody"))
        }
    }

    private var isAdvancedSelection: Bool {
        state.selection.isAdvanced
    }
}

/// The power-user table: every launchd job and BTM record on the system,
/// with its own search field, toolbar, inspector, and removal dialog.
struct AdvancedItemsView: View {
    private var state: AppState { .shared }

    var body: some View {
        @Bindable var state = state
        ItemTableView()
            .navigationTitle(state.selection.displayTitle)
            .navigationSubtitle(L("common.itemCount", state.visibleItems.count))
            .searchable(text: $state.searchText, placement: .toolbar, prompt: Text(L("advanced.searchPrompt")))
            .toolbar {
                ToolbarItemGroup {
                    Picker(L("advanced.scope"), selection: $state.showAppleItems) {
                        Text(L("advanced.scope.thirdParty")).tag(false)
                        Text(L("common.all")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .help(L("advanced.scope.help"))

                    Menu {
                        Picker(L("filter.runState"), selection: $state.runStateFilter) {
                            ForEach(AppState.RunStateFilter.allCases, id: \.self) { filter in
                                Text(filter.displayName).tag(filter)
                            }
                        }
                        .pickerStyle(.inline)
                        Picker(L("filter.enablement"), selection: $state.enablementFilter) {
                            ForEach(AppState.EnablementFilter.allCases, id: \.self) { filter in
                                Text(filter.displayName).tag(filter)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        // Mail-style: the icon fills while a filter is
                        // active, so a narrowed list is never a mystery.
                        Label(L("filter.title"), systemImage: "line.3.horizontal.decrease.circle")
                            .symbolVariant(state.anyTableFilterActive ? .fill : .none)
                    }
                    .help(L("filter.help"))

                    RefreshToolbarButton()

                    Button {
                        state.inspectorPresented.toggle()
                    } label: {
                        Label(L("inspector.toggle"), systemImage: "sidebar.trailing")
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help(L("inspector.toggleHelp"))
                }
            }
            .alert(L("fda.alert.title"), isPresented: $state.showFullDiskAccessPrompt) {
                Button(L("common.openPrivacySettings")) {
                    state.openFullDiskAccessSettings()
                }
                Button(L("common.notNow"), role: .cancel) {}
            } message: {
                Text(L("fda.alert.body"))
            }
            .inspector(isPresented: $state.inspectorPresented) {
                Group {
                    if let item = state.selectedItem {
                        ItemDetailView(item: item)
                    } else {
                        // Reachable only via the toolbar toggle with nothing
                        // selected — row clicks always land on the branch above.
                        ContentUnavailableView {
                            Label(L("inspector.empty.title"), systemImage: "info.circle")
                        } description: {
                            Text(L("inspector.empty.body"))
                        }
                    }
                }
                .inspectorColumnWidth(min: 300, ideal: 340)
            }
    }
}
