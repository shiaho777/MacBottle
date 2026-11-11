# Release engineering

## Current pipeline

`.github/workflows/Release.yml` runs on a `v*` tag (or manually). It:

1. Builds `Release` for macOS.
2. If `DEVELOPER_ID_CERTIFICATE` is present, signs with the Developer ID
   Application identity and a secure timestamp.
3. If `APPLE_ID` + `APPLE_APP_PASSWORD` are present, submits the zip to
   `notarytool`, staples the app, and repackages it.
4. Publishes `MacBottle.zip` and its SHA-256 to a GitHub Release.

Without the signing secrets the job still produces an unsigned zip, and
the step summary says so. It never labels an unsigned build notarized.

## Required secrets

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE` | base64 `.p12` Developer ID Application certificate |
| `DEVELOPER_ID_PASSWORD` | `.p12` password |
| `APPLE_TEAM_ID` | Developer Team ID |
| `APPLE_ID` | Apple ID for notarytool |
| `APPLE_APP_PASSWORD` | app-specific password for notarytool |
| `ENGINE_SIGNING_KEY` | Ed25519 key for `engine-manifest.json` |

## App updates

MacBottle does not use Sparkle. `AppUpdateChecker` (MacBottleKit) reads
`https://api.github.com/repos/shiaho777/MacBottle/releases/latest`,
skips drafts and prereleases, and compares the release tag with
`CFBundleShortVersionString`. When a newer release exists the app offers
to open the GitHub Release page; the user downloads and replaces the app
themselves. No update keys or appcast are required.

- **App menu → Check for Updates…** runs a manual check and always
  reports the result.
- The automatic-update toggle under **Settings → Updates**
  (`checkAppUpdates`, on by default) runs a silent check at launch that
  only speaks up when a newer release exists.

The tag must parse as a version: an optional `v`, then one to three
numeric parts (`v1.2.3`, `1.2`). Anything after `-` or `+` is ignored
for comparison; only GitHub's prerelease flag excludes a release. Keep
`MARKETING_VERSION` in the Xcode project in step with the tag, otherwise
the comparison is meaningless. An update is reported only when the
release is strictly newer. `MARKETING_VERSION` was lowered from the
inherited Whisky `2.3.5` to `0.7.0` before the first public release, so
`v0.7.0` is both the project version and the first tag; no earlier
release exists that could compare against the old number.

## Versioning

- Tag `v<semver>` on `main` after CI is green.
- The tag is the release identity; do not move tags.
- `MacBottle.zip.sha256` is the integrity check for the downloaded zip.

## Remaining manual step

Notarization requires a real Apple Developer account. The workflow is
ready; the first notarized release must be validated on a clean Mac with
Gatekeeper enabled.
