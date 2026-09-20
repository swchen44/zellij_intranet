# Zellij Offline Portable Packaging Implementation Plan

> Historical implementation record. The current authoritative official-bundle plan is
> [`2026-09-21-zellij-offline-bundle.md`](2026-09-21-zellij-offline-bundle.md). This file
> is retained because it records the original source-build investigation and completed
> `surfer` Linux evidence.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 從固定版本的官方 Zellij release binary 產生可在公司內網直接解壓執行的 Linux 與 Windows portable packages，並驗證兩個實際使用情境。

**Architecture:** 由 Python standard-library packager 下載固定 tag 的官方 target-specific archive，先用官方 `.sha256sum` 驗證解壓後 binary，再建立 portable archive。Linux 使用 `x86_64-unknown-linux-musl`，Windows 使用 `x86_64-pc-windows-msvc`；每個 artifact 附帶 release、variant、target、upstream binary SHA-256 與 package SHA-256 manifest。runtime package 不包含 Rust、Cargo、Cargo registry、WASM toolchain 或 Yazi/Claude Code/Codex。

**Tech Stack:** Python 3 standard library (`urllib`, `tarfile`, `zipfile`, `hashlib`, `json`), official GitHub Release assets, `tar`/`gzip`/ZIP runtime verification, SHA-256；Rust/Cargo/musl/MSVC 保留為 source-build fallback。

**Spec:** `docs/superpowers/specs/2026-09-20-zellij-offline-packaging-design.md`

## Strategy amendment (2026-09-20)

正式交付策略已改為「官方 release binary 優先，source build 作為 fallback」。
`packaging/package_official.py` 接受明確的 release version，下載官方
`no-web` 或 `full` assets，驗證官方解壓後 binary 的 `.sha256sum`，再產生 Linux
x86_64 與 Windows x86_64 portable archives、manifest 與本地 package checksum。

初始 acceptance 使用 `v0.45.1`、`no-web` 完成 Linux x86_64 official package 與
`surfer` temporary-directory runtime acceptance；packager 現在預設改用官方 `full`
variant。Windows x86_64 已完成官方 PE/package 與 checksum verification，但
Windows Terminal/ConPTY runtime gate 仍待真正 Windows host。ARM64 不列入本次預設
targets，也不做 runtime verification。後續 Tasks 的
Rust、Cargo、musl、MSVC 與 `cargo-xwin` 內容保留，僅在官方 release 缺少必要
variant、需要客製 source 或需要 reproducible source build 時使用。

## Implementation status (2026-09-20)

Linux x86_64 已完成 build、package、checksum、remote sandbox verification 與
`ssh -tt` interactive smoke。實際可連線的 SSH alias 是 `surfer`，也是本計畫
唯一使用的 Linux integration host。由於 upstream `cargo xtask ci cross` 會無條件嘗試 `cargo install
cross`，本次使用 Task 3 Step 2 的 air-gapped fallback；標準官方 cross pipeline
與 Windows native runtime gate 仍保留為後續工作，未被誤標為完成。

Windows packaging scripts 已加入。Apple Silicon Mac 已以 `cargo-xwin` + `clang-cl`
成功產出 `terminal-only` candidate binary、ZIP、manifest 與 checksum；Windows
native MSVC rebuild 與 Windows Terminal runtime gate 尚未完成。

借用主機的低記憶體、persistent swap、SSH daemon priority、第二條 SSH status
連線、build output 中斷恢復、plugin 數量判讀與 macOS verifier 限制，集中記錄在
`docs/superpowers/LESSONS-LEARNED.md`。

## Global Constraints

- 只以 tagged release 或固定 Git commit 建置，不以 moving `main` 交付。
- 官方 binary workflow 必須指定 tagged release version，不使用 `latest` 作為正式 package 輸入。
- 官方 binary workflow 預設使用 `full` variant；`no-web` 必須明確指定，並只驗證 Linux x86_64 與 Windows x86_64。
- ARM64 本次不列入預設 targets，也不宣稱已完成 ARM64 runtime verification。
- 本次基線來源固定為 package version `0.46.0`、source commit `474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb`、Git describe `v0.44.1-122-g474ea0cef`、Rust toolchain `1.95.0`。
- Linux target 固定為 `x86_64-unknown-linux-musl`；Windows 基線 target 為 `x86_64-pc-windows-msvc`。
- `surfer` 是目前指定且實際可連線的 x86_64 Linux integration host。驗證一律在獨立 sandbox 目錄進行，不移除或覆寫既有 Zellij 安裝。
- 不啟用 `disable_automatic_asset_installation`；builtin WASM plugins 必須保持 bundled。
- Linux 初版保留 upstream default features；Windows 初版固定使用
  `terminal-only`（`--no-default-features --features plugins_from_target`），保留
  bundled WASM plugins，排除兩個使用情境不需要的 `vendored_curl` 與
  `web_server_capability`。若需求日後包含 web/share，必須另建 profile 並在 Windows
  native host 驗證。
