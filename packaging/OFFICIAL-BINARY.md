# Official Zellij Binary Packaging

這是公司內網交付 Zellij 的主要流程。它使用 Zellij 官方 GitHub Release 的
prebuilt binary，不需要 Rust、Cargo、`protoc`、musl toolchain、Windows MSVC
或 source tree 才能產生 runtime package。

目前驗證矩陣只包含：

```text
linux-x86_64   -> x86_64-unknown-linux-musl
windows-x86_64 -> x86_64-pc-windows-msvc
```

ARM64 這一輪不下載、不做 runtime verification。官方 release 仍可能提供 ARM64
asset，但不能把「有 asset」標示成「已通過公司驗收」。

打包器預設使用官方 `full` variant，包含 Zellij Web Server/Web Client capability；
Web Server 預設不會自動啟動。若只需要純 terminal、SSH、Zellij、Yazi，才明確
指定 `--variant no-web`。

## 產生 package

在有外網的 staging machine 執行，版本必須明確指定：

```bash
python3 packaging/package_official.py package \
  --version v0.45.1 \
  --output-dir dist/official
```

省略 `--layout` 時預設產生 `flat-bin`。若要重現舊的 archive root，才明確指定：

```bash
python3 packaging/package_official.py package \
  --version v0.45.1 \
  --layout standard \
  --output-dir dist/official
```

省略 `--variant` 時預設為 `full`。這是正式打包指令。若只需要不含 Web capability
的精簡版本，才使用：

```bash
python3 packaging/package_official.py package \
  --version v0.45.1 \
  --variant no-web \
  --output-dir dist/official
```

每次 package 會依序對 Linux x86_64、Windows x86_64 執行：

1. 下載官方 archive。
2. 下載同版本、同 variant、同 target 的官方 `.sha256sum`。
3. 解壓 archive。
4. 用官方 checksum 驗證解壓後的 `zellij` 或 `zellij.exe` binary。
5. 只取 binary 與 package metadata，重新建立 portable archive。
6. 產生 package `.sha256` 與 `.manifest.json`。
7. 立即執行本地 package verification。

封裝會固定 TAR/GZIP/ZIP metadata timestamp、owner 與 entry order；相同 version、
variant、target、upstream asset 與 license input 應產生相同 archive bytes，讓
package SHA-256 可以比較不同次執行結果。

官方 checksum 驗證的是解壓後 binary，不是下載的 archive。這是官方 asset 的
實際格式，不能把 checksum 檔名直接附加到 archive 名稱後面，也不能把 archive
hash 當成 upstream binary provenance。script 會同時記錄兩者：

```text
upstream_binary_sha256
downloaded_archive_sha256
```

## 產物

以 `v0.45.1`、預設 `full` 為例：

```text
dist/official/
├── zellij-v0.45.1-full-x86_64-unknown-linux-musl-flat-bin.tar.gz
├── zellij-v0.45.1-full-x86_64-unknown-linux-musl-flat-bin.tar.gz.sha256
├── zellij-v0.45.1-full-x86_64-unknown-linux-musl-flat-bin.manifest.json
├── zellij-v0.45.1-full-x86_64-pc-windows-msvc-flat-bin.zip
├── zellij-v0.45.1-full-x86_64-pc-windows-msvc-flat-bin.zip.sha256
└── zellij-v0.45.1-full-x86_64-pc-windows-msvc-flat-bin.manifest.json
```

每個 archive 都包含：

```text
zellij_bin/
  zellij 或 zellij.exe
  README.md
  README.txt
  BUILD-INFO.txt
  ZELLIJ-USER-GUIDE.md
  LICENSE.md
```

使用者可以把完整的 `zellij_bin` 資料夾複製到 `~/local/bin/zellij_bin/`，再把這個
資料夾加入 `PATH`。不要只複製 binary，因為 package README、操作手冊、license 與
provenance metadata 都是交付內容。

