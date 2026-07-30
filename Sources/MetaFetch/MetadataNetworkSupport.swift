import Foundation

enum BoundedJSONRequest {
    static let timeoutInterval: TimeInterval = 15
    private static let maximumResponseBytes = 4 * 1024 * 1024

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if response.expectedContentLength > maximumResponseBytes {
            throw URLError(.dataLengthExceedsMaximum)
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumResponseBytes))
        }

        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumResponseBytes {
                throw URLError(.dataLengthExceedsMaximum)
            }
        }

        return (data, response)
    }
}

actor TVMazeResponseCache {
    struct Response: Sendable {
        let data: Data
        let statusCode: Int
    }

    private struct CachedResponse: Sendable {
        let response: Response
        let expiresAt: Date
    }

    static let shared = TVMazeResponseCache()

    private let lifetime: TimeInterval = 15 * 60
    private let maximumEntries = 128
    private var responses: [URL: CachedResponse] = [:]
    private var inFlight: [URL: Task<Response, Error>] = [:]

    func response(for request: URLRequest) async throws -> Response {
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let now = Date()
        if let cached = responses[url], cached.expiresAt > now {
            return cached.response
        }
        responses[url] = nil

        if let task = inFlight[url] {
            return try await task.value
        }

        let task = Task<Response, Error> {
            let (data, urlResponse) = try await BoundedJSONRequest.data(for: request)
            guard let response = urlResponse as? HTTPURLResponse,
                  response.url?.scheme?.lowercased() == "https",
                  response.url?.host?.lowercased() == "api.tvmaze.com" else {
                throw URLError(.badServerResponse)
            }
            return Response(data: data, statusCode: response.statusCode)
        }
        inFlight[url] = task

        do {
            let response = try await task.value
            inFlight[url] = nil
            if (200..<300).contains(response.statusCode) {
                responses[url] = CachedResponse(
                    response: response,
                    expiresAt: now.addingTimeInterval(lifetime)
                )
                evictIfNeeded()
            }
            return response
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    private func evictIfNeeded() {
        guard responses.count > maximumEntries else {
            return
        }

        let overflow = responses.count - maximumEntries
        let oldestURLs = responses
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(overflow)
            .map(\.key)
        for url in oldestURLs {
            responses[url] = nil
        }
    }
}
