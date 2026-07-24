# MetaFetch Security And Release Notes

## Trust Boundaries

MetaFetch accepts local file and folder URLs, remote metadata JSON, remote artwork, optional user-supplied provider keys, and GitHub release assets. All of these inputs are treated as untrusted. The app has no server-side authentication, multi-tenant data, or inbound network service.

The packaged app uses App Sandbox with outbound-network, user-selected read/write, and app-scoped bookmark entitlements. File access begins with a user selection; only the watch-folder bookmark is persisted.

## File Safety

- Imports must resolve to local, readable, writable, regular `.mp4` files and cannot be symlinks.
- File identity is recorded at import and checked again immediately before writing.
- Native writes replace only MetaFetch-managed Apple/iTunes metadata items; unrelated metadata items are retained.
- In-place writes keep a bounded copy of the overwritten header region and restore it if verification fails.
- Container rewrites use Apple’s item-replacement directory on the destination volume for both prepared output and a temporary rollback copy. `NSFileCoordinator` coordinates the atomic replacement; rollback storage is removed only after readback verification succeeds.
- Optional `Create Safety Backups` produces a separate user-visible backup that remains after a successful save. This is distinct from the temporary transactional journal.
- Success requires readback verification of every requested tag, media kind, episode values, and requested artwork.
- JSON/NFO sidecars are limited to 1 MiB. NFO parsing disables external entity resolution to prevent local-file or network entity expansion.
- Headroom repair invokes FFmpeg only from fixed Homebrew paths, rejects symlinked executables, stream-copies media, and transactionally validates the repaired MP4 before replacing the original.
- Recovery restores are restricted to regular non-symlink files in the same directory as the derived original and require MP4 readback validation.

An abrupt power loss can interrupt any filesystem operation. Keep irreplaceable media backed up independently even when safety backups are enabled.

## Network Safety

- Metadata JSON requests use HTTPS, request timeouts, and response-size limits.
- TVMaze season catalogs use a bounded 15-minute cache and coalesce identical in-flight requests to avoid request storms during batch imports.
- Artwork is restricted to approved HTTPS hosts, bounded by response size, MIME checked, downsampled before use, and stored in an evicting cache.
- Optional TMDb and OMDb keys are stored in macOS Keychain and are never bundled in the repository.

## Update Safety

Sparkle 2.9.4 is pinned through SwiftPM. It is activated only when the signed bundle contains both an HTTPS `SUFeedURL` and a valid base64 `SUPublicEDKey`. Production builds retain hardened runtime and library validation. Local ad-hoc builds intentionally omit hardened runtime because ad-hoc nested code has no stable Team ID; they are development artifacts and must not be distributed.

`Scripts/verify_app_bundle.sh` makes packaging fail unless Sparkle's executable is embedded, MetaFetch links to the expected framework install name, `@executable_path/../Frameworks` is present, the bundle identifier is correct, and the nested code signature passes strict verification. CI runs the same check after every app build.

The updater only accepts trusted GitHub release URLs and bounded installer assets. Every installer must have an exact-name SHA-256 sidecar, for example:

```text
MetaFetch-2.01.dmg
MetaFetch-2.01.dmg.sha256
```

DMGs must also pass strict macOS code-signature validation. When the installed app has a Developer ID Team ID, the downloaded DMG must match that team. Installers are moved to Downloads and revealed in Finder; MetaFetch does not open or silently install them.

Production releases should be Developer ID signed, notarized, stapled, and generated with `Scripts/build_release_dmg.sh` so the checksum filename matches the updater contract.

## Export And CI Safety

- CSV reports and tagging-history exports prefix spreadsheet-formula cells so attacker-controlled filenames remain text.
- Redacted diagnostics are generated only on explicit export, omit provider keys, filenames, and paths, and use per-export salted SHA-256 identifiers that cannot be correlated across bundles.
- GitHub Actions uses read-only repository permissions, a SHA-pinned checkout action, concurrency cancellation, and a job timeout.

## Residual Risks

- MP4 is a complex binary format. Unusual containers may be rejected or require AVFoundation fallback rather than modified natively.
- ZIP and PKG assets receive checksum verification but currently do not receive the DMG-specific signing-team comparison. Prefer signed, notarized DMGs for production releases.
- Provider data can be inaccurate even when transport validation succeeds. Users should review ambiguous matches before saving.
- A security-scoped bookmark can become stale after a folder move or permission change; MetaFetch requires the user to select the watch folder again rather than broadening filesystem access.
- Automatic headroom repair depends on a separately installed FFmpeg binary. MetaFetch validates its location and file type but does not manage or update that external dependency.
