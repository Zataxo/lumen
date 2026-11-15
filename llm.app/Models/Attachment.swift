import Foundation
import SwiftData

/// An image attached to a user message. Stored downscaled (JPEG, ≤ 1568 px) outside the
/// database file so chats stay small and fast to load.
@Model
final class Attachment {
    @Attribute(.unique) var id: UUID
    var position: Int
    @Attribute(.externalStorage) var data: Data
    var pixelWidth: Int
    var pixelHeight: Int
    var message: Message?

    init(data: Data, position: Int, pixelWidth: Int, pixelHeight: Int) {
        self.id = UUID()
        self.data = data
        self.position = position
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

extension Message {
    var sortedAttachments: [Attachment] { attachments.sorted { $0.position < $1.position } }
}

/// An image picked, pasted or dropped into the composer, already downscaled.
nonisolated struct PendingImage: Identifiable, Hashable, Sendable {
    let id = UUID()
    var data: Data
    var pixelWidth: Int
    var pixelHeight: Int

    /// Longest side sent to models: large enough for OCR, small enough for fast uploads.
    static let maxPixelSize = 1568
    static let maxCount = 4

    /// Downscales and re-encodes any image format ImageIO reads (HEIC, PNG, TIFF, WebP…).
    static func prepare(_ data: Data) -> PendingImage? {
        guard let jpeg = ImageDownscaler.jpegThumbnail(from: data, maxPixelSize: maxPixelSize),
              let size = ImageDownscaler.pixelSize(of: jpeg)
        else { return nil }
        return PendingImage(data: jpeg, pixelWidth: Int(size.width), pixelHeight: Int(size.height))
    }
}
