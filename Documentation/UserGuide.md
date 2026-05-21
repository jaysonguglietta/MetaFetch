# MetaFetch User Guide

MetaFetch tags MP4 files with movie or TV episode metadata. It does not delete your files. When saving, it updates the original file with Apple/iTunes-style MP4 metadata atoms when possible, or writes a tagged temporary copy and replaces the original when the container needs to be rebuilt.

For speed, MetaFetch does not create a sidecar safety backup by default. Metadata-only saves write directly to the original MP4 header. Container rebuilds still write a temporary tagged copy first, then replace the original when the rebuild finishes. If you want extra protection, enable `Create Safety Backups` from the `Options` toolbar menu before saving.

After every save, MetaFetch reads the MP4 back and verifies that core tags such as title and show name actually persisted. If a metadata-only fast save reports success but the tags are not readable afterward, MetaFetch falls back to a full container rewrite instead of silently leaving the file untagged.

MetaFetch also remembers the file identity when you import a file. If that path becomes a symlink, stops being a writable local MP4, or points to a different file before saving, MetaFetch stops before writing and asks you to remove and re-add the file.

## Choose A Deck

When MetaFetch opens, choose one mode:

- `Movie`: Use this for standalone films.
- `TV Show`: Use this for episode files.

If you picked the wrong mode, use `Start Over / Choose Movie or TV Show`. If files are already loaded, MetaFetch asks for confirmation first. This only clears the current queue inside the app.

## Movie Workflow

1. Choose `Movie`.
2. Drop one or more `.mp4` movie files.
3. Review the cleaned title query.
4. Pick the best Wikipedia match.
5. Edit title, sort title, genre, year, creator, description, or custom poster if the source needs a tweak.
6. Check poster headroom if artwork is selected and you care about save speed.
7. Save metadata back to the MP4 and review the save report.

Good filenames:

```text
The.Matrix.1999.1080p.BluRay.mp4
Mad.Max.Fury.Road.(2015).WEB-DL.mp4
```

If a title has multiple versions or remakes, include the release year in the search box before searching again.

## TV Workflow

1. Choose `TV Show`.
2. Drop one or more `.mp4` episode files.
3. Check the episode detection hint under the search box.
4. Pick the correct TVMaze episode result.
5. Edit title, sort title, series, sort series, season, episode, genre, year, network, description, or custom poster if needed.
6. Save metadata back to the MP4 and review the save report.

Good filenames:

```text
Severance.S02E04.mp4
Severance.2x04.mp4
```

Folder-aware examples:

```text
Severance/Season 2/Episode 04.mp4
Severance Season 2/E04.mp4
```

If MetaFetch shows `Series Only`, it found the show but not a specific episode. Add an episode code like `S02E04` to the search box and search again.

If you intentionally want to save a series-level result to an episode file, MetaFetch asks you to confirm that choice before the save button is enabled.

For 3 or 4 episodes from the same show, drop them together. MetaFetch switches the main workspace into a batch layout with the loaded files on one side and a shared show search on the other.

For a larger season, use `Add Season Folder` or drop a folder. MetaFetch recursively scans the folder for local writable `.mp4` files and ignores hidden files and non-video sidecars.

Search the show title once, then click the correct show card. MetaFetch applies that show name to each file while preserving each detected episode code, such as `S01E03` or `S01E04`, and searches for the matching episode per file.

Batch controls:

- `Search Show`: Finds shared show cards in the right-side search table.
- `Series`: Pick the show match that should drive the whole batch.
- `Seasons`: Review the loaded files by detected season and episode code, then jump into any row that needs attention.
- `Data`: Inspect the selected episode metadata and choose a different returned match for that file when needed.
- `Cover`: Choose episode-specific artwork or apply the selected series cover to every tagged episode.
- Clicking a show card applies that show to every loaded episode file.
- `Save # + Posters`: Saves every ready file that already has a selected episode match, including poster artwork when the source provides it.

## What Gets Written

MetaFetch writes the selected title, description, genre when available, media kind, and artwork when poster saving is enabled. These are written as MP4 `moov/udta/meta/ilst` atoms so Apple-style media apps can read them.

Movie files receive movie-style metadata from Wikipedia, including a downloaded synopsis/description, year, genre, director when it can be parsed, source link, and artwork when available. TV episode files receive episode-focused metadata from TVMaze, including episode title, show title, season number, episode number, downloaded episode description, network, source link, and episode or series artwork.

The `Downloaded Details` panel shows the source description. The `Manual Edit` panel shows the editable values that MetaFetch will actually write, including sort title, sort series, and an optional custom poster image. In TV batch mode, use the `Data` tab to review and edit the selected episode's downloaded details.

The `Tag Preview Diff` panel compares the provider values with the final edited values that will be written. Use it as a last sanity check before saving, especially after manual edits or batch-applied series choices.

## Metadata Providers

Movie search works without setup through Wikipedia/Wikimedia. TV search works without setup through TVMaze.

For broader movie coverage, open `Options > Metadata Providers` and add your own provider keys:

- `TMDb API Key`: Adds optional TMDb movie results and TMDb poster URLs.
- `OMDb API Key`: Adds optional IMDb-backed movie details such as director, rating, genre, plot, and poster.

Provider keys are stored locally in macOS Keychain. They are not bundled into the app, committed to the repository, or shared with GitHub. If a key is blank, MetaFetch skips that provider and continues using the remaining sources.

Use `Options > Advanced Preferences` to choose a preferred movie provider. The preferred provider receives a ranking boost, but MetaFetch still shows results from the other enabled sources.

