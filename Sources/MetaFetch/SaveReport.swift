import Foundation

struct MetadataWriteOptions: Sendable {
    var createSafetyBackup: Bool

    static let speedFirst = MetadataWriteOptions(createSafetyBackup: false)
}

enum MetadataWritePath: String, Sendable {
    case nativeMetadataOnly
    case nativeContainerRewrite
    case avFoundationRewrite

    var label: String {
        switch self {
        case .nativeMetadataOnly:
            return "Fast metadata-only"
        case .nativeContainerRewrite:
            return "Native container rewrite"
        case .avFoundationRewrite:
            return "AVFoundation rewrite"
        }
    }

    var detail: String {
        switch self {
        case .nativeMetadataOnly:
            return "Updated the existing MP4 header without rewriting media data."
        case .nativeContainerRewrite:
            return "Rebuilt the MP4 container without re-encoding video or audio."
        case .avFoundationRewrite:
            return "Used AVFoundation passthrough export for an unusual MP4 layout."
        }
    }
}

struct MetadataWriteOutcome: Sendable {
    let path: MetadataWritePath
    let includedArtwork: Bool
    let backupURL: URL?
}

struct SaveReport: Identifiable, Sendable {
    let id = UUID()
    let createdAt: Date
    let entries: [SaveReportEntry]

    var successCount: Int {
        entries.filter(\.didSucceed).count
    }

    var failureCount: Int {
        entries.count - successCount
    }

    var summary: String {
        if entries.isEmpty {
            return "No files were saved."
        }

        if failureCount == 0 {
            return "Saved and verified \(successCount) file\(successCount == 1 ? "" : "s")."
        }

        return "Saved \(successCount) of \(entries.count) file\(entries.count == 1 ? "" : "s"); \(failureCount) need\(failureCount == 1 ? "s" : "") attention."
    }

    func csvData() -> Data {
        let header = [
            "filename",
            "title",
            "status",
            "save_path",
            "included_artwork",
            "backup_path",
            "duration_seconds",
            "error",
            "file_path",
        ]
        let rows = entries.map { entry in
            [
                entry.filename,
                entry.title,
                entry.statusLabel,
                entry.pathLabel,
                entry.outcome?.includedArtwork == true ? "true" : "false",
                entry.outcome?.backupURL?.path ?? "",
                String(format: "%.3f", entry.duration),
                entry.errorMessage ?? "",
                entry.fileURL.path,
            ]
        }
        let csv = ([header] + rows)
            .map { $0.map(Self.csvEscaped).joined(separator: ",") }
            .joined(separator: "\n")
        return Data((csv + "\n").utf8)
    }

    func jsonData() throws -> Data {
        let payload = ExportPayload(
            createdAt: createdAt,
            summary: summary,
            successCount: successCount,
            failureCount: failureCount,
            entries: entries.map(ExportEntry.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private static func csvEscaped(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    private struct ExportPayload: Encodable {
        let createdAt: Date
        let summary: String
        let successCount: Int
        let failureCount: Int
        let entries: [ExportEntry]
    }

    private struct ExportEntry: Encodable {
        let filename: String
        let title: String
        let status: String
        let savePath: String
        let includedArtwork: Bool
        let backupPath: String?
        let durationSeconds: Double
        let error: String?
        let filePath: String

        init(_ entry: SaveReportEntry) {
            filename = entry.filename
            title = entry.title
            status = entry.statusLabel
            savePath = entry.pathLabel
            includedArtwork = entry.outcome?.includedArtwork == true
            backupPath = entry.outcome?.backupURL?.path
            durationSeconds = entry.duration
            error = entry.errorMessage
            filePath = entry.fileURL.path
        }
    }
}

struct SaveReportEntry: Identifiable, Sendable {
    let id = UUID()
    let filename: String
    let fileURL: URL
    let title: String
    let outcome: MetadataWriteOutcome?
    let errorMessage: String?
    let duration: TimeInterval

    var didSucceed: Bool {
        outcome != nil && errorMessage == nil
    }

    var statusLabel: String {
        didSucceed ? "Verified" : "Failed"
    }

    var pathLabel: String {
        outcome?.path.label ?? "Not written"
    }

    var durationLabel: String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: Measurement(value: duration, unit: UnitDuration.seconds))
    }
}

struct MP4HeadroomInspection: Sendable {
    enum Status: Sendable {
        case enough
        case needsRewrite
        case unavailable(String)
    }

    let status: Status
    let reservedBytes: UInt64?
    let requiredBytes: UInt64?

    var headline: String {
        switch status {
        case .enough:
            return "Header room looks good"
        case .needsRewrite:
            return "Poster save may rewrite the container"
        case .unavailable:
            return "Headroom could not be inspected"
        }
    }

    var detail: String {
        switch status {
        case .enough:
            return "This MP4 appears to have enough reserved metadata space for the selected tags and artwork."
        case .needsRewrite:
            return "The selected metadata is larger than the reserved MP4 header space, so MetaFetch may rebuild the container without re-encoding media. For future conversions, reserve metadata room with FFmpeg: `-moov_size 16777216`."
        case .unavailable(let message):
            return message
        }
    }
}

protocol MP4HeadroomInspecting: Sendable {
    func inspect(
        fileURL: URL,
        result: MediaSearchResult,
        includeArtwork: Bool
    ) async -> MP4HeadroomInspection
}

struct MP4HeadroomInspector: MP4HeadroomInspecting {
    private let atomWriter = MP4AtomMetadataWriter()

    func inspect(
        fileURL: URL,
        result: MediaSearchResult,
        includeArtwork: Bool
    ) async -> MP4HeadroomInspection {
        do {
            let artworkData = includeArtwork
                ? try await ArtworkPipeline.shared.preparedArtwork(for: result.artworkURL)
                : nil
            return try atomWriter.inspectHeadroom(
                at: fileURL,
                using: result,
                artworkData: artworkData
            )
        } catch {
            return MP4HeadroomInspection(
                status: .unavailable(error.localizedDescription),
                reservedBytes: nil,
                requiredBytes: nil
            )
        }
    }
}
