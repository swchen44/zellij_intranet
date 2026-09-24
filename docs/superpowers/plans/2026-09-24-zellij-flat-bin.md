# Zellij flat-bin implementation plan

## Objective

Make the official Zellij packager use the same portable delivery shape as Yazi:
`zellij_bin/` as the only archive root, direct binary and documentation files,
explicit `flat-bin` artifact names, checksum/manifest evidence, and package-local
instructions for copying the complete directory into a user-local `PATH`.

## Constraints

- Work serially; do not compile on or stress `surfer`.
- Do not rerun the existing Linux runtime experiment on `surfer`.
- Do not claim Windows runtime acceptance; it remains for the other Windows host.
- Do not replace public GitHub Release assets in this implementation pass.
- Keep `standard` layout verification compatibility for existing local/release files.

## Tasks

1. [x] Update unit tests first for the new default layout, archive names, manifest fields,
   README copy/PATH instructions, and explicit standard-layout compatibility.
2. [x] Extend `packaging/package_official.py` with `--layout {flat-bin,standard}`,
   default `flat-bin`, deterministic `zellij_bin/` archive members, layout-aware
   package README/build info/manifest, and layout-aware verification.
3. [x] Update Linux and Windows acceptance/verifier scripts to detect the manifest/layout
   and find `zellij_bin` without removing compatibility with standard packages.
4. [x] Update root README, package guide, specs, plans and lessons learned so commands,
   archive names, copy-to-local behavior and release boundaries are consistent.
5. [x] Run Python unit tests, shell syntax/contract tests, local package creation using
   synthetic binaries, archive inspection and official package verification if the
   existing local official inputs are available. Use one target at a time.
6. [x] Review Git diff and status. Leave release upload/replacement for explicit approval.

## Acceptance criteria

- `python3 packaging/package_official.py package --version v0.45.1` defaults to
  `*-flat-bin.*` artifacts.
- Flat archives contain exactly `zellij_bin/<six documented files>`.
- Both Linux and Windows local verifiers accept the new layout.
- Existing standard package layout remains verifiable.
- Package-local README and project docs show the same `zellij_bin` copy/PATH workflow.
- No `surfer` compile or runtime command is started by this plan.
