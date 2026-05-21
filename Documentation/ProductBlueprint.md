# MetaFetch Product Blueprint

## App Goal

MetaFetch is a polished native macOS utility for tagging local MP4 movie and TV episode files. The app should let someone drop files, search by cleaned filename or manual title, review likely matches, choose artwork/details, and write Apple/iTunes-style metadata back to the original MP4 as quickly as the container safely allows.

The first screen is the working app experience: choose `Movie` or `TV Show`, then drop files and start tagging. MetaFetch is intentionally a focused desktop tool, not a media library, streaming app, or marketing site.

## Core Workflows

### Movie Tagging

1. Choose `Movie`.
2. Drop or pick one or more local writable MP4 files.
3. Review the cleaned search query derived from each filename.
4. Search Wikipedia/Wikimedia results plus optional TMDb and OMDb results when provider keys are configured.
5. Choose the best match after checking confidence, year, source, synopsis, and poster.
6. Adjust fields in the manual metadata editor when the source needs a tweak.
7. Check poster headroom when artwork is selected and speed matters.
8. Save metadata and optional poster artwork back to the MP4.
9. See progress, success, a save report, or a clear failure reason.

### TV Episode Tagging

1. Choose `TV Show`.
2. Drop one or more local writable MP4 episode files.
3. Let MetaFetch detect episode codes such as `S01E03`, `2x07`, or folder-based season context.
4. For a single file, search and choose the exact episode match.
5. For multiple files from one show, use the batch workspace to search the show once, apply it across detected episodes, review each episode, choose cover behavior, and save all ready files.
6. Import season folders when there are many episodes to queue.
7. Block accidental series-only saves for episode files unless the user explicitly confirms that choice.

### Updates And Help

1. Use in-app help for workflow guidance, save behavior, and troubleshooting.
2. Use the update checker to compare against GitHub Releases.
3. Download installable release assets to Downloads and reveal them in Finder, keeping installation user-confirmed.

## Key Screens

- Mode picker: The startup deck that chooses Movie or TV Show and sets the mental model before files are imported.
- Drop/import empty state: The primary file intake surface with examples and validation feedback.
- File queue/sidebar: The loaded MP4 list, save status, and quick navigation between files.
- Search results: Candidate metadata cards with artwork, source, confidence, match details, and source links.
- Selected metadata preview: The current match, downloaded description/details, poster state, and save action.
- Manual metadata editor: Per-file editable title, sort title, series, sort series, creator, genre, year, description, season, episode, and custom poster fields.
- Save path inspector: Poster-headroom check, safety-backup status, and last write outcome.
- TV batch workspace: A split layout with episode list on the left and shared search/review tools on the right.
- TV batch tabs: `Series`, `Seasons`, `Data`, and `Cover` for shared-show selection, episode review, metadata inspection, and artwork choices.
- Provider settings sheet: Optional TMDb and OMDb movie provider keys with clear enabled/disabled status.
- Advanced preferences sheet: Power controls for poster defaults, provider priority, safety backups, TV batch auto-apply, watch folders, and rename-after-save templates.
- Save report actions: Retry failed saves, retry failures without posters, and export reports.
- Help sheet: A concise in-app guide for workflows, shortcuts, save speed, updates, and troubleshooting.
- Update sheet: Release check status, newer-version details, download progress, and failure states.

## Data Models And Services

