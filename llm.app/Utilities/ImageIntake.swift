import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Reads images from the pasteboard, drag-and-drop providers and picked files.
enum ImageIntake {
    /// Whether the pasteboard holds an image. Detection only — doesn't trigger the iOS paste prompt.
    static var pasteboardHasImage: Bool {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
            || pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]])
        #else
        return UIPasteboard.general.hasImages
        #endif
    }

    /// Raw image data on the pasteboard, preferring the original encoding over re-encoding.
    static func pasteboardImages() -> [Data] {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        ) as? [URL], !urls.isEmpty {
            return urls.compactMap { try? Data(contentsOf: $0) }
        }
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier), NSPasteboard.PasteboardType(UTType.heic.identifier)]
        return (pasteboard.pasteboardItems ?? []).compactMap { item in
            types.lazy.compactMap { item.data(forType: $0) }.first
        }
        #else
        let pasteboard = UIPasteboard.general
        let preferred = [UTType.png, .jpeg, .heic].map(\.identifier)
        var datas: [Data] = []
        for index in 0..<pasteboard.numberOfItems {
            let set = IndexSet(integer: index)
            if let data = preferred.lazy.compactMap({ pasteboard.data(forPasteboardType: $0, inItemSet: set)?.first as? Data }).first {
                datas.append(data)
            }
        }
        if datas.isEmpty, let images = pasteboard.images {
            datas = images.compactMap { $0.jpegData(compressionQuality: 0.9) }
        }
        return datas
        #endif
    }

    /// Loads image data from dropped items (images or image files).
    static func load(_ providers: [NSItemProvider]) async -> [Data] {
        var result: [Data] = []
        for provider in providers {
            if let data = await loadData(from: provider) { result.append(data) }
        }
        return result
    }

    private static func loadData(from provider: NSItemProvider) async -> Data? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            guard let url else { return nil }
            return read(url)
        }
        return nil
    }

    /// Reads a user-picked or dropped file, including security-scoped URLs from the sandbox.
    static func read(_ url: URL) -> Data? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}

/// Decoded, display-sized images for attachments, cached so scrolling doesn't re-decode JPEGs.
final class AttachmentImageCache {
    static let shared = AttachmentImageCache()
    private let cache = NSCache<NSString, PlatformImage>()

    init() { cache.countLimit = 200 }

    func image(id: UUID, maxPixelSize: Int) -> PlatformImage? {
        cache.object(forKey: key(id, maxPixelSize))
    }

    func load(id: UUID, data: Data, maxPixelSize: Int) async -> PlatformImage? {
        if let cached = image(id: id, maxPixelSize: maxPixelSize) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            ImageDownscaler.jpegThumbnail(from: data, maxPixelSize: maxPixelSize, quality: 0.9)
        }.value
        guard let decoded, let image = PlatformImage(data: decoded) else { return nil }
        cache.setObject(image, forKey: key(id, maxPixelSize))
        return image
    }

    private func key(_ id: UUID, _ size: Int) -> NSString { "\(id.uuidString)-\(size)" as NSString }
}

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif
