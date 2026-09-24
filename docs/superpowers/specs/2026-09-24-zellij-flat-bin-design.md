# Zellij flat-bin package design

## Decision

Zellij follows the same delivery contract as the Yazi bundle. The default official
package is a portable archive with one top-level directory, `zellij_bin/`, and all
runtime files directly inside that directory.

```text
zellij_bin/
├── zellij 或 zellij.exe
├── README.md
├── ZELLIJ-USER-GUIDE.md
├── README.txt
├── BUILD-INFO.txt
└── LICENSE.md
```

The user copies the complete `zellij_bin/` directory to
`~/local/bin/zellij_bin/` on Linux or the equivalent user-local directory on
Windows, then adds that directory to `PATH`. Zellij itself has no data directory,
launcher, shared library directory, or external builtin-plugin directory.

## Scope and targets

- Official upstream release: `v0.45.1`.
- Default variant: `full`, which retains the upstream Web capability.
- Linux: `x86_64-unknown-linux-musl`, packaged as `.tar.gz`.
- Windows: `x86_64-pc-windows-msvc`, packaged as `.zip`.
- ARM64: excluded from this release and not runtime-verified.
- Zellij and Yazi remain separate packages.
- Linux `surfer` acceptance is existing evidence and is not rerun for this layout-only change.
- Windows native acceptance remains a user-side test on the other Windows computer.

The `standard` layout remains readable by local verifiers for backward compatibility
with earlier packages, but new packaging commands default to `flat-bin`.

## Naming and provenance

Default artifacts are:

```text
zellij-v0.45.1-full-x86_64-unknown-linux-musl-flat-bin.tar.gz
zellij-v0.45.1-full-x86_64-pc-windows-msvc-flat-bin.zip
```

Each artifact has a matching `.sha256` and `.manifest.json`. The manifest records
the package layout, top-level package directory, official upstream asset, upstream
binary SHA-256, downloaded upstream archive SHA-256, and repackaged archive SHA-256.

## Runtime boundary

The package includes only the official Zellij binary and offline documentation.
Builtin WASM plugins remain embedded in the binary. Rust, Cargo, OpenSSL, Git,
package managers, SSH, Windows Terminal, shells, Yazi, Claude Code, Codex and
Yazi preview helpers are external requirements for the relevant user scenario.

The package README must explain prerequisites, direct execution, the copy-to-local
directory workflow, `PATH`, builtin plugins, Web variant boundary, ARM64 boundary,
checksums, and project/upstream links.

## Verification

The Python verifier must validate both archive layouts, while the new flat-bin
artifacts must specifically prove:

1. the archive has the single top-level directory `zellij_bin/`;
2. the binary and all six documented files are directly under `zellij_bin/`;
3. Linux executable permissions are retained;
4. README, user guide, checksum, manifest and upstream links are present;
5. no source-build directories or build-only dependencies are included.

This change does not silently replace or mutate the public GitHub Release. Release
asset replacement is a separate action because the current public tag contains a
diagnostic Windows ZIP instead of the canonical Windows official ZIP.
