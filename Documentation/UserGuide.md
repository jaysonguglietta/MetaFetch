# MetaFetch User Guide

MetaFetch tags MP4 files with movie or TV episode metadata. It does not delete your files. When saving, it updates the original file in place when possible or writes a tagged temporary copy through AVFoundation and replaces the original when needed.

For speed, MetaFetch does not create a sidecar safety backup before saving. Metadata-only saves write directly to the original MP4 header. Full container rewrites still write a temporary tagged copy first, then replace the original when export finishes.

After every save, MetaFetch reads the MP4 back and verifies that core tags such as title and show name actually persisted. If a metadata-only fast save reports success but the tags are not readable afterward, MetaFetch falls back to a full container rewrite instead of silently leaving the file untagged.

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
5. Save metadata back to the MP4.

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
5. Save metadata back to the MP4.

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

## What Gets Written

MetaFetch writes the selected title, description, genre when available, media kind, and artwork when poster saving is enabled.

Movie files receive movie-style metadata. TV episode files receive episode-focused metadata such as show title, season number, episode number, and episode title when the source returns those fields.

## Search And Review Tips

- Shorter searches often work better than long release filenames.
- Add a year for remakes, reboots, or titles with many similarly named results.
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

`Fast Save Metadata` appears when poster artwork is off or unavailable. MetaFetch first tries a metadata-only header update. If the file does not support that path, it falls back to a full MP4 container rewrite.

`Save Metadata + Poster` includes artwork. This usually takes longer because AVFoundation may need to write a new MP4 container. The video and audio are passed through rather than re-encoded.

Fast saves work best when the MP4 has free space near the front of the container for metadata growth. Files converted with only `-movflags +faststart` often have a front `moov` atom but almost no padding, so larger tags or artwork may require a full rewrite.

If you create MP4s with FFmpeg before using MetaFetch, reserve metadata headroom during conversion:

```bash
-moov_size 16777216
```

That reserves about 16 MiB for later metadata edits. You can still lower this value if you never save artwork, or raise it if you use large posters.

## In-App Help

Use the `Help` toolbar button for a quick version of this guide inside MetaFetch. You can also choose `Help > MetaFetch Help` from the macOS menu bar or press `Command-Shift-?`.

## Updates

Use `Updates` in the toolbar or `Check for Updates...` from the app menu to ask GitHub whether a newer MetaFetch release is available.

MetaFetch compares the installed app version with the latest release tag in `jaysonguglietta/MetaFetch`. Tags like `v1.1` and `1.1` are both understood as version `1.1`.

If the newer release includes a `.dmg`, `.zip`, or `.pkg` asset, MetaFetch can download it to your Downloads folder and open it. The final install remains visible and user-confirmed so macOS does not silently replace the app while it is running.

If the update checker says a release has no installable asset, open the release page and download the app manually.

## Keyboard Shortcuts

- `Command-Shift-?`: Open MetaFetch Help.
- `Command-Option-S`: Show or hide the sidebar.

## Troubleshooting

- If search returns the wrong title, edit the search field and search again.
- If TV mode only finds the series, add an episode code like `S01E03`.
- If the sidebar is hidden, use `Hide Sidebar` / `Show Sidebar` in the toolbar.
- If saving is slow, turn off poster artwork and use `Fast Save Metadata`.
- If a newly converted MP4 never accepts tags quickly, rebuild it with MP4 metadata headroom such as `-moov_size 16777216`.
- If update checking fails, confirm you can reach GitHub and that the latest release includes a `.dmg`, `.zip`, or `.pkg` asset.
- If the app feels stuck on a bad batch, use `Start Over` to clear the queue and choose a mode again.
- If you see old `.metafetch-backup-*` files, they came from an earlier MetaFetch build and are no longer created by the current speed-first save path.

## Feature Suggestions

See [Feature Suggestions](FeatureSuggestions.md) for a prioritized list of product improvements.
