# Zellij offline bundle implementation plan

## Objective

沿用 Yazi 已採用的「官方固定版本 + Python bundle + checksum/manifest + GitHub Release」
方法，整理 Zellij 的 Linux/Windows x86_64 portable delivery。Linux `surfer` runtime
實驗已完成，本次不重跑；Windows 仍由使用者在另一台 Windows computer 執行實機 gate。

## Fixed decisions

- Project：`swchen44/zellij_intranet`
- Official delivery baseline：`v0.45.1`, default variant `full`
- Linux：`x86_64-unknown-linux-musl`, `tar.gz`
- Windows：`x86_64-pc-windows-msvc`, `zip`
- ARM64：不打包、不驗證
- Zellij 與 Yazi 分開 release；不把 Yazi、SSH、Windows Terminal 或 helper 混進 Zellij
- Source fallback：`0.46.0` / commit `474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb`
- 不把 release archive commit 到 Git；archive 用 GitHub Release，checksum/manifest 可追蹤

## Repository layout

```text
README.md
docs/
  plans/2026-09-21-zellij-windows-acceptance.md
  superpowers/specs/2026-09-21-zellij-offline-bundle-design.md
  superpowers/plans/2026-09-21-zellij-offline-bundle.md
  superpowers/LESSONS-LEARNED.md
packaging/
  package_official.py
  tests/
  acceptance/
dist/official/
  *.sha256
  *.manifest.json
  # *.tar.gz and *.zip are local/release files, ignored by Git
```

## Work items

### 1. Package contract

- [x] Official release version and target matrix are explicit in `packaging/targets.toml`.
- [x] Python packager accepts `--version`, defaults to `full`, and supports explicit `no-web`.
- [x] Package root includes `README.md`, offline `ZELLIJ-USER-GUIDE.md`, compatibility
  `README.txt`, `BUILD-INFO.txt`, `LICENSE.md`, and the platform binary.
- [x] Package README documents prerequisites, Linux/PowerShell usage, PATH, boundary, links,
  runtime network policy, and full/no-web behavior.
- [x] Manifest identifies `README.md` as the package README and
  `ZELLIJ-USER-GUIDE.md` as the offline user guide.

### 2. Tests and verification

- [x] Unit tests check Linux/Windows archive members, README content and user guide content.
- [x] Local verifier checks archive SHA-256, manifest, binary, executable bit, README sections,
  offline user guide sections, and project/upstream links.
- [x] Packaging contract test checks docs, targets, scripts, README generation, and archive
  ignore rules.
- [x] Repackage official `v0.45.1` full artifacts and run local verify on both targets.
- [x] Inspect archive contents directly with `tar`/`unzip` and record package README result.
- [x] Do not rerun the already completed `ssh surfer` Linux experiment for documentation-only
  and package-README changes.

### 3. Documentation

- [x] Root README has Why/What/How/Boundary, user steps, developer steps, package README
  contract, and GitHub Release policy.
- [x] Official binary guide records exact commands, full/no-web distinction, runtime boundary,
  package layout, release assets, and Linux/Windows acceptance boundary.
- [x] Lessons learned distinguishes official `v0.45.1` from source fallback `0.46.0` and
  records the borrowed low-memory `surfer` lessons.
- [x] Historical 2026-09-20 plan/spec are retained; this file is the current authoritative
  official-bundle plan.

### 4. Release hygiene

- [x] Add `dist/official/*.tar.gz` and `dist/official/*.zip` to `.gitignore`.
- [x] Stop tracking current archive files while retaining local copies for release upload.
- [x] Commit docs/scripts/metadata only.
- [x] Push `main` to the public GitHub repository.
- [x] Create and verify public release tag `zellij-v0.45.1` with Linux/Windows archive,
  checksum, and manifest assets; re-downloaded Release assets passed local SHA-256 checks.

### 5. Windows acceptance handoff

- [x] Provide a separate Windows plan with Windows Codex + Computer Use as preferred method.
- [ ] User runs PowerShell package smoke on the other Windows x86_64 computer.
- [ ] User runs Windows Terminal standalone control test.
- [ ] User runs Windows Terminal → native Zellij → Yazi scenario.
- [ ] User records ConPTY resize, mouse, Unicode/CJK, clipboard, detach/attach, shell, and
  clean-profile results.
- [ ] User returns logs, package hash, Windows/Terminal versions, and screenshots or failure
  evidence for the project record.

## Commands for the implementation session

```sh
python3 packaging/tests/test_official_package.py
./packaging/tests/test-packaging.sh
python3 packaging/package_official.py package \
  --version v0.45.1 \
  --output-dir dist/official
python3 packaging/package_official.py verify \
  dist/official/zellij-v0.45.1-full-x86_64-unknown-linux-musl.tar.gz
python3 packaging/package_official.py verify \
  dist/official/zellij-v0.45.1-full-x86_64-pc-windows-msvc.zip
```

No command in this plan starts a new build on `surfer`; source-build fallback remains
documented separately and is intentionally not part of the official release update.