- Linux 產物使用 `tar.gz`，保留 executable bit；Windows 產物使用 `zip`，內含 `zellij.exe`。
- 兩個使用情境中的 Claude Code、Codex、Yazi 都視為目標主機上已安裝的外部 command，不納入 Zellij package。
- 每次交付都必須在 clean runtime environment 驗證，不以 build machine 可以執行作為完成條件。Linux 必須在 `surfer` 這台 x86_64 host 完成實機驗收。
- 所有跨平台 package script 必須 fail fast，並在輸出中列出 version、commit、target、feature profile 與 artifact path。

---

### Task 1: 固定版本與實際主機 target matrix

**Files:**
- Create: `packaging/targets.toml`
- Create: `README.md`
- Read: `zellij/Cargo.toml`
- Read: `zellij/rust-toolchain.toml`

**Interfaces:**
- Consumes: source checkout、實際 Linux SSH hosts 的 `uname -m`/`ldd --version`、Windows host architecture。
- Produces: 一份可供 build scripts 與驗收使用的 target matrix。

- [x] **Step 1: 建立 artifact target 設定**

  在 `packaging/targets.toml` 固定以下內容：

  ```toml
  package_version = "0.46.0"
  source_commit = "474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb"
  source_describe = "v0.44.1-122-g474ea0cef"
  rust_toolchain = "1.95.0"
  linux_targets = ["x86_64-unknown-linux-musl"]
  windows_targets = ["x86_64-pc-windows-msvc"]
  feature_profile = "default"
  bundled_plugins = true

  [linux_hosts.surfer]
  ssh_alias = "surfer"
  architecture = "x86_64"
  target = "x86_64-unknown-linux-musl"
  verification_mode = "sandbox"
  ```

- [x] **Step 2: 盤點 Linux 遠端主機**

  對每一種實際主機執行：

  ```bash
  ssh -o BatchMode=yes -o ConnectTimeout=10 surfer \
    'uname -m; uname -srm; getconf LONG_BIT; sed -n "s/^PRETTY_NAME=//p" /etc/os-release; command -v bash; command -v sh; command -v tar; command -v file; command -v readelf; command -v script; command -v timeout; command -v zellij; zellij --version'
  ```

  `x86_64` 對應 `x86_64-unknown-linux-musl`。`surfer` 的實測結果必須寫入 `packaging/acceptance/linux-matrix.md`：確認它是 64-bit x86_64 Linux，並記錄既有 Zellij installation 作為 baseline/reference；package test 不使用既有安裝，也不移除它。

- [x] **Step 3: 固定來源版本與版本輸出格式**

  建置前執行：

  ```bash
  cd zellij
  git describe --tags --always --dirty
  git rev-parse HEAD
  cargo metadata --format-version 1 --no-deps
  rustc +1.95.0 --version
  cargo --version
  ```

  驗證 `git rev-parse HEAD` 等於 `474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb`，`git describe --tags --always` 等於 `v0.44.1-122-g474ea0cef`，且 checkout 是 clean。若任一條件不符，停止 packaging；manifest 不得把其他來源誤宣告成正式 artifact。

- [x] **Step 4: 寫清楚兩個情境的邊界**

  在 `README.md` 記錄：情境一使用 Linux binary，Windows 端只使用 Windows Terminal + SSH；情境二使用 Windows binary，子程式由 Windows shell 提供。明確寫出 Yazi 不由此 package 安裝。

- [x] **Step 5: 驗證設定與來源一致**

  執行：

  ```bash
  test "$(sed -n 's/^version = "\([^"]*\)"/\1/p' zellij/Cargo.toml | head -n 1)" = "0.46.0"
  test "$(git -C zellij rev-parse HEAD)" = "474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb"
  test "$(git -C zellij describe --tags --always)" = "v0.44.1-122-g474ea0cef"
  git -C zellij diff --check
  ```

  Expected: version 相符，且 packaging 文件沒有 whitespace error。

### Task 2: 建立可重現的 build runner 與 dependency policy

**Files:**
- Create: `packaging/BUILDING-OFFLINE.md`
- Create: `packaging/check-build-tools.sh`
- Modify: `zellij/.github/workflows/release.yml` only if internal CI will own the artifact build

