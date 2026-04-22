# MetaFetch

MetaFetch is a native macOS SwiftUI app for tagging `.mp4` files with movie or TV episode metadata.

## Features

- Choose `Movie` or `TV Show` when the app starts.
- Drag and drop one or more `.mp4` files, or use the file picker.
- Clean filenames into searchable titles automatically.
- Detect TV episode codes like `S01E03` and `2x07`.
- Use folder context for TV files like `Severance/Season 2/Episode 04.mp4`.
- Review match confidence, result source, and source page links before saving.
- Write title, synopsis, genre, artwork, and movie or episode-specific metadata back to the MP4.
- Use a fast metadata-only save path when artwork is off and the file supports it.
- Verify saved metadata by reading the MP4 back after writing, then fall back safely if a fast save does not stick.
- Use temporary recovery backups during writes and clean them up automatically after verified success.

## Run

Open the package in Xcode and run the `MetaFetch` target, or launch the bundled app:

```bash
./Scripts/run_app.sh
```

That path builds and opens a real `.app` bundle with the bundle identifier `com.jaysonguglietta.metafetch`.

## Documentation

See [User Guide](Documentation/UserGuide.md) for the full workflow, naming tips, save behavior, and troubleshooting.

See [Feature Suggestions](Documentation/FeatureSuggestions.md) for the next product ideas worth considering.

In the app, use the `Help` toolbar button or choose `Help > MetaFetch Help` with `Command-Shift-?`.

## Development

Run the test suite:

```bash
swift test
```

Build the local app bundle:

```bash
./Scripts/build_app.sh
```

## Data Sources

- Movies use Wikipedia/Wikimedia metadata and page images.
- TV shows and episodes use TVMaze metadata.

Match quality depends on source coverage. Always review close matches before saving.

## MP4 Conversion Tip

If you convert MKV files to MP4 before tagging, reserve metadata headroom in the MP4 container so MetaFetch can update tags faster and more reliably:

```bash
-moov_size 16777216
```

This leaves about 16 MiB near the front of the file for title, TV episode, description, and artwork atoms. Without that headroom, many `+faststart` MP4s need a full container rewrite when metadata grows.
