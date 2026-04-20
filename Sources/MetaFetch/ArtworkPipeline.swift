import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ArtworkPipeline {
    static let shared = ArtworkPipeline()

    private var preparedArtworkByURL: [URL: Data] = [:]
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
            return cached
        }

        if let task = inFlightTasks[url] {
            return try await task.value
        }

        let task = Task<Data?, Error>(priority: .utility) {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let (data, _) = try await URLSession.shared.data(for: request)
            guard !data.isEmpty else {
                return nil
            }

            return Self.downsampledArtwork(from: data) ?? data
        }

        inFlightTasks[url] = task
        defer {
            inFlightTasks[url] = nil
        }

        let preparedArtwork = try await task.value
        if let preparedArtwork {
            preparedArtworkByURL[url] = preparedArtwork
        }

        return preparedArtwork
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
