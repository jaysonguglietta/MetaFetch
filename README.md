# MetaFetch

MetaFetch is a native macOS SwiftUI app for tagging `.mp4` movie files with metadata fetched from an online movie search.

## What it does

- Accepts `.mp4` files via drag and drop or the system file picker.
- Guesses a search title from the filename, while still letting you edit the title manually.
- Searches Wikipedia/Wikimedia movie pages with no API key required.
- Shows the best matches so you can pick the correct movie.
- Writes title, description, genre, creator, release date, and poster art back into the MP4.

## Run it

Open the package in Xcode and run the `MetaFetch` target, or launch it from Terminal:

```bash
swift run
```

If you want to launch it as a real macOS `.app` bundle with a bundle identifier, use:

```bash
./Scripts/run_app.sh
```

That path avoids the AppKit warning about a missing main bundle identifier that can appear when `swift run` launches the bare executable directly.

## Notes

- The first version is focused on `.mp4` files only.
- Metadata search currently uses Wikimedia data, so match quality depends on Wikipedia page coverage and page images.
- Saving rewrites the original file through AVFoundation using a passthrough export, then replaces the original only after the export succeeds.