**Interfaces:**
- Consumes: Task 1 的 target matrix、固定的 `Cargo.lock`、Rust toolchain。
- Produces: 可在有網路的 build runner 建置，並可把完成的 binary 帶入完全離線 runtime environment 的流程。

- [x] **Step 1: 把 build-time 與 runtime dependency 分開寫入文件**

  `BUILDING-OFFLINE.md` 必須列出：Rust `1.95.0`、`wasm32-wasip1`、Linux musl linker/toolchain、`cross`、`protoc`、Windows MSVC、NASM。文件同時寫明這些不進入使用者 package。

- [x] **Step 2: 實作 build tool preflight**

  `check-build-tools.sh` 應檢查 `git`, `rustc`, `cargo`, `rustup`, `protoc`，以及 Linux build 時的 `cross` 或 `musl-gcc`。找不到任何工具時以非零狀態結束，並列出缺少的工具名稱。

- [x] **Step 3: 固定 Cargo lock 與 Rust targets**

  Linux build runner 執行：

  ```bash
  rustup toolchain install 1.95.0
  rustup target add --toolchain 1.95.0 wasm32-wasip1 x86_64-unknown-linux-musl
  cargo metadata --locked --format-version 1 --no-deps
  ```

  標準 Linux artifact build 對兩個 target 各執行一次 source 內的官方 pipeline：

  ```bash
  cargo xtask ci cross x86_64-unknown-linux-musl
  cargo xtask ci build-release
  ```

  這些 commands 會依照目前 source 的順序處理 protobuf、release builtin plugins 與 cross-compiled native binary。

  Windows build runner 執行：

  ```powershell
  rustup toolchain install 1.95.0
  rustup target add --toolchain 1.95.0 wasm32-wasip1
  cargo metadata --locked --format-version 1 --no-deps
  ```

- [x] **Step 4: 定義真正離線 build runner 的預載策略**

  若公司連 build runner 也沒有外網，先在有網路的 staging machine 預載 Cargo registry、git dependencies、Rust toolchain、`cross`、`protoc`、musl toolchain 與 Windows build tools，再把 build cache 搬入。執行 build 時設 `CARGO_NET_OFFLINE=true`，並禁止 script 自動 `cargo install` 或下載工具。原因是目前 `zellij/xtask/src/ci.rs` 的 `cross_compile` 會先呼叫 `cargo install cross`，即使 `cross` 已存在也不會跳過。

  offline fallback 仍先呼叫 `cargo xtask build --release --plugins-only`，再執行預載好的 `cross build --locked --release --target x86_64-unknown-linux-musl`。這保留 protobuf 與 plugin build 順序，只避開會觸發下載的 wrapper。這個階段只解決「如何建置」，不把整個 Cargo cache 塞進發給使用者的 archive。

- [x] **Step 5: 驗證 dependency policy**

  在 clean runtime machine 先確認：

  ```bash
  command -v cargo || true
  command -v rustc || true
  command -v openssl || true
  ```

  Expected: 即使上述工具不存在，完成的 Zellij binary 仍能進入 Task 3/Task 4 的 package smoke tests。

### Task 3: 建立 Linux portable artifact

