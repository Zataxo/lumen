import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The input bar: grows to 8 lines, sends with Return (macOS) or ⌘↩, stops with ⌘.
/// The + menu attaches images (Photos, Files, Paste) for models that can see.
struct ComposerView: View {
    @Bindable var session: ChatSession
    let canSend: Bool
    /// nil when the server doesn't report capabilities.
    let supportsVision: Bool?
    let modelName: String?

    @FocusState private var isFocused: Bool
    @Environment(\.appAccent) private var accent
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var photoItems: [PhotosPickerItem] = []

    /// One size for both round buttons and a single line of text, so the +, the text and the
    /// send button share a center line, and the bar is a pill with even insets all round.
    private static let controlSize: CGFloat = 36
    private static let barInset: CGFloat = 6
    private static let barRadius = (controlSize + 2 * barInset) / 2

    private var canSubmit: Bool {
        session.canSendDraft && canSend && !session.isPreparingImages
    }

    var body: some View {
        VStack(spacing: Spacing.small) {
            if let notice = session.notice {
                Label(Self.text(for: notice), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                if !session.pendingImages.isEmpty || session.isPreparingImages {
                    // Lines up with the + button's left edge.
                    PendingImagesTray(session: session)
                }
                HStack(alignment: .bottom, spacing: Spacing.small) {
                    attachMenu
                    TextField(session.pendingImages.isEmpty ? "Message" : "Ask about the image…", text: $session.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...8)
                        .focused($isFocused)
                        .padding(.vertical, 7)
                        // A single line centers on the buttons; longer drafts grow upward
                        // while the buttons stay beside the last line.
                        .frame(minHeight: Self.controlSize)
                        #if os(macOS)
                        .onSubmit(send)
                        .onPasteCommand(of: [.image, .png, .jpeg, .tiff, .fileURL]) { _ in pasteImages() }
                        #endif
                    actionButton
                }
            }
            .padding(Self.barInset)
            .glassSurface(in: RoundedRectangle(cornerRadius: Self.barRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.barRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(isFocused ? 0.14 : 0.08), lineWidth: 1)
            }
        }
        .frame(maxWidth: 780)
        .padding(.horizontal, Spacing.large)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.medium)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: session.notice)
        .animation(.snappy, value: session.isStreaming)
        .animation(.snappy, value: session.pendingImages.count)
        #if os(macOS)
        .onAppear { isFocused = true }
        #endif
        .onChange(of: session.draft.hasSuffix("\n\n")) { _, endsWithBlankLine in
            if endsWithBlankLine { isFocused = true }
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $photoItems,
            maxSelectionCount: max(1, PendingImage.maxCount - session.pendingImages.count),
            matching: .images
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task {
                var datas: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
                }
                session.addImages(datas)
            }
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                session.addImages(urls.compactMap(ImageIntake.read))
            }
        }
        .focusedSceneValue(\.composerActions, ComposerActions(pasteImage: pasteImages, canAttach: supportsVision != false))
    }

    // MARK: Attach

    @ViewBuilder
    private var attachMenu: some View {
        if supportsVision == false {
            // Not `.disabled`: on iPad and iPhone there's no hover tooltip, so a dead button
            // gives no clue. Tapping explains why instead.
            Button(action: explainNoVision) { attachLabel }
                .buttonStyle(.plain)
                .help(noVisionMessage)
                .accessibilityLabel("Attach images")
                .accessibilityHint(noVisionMessage)
        } else {
            Menu {
                Button("Photo Library", systemImage: "photo.on.rectangle") { isPhotoPickerPresented = true }
                Button("Choose File…", systemImage: "folder") { isFileImporterPresented = true }
                Button("Paste Image", systemImage: "doc.on.clipboard") { pasteImages() }
                    .disabled(!ImageIntake.pasteboardHasImage)
            } label: {
                attachLabel
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(session.pendingImages.count >= PendingImage.maxCount)
            .help("Attach images")
            .accessibilityLabel("Attach images")
        }
    }

    private var attachLabel: some View {
        Image(systemName: "plus")
            .font(.system(size: 16, weight: .semibold))
            .frame(width: Self.controlSize, height: Self.controlSize)
            .background(Color.primary.opacity(0.07), in: Circle())
            .foregroundStyle(supportsVision == false ? Color.secondary.opacity(0.5) : Color.secondary)
            .contentShape(Circle())
    }

    private var noVisionMessage: String {
        "\(modelName ?? "This model") can't read images. To attach photos, switch to a model with Vision, such as gemma3, llava or qwen2.5vl."
    }

    private func explainNoVision() {
        session.notice = .other(noVisionMessage)
    }

    /// Plain notices (`.other`) carry their own text; errors show their hint or title.
    static func text(for notice: ProviderError) -> String {
        if case .other(let message) = notice { return message }
        return notice.hint ?? notice.title
    }

    private func pasteImages() {
        guard supportsVision != false else {
            explainNoVision()
            return
        }
        let datas = ImageIntake.pasteboardImages()
        if datas.isEmpty {
            session.notice = .other("There's no image on the clipboard.")
        } else {
            session.addImages(datas)
        }
    }

    // MARK: Send / Stop

    @ViewBuilder
    private var actionButton: some View {
        if session.isStreaming {
            Button(action: session.stop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: Self.controlSize, height: Self.controlSize)
                    // Explicit colors: `.primary` picks up the glass's vibrancy and washes out.
                    .background(accent, in: Circle())
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .help("Stop (⌘.)")
            .accessibilityLabel("Stop generating")
            .transition(.scale.combined(with: .opacity))
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: Self.controlSize, height: Self.controlSize)
                    .background(canSubmit ? accent : Color.primary.opacity(0.07), in: Circle())
                    .foregroundStyle(canSubmit ? Color.white : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send (⌘↩)")
            .accessibilityLabel("Send message")
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func send() {
        guard canSubmit, !session.isStreaming else { return }
        let text = session.draft
        session.draft = ""
        session.send(text)
    }
}

/// Lets the Edit menu's "Paste Image" reach the focused window's composer.
struct ComposerActions {
    var pasteImage: () -> Void
    var canAttach: Bool
}

extension FocusedValues {
    @Entry var composerActions: ComposerActions?
}
