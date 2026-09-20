# Zellij 內網封裝經驗與 Lessons Learned

最後更新：2026-09-20

這份文件保存目前實際 build、package 與 SSH 驗證得到的經驗。`surfer` 是借用的
x86_64 Linux build/test runner，不是正式部署主機；正式交付不能依賴它長期存在。

## 已固定的來源與產物

- Zellij version：`0.46.0`。
- source commit：`474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb`。
- Git describe：`v0.44.1-122-g474ea0cef`。
- Rust toolchain：`1.95.0`。
- Linux target：`x86_64-unknown-linux-musl`。
- Windows target：`x86_64-pc-windows-msvc`。
- Windows feature profile：`terminal-only`（`--no-default-features --features plugins_from_target`）。
- artifact：`zellij-x86_64-unknown-linux-musl.tar.gz`。
- artifact SHA-256：`be41a661f6f3c00b2e2a1b0dbc40313c05461018f2e91ba8b1f73d116dc46ca6`。

## 借用 build host 的限制

- `surfer` 是 Ubuntu 24.04 x86_64、單 CPU、約 960 MiB RAM。
- runtime 使用者沒有 root；build tools、`protoc`、Rust toolchain 與 musl
  compiler 可以由管理員以 root 安裝。
- 遠端沒有既有 `zellij` command；驗證仍然使用 package 的絕對路徑，不依賴
  `PATH` 中的既有版本。
- build host 已建立 2 GiB persistent `/swapfile`，`/etc/fstab` 為：

```text
/swapfile none swap sw 0 0
```

設定後以 `systemctl daemon-reload`、`swapon --show` 確認，重新開機後再確認。
swap 是 build host 的工具，不進入 package。

- 低記憶體 build 期間曾暫時提高 SSH daemon master process priority，避免
  compiler memory pressure 讓管理連線失去回應；這不是 Zellij runtime 需求，
  build 完成後應恢復 priority。
- 第二條 SSH 只能用來查 status。精確查 `pgrep -x cargo`、`pgrep -x rustc`、
  `free`、`swapon --show` 與 binary，不要平行啟動另一個 build。

## Build pipeline 的決策與失敗經驗

- upstream `cargo xtask ci cross` 目前會無條件嘗試 `cargo install cross`，不適合
  直接在 air-gapped runner 執行。
- 實際成功流程是先執行：

```text
cargo +1.95.0 xtask build --release --plugins-only
cargo +1.95.0 build --locked --release --target x86_64-unknown-linux-musl
```

- build script 固定 `CARGO_BUILD_JOBS=1`、`CARGO_INCREMENTAL=0`、
  `LTO=false`、`codegen-units=16`、`opt-level=2`，避免一顆 CPU、低 RAM 主機
  在 release code generation 期間 OOM。
- plugin build 產生 13 個 source-side WASM assets，runtime `setup --dump-plugins`
  實際 dump 12 個；後續驗收以 runtime dump 結果與 package 行為為準，不直接把
  source asset 數量當成使用者可見 plugin 數量。
- 第一次長時間 build 的 SSH output 曾中斷。正確恢復方式是從第二條 SSH 確認
  `cargo`/`rustc` 已結束、target binary 存在、`file`/`readelf`/`--version`
  通過，再繼續 package；不要看到 SSH output 中斷就刪除 target 或重跑平行 build。

## Package 與 runtime 驗證經驗

- binary 實測為 `ELF 64-bit LSB pie executable, x86-64, static-pie linked`，
  `readelf` 沒有 `INTERP`。這兩項要一起檢查，不能只看 version。
- builtin WASM plugins 內嵌 binary；在隔離的 `HOME`、XDG config/cache 與無外部
  plugin directory 下，`--version`、`setup --check`、default layout dump 與
  12 個 plugin dump 都成功。
- package 只包含 binary、README、license、build info，不包含 Rust、Cargo、
  source tree、registry、Yazi、Claude Code、Codex 或 SSH。
