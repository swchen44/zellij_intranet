# Zellij intranet bundle

## Why

公司內網的執行環境不能在 runtime 下載 Zellij 或安裝 Rust build dependencies。這個
project 將固定版本的官方 Zellij binary 重新封裝成 Linux x86_64 與 Windows x86_64
portable archive；使用者取得 archive 後解壓即可執行，不需要 Rust、Cargo、OpenSSL、
`protoc`、musl toolchain、Visual Studio、Git、Scoop 或外網。

Zellij 與 Yazi 分開管理。Zellij package 只負責 terminal multiplexer；Yazi、SSH、
Windows Terminal、shell、Claude Code、Codex 與 Yazi 的圖片/影片/PDF helper 都是外部
環境或另一個 bundle。

## What

目前的正式官方 binary baseline：

- upstream release：`v0.45.1`
- variant：`full`（預設；包含 upstream Web Server/Web Client capability，但不會自動啟動）
- Linux：`x86_64-unknown-linux-musl`，輸出 `tar.gz`
- Windows：`x86_64-pc-windows-msvc`，輸出 `zip`
- ARM64：本版本不打包、不驗證

source-build fallback 仍保留：`0.46.0`、source commit
`474ea0cef620c83d6ec05a7c28c7f80c4f63bbbb`、Rust `1.95.0`。它只在官方 release
缺少需要的 feature、需要固定 source 修改，或需要自行重建時使用；不要把 source
fallback 的版本與官方 `v0.45.1` artifact 混寫。

每個 package 內包含：

```text
zellij 或 zellij.exe
README.md       # 解壓後使用說明，必須隨 package 一起驗證
ZELLIJ-USER-GUIDE.md # 使用場景、快捷鍵與操作手冊，隨 package 一起提供
README.txt      # 舊流程相容檔
BUILD-INFO.txt
LICENSE.md
```

完整的使用場景說明請先閱讀
[`docs/ZELLIJ-USER-GUIDE.md`](docs/ZELLIJ-USER-GUIDE.md)。同一份文件也會放入每個
Linux/Windows package 的 `ZELLIJ-USER-GUIDE.md`，解壓後不需要連外網即可查閱。

## How：使用者步驟

### 情境 1：Windows Terminal → SSH → Linux → Zellij → Yazi

1. 取得 Linux `.tar.gz`、同名 `.sha256` 與 `.manifest.json`，先驗證 archive checksum。
2. 將完整 archive 傳到公司內網 Linux 主機；不需要 root。
3. 解壓並閱讀 package 內的 `README.md`；直接執行：

   ```sh
   mkdir zellij-v0.45.1-full-x86_64-unknown-linux-musl
   tar -xzf zellij-v0.45.1-full-x86_64-unknown-linux-musl.tar.gz \
     -C zellij-v0.45.1-full-x86_64-unknown-linux-musl
   cd zellij-v0.45.1-full-x86_64-unknown-linux-musl
   ./zellij --version
   ./zellij
   ```

4. 在 Zellij pane 中執行主機上已存在的 `yazi`。Yazi 不會由這個 archive 安裝。
5. 如果要讓目前 shell 暫時找到 Zellij：

   ```sh
   export PATH="$PWD:$PATH"
   zellij
   ```

Windows Terminal 只提供 terminal、SSH 與 terminal protocol；真正的 Zellij、Yazi、
shell 與其他 CLI 都在 Linux host 執行。圖片、影片與 PDF 預覽要按照 Yazi bundle
的 helper 與 terminal graphics protocol 另行驗收，不能由 Zellij package 推論。

### 情境 2：Windows Terminal → Windows native Zellij → Yazi

1. 取得 Windows `.zip`、同名 `.sha256` 與 `.manifest.json`，在 PowerShell 驗證 checksum。
2. 用 Windows Terminal 解壓完整目錄，不需要 admin rights：

   ```powershell
   Expand-Archive .\zellij-v0.45.1-full-x86_64-pc-windows-msvc.zip .\zellij
   cd .\zellij
   .\zellij.exe --version
   .\zellij.exe
   ```

3. 在 Zellij pane 中執行 Windows host 上已安裝的 `yazi`。
4. 若要暫時加入目前 PowerShell 的 PATH：

   ```powershell
   $env:Path = "$PWD;$env:Path"
   zellij.exe
   ```

Windows native runtime 必須在另一台真正的 Windows x86_64 computer 驗收；macOS、Linux、
Wine 或只有 PE 檔案檢查，都不能代替 Windows Terminal/ConPTY 實測。

## Boundary

- package 是 Zellij portable binary，不是完整工作站環境。
- 不包含 Yazi、SSH、Windows Terminal、shell、Claude Code、Codex、Git 或公司認證設定。
- 不包含圖片、影片、PDF、archive preview helper；這些屬於 Yazi project。
- runtime 不需要外網；builtin WASM plugins 已嵌入官方 binary。
- `full` variant 有 upstream Web capability，但不會自動啟動 server。若要在內網暴露
  Web endpoint，仍要設定 authentication、HTTPS、listen address 與 port，並通過安全審查。