**Files:**
- Create: `packaging/build-linux.sh`
- Create: `packaging/package-linux.sh`
- Create: `packaging/verify-linux.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1 的 `x86_64-unknown-linux-musl` target、Task 2 的 build runner、Zellij builtin plugin assets。
- Produces: `dist/zellij-x86_64-unknown-linux-musl.tar.gz`、同名 manifest 與 SHA-256 file。

- [ ] **Step 1: 使用官方 Linux release pipeline**

  標準 build runner 在 Zellij source root 執行：

  ```bash
  cargo xtask ci cross x86_64-unknown-linux-musl
  test -x target/x86_64-unknown-linux-musl/release/zellij
  cargo xtask ci build-release
  ```

  Expected: protobuf、release builtin plugins 與 Linux native binary 都由 source 內建 pipeline 產生。不得使用 `disable_automatic_asset_installation`。

- [x] **Step 2: 建立 air-gapped Linux fallback**

  只有在 build runner 完全離線時，`build-linux.sh` 才使用以下 fallback：

  ```bash
  cargo xtask build --release --plugins-only
  cross build --locked --release --target x86_64-unknown-linux-musl
  test -x target/x86_64-unknown-linux-musl/release/zellij
  ```

  `cross` 必須由 Task 2 預先提供；fallback 不得呼叫 `cargo install cross`。標準 runner 不得用 fallback 取代官方 pipeline。

- [x] **Step 3: 驗證 Linux binary 的 dependency 形態**

  `verify-linux.sh` 執行：

  ```bash
  binary=target/x86_64-unknown-linux-musl/release/zellij
  file "$binary"
  if readelf -lW "$binary" | grep -q ' INTERP '; then
    echo 'unexpected ELF interpreter: binary is not fully static'
    exit 1
  fi
  ldd "$binary" 2>&1 || true
  "$binary" --version
  ```

  Expected: `file` 顯示 Linux x86-64 executable，ELF 不含 `INTERP`；`ldd` 若輸出 `not a dynamic executable` 視為 static binary 的正常證據，`--version` 回傳 `0.46.0`。真正的 runtime 判定以 `surfer` clean Linux host 的實際啟動為準。

- [x] **Step 4: 組合 Linux archive**

  建立 `zellij-x86_64-unknown-linux-musl/`，至少包含：

  ```text
  zellij
  README.txt
  LICENSE.md
  BUILD-INFO.txt
  ```

  `BUILD-INFO.txt` 寫入 package version、Git describe、source commit、Rust toolchain、target、feature profile、builtin plugin status 與 build timestamp。用 tar 保留 executable bit：

  ```bash
  tar -czf dist/zellij-x86_64-unknown-linux-musl.tar.gz \
    -C dist/zellij-x86_64-unknown-linux-musl \
    zellij README.txt LICENSE.md BUILD-INFO.txt
  sha256sum dist/zellij-x86_64-unknown-linux-musl.tar.gz \
    > dist/zellij-x86_64-unknown-linux-musl.tar.gz.sha256
  ```

- [x] **Step 5: 在空目錄執行 Linux package smoke test**

  ```bash
  test_dir="$(mktemp -d)"
  tar -xzf dist/zellij-x86_64-unknown-linux-musl.tar.gz -C "$test_dir"
  package_dir="$test_dir/zellij-x86_64-unknown-linux-musl"
  "$package_dir/zellij" --version
  "$package_dir/zellij" setup --check
  "$package_dir/zellij" setup --dump-layout default > "$test_dir/default.kdl"
  test -s "$test_dir/default.kdl"
  plugin_dir="$test_dir/dumped-plugins"
  "$package_dir/zellij" setup --dump-plugins "$plugin_dir"
  test "$(find "$plugin_dir/plugins" -name '*.wasm' | wc -l | tr -d ' ')" -ge 12
  ```

  Expected: package 不需要 source tree、`target/`、Cargo cache 或外部 plugin directory 即可完成 commands；`setup --check` 只負責顯示路徑，builtin plugin 是否 bundled 以 `--dump-plugins` 與 default layout 測試判定。

### Task 4: 建立 Windows portable artifact

**Files:**
- Create: `packaging/build-windows.ps1`
- Create: `packaging/package-windows.ps1`
- Create: `packaging/build-windows-local.sh`
- Create: `packaging/package-windows-local.sh`
- Create: `packaging/check-windows-local-tools.sh`
- Create: `packaging/verify-windows.ps1`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1 的 `x86_64-pc-windows-msvc` target、Task 2 的 Windows build runner、Zellij builtin plugin assets。
- Produces: `dist/zellij-x86_64-pc-windows-msvc.zip`、同名 manifest 與 SHA-256 file。

- [ ] **Step 1: 準備 Windows build tools**

  Windows build runner 必須具備 Visual Studio MSVC toolchain、Rust `1.95.0`、`wasm32-wasip1` 與 NASM。執行：

  ```powershell
  rustup target add --toolchain 1.95.0 wasm32-wasip1
  where.exe nasm
  ```

  找不到 NASM 或 MSVC linker 時直接失敗，不改用 Windows GNU target 取代。

- [ ] **Step 2: 建置 Windows release binary**

  `build-windows.ps1` 設定 static CRT 後執行：

  ```powershell
  $env:RUSTFLAGS = "-C target-feature=+crt-static"
  cargo xtask ci build-release
  if (-not (Test-Path target\release\zellij.exe)) { throw "zellij.exe was not built" }
  ```

  Windows 初版使用 `terminal-only` profile，保留 builtin plugins，並以
  `--no-default-features --features plugins_from_target` 排除不需要的 web/share 與
  vendored OpenSSL。

- [ ] **Step 3: 驗證 Windows binary**

  ```powershell
  .\target\release\zellij.exe --version
  .\target\release\zellij.exe setup --check
  Get-Item .\target\release\zellij.exe | Select-Object Length, LastWriteTime
  ```

  Expected: version 是 `0.46.0`，`setup --check` 成功；builtin plugin 是否 bundled 由 Step 5 的 dump 與 clean runtime 測試判定，不把 `setup --check` 的文字輸出當成唯一證據。

- [ ] **Step 4: 組合 Windows zip**

  package root 使用 `zellij-x86_64-pc-windows-msvc/`，至少包含：

  ```text
  zellij.exe
  README.txt
  LICENSE.md
  BUILD-INFO.txt
  ```

  建立 archive 與 checksum：

  ```powershell
  Compress-Archive `
    -Path dist\zellij-x86_64-pc-windows-msvc\zellij.exe, `
          dist\zellij-x86_64-pc-windows-msvc\README.txt, `
          dist\zellij-x86_64-pc-windows-msvc\LICENSE.md, `
          dist\zellij-x86_64-pc-windows-msvc\BUILD-INFO.txt `
    -DestinationPath dist\zellij-x86_64-pc-windows-msvc.zip -Force
  (Get-FileHash dist\zellij-x86_64-pc-windows-msvc.zip -Algorithm SHA256).Hash.ToLower() `
    | Out-File -Encoding ascii dist\zellij-x86_64-pc-windows-msvc.zip.sha256
  ```

- [ ] **Step 5: 在沒有 build tools 的 clean Windows profile 解壓測試**

  解壓到短路徑，例如 `C:\Tools\zellij\`，然後執行：

  ```powershell
  where.exe cargo 2>$null
  where.exe rustc 2>$null
  where.exe openssl 2>$null
  where.exe cl 2>$null
  .\zellij-x86_64-pc-windows-msvc\zellij.exe --version
  .\zellij-x86_64-pc-windows-msvc\zellij.exe setup --check
  $smoke = Join-Path $env:TEMP "zellij-portable-smoke"
  New-Item -ItemType Directory -Force $smoke | Out-Null
  .\zellij-x86_64-pc-windows-msvc\zellij.exe setup --dump-layout default | Out-File "$smoke\default.kdl"
  .\zellij-x86_64-pc-windows-msvc\zellij.exe setup --dump-plugins "$smoke\plugins"
  if ((Get-ChildItem "$smoke\plugins" -Recurse -Filter *.wasm).Count -lt 12) { throw "builtin plugins were not dumped" }
  ```

  驗收條件是：在 deny-egress 的 clean Windows profile 中，即使 `cargo`、`rustc`、`openssl`、`cl` 都不存在於 `PATH`，Zellij 仍能啟動、執行 `setup --check`、dump default layout 與 12 個 builtin plugins，且 Windows loader 不回報缺少 private DLL 或 Visual C++ runtime。若 clean host 啟動失敗，Windows artifact 未通過驗收；不能把 `+crt-static` 當成已驗證結果。

### Task 5: 共用 package manifest、checksum 與驗證入口

**Files:**
- Create: `packaging/manifest.sh`
- Create: `packaging/verify-package.sh`
- Create: `packaging/verify-package.ps1`
- Modify: `packaging/build-linux.sh`
- Modify: `packaging/build-windows.ps1`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 3 與 Task 4 的 binary/archive。
- Produces: 統一格式的 manifest、checksum 與可重跑的驗證結果。

- [x] **Step 1: 定義 manifest 欄位**

  每個 package manifest 必須包含以下欄位：

  ```json
  {
    "product": "zellij",
    "version": "0.46.0",
    "source_commit": "474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb",
    "source_describe": "v0.44.1-122-g474ea0cef",
    "rust_toolchain": "1.95.0",
    "target": "x86_64-unknown-linux-musl",
    "feature_profile": "default",
    "bundled_plugins": true,
    "archive": "zellij-x86_64-unknown-linux-musl.tar.gz",
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
  }
  ```

  Windows manifest 將 `target` 與 `archive` 替換成 Windows artifact 的值。

- [x] **Step 2: 驗證 archive 內容**

  `verify-package.sh` 必須拒絕以下情況：archive 缺少主 binary、binary 名稱不符 target、`BUILD-INFO.txt` 缺少 package version/source describe/source commit/Rust toolchain、archive 內出現 `target/`、`.cargo/` 或 Cargo registry。

- [x] **Step 3: 驗證 checksum 與 executable bit**

  Linux：用 `sha256sum -c` 驗證 archive；解壓後檢查 `test -x`。Windows：用 `Get-FileHash` 比對 manifest。Windows 不使用 executable bit 判斷。

- [ ] **Step 4: 加入重複 build 檢查**

  在同一個 source commit、同一個 build image/toolchain 與同一個 feature profile 重建兩次，至少比較 binary hash、archive manifest 與 target。若 timestamp 造成 archive hash 不同，將 archive timestamp 正規化，或把 timestamp 從可重現的 manifest hash 排除並另外記錄。

- [ ] **Step 5: 建立單一驗證入口**

  `README.md` 只指向兩個入口：Linux `./packaging/verify-package.sh`，Windows `./packaging/verify-package.ps1`。任何 package release 前必須先跑這兩個入口，輸出保存到 artifact release record。

### Task 6: Linux x86_64 integration test 與 surfer sandbox

**Files:**
- Create: `packaging/acceptance/linux-matrix.md`
- Create: `packaging/acceptance/linux-matrix.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 3 的 Linux archive、`surfer` host inventory、SSH、可限制外連的測試環境。
- Produces: x86_64 host mapping、clean package smoke test、builtin plugin test 與不影響既有安裝的 Linux acceptance record。

