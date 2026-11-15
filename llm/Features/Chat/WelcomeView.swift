import SwiftData
import SwiftUI

/// The new-chat screen: a greeting (by name when a profile exists), the current model, and a
/// few suggested prompts. A suggestion that ends in a blank line is put in the composer for
/// the user to finish; the others are sent straight away.
struct WelcomeView: View {
    let session: ChatSession
    let server: ServerConfig?
    let modelID: String?

    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var suggestions = PromptSuggestion.sample(4)
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appAccent) private var accent
    @Environment(AuthStore.self) private var auth
    @AppStorage(AppearanceKeys.accent) private var accentPreference = PaletteColor.blue

    private var profile: UserProfile? { profiles.first }

    /// The orb follows the accent color, nudged toward cyan so the default blue still glows
    /// like the app icon.
    private var orbTint: Color {
        accentPreference == .blue ? Color(red: 0.30, green: 0.80, blue: 0.98) : accent
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xLarge) {
                Spacer(minLength: Spacing.xxLarge)
                header
                suggestionGrid
                Spacer(minLength: Spacing.large)
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, Spacing.large)
            .frame(maxWidth: .infinity, minHeight: 0)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85)) {
                hasAppeared = true
            }
        }
        .task(id: server?.id) {
            if let server { await ModelListModel.ensureDefaultModel(for: server) }
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.medium) {
            NeuralOrbView(size: 132, tint: orbTint)
                .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.85)
                .overlay(alignment: .bottomTrailing) {
                    if let profile {
                        AvatarView(profile: profile, size: 34)
                            .overlay { Circle().strokeBorder(Color.lumenBackground, lineWidth: 3) }
                            .offset(x: -6, y: -6)
                    }
                }
                .padding(.bottom, -Spacing.small)
            Text(Greeting.text(name: profile?.name ?? auth.currentAccount?.displayName))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
            if let server {
                Text(modelID.map { "Chatting with \($0) on \(server.name)" } ?? "Choose a model to start")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 8)
    }

    private var suggestionGrid: some View {
        let columns = horizontalSizeClass == .compact
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Spacing.medium), GridItem(.flexible(), spacing: Spacing.medium)]
        return LazyVGrid(columns: columns, spacing: Spacing.medium) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                SuggestionCard(suggestion: suggestion) { use(suggestion) }
                    .disabled(modelID == nil)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared || reduceMotion ? 0 : 12)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85).delay(0.05 * Double(index + 1)),
                        value: hasAppeared
                    )
            }
        }
    }

    private func use(_ suggestion: PromptSuggestion) {
        if suggestion.prompt.hasSuffix("\n\n") {
            session.draft = suggestion.prompt
        } else {
            session.send(suggestion.prompt)
        }
    }
}

private struct SuggestionCard: View {
    let suggestion: PromptSuggestion
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.medium) {
                Image(systemName: suggestion.symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(suggestion.prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.07 : 0.04))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .accessibilityHint("Sends this prompt")
    }
}
