# Security Policy

## Reporting a vulnerability

Report privately through GitHub's **Security → Report a vulnerability** tab
on this repository. Do not open a public issue for a vulnerability that
could be exploited before a fix ships.

Please include the affected version, macOS version, steps to reproduce,
and whether the issue is in the app, WhiskyKit, a recipe, or the engine
download path.

## Trust model (current)

MacBottle runs untrusted Windows binaries inside a Wine prefix. That is
the product; a compromised game or installer is outside the app's
sandbox and can read anything the user can read. There is no VM boundary.

The app itself is **not sandboxed**. The hardened runtime is enabled and
the `allow-unsigned-executable-memory` entitlement is required for Wine's
JIT; camera and microphone entitlements are not requested.

### Recipes

Remote recipes are fetched from the repository's raw CDN, and each
manifest entry carries a SHA-256 digest that is verified before decoding.
The manifest is served from the same origin as the files it describes, so
this detects corruption and cache poisoning but **not** a full repository
compromise. A signed manifest is not implemented yet.

Recipes are data, not code. They can set environment variables, run
winetricks verbs, and write registry values, so a malicious recipe still
has meaningful influence over a bottle. Review recipe changes in the diff
sheet before accepting them.

### Engine archives

`EngineDownloadService` verifies the archive is a readable tar.gz and
records its SHA-256 on first use. Later downloads must match that digest
or the user is asked to accept the change explicitly. This is
trust-on-first-use, not cryptographic provenance: the first download
relies on HTTPS and the upstream host. A signed release manifest with a
project-held key is the next step and is tracked on the engine track.

`Tar.untar` rejects absolute paths and `..` entries, extracts into
staging, resolves every entry with `realpath(3)` to reject symlink
escapes, and swaps top-level items into place with rollback.

### Credentials

Steam credentials are written to a `0600` script file in the temporary
directory for the duration of a `steamcmd` run and removed afterwards.
They are not stored in the app's preferences. A crash can leave the
script behind; the file is not encrypted at rest.

## Supported versions

Only the latest release on `main` is supported. Pre-release builds and
locally built Debug bundles are not.