`README.md` 是 package 內的主要使用文件，必須包含 prerequisites、Linux/Windows
執行方式、PATH、boundary、`full`/`no-web` 說明與 project/upstream links。`README.txt`
保留給舊流程相容，不取代 Markdown 文件。解壓後可直接執行 binary；runtime 不會連外
下載任何東西；Yazi、shell、SSH、Windows Terminal 與 Claude Code/Codex 仍然各自管理。

可以直接檢查兩個 package 的內部文件：

```bash
tar -xOzf dist/official/zellij-v0.45.1-full-x86_64-unknown-linux-musl-flat-bin.tar.gz zellij_bin/README.md
unzip -p dist/official/zellij-v0.45.1-full-x86_64-pc-windows-msvc-flat-bin.zip zellij_bin/README.md
```

上述內容應可看到 `Prerequisites`、`Add to PATH`、`Boundary`、`Links` 四個 section。
`package_official.py verify` 與 `packaging/tests/test_official_package.py` 也會自動
檢查這個 contract。

## 離線驗證

把 archive、同名 `.sha256` 與 `.manifest.json` 一起帶入內網後，可以只用本地
Python 驗證：

```bash
python3 packaging/package_official.py verify \
  dist/official/zellij-v0.45.1-full-x86_64-unknown-linux-musl-flat-bin.tar.gz
```

Verifier 也接受舊的 direct-root `standard` archive，並以 manifest 的 `layout` 欄位
判斷兩者；新產物固定使用 `flat-bin`。

Windows 端可用 PowerShell 執行相同 Python script 的 `verify` 子命令；驗證流程
不會呼叫網路。

## Runtime acceptance

官方 checksum 通過只代表 binary 與官方 release asset 相符，還要分開做 runtime
驗收：

- Linux x86_64：在 `ssh surfer` 的 temporary directory 解壓，執行 `zellij --version`
  與 `zellij setup --dump-plugins`，不要碰既有 Zellij。
- Windows x86_64：在 Windows Terminal 執行 `zellij.exe --version`，建立/關閉
  session，測試 resize、mouse、detach/attach，並在 Zellij pane 啟動 Yazi。
- Windows scenario 1：Windows Terminal → SSH → `surfer` 或公司 Linux → Zellij →
  Yazi。Windows 端只提供 terminal、SSH 與 terminal protocol。
- Windows scenario 2：Windows Terminal → Windows Zellij → Yazi。這個情境必須在
  真正 Windows host 驗收 ConPTY，不能由 macOS 或 Linux 推論通過。

`full` variant 另外驗收：

- 確認 `zellij web --status` 可以執行。
- 預設設定下 Web Server 不應自行對外監聽或自動啟動。
- 若要在內網其他主機使用，必須明確設定 listen IP、port、authentication 與 HTTPS；
  不應因為是公司內網就直接暴露未加密 endpoint。
- Linux SSH 情境優先使用 SSH port forwarding，Windows native 情境則在 Windows
  Terminal 與 Windows host 上驗證 web server、token、port 與 ConPTY 行為。

官方 Windows prebuilt binary 不等於 Yazi Windows runtime dependencies 已完成。
`file.exe`、previewer、`ffmpeg`、`7zip`、`ripgrep` 等由 Yazi package 另外處理。

## GitHub Release distribution

Release archive 不提交到 Git history；`.gitignore` 會防止後續將
`dist/official/*.tar.gz` 或 `dist/official/*.zip` 加入 Git。`.sha256` 與
`.manifest.json` 保留作為 provenance evidence。正式交付 tag 使用
`zellij-v0.45.1`，Release asset 應包含兩個 target 各自的 archive、checksum 與
manifest。現有歷史若已有先前提交的 archive，不在本次工作中改寫歷史；只停止未來
追蹤並把交付檔放到 GitHub Release。

Project：<https://github.com/swchen44/zellij_intranet>
Upstream：<https://github.com/zellij-org/zellij>

目前本機 flat-bin 產物與 checksum/manifest 已完成驗證；公開
`zellij-v0.45.1` Release 尚未在本次變更中替換 assets。現有公開 Windows asset 的
diagnostic 狀態必須在另一次 Release maintenance 中處理，不能把本機產物 hash 當成
已上傳證據。
