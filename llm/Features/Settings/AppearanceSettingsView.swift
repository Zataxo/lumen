import SwiftUI

/// Settings → Appearance: theme, accent, text size and message spacing. Changes apply instantly.
struct AppearanceSettingsView: View {
    @AppStorage(AppearanceKeys.theme) private var theme = ThemePreference.system
    @AppStorage(AppearanceKeys.accent) private var accent = PaletteColor.blue
    @AppStorage(AppearanceKeys.textSize) private var textSize = TextSizePreference.standard
    @AppStorage(AppearanceKeys.spacing) private var spacing = MessageSpacing.comfortable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            #if os(macOS)
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                LabeledContent("Accent Color") {
                    AccentSwatches(selection: $accent, compact: true)
                }
            }
            #else
            Section("Theme") {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Accent Color") {
                AccentSwatches(selection: $accent)
            }
            #endif

            Section {
                Picker("Text Size", selection: $textSize) {
                    ForEach(TextSizePreference.allCases) { Text($0.title).tag($0) }
                }
                Picker("Message Spacing", selection: $spacing) {
                    ForEach(MessageSpacing.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Messages")
            } footer: {
                Text("Text size applies on top of the system text size setting.")
                    .font(.caption)
            }

            Section("Preview") {
                AppearancePreview()
                    .listRowInsets(EdgeInsets(top: Spacing.medium, leading: Spacing.medium, bottom: Spacing.medium, trailing: Spacing.medium))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .animation(Motion.spring(reduceMotion: reduceMotion), value: textSize)
        .animation(Motion.spring(reduceMotion: reduceMotion), value: spacing)
    }
}

private struct AccentSwatches: View {
    @Binding var selection: PaletteColor
    /// A single trailing row of small swatches (macOS Settings row).
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: Spacing.small) {
                ForEach(PaletteColor.allCases) { color in
                    Button {
                        selection = color
                    } label: {
                        Circle()
                            .fill(color.color.gradient)
                            .frame(width: 18, height: 18)
                            .overlay {
                                if selection == color {
                                    Circle().fill(.white).frame(width: 6, height: 6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                    .accessibilityLabel(color.name)
                    .accessibilityAddTraits(selection == color ? .isSelected : [])
                }
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 44), spacing: Spacing.small)], spacing: Spacing.small) {
            ForEach(PaletteColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.color.gradient)
                        .frame(width: 28, height: 28)
                        .overlay {
                            if selection == color {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(3)
                        .overlay {
                            Circle().strokeBorder(selection == color ? color.color : .clear, lineWidth: 2)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.name)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
        .padding(.vertical, Spacing.xSmall)
    }
}

/// A miniature conversation using the live typography settings.
private struct AppearancePreview: View {
    @Environment(\.messageTypography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: typography.messageSpacing) {
            HStack {
                Spacer(minLength: 40)
                Text("How do I reverse an array?")
                    .font(typography.body)
                    .padding(.horizontal, Spacing.medium + 2)
                    .padding(.vertical, Spacing.small + 2)
                    .background(Color.userBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            MarkdownView(document: MarkdownParser.parse("Use **`reversed()`** for a new collection:\n\n```swift\nlet backwards = Array(numbers.reversed())\n```"))
        }
        .allowsHitTesting(false)
    }
}
