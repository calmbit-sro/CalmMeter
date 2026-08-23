import SwiftUI
import CalmMeterCore

/// The manual-paste OAuth sign-in: open the browser, approve, paste the
/// `CODE#STATE` string back. Lives in a regular window (not the menu popover,
/// which closes on focus loss during the browser round-trip).
struct SignInView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss

    /// One sign-in attempt's PKCE material; regenerated on every browser open,
    /// which invalidates any code minted for the previous attempt.
    @State private var pkce: PKCE?
    @State private var pasted = ""
    @State private var errorText: String?
    @State private var isExchanging = false
    @State private var signedInEmail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let email = signedInEmail {
                success(email)
            } else {
                form
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("signin.explainer")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                stepBadge(1)
                Button {
                    let fresh = PKCE()
                    pkce = fresh
                    errorText = nil
                    NSWorkspace.shared.open(ClaudeOAuth.authorizeURL(challenge: fresh.challenge, state: fresh.state))
                } label: {
                    Label("signin.open_browser", systemImage: "safari")
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                stepBadge(2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("signin.paste_caption")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("signin.paste_placeholder", text: $pasted)
                        .textFieldStyle(.roundedBorder)
                        .disabled(pkce == nil)
                        .onSubmit { submit() }
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Label("signin.claude_code_hint", systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if isExchanging { ProgressView().controlSize(.small) }
                Button("signin.confirm") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pkce == nil || pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExchanging)
            }
        }
    }

    private func success(_ email: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            Text(Localized.string("signin.success", email))
                .font(.system(size: 12, weight: .medium))
            Button("signin.done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepBadge(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 11, weight: .bold))
            .frame(width: 18, height: 18)
            .background(Circle().fill(Color.accentColor.opacity(0.2)))
    }

    private func submit() {
        guard let pkce, !isExchanging else { return }
        isExchanging = true
        errorText = nil
        let input = pasted
        Task {
            do {
                try await auth.completeSignIn(pasted: input, pkce: pkce)
                signedInEmail = auth.accountEmail ?? ""
                await store.refreshNow()
            } catch {
                errorText = Localized.signInError(error)
            }
            isExchanging = false
        }
    }
}
