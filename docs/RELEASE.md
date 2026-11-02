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
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA key for the appcast (when enabled) |

## Appcast

`scripts/generate-appcast.sh` wraps Sparkle's `generate_appcast`. Put the
release zip in a directory, point `SPARKLE_BIN` at Sparkle's `bin`, and
set `SPARKLE_ED_PRIVATE_KEY_FILE` to the private key. Commit the
generated `appcast.xml` to the repository root, which is the
`SUFeedURL` in `Info.plist`.

Sparkle is intentionally **not started** in `WhiskyApp.init()` yet. Set
`startingUpdater: true` and add `SUPublicEDKey` to `Info.plist` only
after the first signed appcast is published; starting it with a missing
feed/key produces “Unable to Check For Updates” dialogs.

## Versioning

- Tag `v<semver>` on `main` after CI is green.
- The tag is the release identity; do not move tags.
- `MacBottle.zip.sha256` is the external integrity check for downloads
  that do not go through Sparkle.

## Remaining manual step

Notarization requires a real Apple Developer account. The workflow is
ready; the first notarized release must be validated on a clean Mac with
Gatekeeper enabled.
