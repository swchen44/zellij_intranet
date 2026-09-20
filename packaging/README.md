# Zellij offline packages

目前正式優先流程是使用官方 release binary，再由
[`package_official.py`](package_official.py) 下載、驗證與重新封裝。操作方式與
驗收標準記錄在 [`OFFICIAL-BINARY.md`](OFFICIAL-BINARY.md)。

`package_official.py package` 預設使用官方 `full` variant；只有明確指定
`--variant no-web` 時才產生不含 Web capability 的精簡版本。

既有 source build scripts 保留作為 fallback，原因是未來可能需要官方沒有提供的
feature profile 或固定 source commit；一般內網交付不需要執行 source build。

source-build fallback 仍產生獨立的 Linux x86_64 portable package。Zellij、Yazi、
Claude Code 與 Codex 各自封裝；Zellij archive 不包含其他 command，也不需要 Rust、
Cargo、OpenSSL、WASM toolchain 或 Cargo registry 才能在 runtime 執行。一般交付請
使用 [`OFFICIAL-BINARY.md`](OFFICIAL-BINARY.md) 的官方 binary workflow。

借用的 `surfer` build/test runner、低記憶體 OOM 修正、persistent swap、offline
fallback、第二條 SSH status 連線與已知限制，集中記錄在
[`docs/superpowers/LESSONS-LEARNED.md`](../docs/superpowers/LESSONS-LEARNED.md)。

目前 Linux artifact 固定為：

```text
zellij-x86_64-unknown-linux-musl.tar.gz
```

## Build host

Build host 必須是 Linux x86_64，並具備 Rust `1.95.0`、`wasm32-wasip1`、
`x86_64-unknown-linux-musl`、`musl-gcc`、`protoc`、`tar`、`gzip`、`file` 與
`readelf`。這些是 build-time tools，不會進入 archive。

`surfer` 是目前可連線的 x86_64 test/build host；所有文件與驗證命令都使用此
SSH alias。

這台 host 只有一顆 CPU、記憶體很小，build script 強制 `CARGO_BUILD_JOBS=1`，
並使用低記憶體 release profile。不要同時編譯另一個 target。

```bash
./packaging/check-build-tools.sh x86_64-unknown-linux-musl
./packaging/build-linux.sh
```

`build-linux.sh` 會先以 upstream `cargo xtask build --release --plugins-only`
產生 protobuf 與 bundled WASM plugins，再以預裝的 musl linker 建立 Linux binary。
它不呼叫會自動下載 `cross` 的 `cargo xtask ci cross`，適合內網 build runner。

## Windows build modes

正式 Windows build 由 Windows native MSVC runner 執行：

```powershell
./packaging/build-windows.ps1
./packaging/package-windows.ps1
./packaging/verify-package.ps1 .\dist\zellij-x86_64-pc-windows-msvc.zip
```

本地 Apple Silicon Mac 可以先產生 candidate，但不能取代 Windows runtime gate。
candidate 使用 `cargo-xwin` 提供 MSVC-compatible Windows SDK/CRT sysroot：

```bash
brew install llvm nasm protobuf
rustup target add --toolchain 1.95.0 wasm32-wasip1 x86_64-pc-windows-msvc
rustup component add --toolchain 1.95.0 llvm-tools-preview
cargo +1.95.0 install --locked cargo-xwin
./packaging/check-windows-local-tools.sh
./packaging/build-windows-local.sh
./packaging/package-windows-local.sh
```

Windows 初版 package 固定使用 `terminal-only` feature profile：保留 bundled WASM
plugins，但不啟用 web/share capability，也不拉入 vendored OpenSSL。這符合
Windows Terminal + Zellij + Yazi 的兩個使用情境；若日後需要 Zellij web/share，應
另做 feature profile 與完整 Windows native build，不要直接混用此 ZIP。

Mac candidate 的 manifest 會標示 `build_method=cargo-xwin-macos`、
`feature_profile=terminal-only` 與
`runtime_verification=pending-windows-host`。不能在 Mac 上執行 `zellij.exe`、
驗證 Windows loader 或宣稱 Windows Terminal/ConPTY 通過。

## Package and verify

```bash
./packaging/package-linux.sh
./packaging/verify-package.sh \
  dist/zellij-x86_64-unknown-linux-musl.tar.gz
```

輸出包含：

```text
dist/zellij-x86_64-unknown-linux-musl.tar.gz
dist/zellij-x86_64-unknown-linux-musl.manifest.json
dist/zellij-x86_64-unknown-linux-musl.tar.gz.sha256
```

package 內至少包含 `zellij`、`README.txt`、`LICENSE.md` 與 `BUILD-INFO.txt`。
Builtin plugins 會嵌入 binary；`setup --dump-plugins` 應能在無網路、無外部
plugin directory 下輸出至少 12 個 `.wasm`。

## Remote sandbox acceptance

驗證只使用 remote temporary directory，不會移除、覆寫或停止既有 Zellij：

```bash
ZELLIJ_SSH_HOST=surfer \
  ./packaging/acceptance/linux-matrix.sh \
  dist/zellij-x86_64-unknown-linux-musl.tar.gz
```

若要進入互動測試，使用：

```bash
ZELLIJ_SSH_HOST=surfer \
  ./packaging/acceptance/ssh-linux.sh \
  dist/zellij-x86_64-unknown-linux-musl.tar.gz
```

該 script 會透過 `ssh -tt` 啟動 sandbox binary；Windows Terminal 端只負責
terminal、SSH 與 terminal protocol。Yazi、Claude Code、Codex 必須另外存在於
Linux host 的 shell environment。
