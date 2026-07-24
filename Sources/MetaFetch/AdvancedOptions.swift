import Foundation

enum MetadataProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case balanced
    case speed
    case archival
    case plex
    case jellyfin

    var id: Self { self }

    var label: String {
        switch self {
        case .balanced: "Balanced"
        case .speed: "Fast Library"
        case .archival: "Archival"
        case .plex: "Plex"
        case .jellyfin: "Jellyfin"
        }
    }

    var detail: String {
        switch self {
        case .balanced: "Posters on, manual review for anything below an exact match."
        case .speed: "Metadata-first saves, no safety copy, exact matches only."
        case .archival: "Posters and recoverable backups with conservative matching."
        case .plex: "Plex-friendly names, posters, sort fields, and exact-match automation."
        case .jellyfin: "Jellyfin-friendly episode names, posters, and strong-match review."
        }
    }

    var savesPosters: Bool { self != .speed }
    var createsBackups: Bool { self == .archival }
    var repairsHeadroom: Bool { self == .archival }
    var renamesAfterSave: Bool { self == .plex || self == .jellyfin }
    var confidenceRule: ConfidenceRule {
        switch self {
        case .speed, .plex: .exactOnly
        case .balanced, .archival, .jellyfin: .clearExact
        }
    }
}

enum ConfidenceRule: String, CaseIterable, Identifiable, Codable, Sendable {
    case clearExact
    case exactOnly
    case strongOrBetter
    case manual

    var id: Self { self }

    var label: String {
        switch self {
        case .clearExact: "Clear Exact"
        case .exactOnly: "Any Exact"
        case .strongOrBetter: "Strong or Better"
        case .manual: "Always Review"
        }
    }

    var detail: String {
        switch self {
        case .clearExact: "Auto-select only when an exact result leads the next result by 30 points."
        case .exactOnly: "Auto-select the first exact result."
        case .strongOrBetter: "Auto-select exact or strong results."
        case .manual: "Never auto-select a provider result."
        }
    }

    func accepts(_ result: MediaSearchResult, runnerUp: MediaSearchResult?) -> Bool {
        switch self {
        case .clearExact:
            guard result.matchConfidence == .exact else { return false }
            return runnerUp == nil || result.matchScore - (runnerUp?.matchScore ?? 0) >= 30
        case .exactOnly:
            return result.matchConfidence == .exact
        case .strongOrBetter:
            return result.matchConfidence != .possible
        case .manual:
            return false
        }
    }
}

struct RenamePreset: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var movieTemplate: String
    var tvTemplate: String

    static let builtIns: [RenamePreset] = [
        RenamePreset(
            id: "metafetch-standard",
            name: "MetaFetch Standard",
            movieTemplate: "{title} ({year})",
            tvTemplate: "{series} - {season_episode} - {title}"
        ),
        RenamePreset(
            id: "plex",
            name: "Plex",
            movieTemplate: "{title} ({year})",
            tvTemplate: "{series} - {season_episode} - {title}"
        ),
        RenamePreset(
            id: "compact",
            name: "Compact",
            movieTemplate: "{sort_title} {year}",
            tvTemplate: "{sort_series} {season_episode} {title}"
        ),
    ]
}

enum MediaAssetRole: String, CaseIterable, Codable, Sendable {
    case primary
    case trailer
    case featurette
    case deletedScene
    case interview
    case sample
    case extra

    var label: String {
        switch self {
        case .primary: "Main Feature"
        case .trailer: "Trailer"
        case .featurette: "Featurette"
        case .deletedScene: "Deleted Scene"
        case .interview: "Interview"
        case .sample: "Sample"
        case .extra: "Extra"
        }
    }

    var allowsAutomaticMatch: Bool { self == .primary }
}

enum MediaAssetRoleDetector {
    static func role(for fileURL: URL) -> MediaAssetRole {
        let name = fileURL.deletingPathExtension().lastPathComponent.lowercased()
        let rules: [(MediaAssetRole, String)] = [
            (.deletedScene, #"\bdeleted[ ._-]*scenes?\b"#),
            (.featurette, #"\b(featurette|behind[ ._-]*the[ ._-]*scenes|making[ ._-]*of)\b"#),
            (.trailer, #"\b(trailer|teaser)\b"#),
            (.interview, #"\b(interview|q[ ._-]*and[ ._-]*a|q&a)\b"#),
            (.sample, #"\b(sample|preview)\b"#),
            (.extra, #"\b(extras?|bonus)\b"#),
        ]

        for (role, pattern) in rules where name.range(of: pattern, options: .regularExpression) != nil {
            return role
        }
        return .primary
    }
}

struct FolderImportGroup: Identifiable, Sendable {
    let showTitle: String
    let seasonNumber: Int?
    let fileIDs: [UUID]

    var id: String { "\(showTitle.lowercased())-\(seasonNumber ?? -1)" }
    var label: String {
        let season = seasonNumber.map { "Season \($0)" } ?? "Season not detected"
        return "\(showTitle) • \(season)"
    }
}
