# MetaFetch

MetaFetch is a native macOS SwiftUI app for tagging `.mp4` files with movie or TV episode metadata.

## Features

- Choose `Movie` or `TV Show` when the app starts.
- Drag and drop one or more `.mp4` files, or use the file picker.
- Import a season folder and recursively queue local writable `.mp4` files.
- Use the TV batch workspace to show multiple episodes as a file list, search the show once, browse Series/Seasons/Data/Cover tabs, and apply choices across detected episodes.
- Clean filenames into searchable titles automatically.
- Detect TV episode codes like `S01E03` and `2x07`.
- Use trailing TV episode titles, like `S03E03 - Toronto`, as a fallback when a provider lists the episode under a rebranded show or different season.
- Use folder context for TV files like `Severance/Season 2/Episode 04.mp4`.
- Review match confidence, result source, and source page links before saving.
- Edit title, sort title, series, sort series, season/episode numbers, genre, year, creator, and description before saving.
- Override provider artwork with a custom local poster image before saving.
- Download movie and TV episode details/descriptions, then write title, synopsis, genre, artwork, and movie or episode-specific metadata back to Apple/iTunes-style MP4 atoms.
- Check MP4 metadata headroom before poster saves to see whether a fast header update or container rewrite is likely.
- Optionally repair insufficient poster headroom automatically with a trusted local FFmpeg installation before saving.
- Use a native MP4 atom writer first, then fall back to AVFoundation only when the file layout requires it.
- Verify every requested metadata field and requested poster by reading the MP4 back after writing, then roll back or fall back if a save does not stick.
- Preserve unrelated third-party MP4 metadata while replacing only the Apple/iTunes-style fields managed by MetaFetch.
- Prioritize speed by writing without creating sidecar safety backups by default.
- Stage rewrites and temporary rollback data on the movie’s own volume, coordinate atomic replacement, and optionally keep a separate user-visible safety backup when protection matters more than speed.
- Review save reports showing which files verified, failed, included posters, used fast metadata-only saves, or required rewrites.
- Export save reports as CSV or JSON.
- Group folder and season imports by detected show and season in the TV batch workspace.
- Reconcile a complete TV season against TVMaze, identify missing or duplicate episode numbers, and apply only unambiguous matches.
- Export a read-only season reconciliation plan as formula-safe CSV or structured JSON before applying any episode matches.
- Add optional TMDb and OMDb movie provider keys for broader movie search coverage.
- Store optional provider keys locally in macOS Keychain.
- Import and export editable metadata as bounded JSON or NFO, and inspect the raw MP4 atoms already present in a file.
- Save content ratings, community ratings, and IMDb/TMDb/TVMaze identifiers when providers return them.
- Tune metadata profiles, match-confidence rules, extras detection, poster defaults, provider priority, automatic headroom repair, safety backups, TV batch auto-apply, watch folders, and rename-after-save templates.
- Create and delete custom rename presets for different media libraries.
- Filter loaded files by exact matches, review state, series-only matches, saved files, failures, or poster availability.
- Retry failed save report rows, including a faster retry-without-posters path.
- Preview current MP4 tags, when readable, versus the final edited tags before writing.
- Review provider diagnostics showing searched, skipped, failed, and no-key provider states.
- Track local provider health and recent tagging history in Advanced Preferences, including CSV history export.
- Optionally rename files after verified saves using movie or TV filename templates.
- Check GitHub Releases for newer versions, download an installer asset, and reveal it in Finder for user-confirmed installation.
- Use signed Sparkle appcast updates when a production build is configured with an HTTPS feed and EdDSA public key; retain the verified GitHub flow as a fallback.
- Restore the newest usable safety backup with `Undo Last Save`, browse recovery records, or export a redacted diagnostics bundle for support.
- Run inside the macOS App Sandbox with user-selected read/write access and a security-scoped watch-folder bookmark.
- Re-check imported file identity before saving so MetaFetch refuses to tag a path that changed after import.

## Run

Open the package in Xcode and run the `MetaFetch` target, or launch the bundled app:

```bash
./Scripts/run_app.sh
```

That path builds and opens a real `.app` bundle with the bundle identifier `com.jaysonguglietta.metafetch`.

## Documentation

See [User Guide](Documentation/UserGuide.md) for the full workflow, naming tips, save behavior, and troubleshooting.

See [Product Brief](Documentation/ProductBrief.md) for the target users, product problem, main workflows, assumptions, and done criteria.

See [Product Blueprint](Documentation/ProductBlueprint.md) for the app goal, core workflows, key screens, data models, and edge cases.

See [Feature Suggestions](Documentation/FeatureSuggestions.md) for the next product ideas worth considering.

See [Security and Release Notes](Documentation/Security.md) for file-write guarantees, network boundaries, updater requirements, and residual risks.

In the app, use the `Help` toolbar button or choose `Help > MetaFetch Help` with `Command-Shift-?`.

## Development

Run the test suite:

```bash
swift test
```