- [x] **Step 1: 固定 x86_64-to-artifact mapping**

  `linux-matrix.sh` 先執行 host inventory，再確認 `surfer` 只能使用 x86_64 artifact；不得只依 host name 或「看起來能啟動」判斷：

  ```bash
  host=surfer
  architecture="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" 'uname -m')"
  case "$architecture" in
    x86_64) linux_target=x86_64-unknown-linux-musl ;;
    *) echo "unsupported Linux architecture: $architecture" >&2; exit 1 ;;
  esac
  test -f "dist/zellij-$linux_target.tar.gz"
  ```

  `linux-matrix.md` 必須記錄：`surfer x86_64 → x86_64-unknown-linux-musl`。

- [x] **Step 2: 建立不碰既有 Zellij 的 surfer sandbox**

  在 `surfer` 建立由 `mktemp` 產生的獨立目錄，把 archive 透過 SSH stream 解壓；不得寫入既有 Zellij 安裝目錄或既有 PATH：

  ```bash
  remote_tmp="$(ssh -o BatchMode=yes -o ConnectTimeout=10 surfer \
    'mktemp -d "${TMPDIR:-/tmp}/zellij-package.XXXXXX"')"
  ssh surfer "tar -xzf - -C '$remote_tmp'" \
    < "dist/zellij-x86_64-unknown-linux-musl.tar.gz"
  ```

  測試前後都保存以下 baseline；`ZELLIJ_PATH` 與 `ZELLIJ_VERSION` 必須維持原值：

  ```bash
  ssh surfer 'command -v zellij; zellij --version'
  ```

  記錄 `surfer` 的既有 Zellij path/version。此步驟不移除或覆寫既有安裝，也不停止或重啟使用者既有 session。

