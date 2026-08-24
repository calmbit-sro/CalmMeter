import SwiftUI
import CalmMeterCore

/// First-run guide: where the app lives, whether it's connected to Claude, and
/// the one setting worth deciding up front. A menu-bar agent shows no window
/// and no Dock icon on launch, so without this a new user sees nothing but a
/// new glyph in the bar. Opened once automatically (`SettingsKey.welcomeShown`)
/// and re-openable from Preferences. Step 2 tracks the live store/auth state,
/// so it flips to "connected" by itself after a sign-in.
struct WelcomeView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var auth: AuthStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.barDisplayMode) private var barModeRaw = BarDisplayMode.dotAndFiveHour.rawValue
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            step(1, title: "welcome.step1.title") { locate }
            step(2, title: "welcome.step2.title") { connection }
            step(3, title: "welcome.step3.title") { finish }
            HStack {
                Spacer()
                Button("welcome.done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            // Reconcile the toggle with the actual system state, as Preferences does.
            launchAtLogin = LoginItem.isEnabled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("welcome.title").font(.system(size: 16, weight: .semibold))
                Text("welcome.subtitle").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 1: find it in the menu bar

    private var locate: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("welcome.step1.body")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            // The real label, live — so the user can match it against the bar.
            HStack(spacing: 6) {
                Text("welcome.step1.preview_caption")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                BarLabel(
                    usage: store.usage,
                    error: store.lastError,
                    mode: BarDisplayMode(rawValue: barModeRaw) ?? .dotAndFiveHour,
                    rules: UserDefaults.standard.colorRules
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            }
        }
    }

    // MARK: - Step 2: connection to Claude

    /// Mirrors `AutoCredentialProvider`'s priority: own sign-in first, then
    /// whatever the poller managed with Claude Code's login.
    private enum ConnectionState {
        case checking
        case signedIn(email: String)
        case claudeCode
        case needsSignIn
        case failed(UsageErrorKind)
    }

    private var connectionState: ConnectionState {
        if let email = auth.accountEmail { return .signedIn(email: email) }
        if store.usage != nil { return .claudeCode }
        if let err = store.lastError {
            return (err == .notLoggedIn || err == .signedOut) ? .needsSignIn : .failed(err)
        }
        return .checking
    }

    @ViewBuilder
    private var connection: some View {
        switch connectionState {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("welcome.step2.checking").font(.system(size: 12)).foregroundStyle(.secondary)
            }

        case .signedIn(let email):
            status(.ok, email.isEmpty
                   ? Localized.string("welcome.step2.signed_in")
                   : Localized.string("signin.success", email))

        case .claudeCode:
            status(.ok, Localized.string("welcome.step2.claude_code"))

        case .needsSignIn:
            VStack(alignment: .leading, spacing: 8) {
                status(.attention, Localized.string("welcome.step2.needs_sign_in"))
                Button {
                    openWindow(id: "signin")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Text("signin.button").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Text("welcome.step2.or_claude_code")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .failed(let err):
            HStack(alignment: .firstTextBaseline) {
                status(.error, Localized.error(err))
                Spacer()
                Button("welcome.retry") { Task { await store.refreshNow() } }
                    .controlSize(.small)
                    .disabled(store.isLoading)
            }
        }
    }

    private enum StatusKind { case ok, attention, error }

    private func status(_ kind: StatusKind, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch kind {
            case .ok:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .attention:
                Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(.orange)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 3: launch at login

    private var finish: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("welcome.launch_at_login", isOn: $launchAtLogin)
                .font(.system(size: 12))
                .onChange(of: launchAtLogin) { LoginItem.setEnabled($0) }
            HStack(spacing: 4) {
                Text("welcome.step3.body")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Preferences…") {
                    openWindow(id: "preferences")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    // MARK: - Layout helper

    private func step<Content: View>(
        _ number: Int, title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            StepBadge(number)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
