import CryptoKit
import Foundation

@MainActor
enum DiagnosticsExporter {
    static func data(
        appVersion: String,
        files: [MovieFileEntry],
        providerHealth: [ProviderHealthRecord],
        taggingHistory: [TaggingHistoryRecord]
    ) throws -> Data {
        var generator = SystemRandomNumberGenerator()
        let redactionSalt = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let payload = Payload(
            generatedAt: Date(),
            appVersion: appVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            locale: Locale.current.identifier,
            queue: files.map { file in
                QueueItem(
                    fileID: hash(file.fileURL.standardizedFileURL.path, salt: redactionSalt),
                    mode: file.mediaMode.rawValue,
                    assetRole: file.assetRole.rawValue,
                    status: file.statusMessage,
                    hasError: file.errorMessage != nil,
                    selectedProvider: file.selectedResult?.sourceName,
                    selectedConfidence: file.selectedResult?.matchConfidence.rawValue,
                    lastSavePath: file.lastSaveOutcome?.path.rawValue
                )
            },
            providers: providerHealth.map { record in
                ProviderItem(
                    name: record.providerName,
                    searchedCount: record.searchedCount,
                    skippedCount: record.skippedCount,
                    failedCount: record.failedCount,
                    lastStatus: record.lastStatus.rawValue,
                    lastUpdated: record.lastUpdated
                )
            },
            recentSaves: taggingHistory.prefix(20).map { record in
                SaveItem(
                    savedAt: record.savedAt,
                    fileID: hash(record.filePath, salt: redactionSalt),
                    mode: record.mode,
                    source: record.sourceName,
                    writePath: record.writePath,
                    includedArtwork: record.includedArtwork
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private static func hash(_ value: String, salt: Data) -> String {
        SHA256.hash(data: salt + Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct Payload: Encodable {
        let generatedAt: Date
        let appVersion: String
        let osVersion: String
        let locale: String
        let queue: [QueueItem]
        let providers: [ProviderItem]
        let recentSaves: [SaveItem]
        let privacyNotice = "No API keys, filenames, or filesystem paths are included. Per-export salted file identifiers cannot be correlated across bundles."
    }

    private struct QueueItem: Encodable {
        let fileID: String
        let mode: String
        let assetRole: String
        let status: String
        let hasError: Bool
        let selectedProvider: String?
        let selectedConfidence: String?
        let lastSavePath: String?
    }

    private struct ProviderItem: Encodable {
        let name: String
        let searchedCount: Int
        let skippedCount: Int
        let failedCount: Int
        let lastStatus: String
        let lastUpdated: Date
    }

    private struct SaveItem: Encodable {
        let savedAt: Date
        let fileID: String
        let mode: String
        let source: String
        let writePath: String
        let includedArtwork: Bool
    }
}