- [x] **Step 3: 在 surfer sandbox 驗證 package 內容與 clean runtime**

  在遠端執行以下檢查，所有 config/cache 都指向 sandbox；若公司測試網路可控，使用 deny-egress profile 執行：

  ```bash
  ssh surfer "set -eu
  package_dir='$remote_tmp/zellij-x86_64-unknown-linux-musl'
  file \"\$package_dir/zellij\"
  if readelf -lW \"\$package_dir/zellij\" | grep -q ' INTERP '; then
    echo 'unexpected ELF interpreter in x86_64 package' >&2
    exit 1
  fi
  XDG_CONFIG_HOME='$remote_tmp/config' XDG_CACHE_HOME='$remote_tmp/cache' \
    \"\$package_dir/zellij\" --version
  XDG_CONFIG_HOME='$remote_tmp/config' XDG_CACHE_HOME='$remote_tmp/cache' \
    \"\$package_dir/zellij\" setup --check
  XDG_CONFIG_HOME='$remote_tmp/config' XDG_CACHE_HOME='$remote_tmp/cache' \
    \"\$package_dir/zellij\" setup --dump-layout default > '$remote_tmp/default.kdl'
  test -s '$remote_tmp/default.kdl'
  XDG_CONFIG_HOME='$remote_tmp/config' XDG_CACHE_HOME='$remote_tmp/cache' \
    \"\$package_dir/zellij\" setup --dump-plugins '$remote_tmp/plugins'
  test \"\$(find '$remote_tmp/plugins' -name '*.wasm' | wc -l | tr -d ' ')\" -ge 12
  "
  ```

  Expected: `file` 顯示 Linux x86-64 executable；`readelf` 沒有 `INTERP`；version、default layout、至少 12 個 builtin WASM plugins 都成功；清空 cache 後仍不需要下載 plugin。`ldd` 若顯示 `not a dynamic executable` 是可接受的 static binary 證據，不單獨作為失敗條件。