- `AppModel`: Main application state, imported file queue, selected mode, search/save orchestration, batch workflow, notices, and confirmation state.
- `MovieFileEntry`: One imported MP4 plus query text, parsed media hints, selected match, search results, save status, file identity, and progress labels.
- `MediaLibraryMode`: The user-selected workflow, currently movie or TV show.
- `ParsedMediaQuery`: Filename/folder-derived title, year, season, episode, and confidence hints.
- `MediaSearchResult`: A normalized metadata result from Wikipedia/Wikimedia, optional TMDb/OMDb, or TVMaze, including title, description, media kind, artwork URL, source URL, match quality, sort fields, and episode fields.
- `TVBatchTab`: The batch workspace sections used to keep multi-episode tagging reviewable.
- `MovieSearchService`: Network metadata lookups, provider-specific parsing, ranking, and result normalization.
- `ArtworkPipeline`: Bounded artwork fetch, MIME and host validation, downsampling, caching, and eviction.
- `MP4MetadataWriter`: Native MP4 atom write path, verification, and fallback container rewrite behavior.
- `UpdateService`: GitHub Releases version comparison, bounded asset download, and reveal-in-Finder install handoff.
- `MetadataDraft`: Editable per-file metadata applied over the selected provider result before writing.
- `SaveReport`: Single-save and batch-save outcomes including write path, duration, poster state, errors, and backup locations.
- `MP4HeadroomInspection`: A pre-save estimate of whether selected metadata/artwork fits in reserved MP4 header space.
- `MetadataProviderPreferences`: Local Keychain-backed provider key preferences used to enable optional TMDb and OMDb movie search without bundling secrets.
- `FileQueueFilter`: Sidebar and TV batch filtering for exact matches, review states, series-only rows, saved rows, failures, and poster availability.
- `MetadataProviderSource`: Provider preference for ranking movie results without hiding alternate sources.

## Important Edge Cases

- Dropped files can include duplicates, folders, symlinks, unsupported extensions, remote URLs, unreadable files, or unwritable files.
- Dropped folders can contain multiple seasons, non-video files, hidden files, or no writable MP4 files.
- A path can change after import; MetaFetch must re-check identity before saving so it does not tag the wrong object.
- Search results can be empty, ambiguous, stale by the time they return, or series-only when an episode is expected.
- Optional provider keys can be missing, revoked, rate limited, or configured incorrectly; MetaFetch should skip failing optional providers without breaking default search.
- TV filenames can omit show names, use folder context, include specials, or have malformed episode codes.
- Artwork can be absent, oversized, redirected to an unexpected host, invalid image data, or slow to download.
- MP4 files can have no metadata headroom, oversized `moov` atoms, unusual atom nesting, or layouts that require a full container rewrite.
- Save operations can be cancelled, interrupted, fail verification, or leave the user unsure whether tags persisted unless the app reads back after writing.
- Update releases can have no installable asset, oversized downloads, invalid URLs, or versions that compare differently with and without a leading `v`.
- Rename-after-save templates can collide with existing filenames or produce unsafe names; MetaFetch sanitizes names and adds suffixes.
- Watch folders can contain duplicates or unsupported files; MetaFetch imports only new validated MP4 files and leaves duplicates alone.

## Product Assumptions

- MetaFetch is currently a macOS app. Responsive design means the layout adapts across desktop window sizes rather than shipping an iPhone UI.
- The app should not use bundled sample media by default because the useful path starts with the user's local MP4 files and live metadata sources.
- Speed is prioritized by default, but safety backups can be enabled when the user wants a recoverable copy before writing.
- Wikipedia/Wikimedia and TVMaze are the no-key defaults. TMDb and OMDb are optional user-configured providers and no API keys are shipped in the app.
- GitHub Releases downloads are treated as user-confirmed installer handoffs, not silent self-replacement.

## Usability Principles

- Keep the next action obvious: choose a mode, drop files, search, select, save.
- Prefer visible review over hidden automation for ambiguous matches.
- Show progress during writes and avoid instant-success states when real file work is still pending.
- Make failures actionable: tell the user whether the issue is import validation, no results, artwork, MP4 layout, permissions, verification, or network reachability.
- Keep batch TV tagging calm by applying shared show choices across files while preserving per-episode review.

## Future Product Enhancements

- Add a true current-tag reader for current MP4 metadata versus new tag diff.
- Add custom release date handling beyond year-only edits.
- Add provider request telemetry for timeouts, authentication errors, rate limits, and response-size failures.
- Add rename preset management and a lightweight tagging history log.
- Replace the lightweight GitHub updater with a signed Sparkle appcast if fully automatic updates become a product requirement.
