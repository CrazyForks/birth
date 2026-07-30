import AppKit
import SwiftUI

public struct BirthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            // Custom About panel with the author credit (kooky-style).
            CommandGroup(replacing: .appInfo) {
                Button(L("about.title", BirthInfo.name)) {
                    AboutWindowController.shared.show()
                }
            }
            // Finder-style quick jumps to the two everyday destinations.
            CommandGroup(after: .sidebar) {
                Divider()
                Button(L("sidebar.loginApps")) { AppState.shared.selection = .loginApps }
                    .keyboardShortcut("1", modifiers: .command)
                Button(L("menu.allItems")) { AppState.shared.selection = .all }
                    .keyboardShortcut("2", modifiers: .command)
            }
        }
        // System-provided 设置… menu item + ⌘, come with the scene.
        Settings {
            SettingsView()
        }
    }
}

/// Makes the app behave like a real GUI app even when launched from
/// `swift run` without a bundle (no Info.plist, no Dock icon by default).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Pre-click selection snapshot for the repeat-click detector (see
        // AppState.noteMouseDown). Local monitors fire before the event is
        // dispatched, i.e. before the table mutates the selection. Lives
        // here so only the real app — never a test AppState — registers an
        // app-global input monitor; deliberately never removed.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated { AppState.shared.noteMouseDown() }
            return event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
