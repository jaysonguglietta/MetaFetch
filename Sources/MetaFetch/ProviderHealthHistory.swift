import Foundation

struct ProviderHealthRecord: Codable, Identifiable, Equatable, Sendable {
    var providerName: String
    var searchedCount: Int
    var skippedCount: Int
    var failedCount: Int
    var lastStatus: MetadataProviderDiagnostic.Status
    var lastDetail: String
    var lastUpdated: Date

    var id: String {
        providerName
    }

    var summary: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relativeDate = formatter.localizedString(for: lastUpdated, relativeTo: Date())

        return "\(searchedCount) searched / \(failedCount) failed / \(skippedCount) skipped • last \(lastStatus.rawValue) \(relativeDate)"
    }
}

enum ProviderHealthHistory {
    private static let storageKey = "MetaFetchProviderHealthHistory"

    static func records() -> [ProviderHealthRecord] {
        loadRecords().values.sorted {
            $0.providerName.localizedStandardCompare($1.providerName) == .orderedAscending
        }
    }

    static func record(_ diagnostics: [MetadataProviderDiagnostic]) {
        guard !diagnostics.isEmpty else {
            return
        }

        var recordsByProvider = loadRecords()
        let now = Date()

        for diagnostic in diagnostics {
            var record = recordsByProvider[diagnostic.providerName] ?? ProviderHealthRecord(
                providerName: diagnostic.providerName,
                searchedCount: 0,
                skippedCount: 0,
                failedCount: 0,
                lastStatus: diagnostic.status,
                lastDetail: diagnostic.detail,
                lastUpdated: now
            )

            switch diagnostic.status {
            case .searched:
                record.searchedCount += 1
            case .skipped:
                record.skippedCount += 1
            case .failed:
                record.failedCount += 1
            }

            record.lastStatus = diagnostic.status
            record.lastDetail = diagnostic.detail
            record.lastUpdated = now
            recordsByProvider[diagnostic.providerName] = record
        }

        saveRecords(recordsByProvider)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func loadRecords() -> [String: ProviderHealthRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([String: ProviderHealthRecord].self, from: data) else {
            return [:]
        }

        return records
    }

    private static func saveRecords(_ records: [String: ProviderHealthRecord]) {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
