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
            "操作失败",
            isPresented: Binding(
                get: { state.lastErrorMessage != nil },
                set: { if !$0 { state.lastErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(state.lastErrorMessage ?? "")
        }
        // Root-level: removal can now start from 启动应用 (agent rows) as
        // well as the advanced table, so the dialog must outlive both.
        .confirmationDialog(
            "移除“\(state.itemPendingRemoval?.displayName ?? "")”？",
            isPresented: Binding(
                get: { state.itemPendingRemoval != nil },
                set: { if !$0 { state.itemPendingRemoval = nil } }
            )
        ) {
            Button("移到废纸篓", role: .destructive) {
                state.confirmRemoval()
            }
        } message: {
            Text("该任务会先停止运行，其 plist 文件将移到废纸篓。Birth 会在 ~/Library/Application Support/Birth/Backups 中保留一份备份。")
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
            .navigationSubtitle("共 \(state.visibleItems.count) 项")
            .searchable(text: $state.searchText, placement: .toolbar, prompt: "名称、开发者、路径或 PID")
            .toolbar {
                ToolbarItemGroup {
                    Picker("范围", selection: $state.showAppleItems) {
                        Text("第三方").tag(false)
                        Text("全部").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .help("“第三方”只显示非 Apple 的启动项；“全部”包含 macOS 自带的系统服务")

                    Menu {
                        Picker("运行状态", selection: $state.runStateFilter) {
                            ForEach(AppState.RunStateFilter.allCases, id: \.self) { filter in
                                Text(filter.displayName).tag(filter)
                            }
                        }
                        .pickerStyle(.inline)
                        Picker("启用状态", selection: $state.enablementFilter) {
                            ForEach(AppState.EnablementFilter.allCases, id: \.self) { filter in
                                Text(filter.displayName).tag(filter)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        // Mail-style: the icon fills while a filter is
                        // active, so a narrowed list is never a mystery.
                        Label("过滤", systemImage: "line.3.horizontal.decrease.circle")
                            .symbolVariant(state.anyTableFilterActive ? .fill : .none)
                    }
                    .help("按运行状态或启用状态过滤")

                    RefreshToolbarButton()

                    Button {
                        state.inspectorPresented.toggle()
                    } label: {
                        Label("显示或隐藏详情", systemImage: "sidebar.trailing")
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("显示或隐藏详情面板（⌥⌘I）")
                }
            }
            .alert("缺少“完全磁盘访问权限”", isPresented: $state.showFullDiskAccessPrompt) {
                Button("打开隐私设置") {
                    state.openFullDiskAccessSettings()
                }
                Button("暂不", role: .cancel) {}
            } message: {
                Text("其余分类均已正常刷新，只有“登录项”分类需要该权限才能读取。授权一次即可——之后每次刷新都会静默包含登录项，不再出现本提示。授权后切回 Birth 会自动刷新。")
            }
            .inspector(isPresented: $state.inspectorPresented) {
                Group {
                    if let item = state.selectedItem {
                        ItemDetailView(item: item)
                    } else {
                        // Reachable only via the toolbar toggle with nothing
                        // selected — row clicks always land on the branch above.
                        ContentUnavailableView {
                            Label("未选择项目", systemImage: "info.circle")
                        } description: {
                            Text("在列表中选择一项即可查看详情。")
                        }
                    }
                }
                .inspectorColumnWidth(min: 300, ideal: 340)
            }
    }
}
