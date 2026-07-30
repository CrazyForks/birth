import SwiftUI

/// The app-wide Settings window (App menu → 设置…, ⌘,). One section for
/// now: language. Language NAMES stay in their own language (App Store
/// convention) — only the "follow the system" option is localized.
struct SettingsView: View {
    private var state: AppState { .shared }

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                Picker(selection: $state.appLanguage) {
                    Text(L("settings.followSystem")).tag(AppState.AppLanguage.system)
                    Text(verbatim: "简体中文").tag(AppState.AppLanguage.chinese)
                    Text(verbatim: "English").tag(AppState.AppLanguage.english)
                } label: {
                    // Bilingual on purpose — the language row must be
                    // readable no matter which language is showing. Plain
                    // SF Symbol, matching the main window's icon language.
                    Label {
                        Text(verbatim: "Language / 语言")
                    } icon: {
                        Image(systemName: "globe")
                    }
                }
                if state.needsRelaunchForLanguage {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                        Text(relaunchNotice)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(relaunchButtonTitle) {
                            state.relaunchApp()
                        }
                    }
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The relaunch notice must speak the TARGET language, not the current
    /// one: the person reading it just chose that language, and rendering
    /// it in the language they are leaving is exactly wrong for the reader
    /// who can't read it. Deliberately NOT L() — these two strings are
    /// hardcoded per target instead of table-looked-up by current locale.
    private var targetIsEnglish: Bool {
        switch state.appLanguage {
        case .english: true
        case .chinese: false
        case .system: state.resolvedSystemLanguage == .english
        }
    }

    private var relaunchNotice: String {
        targetIsEnglish
            ? "The language change takes effect after Birth restarts."
            : "语言切换将在重启 Birth 后生效。"
    }

    private var relaunchButtonTitle: String {
        targetIsEnglish ? "Restart Now" : "立即重启"
    }
}