- [ ] **Step 4: 驗證 x86_64 interactive SSH path**

  從 Windows Terminal 使用強制 pseudo-terminal，執行 sandbox binary 而非 PATH 中的 Snap binary：

  ```bash
  ssh -tt surfer \
    "cd '$remote_tmp/zellij-x86_64-unknown-linux-musl' && exec ./zellij --session x86-package-smoke"
  ```

  驗證 terminal resize、mouse、UTF-8/CJK、colour、alternate screen、detach/attach、OSC 52 copy/paste，以及在 pane 中啟動 `claude`、`codex`、`yazi`。這裡只驗證三個 command 的啟動與 terminal input/output，不研究 Yazi dependency。

- [x] **Step 5: 產生 failure evidence 並清理 sandbox**

  `linux-matrix.md` 保存 host `uname -m`、kernel/OS、artifact target、`file`、`--version`、plugin count、interactive result 與測試時間。只有在完整保存 evidence 後，才刪除本次由 `mktemp` 建立且已驗證路徑格式的 `remote_tmp`；不得使用未展開或不受限的 recursive delete。最後再次執行：

  ```bash
  ssh surfer 'command -v zellij; zellij --version'
  ```

  Expected: path/version 與測試前 baseline 相同，證明 sandbox 驗證沒有替換既有安裝。

### Task 7: 驗收情境一，Windows Terminal → SSH → Linux Zellij