- Linux package verifier 需要 Linux 的 `readelf` 並會執行 Linux binary；在
  macOS build workstation 只能做 archive/checksum/contract checks，Linux
  runtime verifier 必須在 `surfer` 或其他相同 target 的 Linux host 執行。
- `ssh -tt` 互動 smoke 使用獨立 temporary package、`HOME`、
  `XDG_CONFIG_HOME`、`XDG_CACHE_HOME`。空的環境第一次會出現 Zellij first-run
  setup wizard，這是預期行為；測試結束後 temporary directory 會清理。
- Windows Terminal 本身尚未實機驗證，因此目前證據只代表 SSH PTY remote path，
  不代表 Windows ConPTY、resize、mouse、OSC 52 clipboard 已通過。

## Official release binary workflow

- 2026-09-20 起，Zellij 內網交付優先使用官方 GitHub Release binary，不需要在
  `surfer` 上安裝 Rust、Cargo、`protoc` 或 musl toolchain，也不需要重新編譯。
- Python entrypoint：`packaging/package_official.py`。版本必須明確指定，
  例如 `--version v0.45.1`；不使用 `latest`，避免 package 不可追溯。
- `package_official.py` 現在預設使用官方 `full` variant；`no-web` 必須明確指定。
  先前 `v0.45.1` 的初始 acceptance 使用 `no-web`，該 artifact 仍可作為精簡版
  baseline。
- `full` variant 包含 Web Server/Web Client capability，但 Web Server 預設不會自動
  啟動。若對內網其他主機開放，仍要設定 authentication、HTTPS、listen IP 與 port。
- 官方 release 的 `.sha256sum` 檔案驗證的是解壓後 `zellij` 或 `zellij.exe`，不是
  `.tar.gz`/`.zip` archive。正確順序是下載、解壓、找 root binary、比對 binary
  SHA-256，再重新封裝。
- 實際驗證版本：`v0.45.1`。Linux x86_64 binary SHA-256 為
  `0ec6ef07b63c6355c02ce18343d40ef5ef5af19e25313ea9009c8fceda29e94f`；Windows
  x86_64 binary SHA-256 為
  `3d01a2571076885f31a013b3bf1071fd1aba1db2e7b82190c68833737a625346`。
- official package 的 archive root 直接放 `zellij`/`zellij.exe`。舊 source-build
  acceptance 曾假設多一層 package directory，已改成同時支援兩種 layout。
- `ssh surfer` 的 Linux x86_64 temporary-directory acceptance 已通過：
  `--version`、`setup --check`、default layout 與 12 個 builtin plugins dump，且
  既有 Zellij command baseline 未改變。
- Python packager 會固定 TAR/GZIP/ZIP metadata timestamp、owner 與 entry order；
  相同官方 inputs 會產生相同 archive bytes，避免每次重跑只因 archive timestamp
  改變就得到不同 package SHA-256。
- macOS/Linux 可以驗證 release checksum、PE/ELF、archive content 與 package
  metadata；Windows Terminal、ConPTY、Windows loader、resize、mouse、detach/attach
  仍必須在真正 Windows host 驗證。
- ARM64 這一輪不列入 package 預設 targets，也不宣稱 ARM64 runtime 已驗證。

## Windows local candidate 經驗

- 本地環境是 Apple Silicon macOS。它可以用 `cargo-xwin` 取得 MSVC-compatible
  Windows SDK/CRT sysroot，產生 `x86_64-pc-windows-msvc` candidate。
- local candidate 需要 Rust target `x86_64-pc-windows-msvc`、`wasm32-wasip1`、
  `llvm-tools-preview`、Homebrew LLVM、NASM、`protoc` 與 `cargo-xwin`。
- 實際使用版本為 `cargo-xwin 0.23.1`、Homebrew LLVM `23.1.1`、NASM `3.02`；
  preflight 要檢查 host-specific `llvm-tools-aarch64-apple-darwin`，不能用
  `grep -Fx llvm-tools-preview` 判斷，因為 `rustup component list --installed`
  會輸出帶 host suffix 的名稱。
