import Foundation

struct SeasonReconciliationReport: Sendable {
    enum RowStatus: String, Sendable {
        case matched = "Matched"
        case missingFile = "Missing File"
        case duplicateFile = "Duplicate"
        case unknownEpisode = "Unknown Episode"

        var needsAttention: Bool { self != .matched }
    }

    struct Row: Identifiable, Sendable {
        let id: String
        let episodeNumber: Int?
        let episodeTitle: String
        let providerResult: MediaSearchResult?
        let localFileIDs: [UUID]
        let localFilenames: [String]
        let status: RowStatus

        var episodeCode: String {
            guard let episodeNumber else { return "?" }
            return String(format: "E%02d", episodeNumber)
        }

        var canApply: Bool {
            status == .matched && providerResult != nil && localFileIDs.count == 1
        }

        var plannedAction: String {
            switch status {
            case .matched:
                return "Apply provider metadata to one local file"
            case .missingFile:
                return "No change - add the missing local episode"
            case .duplicateFile:
                return "No change - resolve duplicate local files"
            case .unknownEpisode:
                return "No change - review the local episode number"
            }
        }
    }

    let seriesTitle: String
    let seasonNumber: Int
    let rows: [Row]

    var matchedCount: Int { rows.filter { $0.status == .matched }.count }
    var attentionCount: Int { rows.filter { $0.status.needsAttention }.count }

    func csvData(createdAt: Date = Date()) -> Data {
        let generatedAt = ISO8601DateFormatter().string(from: createdAt)
        let header = [
            "generated_at",
            "series",
            "season",
            "episode",
            "episode_title",
            "status",
            "planned_action",
            "will_apply",
            "provider",
            "provider_url",
            "local_file_count",
            "local_filenames",
        ]
        let exportRows = rows.map { row in
            [
                generatedAt,
                seriesTitle,
                String(seasonNumber),
                row.episodeCode,
                row.episodeTitle,
                row.status.rawValue,
                row.plannedAction,
                row.canApply ? "true" : "false",
                row.providerResult?.sourceName ?? "",
                row.providerResult?.sourceURL?.absoluteString ?? "",
                String(row.localFilenames.count),
                row.localFilenames.joined(separator: " | "),
            ]
        }
        return CSVEncoding.data(rows: [header] + exportRows)
    }

    func jsonData(createdAt: Date = Date()) throws -> Data {
        let payload = ExportPayload(
            generatedAt: createdAt,
            seriesTitle: seriesTitle,
            seasonNumber: seasonNumber,
            matchedCount: matchedCount,
            attentionCount: attentionCount,
            rows: rows.map(ExportRow.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private struct ExportPayload: Encodable {
        let generatedAt: Date
        let seriesTitle: String
        let seasonNumber: Int
        let matchedCount: Int
        let attentionCount: Int
        let rows: [ExportRow]
    }

    private struct ExportRow: Encodable {
        let episodeCode: String
        let episodeNumber: Int?
        let episodeTitle: String
        let status: String
        let plannedAction: String
        let willApply: Bool
        let provider: String?
        let providerURL: String?
        let localFilenames: [String]

        init(_ row: Row) {
            episodeCode = row.episodeCode
            episodeNumber = row.episodeNumber
            episodeTitle = row.episodeTitle
            status = row.status.rawValue
            plannedAction = row.plannedAction
            willApply = row.canApply
            provider = row.providerResult?.sourceName
            providerURL = row.providerResult?.sourceURL?.absoluteString
            localFilenames = row.localFilenames
        }
    }
}

@MainActor
enum SeasonReconciler {
    static func build(
        seriesTitle: String,
        seasonNumber: Int,
        providerEpisodes: [MediaSearchResult],
        localFiles: [MovieFileEntry]
    ) -> SeasonReconciliationReport {
        let localByEpisode = Dictionary(grouping: localFiles.filter {
            $0.parsedCurrentQuery.seasonNumber == seasonNumber && $0.parsedCurrentQuery.episodeNumber != nil
        }) { $0.parsedCurrentQuery.episodeNumber! }

        var rows = providerEpisodes.map { episode -> SeasonReconciliationReport.Row in
            let number = episode.episodeNumber
            let files = number.flatMap { localByEpisode[$0] } ?? []
            let status: SeasonReconciliationReport.RowStatus = files.isEmpty
                ? .missingFile
                : (files.count == 1 ? .matched : .duplicateFile)
            return SeasonReconciliationReport.Row(
                id: "provider-\(episode.trackId)",
                episodeNumber: number,
                episodeTitle: episode.trackName,
                providerResult: episode,
                localFileIDs: files.map(\.id),
                localFilenames: files.map(\.filename),
                status: status
            )
        }

        let providerNumbers = Set(providerEpisodes.compactMap(\.episodeNumber))
        let unknownFiles = localFiles.filter {
            guard $0.parsedCurrentQuery.seasonNumber == seasonNumber,
                  let episode = $0.parsedCurrentQuery.episodeNumber else { return false }
            return !providerNumbers.contains(episode)
        }
        rows += unknownFiles.map { file in
            SeasonReconciliationReport.Row(
                id: "local-\(file.id.uuidString)",
                episodeNumber: file.parsedCurrentQuery.episodeNumber,
                episodeTitle: "Not listed by provider",
                providerResult: nil,
                localFileIDs: [file.id],
                localFilenames: [file.filename],
                status: .unknownEpisode
            )
        }

        rows.sort { ($0.episodeNumber ?? Int.max) < ($1.episodeNumber ?? Int.max) }
        return SeasonReconciliationReport(
            seriesTitle: seriesTitle,
            seasonNumber: seasonNumber,
            rows: rows
        )
    }
}
