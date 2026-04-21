import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ArtworkPipeline {
    static let shared = ArtworkPipeline()

    private static let allowedHostSuffixes = [
        "wikimedia.org",
        "tvmaze.com",
    ]
    private static let maximumArtworkBytes = 8 * 1024 * 1024
    private static let maximumCachedArtworkItems = 80

    private var preparedArtworkByURL: [URL: Data] = [:]
    private var preparedArtworkAccessOrder: [URL] = []
    private var inFlightTasks: [URL: Task<Data?, Error>] = [:]

    func prefetch(urls: [URL]) {
        let uniqueURLs = urls.reduce(into: [URL]()) { partialResult, url in
            if !partialResult.contains(url) {
                partialResult.append(url)
            }
        }

        for url in uniqueURLs {
            Task(priority: .utility) {
                _ = try? await self.preparedArtwork(for: url)
            }
        }
    }

    func preparedArtwork(for url: URL?) async throws -> Data? {
        guard let url else {
            return nil
        }

        if let cached = preparedArtworkByURL[url] {
            markArtworkCacheAccess(for: url)
            return cached
        }

        if let task = inFlightTasks[url] {
            return try await task.value
        }

        let task = Task<Data?, Error>(priority: .utility) {
            guard Self.isAllowedArtworkURL(url) else {
                return nil
            }

            let data = try await Self.downloadBoundedArtwork(from: url)
            guard !data.isEmpty else {
                return nil
            }

            return Self.downsampledArtwork(from: data)
        }

        inFlightTasks[url] = task
        defer {
            inFlightTasks[url] = nil
        }

        let preparedArtwork = try await task.value
        if let preparedArtwork {
            cache(preparedArtwork, for: url)
        }

        return preparedArtwork
    }

    private func cache(_ artwork: Data, for url: URL) {
        preparedArtworkByURL[url] = artwork
        markArtworkCacheAccess(for: url)

        while preparedArtworkAccessOrder.count > Self.maximumCachedArtworkItems,
              let evictedURL = preparedArtworkAccessOrder.first {
            preparedArtworkAccessOrder.removeFirst()
            preparedArtworkByURL.removeValue(forKey: evictedURL)
        }
    }

    private func markArtworkCacheAccess(for url: URL) {
        preparedArtworkAccessOrder.removeAll { $0 == url }
        preparedArtworkAccessOrder.append(url)
    }

    private static func isAllowedArtworkURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }

        return allowedHostSuffixes.contains { suffix in
            host == suffix || host.hasSuffix(".\(suffix)")
        }
    }

    private static func downloadBoundedArtwork(from url: URL) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 15
        )
        request.setValue("image/jpeg,image/png,image/webp;q=0.9", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              httpResponse.mimeType?.lowercased().hasPrefix("image/") == true else {
            return Data()
        }

        if httpResponse.expectedContentLength > maximumArtworkBytes {
            return Data()
        }

        var data = Data()
        data.reserveCapacity(min(max(Int(httpResponse.expectedContentLength), 0), maximumArtworkBytes))

        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumArtworkBytes {
                return Data()
            }
        }

        return data
    }

    private static func downsampledArtwork(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 900,
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.82,
        ]

        CGImageDestinationAddImage(
            destination,
            thumbnail,
            destinationOptions as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return outputData as Data
    }
}