- 第一次 candidate build 缺少 `protoc`，在 plugin/protobuf stage 失敗；`protoc`
  必須列入 Mac 與 Windows build runner 的 preflight。
- `cargo-xwin` 的 `clang` backend 在 Homebrew LLVM 23 下會讓 `aws-lc-sys` 的
  HRSS SSE2 C code 與 MSVC `__m128i` headers 不相容。改用 cargo-xwin 官方預設的
  `clang-cl` backend 後，`aws-lc-sys` 可通過。
- Zellij 的 default `vendored_curl` feature 會拉入 `openssl-sys`，Mac cross-build
  會因 vendored OpenSSL 的 Perl configure 需要 Windows path semantics 而失敗。
  本次兩個 Windows 使用情境不需要 web/share，因此固定 `terminal-only` profile；
  它保留 release binary 內嵌的 WASM plugins，但排除 web/share 與 vendored OpenSSL。
- build script 還需把 `-Wno-error=unused-command-line-argument` 放入 `CFLAGS`/
  `CXXFLAGS`，讓 `aws-lc-sys` 的 compile-only sysroot `-L` 不被 `-Werror` 中止；
  C/C++ crates 另外要傳 `/MT`，不能只依賴 Rust 的 `+crt-static`，否則 PE import
  table 仍可能出現 `VCRUNTIME140.dll`。
- 本次 Mac candidate 已成功產生 PE32+ x86-64 binary，並完成 ZIP、manifest 與
  checksum：`zellij-x86_64-pc-windows-msvc.zip`，SHA-256 為
  `4fbd5b9b3225116bf8091209e6c315d45071b93dc6fbaa7c6ea23a4eb07da622`。
- 同一 binary 重新 package 時 ZIP entry timestamp 會讓 archive SHA-256 改變；目前
  尚未做 timestamp normalization/reproducible rebuild，所以 hash 只代表本次 release
  record，不能直接當成重建必然相同的證據。
- `llvm-objdump -p` 對重新產生的 PE binary 只看到 Windows system DLL（如
  `kernel32.dll`、`user32.dll`、`ws2_32.dll`），沒有 `VCRUNTIME140.dll`、MSVCP 或
  `api-ms-win-crt-*` import；這是 package-level evidence，不取代真實 Windows
  loader/runtime 驗收。
- `cargo-xwin` candidate 的 `build_method` 記為 `cargo-xwin-macos`，manifest 的
  `runtime_verification` 必須保持 `pending-windows-host`，直到真正 Windows host
  執行 verifier。
- Rust 官方對非 Windows host 交叉編譯 `*-windows-msvc` 的支援有限；candidate
  可以加快產出與檢查 PE/package，但不能取代 Windows native MSVC build 或
  Windows Terminal/ConPTY 驗收。
- 不改用 `x86_64-pc-windows-gnu` 或 MinGW，因為公司交付 target 固定為 MSVC。
- Mac 上可以檢查 `file` 顯示 PE32+ x86-64、package contents、manifest、checksum
  與 builtin plugin assets；不能在 Mac 上證明 Windows loader、static CRT、
  Windows system DLL、ConPTY 或 user shell 行為。

## 目前尚未完成

- Windows host runtime gate；目前已有官方 Windows PE/package 證據，但尚未在真正
  Windows host 執行 `zellij.exe`。
- Windows Terminal/ConPTY 實機、Claude Code/Codex/Yazi pane、resize、mouse、
  detach/attach 與 clean Windows profile。
- `terminal-only` 以外的完整 upstream default feature build；若未來需要 web/share，
  必須在真正 Windows host 重新規劃與驗證，不能把 Mac OpenSSL workaround 當正式支援。
- 官方 `cross` pipeline 的標準 runner 驗證，現階段只完成 air-gapped fallback。
- reproducible rebuild comparison。
- Windows Terminal 實機、Claude Code/Codex/Yazi pane、resize、mouse、detach/attach
  完整流程與 OSC 52 clipboard。
- 正式內網 artifact drop 與 rollback 流程。
