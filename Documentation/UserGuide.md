# MetaFetch User Guide

MetaFetch tags MP4 files with movie or TV episode metadata. It does not delete your files. When saving, it updates metadata in place when possible or writes a tagged replacement copy through AVFoundation when needed.

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

## In-App Help

Use the `Help` toolbar button for a quick version of this guide inside MetaFetch.

## Troubleshooting

- If search returns the wrong title, edit the search field and search again.
- If TV mode only finds the series, add an episode code like `S01E03`.
- If the sidebar is hidden, use `Hide Sidebar` / `Show Sidebar` in the toolbar.
- If saving is slow, turn off poster artwork and use `Fast Save Metadata`.
- If the app feels stuck on a bad batch, use `Start Over` to clear the queue and choose a mode again.
