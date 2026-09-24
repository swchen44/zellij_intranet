# Zellij offline bundle design

> Historical baseline. The current package-layout contract is in
> [`2026-09-24-zellij-flat-bin-design.md`](2026-09-24-zellij-flat-bin-design.md).

## Why

公司內網的 runtime 不應依賴 GitHub、Rust/Cargo、Scoop、apt 或其他下載器。交付物要能
由 staging machine 下載官方版本、驗證來源、一次打包，帶進 Linux/Windows 內網後解壓
直接執行。

## What

本設計只處理 Zellij；Yazi 是獨立 bundle，兩者在整合驗收時放進同一個使用情境，但不
互相複製 binary 或 dependencies。

| 使用情境 | Zellij artifact | 執行位置 | 本次範圍 |
| --- | --- | --- | --- |
| Windows Terminal → SSH → Linux → Zellij → Yazi | `zellij-v0.45.1-full-x86_64-unknown-linux-musl.tar.gz` | Linux x86_64 | Linux evidence 已完成，不重跑本次文件更新 |
| Windows Terminal → Windows native Zellij → Yazi | `zellij-v0.45.1-full-x86_64-pc-windows-msvc.zip` | Windows x86_64 | 必須在另一台 Windows computer 實測 |

目前正式 baseline 是 upstream `v0.45.1` 的 `full` variant。`no-web` 仍可由 packager
明確產生，但不是本次預設 release。ARM64 不納入本版本。

## Package contract

每個 archive 的 root 固定包含：

```text
zellij 或 zellij.exe
README.md
ZELLIJ-USER-GUIDE.md
README.txt
BUILD-INFO.txt
LICENSE.md
```

`README.md` 是解壓後的使用者文件，不能只把說明放在 repository root。它必須包含：

- 版本、variant、target
- Linux 或 Windows 的 prerequisites 與直接執行命令
- 目前 shell 的 PATH 方法
- builtin WASM plugin 說明
- package boundary、ARM64 狀態、`full`/`no-web` Web capability boundary
- project GitHub、upstream release、upstream documentation links

`ZELLIJ-USER-GUIDE.md` 是隨 archive 交付的完整操作手冊，包含 pane、tab、session、
SSH、Windows Terminal、Yazi 整合、Help 與常見排查。README 做快速啟動與 boundary，
完整場景說明分開保存，讓兩者都能在無外網環境閱讀。

`README.txt` 保留給舊自動化流程；它只需要指向 `README.md`，不取代 Markdown contract。

## Source and provenance

- Official delivery source：Zellij GitHub Release `v0.45.1`。
- Linux upstream asset：`zellij-x86_64-unknown-linux-musl.tar.gz`。
- Windows upstream asset：`zellij-x86_64-pc-windows-msvc.zip`。
- 官方 `.sha256sum` 驗證的是解壓後 root binary；重新封裝後另產生 package SHA-256。
- manifest 同時保存 `upstream_binary_sha256`、`downloaded_archive_sha256`、
  `package_sha256`、target、variant 與 package README filename。
- Source fallback 的 baseline 是 `0.46.0` / commit
  `474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb`，不與 official baseline 混用。

## Runtime dependency boundary

Zellij binary package 不需要 Rust、Cargo、OpenSSL、`protoc`、musl compiler、MSVC、Git
或網路。它仍需要：

- matching x86_64 OS and kernel/runtime APIs
- host terminal and shell
- SSH server/client for the remote Linux scenario
- Windows Terminal/ConPTY for Windows native scenario
- separately installed Yazi、Claude Code、Codex 與使用者自己的 CLI

圖片、影片、PDF、archive preview helper（例如 FFmpeg、7-Zip、Poppler、Chafa）屬於
Yazi bundle，不進 Zellij archive。

`full` 包含 upstream Web Server/Web Client capability，但不會自動啟動。若要暴露 Web
endpoint，需另做 authentication、HTTPS、listen address、port 與內網安全審查；
`no-web` 則排除該 capability。

## Packaging and verification

`packaging/package_official.py` 使用 Python standard library，依序執行下載、官方 binary
checksum、safe extraction、metadata generation、deterministic archive、package checksum
與 local verification。archive 不提交 Git，`.sha256` 與 `.manifest.json` 保留作為
evidence，archive 上傳 GitHub Release。

local verification 必須檢查：

1. package checksum 與 manifest 一致。
2. archive 只含 allowlisted runtime files。
3. binary 存在；Linux binary 保留 executable bit。
4. `README.md` 存在且有 `Prerequisites`、`PATH`、`User guide`、`Boundary`、`Links` sections。
5. `ZELLIJ-USER-GUIDE.md` 存在且包含兩種使用情境與官方資料來源。
6. package README 有 project 與 upstream links。
7. Linux/Windows unit contract 不需要 target host runtime 才可執行。

Linux `surfer` 的既有 runtime acceptance 是歷史證據，包含 `--version`、`setup --check`、
default layout 與 bundled plugin dump；依目前決策，本次只更新文件與 package contract，
不重跑該實驗。Windows runtime gate 仍待另一台 Windows host。

## Distribution

Git repository 保存 scripts、docs、tests、checksum、manifest；`.tar.gz`/`.zip` 由
GitHub Release tag `zellij-v0.45.1` 發佈。內網交付流程是：下載 Release assets → 驗證
`.sha256` → 將完整 archive 與 metadata 同步到內網檔案區 → 使用者離線解壓執行。

Project URL：<https://github.com/swchen44/zellij_intranet>
