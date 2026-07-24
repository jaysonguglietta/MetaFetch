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
    }

    let seriesTitle: String
    let seasonNumber: Int
    let rows: [Row]

    var matchedCount: Int { rows.filter { $0.status == .matched }.count }
    var attentionCount: Int { rows.filter { $0.status.needsAttention }.count }
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
