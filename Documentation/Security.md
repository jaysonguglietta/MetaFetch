# MetaFetch Security And Release Notes

## Trust Boundaries

MetaFetch accepts local file and folder URLs, remote metadata JSON, remote artwork, optional user-supplied provider keys, and GitHub release assets. All of these inputs are treated as untrusted. The app has no server-side authentication, multi-tenant data, or inbound network service.

## File Safety

- Imports must resolve to local, readable, writable, regular `.mp4` files and cannot be symlinks.
- File identity is recorded at import and checked again immediately before writing.
- Native writes replace only MetaFetch-managed Apple/iTunes metadata items; unrelated metadata items are retained.
- In-place writes keep a bounded copy of the overwritten header region and restore it if verification fails.
- Container rewrites use a hidden same-directory rollback journal. The journal is removed only after the replacement passes readback verification and is restored on failure.
- Optional `Create Safety Backups` produces a separate user-visible backup that remains after a successful save. This is distinct from the temporary transactional journal.
- Success requires readback verification of every requested tag, media kind, episode values, and requested artwork.

An abrupt power loss can interrupt any filesystem operation. Keep irreplaceable media backed up independently even when safety backups are enabled.

## Network Safety

- Metadata JSON requests use HTTPS, request timeouts, and response-size limits.
- TVMaze season catalogs use a bounded 15-minute cache and coalesce identical in-flight requests to avoid request storms during batch imports.
- Artwork is restricted to approved HTTPS hosts, bounded by response size, MIME checked, downsampled before use, and stored in an evicting cache.
- Optional TMDb and OMDb keys are stored in macOS Keychain and are never bundled in the repository.

## Update Safety

The updater only accepts trusted GitHub release URLs and bounded installer assets. Every installer must have an exact-name SHA-256 sidecar, for example:

```text
MetaFetch-2.01.dmg
MetaFetch-2.01.dmg.sha256
```

DMGs must also pass strict macOS code-signature validation. When the installed app has a Developer ID Team ID, the downloaded DMG must match that team. Installers are moved to Downloads and revealed in Finder; MetaFetch does not open or silently install them.

Production releases should be Developer ID signed, notarized, stapled, and generated with `Scripts/build_release_dmg.sh` so the checksum filename matches the updater contract.

## Export And CI Safety

- CSV reports and tagging-history exports prefix spreadsheet-formula cells so attacker-controlled filenames remain text.
- GitHub Actions uses read-only repository permissions, a SHA-pinned checkout action, concurrency cancellation, and a job timeout.

## Residual Risks

- MP4 is a complex binary format. Unusual containers may be rejected or require AVFoundation fallback rather than modified natively.
- ZIP and PKG assets receive checksum verification but currently do not receive the DMG-specific signing-team comparison. Prefer signed, notarized DMGs for production releases.
- Provider data can be inaccurate even when transport validation succeeds. Users should review ambiguous matches before saving.