## Search And Review Tips

- Shorter searches often work better than long release filenames.
- Add a year for remakes, reboots, or titles with many similarly named results.
- Add TMDb or OMDb keys if Wikipedia has weak coverage for a movie title.
- In TV mode, include `S01E03` or `2x07` when you want a specific episode result.
- Use `Open Source` before saving when two result cards look similar.

## Review Badges

- `Exact`: High-confidence match.
- `Review`: Plausible match that should be checked.
- `Needs Review`: Results are available, but no safe match is selected.
- `Series Only`: TV mode found a show-level result, not an episode-level result.
- `Saved`: Metadata was written successfully.

Use `Open Source` on result cards to inspect the source page before choosing a match.

## Save Speed

`Fast Save Metadata` appears when no poster artwork is available from the source. MetaFetch first tries its native MP4 atom writer, which can update metadata in the existing movie header when the file has enough headroom.

`Save Metadata + Poster` includes artwork. This may take longer because artwork needs more metadata space. If there is not enough header room, MetaFetch rebuilds the MP4 container and adjusts chunk offsets without re-encoding video or audio. AVFoundation remains a final fallback for unusual files.

Use `Check Poster Headroom` before saving artwork to estimate whether the selected tags and poster fit in the reserved MP4 header space. The save report confirms the actual path used: fast metadata-only, native container rewrite, or AVFoundation rewrite.

After every single or batch save, MetaFetch shows a save report with verified files, failures, duration, poster state, backup location when safety backups are enabled, and the write path used for each MP4. Use the toolbar `Report` button to reopen the latest report, or export it as CSV or JSON.

If a report has failures, use `Retry Failed` to rerun the failed rows or `Retry Without Posters` to attempt a faster metadata-only retry.

Fast saves work best when the MP4 has free space near the front of the container for metadata growth. Files converted with only `-movflags +faststart` often have a front `moov` atom but almost no padding, so larger tags or artwork may require a full rewrite.

If you create MP4s with FFmpeg before using MetaFetch, reserve metadata headroom during conversion:

```bash
-moov_size 16777216
```

That reserves about 16 MiB for later metadata edits. You can still lower this value if you never save artwork, or raise it if you use large posters.

## Advanced Preferences

Use `Options > Advanced Preferences` for power-user workflow controls:

- `Save poster artwork by default`: Controls the default poster behavior for newly imported files. You can still change poster saving per file.
- `Create safety backups before writing`: Creates recoverable sidecar backups before saves when protection matters more than speed.
- `Preferred movie provider`: Gives Wikipedia, TMDb, or OMDb a ranking boost without hiding other sources.
- `Auto-apply a clear exact show match`: Lets TV batch mode apply a confident show result across loaded episodes automatically.
- `Rename files after successful save`: Renames verified files using templates like `{title} ({year})` or `{series} - {season_episode} - {title}`.
- `Watch Folder`: Polls a selected folder and queues new local writable MP4 files automatically.

Queue filters are available in the sidebar and TV episode list. They filter loaded files by exact match, needs review, series-only, saved, failed, or has poster without removing anything.

## In-App Help

Use the `Help` toolbar button for a quick version of this guide inside MetaFetch. You can also choose `Help > MetaFetch Help` from the macOS menu bar or press `Command-Shift-?`.

## Updates

Use `Updates` in the toolbar or `Check for Updates...` from the app menu to ask GitHub whether a newer MetaFetch release is available.

MetaFetch compares the installed app version with the latest release tag in `jaysonguglietta/MetaFetch`. Tags like `v1.1` and `1.1` are both understood as version `1.1`.

If the newer release includes a `.dmg`, `.zip`, or `.pkg` asset, MetaFetch can download it to your Downloads folder and reveal it in Finder. It does not open downloaded installers automatically. Open the downloaded file only after you trust the GitHub release.

If the update checker says a release has no installable asset, open the release page and download the app manually.

## Keyboard Shortcuts

- `Command-Shift-?`: Open MetaFetch Help.
- `Command-Option-S`: Show or hide the sidebar.

## Troubleshooting

- If search returns the wrong title, edit the search field and search again.
- If source metadata is close but not perfect, use `Manual Edit` before saving instead of changing the search result.
- If TV mode only finds the series, add an episode code like `S01E03`.
- If a season folder imports nothing, make sure it contains local writable `.mp4` files and is not a symlink or package.
- If you are tagging several TV episodes, use the batch workspace to search the show once, apply it to all files, review badges, and save all selected matches with posters.
- If the sidebar is hidden, use `Hide Sidebar` / `Show Sidebar` in the toolbar.
- If saving is slow, use `Check Poster Headroom`; the MP4 may not have enough metadata space for a poster and may need a container rebuild.
- If a newly converted MP4 never accepts tags quickly, rebuild it with MP4 metadata headroom such as `-moov_size 16777216`.
- If MetaFetch says the file changed after import, remove that row and add the MP4 again. This protects against tagging the wrong filesystem object.
- If update checking fails, confirm you can reach GitHub and that the latest release includes a `.dmg`, `.zip`, or `.pkg` asset.
- If the app feels stuck on a bad batch, use `Start Over` to clear the queue and choose a mode again.
- If you enable `Create Safety Backups`, MetaFetch leaves `.metafetch-backup-*` files next to the original MP4 so you can recover manually if needed.

## Feature Suggestions

See [Feature Suggestions](FeatureSuggestions.md) for a prioritized list of product improvements.
