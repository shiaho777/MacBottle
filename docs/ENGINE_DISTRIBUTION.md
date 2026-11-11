# Engine distribution

MacBottle no longer depends on the archived Whisky feed. Engine metadata
lives in `engine-manifest.json` and is signed with an Ed25519 key whose
public half is embedded in `MacBottle/Info.plist` as
`MBEngineManifestPublicKey`.

## Trust chain

1. The app fetches `engine-manifest.json` from the repository's raw CDN.
2. `EngineReleaseManifest` reconstructs the deterministic signing payload
   (schema, timestamp, one line per release in fixed field order).
3. `Curve25519.Signing.PublicKey` verifies the signature from
   `Info.plist`. `EngineManifestLoader` fails closed: with no public key
   configured it rejects the manifest instead of trusting it unverified.
4. Only then does `EngineFallbackCatalog.preferredFallback()` use the
   manifest's URL and SHA-256. If the manifest is missing, unsigned,
   tampered with, or has no matching release, the app falls back to the
   digest compiled into the binary.
5. `EngineDownloadService` verifies the downloaded archive against the
   selected SHA-256 before `EngineImportService` stages it.

The signature is the outer trust boundary; the SHA-256 is the inner one.
A compromised CDN cannot swap the archive without the private key, and a
compromised archive cannot pass the digest check.

## Manifest schema 2

Schema 1 described only a download: engine id, version, URL, digest,
size, minimum macOS, and architecture. Schema 2 adds the package metadata
the catalog and installer need, so adding an engine no longer requires a
new Swift branch:

| Field | Required | Meaning |
| --- | --- | --- |
| `display_name` | no | Human-readable name for the engine picker |
| `kind` | no | `wine`, `crossover`, `gptk`, or `custom` |
| `capabilities` | no | Machine tokens such as `wine`, `arm64`, `rosetta`, `d3dmetal`, `dxvk` |
| `package_format` | no | Archive hint (`tar.xz`, `tar.gz`) |
| `install_layout` | no | `wine-root` (default) or `gcenx-app-bundle` |
| `channel` | no | `stable`, `beta`, or a custom channel name |
| `license` | no | License note shown with the package |
| `notes` | no | Short install/limitation note |

Schema 2 signs every field the UI displays. `signingPayload` appends
`display_name`, `kind`, sorted `capabilities`, `package_format`,
`install_layout`, `channel`, `license`, and `notes` to the schema 1 line;
the signer and the client must stay in lockstep. Schema 1 manifests still
decode and verify, so older builds keep working.

Engine IDs are install slots. A new build gets a new ID
(`macbottle-arm64`, `macbottle-crossover`, ...). The only legacy
exception is `crossover`, which still installs into the existing
`Libraries/` folder; newer builds live under `Engines/<engine_id>/`.
Reusing an existing built-in ID for a different archive would collide
with the slot the user already has selected.

## Manifest-driven catalog

`EnginePackageCatalog` turns the signed manifest into `EnginePackage`
values. For each engine it selects the newest release compatible with
the current macOS, and:

- prefers a newer version over a native architecture, so an x86_64
  update is not hidden behind an older arm64 build;
- prefers native arm64 over x86_64 when versions tie;
- keeps x86_64 packages visible on Apple Silicon because they run under
  Rosetta.

`EnginePackageInstaller` downloads the archive through
`EngineDownloadService` (resume support, SHA-256 verification, tar
readability check), then dispatches on `install_layout`: `wine-root`
uses `EngineImportService.importTarball`, `gcenx-app-bundle` uses the
Gcenx-specific extractor. Settings lists every signed package that is
not installed yet and installs it without a restart.

## Publishing an engine package

1. Build or obtain the engine tree, with `Wine/bin/wine64` (or
   `Wine/bin/wine`) at its root.
2. Package it:

   ```sh
   scripts/package-engine.sh ~/engines/macbottle-arm64 dist/wine-arm64.tar.xz
   ```

3. Upload the archive to a GitHub Release or another HTTPS host.
4. Add the release entry and re-sign:

   ```sh
   python3 scripts/add-engine-release.py \
     --engine-id macbottle-arm64 \
     --version 11.21 \
     --url https://github.com/OWNER/REPO/releases/download/engine-11.21/wine-arm64.tar.xz \
     --archive dist/wine-arm64.tar.xz \
     --display-name "MacBottle Wine (ARM64)" \
     --kind wine \
     --layout wine-root \
     --arch arm64 \
     --min-macos 14.0 \
     --capabilities wine,arm64,msync \
     --license "Wine is LGPL-2.1" \
     --notes "Native Apple Silicon build."
   ```

5. Commit `engine-manifest.json`. CI (`EngineManifest.yml`) re-signs the
   Gcenx entry weekly; manual engine entries are preserved.

`EngineDownloadService` trusts the signed digest, not the host. A
compromised CDN cannot swap the archive without the signing key, and a
compromised archive cannot pass the digest check.

### First-party CrossOver-compatible package

The mechanism is ready for it, but the artifact itself is not created
here: Apple's D3DMetal is closed source and CrossOver is licensed, so a
CrossOver-compatible archive with D3DMetal/DXVK cannot be fabricated or
redistributed by this repository. A maintainer with the appropriate
license builds the tree, packages it with the commands above, and adds
it to the manifest. Until then, the signed Gcenx Wine 11.21 fallback is
the only hosted engine, and local import remains fully supported.

## Update checks

The Gcenx engine (`LocalPathEngine` with `manifestEngineID`) checks for
updates against the same signed manifest. At launch, `ContentView` asks
the active engine for an update; the manifest version (for example
`11.21`) is padded to a semantic version and compared with the installed
`WhiskyWineVersion.plist`. A missing, unsigned, or tampered manifest
reports no update.

Accepting the update no longer uninstalls the engine first. Setup opens
at the download step, and the import swaps the new build into place, so
the current engine stays usable if the download fails.

## Updating the manifest

```sh
# One-time: private key, mode 0600, never committed.
# The public half must already be in MacBottle/Info.plist.
export MACBOTTLE_ENGINE_SIGNING_KEY="$(cat ~/.macbottle-engine-signing-key)"

./scripts/update-engine-manifest.sh
```

The script downloads the pinned release, computes its SHA-256 and size,
updates `engine-manifest.json`, and re-signs it. Commit the manifest.

CI runs the same script weekly and via `workflow_dispatch`
(`.github/workflows/EngineManifest.yml`). It requires the repository
secret `ENGINE_SIGNING_KEY` and fails closed if the secret is absent;
it never commits an unsigned manifest.

## Rotating the key

1. Generate a new key pair.
2. Replace `MBEngineManifestPublicKey` in `MacBottle/Info.plist`.
3. Sign `engine-manifest.json` with the new private key.
4. Update the `ENGINE_SIGNING_KEY` repository secret.
5. Ship an app release before or together with the new manifest. Old
   app versions will reject the new signature and fall back to their
   compiled-in digest, which is the intended failure mode.

## Fallbacks

- `EngineFallbackCatalog.gcenxWine`: pinned open-source Wine 11.21
  (x86_64, Rosetta, no D3DMetal/DXVK).
- Local import: folder or `.tar.gz` / `.tar.xz`.
- Legacy recovery: an existing Whisky/CrossOver `Libraries` folder.
- Discovered engines dropped under `Engines/`.

The CrossOver/Whisky primary feed remains dead (404 as of 2026-11).
The signed manifest is now the self-owned distribution mechanism: it
carries package metadata, the catalog installs from it, and the
packaging scripts publish to it. The remaining dependency is a
licensed CrossOver-compatible archive, not client code.