If your shell cannot find the Apple test frameworks directly, run with the same Xcode cache environment used by CI:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/metafetch-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/metafetch-swiftpm-cache \
swift test
```

Build the local app bundle:

```bash
./Scripts/build_app.sh
```

The build fails unless Sparkle is embedded, the executable contains the correct framework runtime path, the bundle identifier is correct, and the complete nested signature verifies. You can rerun those packaging checks directly with:

```bash
./Scripts/verify_app_bundle.sh dist/MetaFetch.app
```

Build with release version metadata:

```bash
APP_VERSION=2.01 APP_BUILD=4 ./Scripts/build_app.sh
```

The local build script ad-hoc signs the app for development. Because ad-hoc code has no stable Team ID, local builds do not enable hardened runtime. Distribution builds require a Developer ID Application identity and retain hardened runtime plus library validation:

```bash
APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build_app.sh
```

To enable signed Sparkle updates in that distribution build, also provide an HTTPS appcast URL and the EdDSA public key generated for the release channel:

```bash
APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
SPARKLE_FEED_URL="https://example.com/metafetch/appcast.xml" \
SPARKLE_PUBLIC_KEY="BASE64_EDDSA_PUBLIC_KEY" \
./Scripts/build_app.sh
```

If either Sparkle value is absent, MetaFetch leaves automatic appcast updates disabled and uses the checksum-verified GitHub release workflow.

Build a GitHub-release-ready DMG with checksum output:

```bash
APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APP_NOTARY_PROFILE="metafetch-notary" \
./Scripts/build_release_dmg.sh
```

`APP_NOTARY_PROFILE` should be an `xcrun notarytool` keychain profile. Omit it for local unsigned/not-notarized test DMGs.

## Updates

Production builds can use Sparkle 2.9.4 with an HTTPS appcast and EdDSA public key embedded at build time. Sparkle verifies the signed appcast and release archive before installation. The feed URL and public key are release configuration, not source-controlled secrets.

MetaFetch checks `jaysonguglietta/MetaFetch` GitHub Releases. A release is considered newer when its tag, such as `v2.01` or `2.01`, is greater than the app’s `CFBundleShortVersionString`.

For in-app downloads, attach an installable asset and its exact-name SHA-256 sidecar to the GitHub release:

- `MetaFetch-2.01.dmg` and `MetaFetch-2.01.dmg.sha256`
- `MetaFetch-2.01.zip` and `MetaFetch-2.01.zip.sha256`
- `MetaFetch-2.01.pkg` and `MetaFetch-2.01.pkg.sha256`

MetaFetch verifies the downloaded bytes against the sidecar before moving the asset to the user’s Downloads folder. DMG downloads must also have a valid macOS code signature; when the installed app has a Developer ID Team ID, the DMG must use the same team. MetaFetch then reveals the asset in Finder without opening it, so the final app replacement remains visible and user-confirmed instead of silently replacing a running app.

For production releases, sign and notarize installer assets before attaching them to GitHub. `Scripts/build_release_dmg.sh` creates a DMG and SHA-256 file for that workflow. The in-app updater intentionally treats GitHub release downloads as manual installs rather than silently trusted code.

## Security Hardening

- Imported files must be local, writable, regular `.mp4` files and cannot be symlinks.
- The app is sandboxed and receives persistent watch-folder access only through a user-approved security-scoped bookmark.
- MetaFetch stores file identity at import and re-checks it immediately before saving.
- The native MP4 atom writer rejects oversized movie headers and overly complex atom layouts before allocating or recursing deeply.
- Writes preserve unknown metadata atoms, use transactional rollback protection, and require full requested-field readback verification before success is reported.
- Artwork downloads are size-bounded, MIME-checked, downsampled, cached with eviction, and rejected when redirects leave the artwork host allowlist.
- Metadata JSON downloads use timeouts and response-size limits; identical TVMaze episode catalogs are coalesced and cached with bounded eviction.
- Update downloads are size-bounded, SHA-256 verified, code-signature checked for DMGs, and revealed in Finder instead of opened automatically.
- CSV exports neutralize spreadsheet-formula prefixes in user-controlled cells.
- JSON/NFO imports are size-bounded; XML external entity resolution is disabled.
- Diagnostics exports are opt-in, omit API keys, filenames, and paths, and use per-export salted file identifiers.
- Sparkle is version-pinned in `Package.resolved`; signed appcast updates are accepted only when an HTTPS feed and EdDSA public key are configured.
- CI uses least-privilege repository permissions, a SHA-pinned checkout action, run concurrency limits, and build timeouts.

## Data Sources

- Movies use Wikipedia/Wikimedia metadata and page images by default.
- Optional movie providers can be enabled with user-supplied TMDb and OMDb keys from `Options > Metadata Providers`.
- TV shows and episodes use TVMaze metadata.

Match quality depends on source coverage. Always review close matches before saving.

## MP4 Conversion Tip

If you convert MKV files to MP4 before tagging, reserve metadata headroom in the MP4 container so MetaFetch can update tags faster and more reliably:

```bash
-moov_size 16777216
```

This leaves about 16 MiB near the front of the file for title, TV episode, description, and artwork atoms. Without that headroom, many `+faststart` MP4s need a full container rewrite when metadata grows.
