import SwiftUI

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

/// An attachment image decoded off the main thread at display size.
struct AttachmentImageView: View {
    let id: UUID
    let data: Data
    var maxPixelSize = 480
    var contentMode: ContentMode = .fill

    @State private var image: PlatformImage?

    init(id: UUID, data: Data, maxPixelSize: Int = 480, contentMode: ContentMode = .fill) {
        self.id = id
        self.data = data
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        _image = State(initialValue: AttachmentImageCache.shared.image(id: id, maxPixelSize: maxPixelSize))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: id) {
            if image == nil {
                image = await AttachmentImageCache.shared.load(id: id, data: data, maxPixelSize: maxPixelSize)
            }
        }
    }
}

/// Thumbnails shown above a sent user message. Tap to view full size.
struct MessageAttachmentsView: View {
    let attachments: [Attachment]
    @State private var previewed: Attachment?

    var body: some View {
        HStack(spacing: Spacing.small) {
            ForEach(attachments) { attachment in
                Button {
                    previewed = attachment
                } label: {
                    AttachmentImageView(id: attachment.id, data: attachment.data)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attached image")
                .accessibilityHint("Shows the image full size")
            }
        }
        .sheet(item: $previewed) { attachment in
            ImagePreviewView(attachment: attachment)
        }
    }

    private var side: CGFloat { attachments.count == 1 ? 180 : 110 }
}

struct ImagePreviewView: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AttachmentImageView(id: attachment.id, data: attachment.data, maxPixelSize: 2048, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .navigationTitle("\(attachment.pixelWidth) × \(attachment.pixelHeight)")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color.black, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 760, minHeight: 420, idealHeight: 600)
        #endif
    }
}

/// Images queued in the composer, with remove buttons.
struct PendingImagesTray: View {
    let session: ChatSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.small) {
                ForEach(session.pendingImages) { image in
                    AttachmentImageView(id: image.id, data: image.data, maxPixelSize: 200)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.snappy) { session.removePendingImage(image.id) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove image")
                        }
                        .transition(.scale.combined(with: .opacity))
                }
                if session.isPreparingImages {
                    ProgressView()
                        .frame(width: 56, height: 56)
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
    }
}

/// Shown over the chat while images are dragged onto it.
struct DropTargetOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .background(.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay {
                Label("Drop images to attach", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, Spacing.large)
                    .padding(.vertical, Spacing.medium)
                    .glassSurface(in: Capsule())
            }
            .padding(Spacing.medium)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
