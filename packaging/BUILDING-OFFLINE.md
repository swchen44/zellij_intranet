# Zellij build-time/offline policy

## Build-time only

下列工具只存在於 build runner，不打包給使用者：

- Rust/Cargo `1.95.0`
- Rust targets `wasm32-wasip1` 與 `x86_64-unknown-linux-musl`
- `musl-gcc`、`protoc`、`file`、`readelf`、`tar`、`gzip`
- Cargo registry/cache 與 Git checkout
- `cross`（若未來使用官方 cross pipeline）
- Windows native build 的 Visual Studio/MSVC、NASM
- Mac candidate build 的 Homebrew LLVM、NASM、`cargo-xwin` 與其 Windows SDK/CRT cache
- Windows `terminal-only` profile 的 Rust feature flags：
  `--no-default-features --features plugins_from_target`

Linux runtime archive 只需要目標 Linux host、terminal、SSH server 與使用者要
在 pane 中執行的 command。

## Preflight

```bash
./packaging/check-build-tools.sh x86_64-unknown-linux-musl
```

缺少任何必要工具時會以 non-zero status 結束。build host 可以由管理員用 root
安裝 Rust、musl toolchain、compiler、protoc 與其他 build dependencies；這些
權限不會成為 runtime 使用者的要求。

## Low-memory runner

本專案的借用 `surfer` x86_64 runner 只有一顆 CPU 與約 960 MiB RAM。所有 build 都必須
固定：

```bash
export CARGO_BUILD_JOBS=1
```

`build-linux.sh` 另外關閉 release LTO、提高 codegen units 並降低 opt level，
避免 compiler peak memory 造成 OOM。建議 build host 配置至少 2 GiB persistent
swap；本次使用 `/swapfile`，並寫入 `/etc/fstab`：

```text
/swapfile none swap sw 0 0
```

設定後使用 `systemctl daemon-reload` 與 `swapon --show` 確認；重新開機後再
確認 swap 還在。swap 是 build host 的暫時資源，不會放入 portable archive。

若 compiler memory pressure 讓 SSH 不穩，可從第二條 SSH 只查精確的 `cargo`、
`rustc` process、RAM、swap 與 target binary。必要時暫時提高 SSH daemon master
process priority，完成 build 後恢復；不要從第二條 SSH 平行啟動 build。

## Air-gapped build

有網路的 staging machine 先準備 Rust toolchain、Cargo registry、Git dependencies
與所有 native tools，再把它們搬到 build runner。執行時可設定：

```bash
export CARGO_NET_OFFLINE=true
./packaging/build-linux.sh
```

目前 script 不會自動執行 `cargo install cross`，也不會在 package 中放入 Cargo
cache。這避免 build-time dependencies 污染 runtime artifact。

Mac 的 `cargo-xwin` 只負責產生 `x86_64-pc-windows-msvc` candidate。它下載或使用
快取的 Microsoft CRT/Windows SDK，這些只存在 build runner，不會進入 ZIP；candidate
仍必須交給 Windows host 做 loader、`zellij.exe`、Windows Terminal 與 ConPTY 驗證。
Mac candidate 與 native Windows package 都使用 `terminal-only` profile，避免為
不使用的 web/share capability 引入 vendored OpenSSL；這不代表完整 upstream
default feature set 已在 Mac 上成功 cross-build。
