# Zellij 內網可攜式封裝設計

## 目標

從已固定版本的官方 Zellij release binary 產生可直接搬進公司內網的 target-specific 產物：

1. Linux `x86_64` 伺服器使用一份 `tar.gz`，由 Windows Terminal 透過 SSH 啟動。
2. Windows x64 使用的 `zip`，由 Windows Terminal 解壓後直接啟動。

使用者端只需要目標作業系統、終端機與要在 pane 中執行的工具。使用者端不安裝 Rust、Cargo、OpenSSL、WASM toolchain 或其他 Rust build dependencies。官方 binary 的下載與重新封裝在有外網的 staging machine 執行，內網 runtime 只解壓與執行。

目前實際 build/test 經驗與借用 `surfer` 主機的限制，集中記錄在
[`docs/superpowers/LESSONS-LEARNED.md`](../LESSONS-LEARNED.md)。

## 2026-09-20 策略修訂

正式交付改採官方 GitHub Release 的 prebuilt binary。source build、Mac
`cargo-xwin` candidate 與 Windows native MSVC build 都保留為 fallback 或研究路徑，
不再是一般版本更新的必要步驟。版本更新由
`packaging/package_official.py` 執行，輸入固定的 release tag，預設下載
official `no-web` variant 的 Linux x86_64 與 Windows x86_64 assets。

官方 `.sha256sum` asset 驗證的是解壓後的 `zellij` 或 `zellij.exe` binary。封裝器
必須先解壓、比對 binary SHA-256，再建立內網 portable archive，並額外記錄下載
archive 的本地 SHA-256。正式 package 不使用 `latest`，避免 moving release 造成
不可追溯的產物。ARM64 這一輪不列入預設 targets，也不做 runtime verification。

官方 Windows package 使用 `x86_64-pc-windows-msvc` asset，不接受 MinGW/GNU 取代。
目前預設 `full` variant，包含官方 Web Server/Web Client capability，但 Web Server
預設不會啟動。若只需要兩個 terminal/SSH/Yazi 情境的最小 capability，才明確使用
官方 `no-web` variant；兩種 variant 都必須在 Windows native host 驗證。

研究範圍不包含 Yazi 的安裝、封裝與相容性研究。Yazi 只在驗收時作為使用者已安裝的 pane command 啟動。

## 研究結論

### 1. Zellij 可以做成 binary-only portable package

目前 source checkout 的識別資訊必須整組保存：package version 是 `0.46.0`，source commit 是 `474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb`，Git describe 是 `v0.44.1-122-g474ea0cef`，Rust toolchain 是 `1.95.0`。package version 與 Git tag 描述不同時，四者都要寫入 manifest，避免日後只靠 `0.46.0` 無法重現來源。

release profile 已設定 LTO、strip 與單一 codegen unit。`zellij-utils/assets/plugins/*.wasm` 在 release build 時由 `include_bytes!` 嵌入 binary，預設不需要把 builtin plugins 另放在安裝目錄。

不要啟用 `disable_automatic_asset_installation`，否則 builtin plugins 不會嵌入 binary，使用者端必須額外提供 plugin directory。

### 2. 兩個情境必須分成兩個 target artifact

| 情境 | 需要的 Zellij binary | 建議產物 |
| --- | --- | --- |
| Windows Terminal → SSH → Linux x86_64 Zellij | Linux x86_64 host binary | `zellij-x86_64-unknown-linux-musl.tar.gz` |
| Windows Terminal → Windows Zellij | Windows native binary | `zellij-x86_64-pc-windows-msvc.zip` |

SSH 情境不需要在 Windows 啟動 Zellij；Windows 端只提供 Windows Terminal、SSH 與 OSC 52 傳輸。Linux host 必須確認為 x86_64，並使用 `x86_64-unknown-linux-musl` artifact。情境二才使用 Windows native Zellij 與 ConPTY。

### 3. Linux 優先使用 musl，Windows 使用 MSVC + static CRT

Linux `x86_64-unknown-linux-musl` 可降低對遠端主機 glibc 版本與 runtime library 的依賴。Windows 使用原生 `x86_64-pc-windows-msvc`，並沿用 upstream release workflow 的 `RUSTFLAGS="-C target-feature=+crt-static"`，目標是降低 Visual C++ runtime 依賴；是否能在公司 clean Windows 主機啟動，必須以實機驗收結果為準。

這兩項只能降低 runtime dependency，不能消除 kernel、Windows system APIs、terminal、shell、SSH server、使用者工具等平台前提。

