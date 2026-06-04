import Foundation

struct TaggingHistoryRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let savedAt: Date
    let filename: String
    let filePath: String
    let title: String
    let mode: String
    let sourceName: String
    let writePath: String
    let includedArtwork: Bool

    init(
        savedAt: Date = Date(),
        filename: String,
        filePath: String,
        title: String,
        mode: String,
        sourceName: String,
        writePath: String,
        includedArtwork: Bool
    ) {
        self.id = UUID()
        self.savedAt = savedAt
        self.filename = filename
        self.filePath = filePath
        self.title = title
        self.mode = mode
        self.sourceName = sourceName
        self.writePath = writePath
        self.includedArtwork = includedArtwork
    }

    var summary: String {
        "\(mode) • \(sourceName) • \(writePath)\(includedArtwork ? " • poster" : "")"
    }
}

enum TaggingHistoryStore {
    private static let storageKey = "MetaFetchTaggingHistory"
    private static let maximumRecords = 50

    static func records() -> [TaggingHistoryRecord] {
        loadRecords()
    }

    static func record(_ record: TaggingHistoryRecord) {
        var records = loadRecords()
        records.insert(record, at: 0)
        if records.count > maximumRecords {
            records = Array(records.prefix(maximumRecords))
        }
        saveRecords(records)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static func csvData(from records: [TaggingHistoryRecord]) -> Data {
        let header = [
            "saved_at",
            "filename",
            "title",
            "mode",
            "source",
            "write_path",
            "included_artwork",
            "file_path",
        ]
        let formatter = ISO8601DateFormatter()
        let rows = records.map { record in
            [
                formatter.string(from: record.savedAt),
                record.filename,
                record.title,
                record.mode,
                record.sourceName,
                record.writePath,
                record.includedArtwork ? "true" : "false",
                record.filePath,
            ]
        }
        let csv = ([header] + rows)
            .map { $0.map(csvEscaped).joined(separator: ",") }
            .joined(separator: "\n")
        return Data((csv + "\n").utf8)
    }

    private static func loadRecords() -> [TaggingHistoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([TaggingHistoryRecord].self, from: data) else {
            return []
        }

        return records
    }

    private static func saveRecords(_ records: [TaggingHistoryRecord]) {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func csvEscaped(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}
