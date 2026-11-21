import AppKit
import QuickLookThumbnailing

/// Makes the thumbnails that icon mode shows in place of the file icons, as Finder does.
@MainActor
enum ThumbnailLoader {
    /// A thumbnail of a file for an icon size.
    struct Request: Hashable {
        let entry: FileEntry
        /// The size of the thumbnail in points.
        let size: CGFloat

        private static let sizes: [CGFloat] = [64, 128, CardLayout.iconSizeRange.upperBound]

        /// A pinch changes the icon size in small steps. The thumbnails have only some sizes,
        /// so that not each step makes new thumbnails. The thumbnail is not smaller than the icon.
        init(entry: FileEntry, iconSize: CGFloat) {
            self.entry = entry
            size = Self.sizes.first { $0 >= iconSize } ?? CardLayout.iconSizeRange.upperBound
        }
    }

    /// The maximum number of pixels along one side of a thumbnail. It keeps the use of memory low.
    private static let maxPixels: CGFloat = 1024

    /// The thumbnails that are ready. The cache removes items when they use too much memory.
    private static let cache = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()

    /// The thumbnail, if it is ready. This does not start the work.
    static func cached(_ request: Request) -> NSImage? {
        cache.object(forKey: key(request))
    }

    /// A static picture of the content of the file.
    /// Returns nil for a folder and for a file that macOS cannot make a thumbnail for.
    /// Such an item keeps its icon.
    static func thumbnail(for request: Request, scale: CGFloat) async -> NSImage? {
        guard !request.entry.isDirectory else { return nil }
        if let image = cached(request) { return image }

        let pixels = min(request.size * scale, maxPixels)
        let generatorRequest = QLThumbnailGenerator.Request(
            fileAt: request.entry.url, size: CGSize(width: request.size, height: request.size),
            scale: pixels / request.size, representationTypes: .thumbnail
        )
        guard let image = await generate(generatorRequest) else { return nil }
        // The cost is the maximum number of bytes that the picture can have.
        cache.setObject(image, forKey: key(request), cost: Int(pixels * pixels * 4))
        return image
    }

    private nonisolated static func generate(_ request: QLThumbnailGenerator.Request) async -> NSImage? {
        try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    /// A changed file has a different date, so it gets a new thumbnail.
    private static func key(_ request: Request) -> NSString {
        "\(request.entry.url.path)|\(request.entry.modified?.timeIntervalSince1970 ?? 0)|\(request.size)" as NSString
    }
}
