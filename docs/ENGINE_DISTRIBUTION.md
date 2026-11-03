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
Self-owned CrossOver-compatible distribution is still the long-term
goal; this manifest is the mechanism that will carry it.