- `no-web` 可用 `--variant no-web` 明確產生；它不應與 `full` artifact 混用或改名冒充。
- 目前只交付 x86_64；ARM64 尚未納入。
- Linux scenario 1 的 clipboard、resize、mouse 等行為同時受 SSH、Windows Terminal、
  terminal protocol 與 Zellij 影響；Windows scenario 2 則另外受 ConPTY 影響。

## 打包與驗證

### Developer steps

在有外網的 staging machine，從 project root 執行。Python packager 會逐一下載官方
release asset、下載官方 `.sha256sum`、驗證解壓後的 binary，再產生 portable package、
package checksum 與 manifest：

```sh
python3 packaging/package_official.py package \
  --version v0.45.1 \
  --output-dir dist/official
```

預設是 `full`。若明確需要無 Web capability 的 package：

```sh
python3 packaging/package_official.py package \
  --version v0.45.1 \
  --variant no-web \
  --output-dir dist/official
```

本機離線 contract/unit tests：

```sh
python3 packaging/tests/test_official_package.py
./packaging/tests/test-packaging.sh
python3 packaging/package_official.py verify \
  dist/official/zellij-v0.45.1-full-x86_64-unknown-linux-musl.tar.gz
python3 packaging/package_official.py verify \
  dist/official/zellij-v0.45.1-full-x86_64-pc-windows-msvc.zip
```

Linux x86_64 的 `surfer` temporary-directory runtime acceptance 已完成並保留在
[`packaging/acceptance/linux-matrix.md`](packaging/acceptance/linux-matrix.md)。依照目前
決策，本次文件與 package README 更新不重跑 Linux 實驗；後續版本只要 source、target、
封裝格式或 runtime contract 有變，才依計畫重新驗收。Windows acceptance 必須由使用者在
另一台 Windows 電腦執行 [`docs/plans/2026-09-21-zellij-windows-acceptance.md`](docs/plans/2026-09-21-zellij-windows-acceptance.md)。

### Package 內的 README.md contract

`package_official.py` 會產生 package-local `README.md`，並由 unit test 與 local verifier
檢查它包含：

- Linux/Windows 的使用方式與 `--version`/`setup --check`
- prerequisites 與 runtime 不需要的 build tools
- Linux shell 與 PowerShell 的 PATH 方法
- package boundary、`full`/`no-web` 行為與 ARM64 狀態
- project GitHub、upstream release 與 upstream documentation links

這個 README 必須跟 binary 一起進 archive；不能只在 project 根目錄提供文件。
完整操作手冊則以 package root 的 `ZELLIJ-USER-GUIDE.md` 提供；README 只做快速啟動與
package boundary，兩者都必須跟 binary 一起進 archive。

## GitHub Release 與大檔案防範

archive 是版本化交付物，不應提交到 Git history。repository 保留 source checkout 以外
的文件、scripts、tests、acceptance scripts、checksum 與 manifest metadata；
`dist/official/*.tar.gz` 和 `dist/official/*.zip` 已加入 `.gitignore`。現有歷史可能保留
先前已提交的 archive；本次會停止後續追蹤，並將可交付 archive 放進 GitHub Release。

Release 內容應包含每個 target 的：

1. archive
2. `.sha256`
3. `.manifest.json`

目前已建立 release tag `zellij-v0.45.1`，project 為
<https://github.com/swchen44/zellij_intranet>。公司內網交付時先下載並驗證 Release
assets，再同步到內網檔案區；runtime 不需要連 GitHub。相關做法與大小限制見
[`packaging/OFFICIAL-BINARY.md`](packaging/OFFICIAL-BINARY.md)。

## 文件位置

- 設計規格：[`docs/superpowers/specs/2026-09-21-zellij-offline-bundle-design.md`](docs/superpowers/specs/2026-09-21-zellij-offline-bundle-design.md)
- 實作計畫：[`docs/superpowers/plans/2026-09-21-zellij-offline-bundle.md`](docs/superpowers/plans/2026-09-21-zellij-offline-bundle.md)
- Windows 驗收計畫：[`docs/plans/2026-09-21-zellij-windows-acceptance.md`](docs/plans/2026-09-21-zellij-windows-acceptance.md)
- 官方 binary 操作說明：[`packaging/OFFICIAL-BINARY.md`](packaging/OFFICIAL-BINARY.md)
- 使用場景說明書：[`docs/ZELLIJ-USER-GUIDE.md`](docs/ZELLIJ-USER-GUIDE.md)
- source fallback build 說明：[`packaging/BUILDING-OFFLINE.md`](packaging/BUILDING-OFFLINE.md)
- 實際經驗與限制：[`docs/superpowers/LESSONS-LEARNED.md`](docs/superpowers/LESSONS-LEARNED.md)
