# MetaFetch

MetaFetch is a native macOS SwiftUI app for tagging `.mp4` files with movie or TV episode metadata.

## Features

- Choose `Movie` or `TV Show` when the app starts.
- Drag and drop one or more `.mp4` files, or use the file picker.
- Use TV batch controls to search and fast-save several episodes from the same show.
- Clean filenames into searchable titles automatically.
- Detect TV episode codes like `S01E03` and `2x07`.
- Use folder context for TV files like `Severance/Season 2/Episode 04.mp4`.
- Review match confidence, result source, and source page links before saving.
- Write title, synopsis, genre, artwork, and movie or episode-specific metadata back to Apple/iTunes-style MP4 atoms.
- Use a native MP4 atom writer first, then fall back to AVFoundation only when the file layout requires it.
- Verify saved metadata by reading the MP4 back after writing, then fall back if a fast save does not stick.
- Prioritize speed by writing without creating sidecar safety backups.
- Check GitHub Releases for newer versions, download an installer asset, and open it for user-confirmed installation.

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

Build with release version metadata:

```bash
APP_VERSION=1.1 APP_BUILD=2 ./Scripts/build_app.sh
```

## Updates

MetaFetch checks `jaysonguglietta/MetaFetch` GitHub Releases. A release is considered newer when its tag, such as `v1.1` or `1.1`, is greater than the app’s `CFBundleShortVersionString`.

For in-app downloads, attach one installable asset to the GitHub release:

- `.dmg`
- `.zip`
- `.pkg`

MetaFetch downloads the asset to the user’s Downloads folder and opens it. The final app replacement remains visible and user-confirmed instead of silently replacing a running app.

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
