import Foundation

enum MediaLibraryMode: String, CaseIterable, Identifiable, Sendable {
    case movie
    case tvShow

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .movie:
            return "Movie"
        case .tvShow:
            return "TV Show"
        }
    }

    var badgeLabel: String {
        switch self {
        case .movie:
            return "MOVIE"
        case .tvShow:
            return "TV"
        }
    }

    var iconName: String {
        switch self {
        case .movie:
            return "film.stack"
        case .tvShow:
            return "tv"
        }
    }

    var sidebarHeading: String {
        switch self {
        case .movie:
            return "Movie\nMetadata Deck"
        case .tvShow:
            return "TV Episode\nMetadata Deck"
        }
    }

    var sidebarDescription: String {
        switch self {
        case .movie:
            return "Drag in tapes, tune the title, pick the right movie card, and stamp the file with fresh metadata."
        case .tvShow:
            return "Drag in episodes, keep the show + episode code sharp, pick the right match, and stamp the MP4 with episode metadata."
        }
    }

    var statsReadyLabel: String {
        switch self {
        case .movie:
            return "Ready"
        case .tvShow:
            return "Matched"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .movie:
            return "Stamp Your MP4s Like It’s 1999"
        case .tvShow:
            return "Tag Episodes Like A Prime-Time Pro"
        }
    }

    var emptyStateCopy: String {
        switch self {
        case .movie:
            return "Drag in movie files, search the title, browse bright matching cards, and write the chosen metadata back into the file with a VHS-era glow."
        case .tvShow:
            return "Drag in episode files, confirm the show and episode match, browse bright cards, and write TV-ready metadata back into the MP4."
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .movie:
            return "Movie title"
        case .tvShow:
            return "Show title or Show Title S01E03"
        }
    }

    var searchHelperCopy: String {
        switch self {
        case .movie:
            return "We clean up the filename first, but you can dial in the title manually before pulling fresh matches."
        case .tvShow:
            return "We clean up the filename first. Include an episode code like S01E03 when you want an exact episode instead of a series-level match."
        }
    }

    var searchingMatchesLabel: String {
        switch self {
        case .movie:
            return "Searching movie matches..."
        case .tvShow:
            return "Searching show and episode matches..."
        }
    }

    var dragTitle: String {
        switch self {
        case .movie:
            return "Drag MP4 Movies Here"
        case .tvShow:
            return "Drag MP4 Episodes Here"
        }
    }

    var dragBody: String {
        switch self {
        case .movie:
            return "Feed the metadata machine with a fresh batch of movie files."
        case .tvShow:
            return "Feed the metadata machine with a fresh batch of episode files."
        }
    }

    var selectionPrompt: String {
        switch self {
        case .movie:
            return "Choose one of the movie cards on the left to preview the metadata that will get written into the MP4."
        case .tvShow:
            return "Choose an episode or series card on the left to preview the metadata that will get written into the MP4."
        }
    }

    var emptyRackCopy: String {
        switch self {
        case .movie:
            return "Search results will land here after the title lookup finishes."
        case .tvShow:
            return "Episode and series matches will land here after the lookup finishes."
        }
    }

    var needsMatchCopy: String {
        switch self {
        case .movie:
            return "Needs a match"
        case .tvShow:
            return "Needs a tag"
        }
    }

    var importNotice: String {
        switch self {
        case .movie:
            return "Choose Movie or TV Show before importing files."
        case .tvShow:
            return "Choose Movie or TV Show before importing files."
        }
    }

    var saveSelectionError: String {
        switch self {
        case .movie:
            return "Choose a movie match before saving."
        case .tvShow:
            return "Choose an episode or series match before saving."
        }
    }

    var emptyQueryError: String {
        switch self {
        case .movie:
            return "Enter a movie title to search."
        case .tvShow:
            return "Enter a show title or include an episode code like S01E03."
        }
    }

    var noResultsError: String {
        switch self {
        case .movie:
            return "No movie matches came back. Try removing the year or shortening the title."
        case .tvShow:
            return "No TV matches came back. Try the series title, or add an episode code like S01E03."
        }
    }

    var modePickerSummary: String {
        switch self {
        case .movie:
            return "Search and stamp feature films."
        case .tvShow:
            return "Search and stamp TV episodes."
        }
    }

    var modePickerDetail: String {
        switch self {
        case .movie:
            return "Best for standalone films and movie collections."
        case .tvShow:
            return "Best for files like Show.Name.S01E03.mp4."
        }
    }
}

enum MediaSearchKind: String, Hashable, Sendable {
    case movie
    case tvEpisode
    case tvSeries

    var label: String {
        switch self {
        case .movie:
            return "Movie"
        case .tvEpisode:
            return "Episode"
        case .tvSeries:
            return "Series"
        }
    }
}
