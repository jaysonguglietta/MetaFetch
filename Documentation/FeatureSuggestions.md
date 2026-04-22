# MetaFetch Feature Suggestions

This is a practical roadmap for turning MetaFetch from a fast tagging utility into a calmer, safer media-library tool.

## Highest Value

- Optional safety mode: Add a preference to create recovery backups for users who prefer maximum protection over fastest saves.
- Manual metadata editor: Let users tweak title, sort title, synopsis, genre, release date, artwork, season, and episode before saving.
- Save report: After `Save All Tagged`, show which files saved, failed, used fast metadata-only writes, or needed full MP4 rewrites.
- MP4 headroom check: Detect files with little or no metadata padding and explain when a full rewrite will be required.
- Batch folder import: Let users drop a season folder and automatically detect show, season, and episode from folder context.

## Usability Polish

- Confidence filters: Add quick filters for `Exact`, `Review`, `Needs Review`, `Series Only`, and `Saved`.
- Retry failed saves: Add a one-click retry for files that fail to write.
- Clear completed: Remove saved files from the queue when the user is done reviewing them.
- Better empty states: Show mode-specific examples directly in the drop zone before files are loaded.
- Sparkle updater: Replace the lightweight GitHub Releases downloader with a fully signed Sparkle appcast for automatic app replacement.

## Metadata Power Features

- Custom artwork picker: Allow dragging a poster image onto a result before saving.
- Alternate sources: Add TMDb or OMDb as optional providers for richer poster and release metadata.
- Ratings and content advisory: Save ratings when a source supports them.
- Chapter and extras awareness: Detect files that look like extras, trailers, or specials and avoid bad auto-matches.

## Library Workflow

- Watch folder mode: Monitor a folder and queue new MP4 files automatically.
- Rename after tagging: Optionally rename files using a template like `Show - S02E04 - Episode Title.mp4`.
- Preferences: Remember default mode, artwork setting, safety-vs-speed save setting, and last import folder.
- History: Keep a small local log of tagged files and selected source URLs.
