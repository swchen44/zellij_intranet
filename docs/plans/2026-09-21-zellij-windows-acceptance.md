# Zellij Windows acceptance plan

## Purpose

驗證 `zellij-v0.45.1-full-x86_64-pc-windows-msvc.zip` 在真正 Windows x86_64 computer
上可由 Windows Terminal 解壓後直接執行。macOS、Linux、Wine、PE header 檢查與 archive
checksum 只能作為前置證據，不能取代 Windows loader、ConPTY 或 native shell 實測。

Linux SSH scenario 的 runtime acceptance 已在 `surfer` 完成；本計畫只處理 Windows host
與兩個使用情境的 Windows 端部分。

## Preferred test method

優先使用另一台 Windows computer 上的 Windows Codex session，並用 Computer Use 觀察與
操作 Windows Terminal UI；PowerShell commands 作為可重複的 command evidence。若該環境
沒有 Computer Use，使用 Windows Terminal + PowerShell，保留完整 transcript、版本與
screenshots。不要用 macOS/Linux 推論 Windows runtime 通過。

## Inputs and clean setup

從 GitHub Release 取得並放在同一個目錄：

```text
zellij-v0.45.1-full-x86_64-pc-windows-msvc.zip
zellij-v0.45.1-full-x86_64-pc-windows-msvc.zip.sha256
zellij-v0.45.1-full-x86_64-pc-windows-msvc.manifest.json
```

建議解壓到使用者可寫、路徑短的 temporary directory，不需要 administrator rights。測試
時使用 clean user/config/cache scope；不要把公司 authentication、既有 Zellij config
或正式 Yazi 設定當成 package 成功的必要條件。

## Test sequence

### W0：Package and README contract

- [ ] PowerShell `Get-FileHash -Algorithm SHA256` 與 `.sha256` 一致。
- [ ] manifest 的 package、target、variant、package SHA-256 一致。
- [ ] `Expand-Archive` 成功，archive root 有 `zellij.exe`、`README.md`、`README.txt`,
  `BUILD-INFO.txt`、`LICENSE.md`。
- [ ] package `README.md` 可讀，包含 `Prerequisites`、`Add to PATH`、`Boundary`、
  `Links`，且 project/upstream links 正確。

### W1：PowerShell executable smoke

在沒有 Rust、Cargo、OpenSSL、Visual Studio build tools 依賴的 runtime PowerShell 執行：

```powershell
.\zellij.exe --version
.\zellij.exe setup --check
.\zellij.exe setup --dump-layout default | Set-Content .\default.kdl
.\zellij.exe setup --dump-plugins .\plugins
```

- [ ] version 為 `0.45.1`。
- [ ] `default.kdl` 非空。
- [ ] `plugins` 至少有 12 個 `.wasm`。
- [ ] process exit code 全部為 0。

### W2：Windows Terminal control test

- [ ] 在 Windows Terminal 直接啟動 `zellij.exe`，確認 native Windows shell 可用。
- [ ] 調整 terminal pane/window size，確認 resize 不會破壞 layout。
- [ ] 測試 mouse selection、pane split/close、Unicode/CJK 顯示與 copy/paste。
- [ ] 建立 session、detach、重新 attach、kill session。
- [ ] 測試短路徑與含空白路徑至少各一次（若公司路徑政策允許）。

### W3：情境 2 整合測試

```text
Windows Terminal → Windows native Zellij → Windows shell → Yazi
```

- [ ] 在 Zellij pane 執行 Windows 版 Yazi bundle 的 launcher。
- [ ] 於 Yazi 內瀏覽文字、archive、圖片、影片與 PDF；helper 的缺失或 terminal
  graphics limitation 要記在 Yazi acceptance，不歸因於 Zellij package。
- [ ] 確認 Zellij pane 中的 `yazi` 可正常啟動、輸入、resize、退出。
- [ ] 若存在 `claude`/`codex`，可各開 pane 作為 optional child-process check；沒有安裝
  時標記 `NOT RUN`，不可標成 Zellij failure。

### W4：情境 1 Windows client control

```text
Windows Terminal → SSH → Linux → Zellij → Yazi
```

這不是重新驗證 Linux binary；只確認另一台 Windows computer 的 client path：

- [ ] Windows Terminal `ssh` 可取得 PTY（使用 `ssh -tt` 或公司既有 SSH command）。
- [ ] remote Linux 啟動既有已驗證的 Zellij package。
- [ ] remote pane 可啟動 Linux Yazi，resize、輸入與 detach/attach 結果記錄清楚。
- [ ] remote clipboard 若測試，分別記錄 OSC 52、Windows Terminal 與 SSH server 的結果。

## Optional `full` Web capability check

只有公司確實要使用 Web Server/Web Client 時才執行；不因 package 是 `full` 就自動把
server 暴露出去：

- [ ] `zellij web --status` 的行為符合該 release 文件。
- [ ] 啟動前後確認沒有未授權的 public/listen endpoint。
- [ ] 若要對內網開放，確認 authentication、HTTPS、listen address、port 與 firewall
  policy；保存 config 與 log，但不要把 token/credential 寫入 Git。
- [ ] 若只需要 terminal workflow，將 Web test 標記 `NOT REQUIRED`，不要自行變更
  release artifact 為另一個 variant。

## Evidence record

測試結束填入：

```text
date:
windows_version:
windows_architecture:
windows_terminal_version:
zellij_package:
package_sha256:
zellij_version:
computer_use_or_powershell:
W0:
W1:
W2:
W3:
W4:
web_check:
screenshots_or_log_paths:
known_limitations:
```

每一項只能填 `PASS`、`FAIL`、`BLOCKED` 或 `NOT RUN`，並附 evidence path。完成 W0/W1
不代表完成 W2/W3；只有 Windows Terminal/ConPTY 實測通過後，才可把 Windows runtime
gate 標為 `PASS`。