**Files:**
- Create: `packaging/acceptance/ssh-linux.md`
- Create: `packaging/acceptance/ssh-linux.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 3 的 `x86_64-unknown-linux-musl` archive、`surfer` Linux SSH host、Windows Terminal、使用者已安裝的 Claude Code/Codex/Yazi。
- Produces: 一份實際 SSH 使用驗收紀錄與 failure evidence。

- [x] **Step 1: 以短路徑部署 x86_64 Linux binary**

  先以 `uname -m` 確認 `surfer` 是 `x86_64`，只能使用 `zellij-x86_64-unknown-linux-musl.tar.gz`。在遠端 host 解壓到 `/opt/tools/zellij/` 或使用者 home 下的短路徑，確認：

  ```bash
  /opt/tools/zellij/zellij --version
  /opt/tools/zellij/zellij setup --check
  ```

- [x] **Step 2: 強制 SSH pseudo-terminal**

  從 Windows Terminal 使用：

  ```bash
  ssh -tt user@linux-host 'cd /opt/tools/zellij && exec ./zellij --session company'
  ```

  Expected: 能進入 Zellij，terminal size 正確，detach 後可用 `zellij attach company` 重新連接。

- [ ] **Step 3: 驗證三個使用者 command 的啟動路徑**

  在 Linux Zellij 中分別開 pane 並執行 `claude`、`codex`、`yazi`。驗收只確認 command 能啟動、輸入輸出能通過 SSH、pane 可切換；不分析 Yazi 的 runtime、terminal protocol 或 dependency。

- [ ] **Step 4: 驗證 SSH terminal 行為與無外網啟動**

  先清除 disposable user cache，再用 deny-egress 的測試環境啟動 default layout，確認 builtin plugins 可載入且沒有 plugin download requirement。接著手動驗證 resize、mouse、UTF-8/CJK、colour、alternate screen、detach/attach。copy/paste 要特別測試 OSC 52，並把結果記在 `ssh-linux.md`，因為 remote Zellij 可用的 clipboard path 受 terminal 與 SSH 傳輸能力限制。

- [x] **Step 5: 驗證主機相容性邊界**

  若 `surfer` 不是 `x86_64`，停止交付並修正 target mapping；不得用「看起來能啟動」取代 architecture check。Task 6 的 sandbox record 必須通過後，`surfer` 才能列入正式交付 host。

### Task 8: 驗收情境二，Windows Terminal → Windows Zellij

**Files:**
- Create: `packaging/acceptance/windows-native.md`
- Create: `packaging/acceptance/windows-native.ps1`
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 4 的 Windows archive、Windows Terminal、Windows shell、使用者已安裝的 Claude Code/Codex/Yazi。
- Produces: clean Windows profile 的啟動與互動驗收紀錄。

- [ ] **Step 1: 解壓到短路徑並確認使用者不需要 admin**

  先解壓到 `C:\Tools\zellij\`，再從 Windows Terminal 執行：

  ```powershell
  C:\Tools\zellij\zellij.exe --version
  C:\Tools\zellij\zellij.exe setup --check
  ```

  Expected: 不修改 system PATH、不需要 MSI、不需要 admin 即可啟動。若公司政策要求 PATH，另記錄為 optional MSI requirement。

- [ ] **Step 2: 驗證 native Windows terminal path**

  在 Windows Terminal 中啟動 Zellij，確認 ConPTY 下的 resize、mouse、copy/paste、Unicode/CJK、PowerShell 或公司指定 shell 都正常。

- [ ] **Step 3: 驗證三個使用者 command**

  在三個 pane 分別執行 `claude`、`codex`、`yazi`，只驗證 command 可由 Windows shell 啟動與接受終端輸入輸出。若 command 不在 `PATH`，將它視為 Windows tool deployment 問題，不修改 Zellij package 來繞過。

- [ ] **Step 4: 驗證 clean runtime dependency**

  在沒有 Rust/Cargo/OpenSSL/Visual Studio build tools 的 clean Windows profile 重新解壓並啟動。把 `where.exe cargo`, `where.exe rustc`, `where.exe openssl`, `where.exe cl` 的結果與 Zellij 啟動結果一併保存。若 Windows loader 回報缺少 private DLL 或 Visual C++ runtime，artifact 失敗；Windows system DLL 才屬於 OS 前提，不列為 portable package 內容。

- [ ] **Step 5: 驗證 config/cache 不依賴 archive write access**

  將 archive 放在使用者可讀但不可寫的資料夾，使用 `zellij setup --check` 確認 config、cache、session IPC 使用使用者 profile 的路徑。若公司要把 config 放到指定位置，使用 `ZELLIJ_CONFIG_DIR` 或 `--config-dir`，不要修改 binary。

### Task 9: 內網交付、升版與 optional MSI

**Files:**
- Modify: `README.md`
- Modify: `zellij/.github/workflows/release.yml` only when CI publishing is approved
- Read: `zellij/wix/main.wxs`

**Interfaces:**
- Consumes: Task 5、Task 6、Task 7、Task 8 的 verified artifacts。
- Produces: 內網 artifact drop、升版規則與回滾方式。

- [ ] **Step 1: 定義 artifact drop 結構**

  每次交付以 version directory 分隔：

  ```text
  zellij/0.46.0/
  ├── zellij-x86_64-unknown-linux-musl.tar.gz
  ├── zellij-x86_64-unknown-linux-musl.manifest.json
  ├── zellij-x86_64-unknown-linux-musl.tar.gz.sha256
  ├── zellij-x86_64-pc-windows-msvc.zip
  ├── zellij-x86_64-pc-windows-msvc.manifest.json
  └── zellij-x86_64-pc-windows-msvc.zip.sha256
  ```

- [ ] **Step 2: 定義升版流程**

  先在 x86_64 Linux（目前為 `surfer`）與一台 Windows Terminal host 完成全部 acceptance tests，再把相同 hash 的 archive 複製到內網 share。保留上一版 artifact，升版失敗時只切回上一版資料夾，不覆寫既有 binary。

- [ ] **Step 3: 定義安全檢查**

  交付前比對 source commit、manifest、SHA-256。package 只允許包含 binary、license、README、build info；不得把 secrets、Cargo credentials、SSH key、公司 config 或使用者工具打包進去。

- [ ] **Step 4: 評估是否需要 MSI**

  只有在需要 Add/Remove Programs、正式 PATH 管理、per-user/per-machine 安裝或企業軟體派送時才啟用既有 WiX flow。MSI build 使用 `zellij/wix/main.wxs`，另產生 MSI SHA-256，不取代解壓即用的 ZIP。

- [ ] **Step 5: 完成 release gate**

  release gate 必須同時取得：Linux archive checksum、Windows archive checksum、兩個 clean runtime smoke test、Linux host mapping、SSH acceptance record、Windows native acceptance record、source commit 與版本對應表。缺一項就不發布到公司內網。

## Self-review checklist

- [ ] 情境一只依賴 Linux Zellij binary，沒有把 Windows native binary 誤放到 SSH host。
- [ ] 情境二只依賴 Windows native MSVC binary，沒有要求使用者安裝 Cargo 或 Rust。
- [ ] Builtin plugins 仍嵌入 binary，package 不依賴 source tree 的 `assets/plugins`。
- [ ] Yazi 沒有被納入 dependency、build 或 packaging research。
- [ ] Linux `x86_64` artifact、host-to-artifact mapping、`surfer` sandbox、SSH pseudo-terminal、OSC 52、Windows ConPTY 與 config/cache 路徑都有驗收項目。
- [ ] `surfer` sandbox 驗證不會移除或覆寫既有 Zellij 安裝。
- [ ] Plan 沒有以 MSI、web server 或外部 plugin 作為初版必要條件。
