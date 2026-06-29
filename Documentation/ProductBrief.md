# MetaFetch Product Brief

## Target Users

- Home media collectors who convert or organize local movie and TV episode files.
- Power users who want Apple/iTunes-style MP4 metadata without maintaining a full media server.
- Users batch-tagging TV seasons who need fast, reviewable, low-friction workflows.

## Core Problem

Converted MP4 files often have poor or missing metadata. MetaFetch helps users identify the right movie or TV episode, review and edit the metadata, include poster artwork when desired, and write tags back to the original local MP4 with clear feedback about speed, verification, and failures.

## Primary Workflows

- Movie tagging: Choose Movie, import MP4 files, search by cleaned filename or manual title, select a match, edit fields, optionally choose a poster, save, and review the save report.
- TV episode tagging: Choose TV Show, import files or a season folder, detect show/season/episode hints, use trailing episode titles as a fallback for provider renumbering, search once for the series, review episode rows, apply shared choices, save all ready episodes, and inspect failures.
- Manual correction: Override provider fields, sort fields, release date, description, series data, and poster image before writing.
- Troubleshooting: Inspect current MP4 tags, provider diagnostics, MP4 headroom, save reports, provider health, and tagging history.

## Main Screens And Views

- Startup mode picker for Movie or TV Show.
- Drop zone and file queue for local writable MP4 intake.
- Search and result selection workspace with provider diagnostics.
- Manual metadata editor and current-vs-final tag preview.
- TV batch workspace with episode list plus Series, Seasons, Data, and Cover tabs.
- Save progress and save report views with retry and export actions.
- Advanced Preferences for providers, posters, backups, rename templates, watch folders, history, and diagnostics.
- In-app Help and update checker.

## Key Data Models

- `MovieFileEntry`: Imported file state, parsed filename hints, selected metadata, save status, progress, file identity, and verification data.
- `ParsedMediaQuery`: Filename/folder-derived title, year, season, episode, and trailing episode-title fallback hints.
- `MediaSearchResult`: Normalized provider result for movies, TV series, seasons, and episodes.
- `MetadataDraft`: User-editable metadata overlay applied before saving.
- `MP4CurrentMetadataSnapshot`: Read-back view of existing MP4 tags for diffing.
- `SaveReport`: Verified write outcome, path used, timing, poster state, retry information, and export data.
- `ProviderHealthRecord`: Local provider success/failure counters for support and troubleshooting.
- `TaggingHistoryRecord`: Local history of recent verified saves.

## Important Edge Cases

- Imported paths can be remote, symlinks, folders, duplicates, unreadable, unwritable, or changed after import.
- Search can return no results, ambiguous results, optional-provider failures, or series-only results for episode files.
- TV filenames may omit show names, use unusual episode codes, include specials, rely on folder context, or point to episodes that providers list under a rebranded show or different season.
- Artwork can be missing, oversized, redirected, invalid, or too large for fast MP4 header updates.
- MP4 containers may lack metadata headroom or use layouts that require a full rewrite.
- Saves can fail verification, be interrupted, or appear successful unless the app reads tags back afterward.
- Rename templates can collide with existing filenames or generate unsafe names.
- Update downloads can be missing, oversized, unsigned, or require user-confirmed installation.

## Assumptions

- MetaFetch is a native macOS desktop utility focused on local MP4 files.
- Default sources should work without bundled API keys; optional TMDb and OMDb keys are user-provided.
- Fast writes matter, so safety backups are optional rather than always-on.
- The app should prioritize visible review over hidden automation when metadata confidence is unclear.
- Responsive design means resilient desktop window layouts, not a separate mobile app.

## Done For This Version

This version is done when a user can import local MP4 movies or TV episodes, find usable metadata, review and edit fields, choose poster behavior, inspect current tags and MP4 headroom, save to the original file, verify the write, understand failures, export save reports, and use documentation or in-app help without hitting dead controls or unexplained states.

Engineering done means the app builds, tests pass, the generated app bundle verifies, security-sensitive network and file paths are bounded, and documentation reflects the shipped behavior.
