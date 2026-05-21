import Foundation

enum FileQueueFilter: String, CaseIterable, Identifiable {
    case all
    case exact
    case needsReview
    case seriesOnly
    case saved
    case failed
    case hasPoster

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .exact:
            return "Exact"
        case .needsReview:
            return "Needs Review"
        case .seriesOnly:
            return "Series Only"
        case .saved:
            return "Saved"
        case .failed:
            return "Failed"
        case .hasPoster:
            return "Has Poster"
        }
    }
}

enum MetadataProviderSource: String, CaseIterable, Identifiable {
    case automatic
    case wikipedia
    case tmdb
    case omdb

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .wikipedia:
            return "Wikipedia"
        case .tmdb:
            return "TMDb"
        case .omdb:
            return "OMDb"
        }
    }

    func priorityBonus(for sourceName: String) -> Int {
        let normalizedSource = sourceName.lowercased()

        switch self {
        case .automatic:
            return 0
        case .wikipedia:
            return normalizedSource == "wikipedia" ? 35 : 0
        case .tmdb:
            return normalizedSource == "tmdb" ? 35 : 0
        case .omdb:
            return normalizedSource == "omdb" ? 35 : 0
        }
    }
}

enum RenameTemplateDefaults {
    static let movie = "{title} ({year})"
    static let tv = "{series} - {season_episode} - {title}"
}