### 4. 建置流程優先沿用 Zellij 官方 pipeline

標準 build runner 優先使用 source 內已有的 `cargo xtask ci cross x86_64-unknown-linux-musl` 與 `cargo xtask ci build-release`。這些 pipeline 會處理 protobuf code generation、builtin plugin build 與 native binary 的順序。

目前 `cargo xtask ci cross` 會先無條件執行 `cargo install cross`。因此 air-gapped build runner 需要預載 `cross` 並使用計畫中的 offline fallback，不能把標準 command 原封不動當成完全離線 command。

### 5. 先做可攜式 archive，不把 MSI 當成基線

解壓即用的需求最適合 `tar.gz` 與 `zip`。MSI 會修改 PATH、Registry 與安裝位置，適合日後要做正式 Windows 安裝管理時再加入。source checkout 已有 WiX v6 MSI 定義，可保留為後續選項。

### 6. build-time dependency 與 runtime dependency 要分開管理

Rust crates、`cross`、`protoc`、`musl-tools`、NASM、WASM target 都是 build-time dependency。它們不應被打包給使用者。若公司內部的 build runner 也完全離線，再另做 Cargo registry/cache 與工具鏈預載；這不是使用者端 portable package 的必要內容。

## 使用情境限制

### SSH 遠端 Linux

- Linux artifact 必須放在實際 Linux host 上，並依 CPU architecture 分包。
- `surfer` 是目前指定且借用中的 x86_64 Linux integration host；正式 artifact 驗收必須放在獨立 sandbox，不能覆寫或移除既有安裝。正式交付應改用可控、可重建的 build/test runner。
- SSH 必須配置 pseudo-terminal，驗收以 `ssh -tt` 為基準。
- remote clipboard 依賴 OSC 52；Linux host 上的本機 clipboard utility 不適用於 SSH remote session。
- Zellij、Claude Code、Codex、Yazi 都在 Linux host 上執行，這些工具的安裝不由 Zellij package 負責。
- archive 解壓路徑要短，避免 IPC socket path 受限。session name 也不能無限制增長。

### Windows native

- 只支援 Windows x64 基線 target `x86_64-pc-windows-msvc`。
- Windows Terminal 啟動 Zellij 時使用 ConPTY；要測試 resize、mouse、Unicode/CJK、copy/paste 與 shell child process。
- Claude Code、Codex、Yazi 必須已存在於 Windows shell 的 `PATH` 或由使用者自行指定路徑。
- Zellij 的 config、cache、session IPC 不應假設位於解壓資料夾。首次啟動用 `zellij setup --check` 記錄實際路徑。

## 基線驗收

每個 artifact 都必須通過：

1. SHA-256 驗證。
2. 在沒有 Rust、Cargo、OpenSSL、Zellij package manager 的 clean environment 解壓。
3. `zellij --version` 或 `zellij.exe --version` 成功。
4. `zellij setup --check` 成功，並另外用 `zellij setup --dump-plugins "$tmp/plugins"` 驗證 builtin `.wasm` 數量。
5. `zellij setup --dump-layout default` 成功，且 default layout 使用的 builtin plugins 可在無外網環境載入。
6. 清除 disposable user cache 後仍能啟動，並完成建立、detach、attach、kill session。
7. 目標情境中可在 pane 啟動 Claude Code、Codex 與 Yazi command。
8. 版本、Git describe、source commit、Rust toolchain、target、feature profile 都寫進 package manifest。

Linux artifact 另外必須通過 x86_64 architecture mapping、`file`/ELF interpreter 檢查，以及 `surfer` 實機的 runtime acceptance。`ldd` 顯示 `not a dynamic executable` 不算失敗，實際啟動與 builtin plugin 載入才是主要判定。

Mac candidate 目前已通過 `file` 的 PE32+ x86-64 檢查、ZIP 內容、manifest 與
SHA-256，並以 PE import table 檢查沒有 Visual C++ runtime DLL；這些證據不能取代
Windows loader、Windows Terminal/ConPTY、Windows shell 與 clean runtime 驗收。

## 來源

- 本地 source：`zellij/Cargo.toml`、`zellij/rust-toolchain.toml`、`zellij/zellij-utils/src/consts.rs`、`zellij/.github/workflows/release.yml`。
- 官方安裝文件：<https://zellij.dev/documentation/installation>
- 官方 Windows FAQ：<https://zellij.dev/documentation/faq>
- 官方 build / plugin packaging 說明：<https://github.com/zellij-org/zellij/blob/main/CONTRIBUTING.md>
