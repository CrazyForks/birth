import BirthCore
import SwiftUI

struct ItemDetailView: View {
    private var state: AppState { .shared }
    let item: LaunchItem
    @State private var showingPlist = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                details
                Divider()
                actions
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingPlist) {
            if let plistURL = item.plistURL {
                PlistViewer(url: plistURL)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayName)
                .font(.title3.weight(.semibold))
            Text(item.label)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.isMasquerading(item) {
                Label(L("detail.masquerade"), systemImage: "exclamationmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            row(L("column.kind")) {
                Text(item.domain.displayName)
            }
            row(L("detail.location")) {
                Text(item.domain.locationDescription)
                    .foregroundStyle(.secondary)
            }
            row(L("column.status")) {
                stateText
            }
            if let signature = state.signature(for: item) {
                row(L("column.developer")) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signature.shortDescription)
                        if let team = signature.teamID {
                            Text(L("detail.teamID", team))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let path = item.executablePath {
                row(L("detail.executable")) {
                    pathText(path)
                }
            }
            if let plistURL = item.plistURL {
                row(L("detail.plist")) {
                    pathText(plistURL.path)
                }
            }
            if let schedule = item.schedule {
                row(L("detail.schedule")) { Text(schedule) }
            }
            if item.runAtLoad || item.keepAlive {
                row(L("detail.behavior")) {
                    Text(behaviorText)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var stateText: some View {
        let enabled = item.enablement.isEnabled
        let base = switch item.enablement {
        case .enabled: L("enablement.enabled")
        case .disabled: L("enablement.disabled")
        case .managedBySystem(let isOn): isOn ? L("enablement.enabledManaged") : L("enablement.disabledManaged")
        case .unknown: L("common.unknown")
        }
        let runtime = switch item.runState {
        case .running(let pid): L("detail.runtimeRunning", pid)
        case .loadedIdle: L("detail.runtimeLoaded")
        case .notLoaded: ""
        case .unknown: L("detail.runtimeUnknown")
        }
        return Text(base + runtime)
            .foregroundStyle(enabled == false ? Color.secondary : Color.primary)
    }

    private var behaviorText: String {
        var parts: [String] = []
        if item.runAtLoad { parts.append(L("detail.runAtLoad")) }
        if item.keepAlive { parts.append(L("detail.keepAlive")) }
        // The separator is localized too: enumeration commas differ (，vs , ).
        return parts.joined(separator: L("common.listSeparator"))
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.isUserRemovable {
                if item.plistURL != nil {
                    Button {
                        showingPlist = true
                    } label: {
                        Label(L("detail.viewPlist"), systemImage: "doc.text.magnifyingglass")
                    }
                }
                Button(role: .destructive) {
                    state.itemPendingRemoval = item
                } label: {
                    Label(L("common.remove"), systemImage: "trash")
                }
            } else {
                Button {
                    state.openLoginItemsSettings()
                } label: {
                    Label(L("common.openSystemSettings"), systemImage: "gear")
                }
                Text(L("detail.loginItemNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pathText(_ path: String) -> some View {
        Button {
            state.revealInFinder(URL(filePath: path))
        } label: {
            Text(path)
                .font(.caption.monospaced())
                .multilineTextAlignment(.leading)
                .foregroundStyle(.link)
        }
        .buttonStyle(.plain)
        .help(L("common.revealInFinder"))
    }
}
