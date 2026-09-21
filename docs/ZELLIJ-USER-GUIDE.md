# Zellij 使用場景說明書

這份文件以本 project 的 portable package 與官方 `default` keybinding preset 為準。
Zellij 是 terminal multiplexer：它管理 sessions、tabs、panes 與 layouts，但不包含
shell、SSH、Windows Terminal、Yazi、Claude Code 或 Codex。

如果使用者已經自行修改 Zellij config 或選用 `Unlock-First` preset，快捷鍵可能不同；
請以畫面上的 status bar、`zellij --help` 與目前版本的 [官方 keybindings 文件](https://zellij.dev/documentation/keybindings)
為準。

## 1. Help、版本與設定檢查

在 package 解壓後的目錄執行：

Linux：

```sh
./zellij --help
./zellij --version
./zellij attach --help
./zellij action --help
./zellij setup --help
./zellij setup --check
```

Windows PowerShell：

```powershell
.\zellij.exe --help
.\zellij.exe --version
.\zellij.exe attach --help
.\zellij.exe action --help
.\zellij.exe setup --help
.\zellij.exe setup --check
```

常用設定檢查與範例：

```sh
zellij setup --dump-config
zellij setup --dump-layout default
zellij setup --dump-plugins ./temporary-plugins
```

Zellij 的 status bar 會顯示目前 mode 的可用快捷鍵。若忘記按鍵，先回到 normal
mode，再使用下表的 mode 入口；完成操作通常按 `Enter` 或 `Esc` 回到 normal mode。

## 2. 最重要的概念

| 名稱 | 用途 | 適合的工作 |
| --- | --- | --- |
| Session | 一個可 detach、重新 attach、保存工作脈絡的工作區 | 一個專案、一個伺服器、一個調查任務 |
| Tab | Session 裡的工作分頁 | `editor`、`logs`、`shell`、`tools` |
| Pane | Tab 裡的終端區塊 | editor、build、log、Yazi、Claude Code |
| Layout | 預先定義 tabs 與 panes 的 KDL 檔案 | 每次啟動都要相同的工作桌面 |
| Floating pane | 可顯示/隱藏的浮動 pane | 長時間 build、臨時 shell、監控資訊 |

建議把「不同工作脈絡」分成不同 session，不要把所有專案塞在一個 session。這樣
重新連線或復原時比較容易找到正確的工作環境。

## 3. 情境一：Windows Terminal → SSH → Linux Zellij → Yazi

這是公司內網的主要使用方式。Windows 端只負責 Windows Terminal 與 SSH；Zellij、
Yazi 與其他 CLI 都在 Linux 主機執行。

### 第一次啟動

在 Windows Terminal 連進 Linux：

```sh
ssh user@linux-host
cd /path/to/project
/path/to/zellij-v0.45.1-full-x86_64-unknown-linux-musl/zellij attach --create survey
```

如果 package 目錄已加入 PATH：

```sh
zellij attach --create survey
```

進入 Zellij 後，可以在不同 pane 執行：

```text
Yazi：          yazi .
程式編輯器：    nvim .
長時間工作：    make test
AI CLI：        claude 或 codex
```

### 暫時離開，稍後回來

1. 在 Zellij 中按 `Ctrl o` 進入 Session mode。
2. 按 `d` detach，回到 SSH shell。
3. 可以離開 SSH；Linux 上的 session 仍可保留。
4. 下次連線後執行：

   ```sh
   zellij attach survey
   ```

也可以列出目前 session：

```sh
zellij list-sessions
# 短寫：
zellij ls
```

### SSH 情境的限制

- 不要在 Windows 端啟動 Linux package；Linux binary 必須在 Linux host 執行。
- SSH 斷線時，Zellij session 可以留在遠端，但正在執行的程式仍受 Linux host 狀態影響。
- 遠端 Zellij 的 clipboard 主要依賴 OSC 52；Zellij 官方 FAQ 指出，SSH remote session
  可用的 clipboard 方法是 OSC 52。Windows Terminal、SSH 設定與公司安全政策仍需另外驗證。
- resize、mouse、Unicode/CJK 與 copy/paste 是 Windows Terminal、SSH、Zellij 三層共同
  作用的結果；先在 SSH 外測試，再判斷是哪一層的限制。

## 4. 情境二：Windows Terminal → Windows native Zellij → Yazi

這個情境使用 Windows package 的 `zellij.exe`，不經過 SSH。Yazi 與 shell 必須已經在
Windows host 上可以執行。

PowerShell：

```powershell
cd C:\Tools\zellij-v0.45.1-full-x86_64-pc-windows-msvc
.\zellij.exe --version
.\zellij.exe setup --check
.\zellij.exe attach --create windows-work
```

如果要讓目前 PowerShell 找到 package：

```powershell
$env:Path = "$PWD;$env:Path"
zellij.exe attach --create windows-work
```

Windows native Zellij 使用 ConPTY。要驗證的項目包括 Windows Terminal 的輸入輸出、
resize、mouse、Unicode/CJK、PowerShell、Yazi pane 與 detach/attach；macOS、Linux、Wine
或只有 PE 檔案檢查，都不能取代真正 Windows host 的驗收。

## 5. 最常用的 pane 操作

以下按鍵以 default preset 為準。

| 目的 | 操作 |
| --- | --- |
| 新增一般 pane | `Alt n` |
| 進入 Pane mode | `Ctrl p` |
| 向下新增 pane | `Ctrl p`、`d` |
| 向右新增 pane | `Ctrl p`、`r` |
| 新增 stacked pane | `Ctrl p`、`s` |
| 切換焦點 | `Alt` + 方向鍵，或 `Alt h/j/k/l` |
| 關閉目前 pane | `Ctrl p`、`x` |
| 目前 pane 全螢幕 | `Ctrl p`、`f` |
| 顯示/隱藏 floating panes | `Alt f`，或 `Ctrl p`、`w` |
| 將 tiled/floating pane 互換 | `Ctrl p`、`e` |
| 固定 floating pane 在最上層 | `Ctrl p`、`i` |
| 進入 Resize mode | `Ctrl n` |
| Resize | `h/j/k/l` 增加，`H/J/K/L` 減少；`+/-` 自動調整 |
| 進入 Move mode | `Ctrl h` |
| 移動 pane | `h/j/k/l` 或方向鍵 |
| 重新命名 pane | `Ctrl p`、`c` |
| 離開 Zellij | `Ctrl q` |

最短的工作流程通常是：`Alt n` 開新 pane，`Alt` + 方向鍵切換，再用 `Ctrl p`、`f`
暫時放大目前 pane。

## 6. Tabs：把工作分類

| 目的 | 操作 |
| --- | --- |
| 進入 Tab mode | `Ctrl t` |
| 建立新 tab | `Ctrl t`、`n` |
| 關閉目前 tab | `Ctrl t`、`x` |
| 重新命名 tab | `Ctrl t`、`r` |
| 前後切換 tab | `Ctrl t`、`h/k` 或 `l/j` |
| 跳到指定 tab | `Ctrl t`、`1` 至 `9` |
| 同步輸入到同一 tab 的 panes | `Ctrl t`、`s` |

建議的專案 workspace：

```text
Tab editor：編輯器與 Yazi
Tab test：   測試、build、lint
Tab logs：   server log、tail、監控
Tab shell：  一般命令與 Git 操作
```

`Ctrl t`、`s` 會把輸入送到多個 pane；執行破壞性指令前，先確認是否已關閉同步，避免
同一個 command 同時送到不該執行的 pane。

## 7. Logs、搜尋與複製輸出

### 捲動與搜尋 scrollback

1. 按 `Ctrl s` 進入 Scroll mode。
2. `j/k` 或方向鍵上下捲動。
3. 按 `s` 輸入搜尋文字，再按 `Enter`。
4. 在 Search mode 中按 `n` 找下一個、`p` 找上一個。
5. 按 `Ctrl c` 回到目前輸出底部並離開 mode。

需要用 editor 檢查或保存整段輸出時，在 Scroll mode 按 `e`。這需要 `$EDITOR` 或
`$VISUAL` 已設定；也可以在 Zellij config 設定 `scrollback_editor`。

### 從外部查詢 pane

在 session 內或指定 session 執行：

```sh
zellij action list-panes --all
zellij action dump-screen --pane-id terminal_3 --full
```

要將 pane 輸出存檔：

```sh
zellij action dump-screen --pane-id terminal_3 --full --path /tmp/pane.txt
```

`terminal_3` 只是示例，先用 `list-panes --all` 找實際 pane ID。這對查 build、server
log 或低資源 Linux host 的狀態很有用。

## 8. 長時間工作與 floating pane

把長時間 command 放到 floating pane，可以暫時隱藏而不停止工作：

```sh
build_pane="$(zellij action new-pane --floating --name build)"
zellij action paste --pane-id "$build_pane" "make test 2>&1"
zellij action send-keys --pane-id "$build_pane" Enter
zellij action hide-floating-panes
```

需要查看進度時：

```sh
zellij action show-floating-panes
```

在手動操作中也可以用 `Alt f` 顯示/隱藏 floating panes。這個模式很適合 build、tail
log、`htop` 或單次調查 command；不要把它誤認為 Linux service manager，主機重開機後
是否能恢復 command 取決於 Zellij session resurrection 與 command 本身。

## 9. Session resurrection：重建工作脈絡

Zellij 預設會保存 session 的 tabs、panes、layout 與 pane command 到使用者 cache，讓
退出或 crash 後可以重建工作脈絡。常用方式：

```sh
zellij ls
zellij attach my-session
```

在既有 session 中按 `Ctrl o`、`w` 開啟 session manager，可以切換 running session，
也可以選擇 exited session 進行 resurrection。需要永久移除不再使用的 session 時，先
使用：

```sh
zellij kill-sessions --help
```

確認目前版本支援的參數後再刪除，避免誤刪公司內網工作脈絡。

## 10. Layout：每次啟動固定工作桌面

先輸出官方 default layout 作為起點：

```sh
zellij setup --dump-layout default > project.kdl
zellij --layout project.kdl
```

Layout 可以定義 tabs、tiled panes、floating panes、command、working directory 與
pane name。適合以下工作：

- 每次進專案都要同時開 editor、Yazi、測試與 logs。
- 同一台 Linux host 上管理多個服務與監控 pane。
- 把可重複的 AI/CLI 工作區交給同事使用相同的 KDL。

建議先從 `setup --dump-layout` 產生的檔案修改，並在 package 版本升級時重新執行
`setup --check`；不要直接把 layout 寫死成某台公司的絕對路徑，除非該路徑已是正式規格。

## 11. `zellij action` 與自動化

Zellij 不只能靠快捷鍵，也可以由 shell script 控制：

```sh
zellij action new-pane --help
zellij action list-panes --json
zellij action current-tab-info --json
```

例如從背景 session 建立 build pane：

```sh
zellij attach --create-background ci-runner
pane_id="$(zellij --session ci-runner action new-pane --name build -- cargo test)"
```

`action` 的具體參數以 `zellij action <name> --help` 為準。要監看 pane 的即時輸出，可
使用 `zellij subscribe`；這適合 CI 或外部 status script，但不屬於一般互動操作的必要
步驟。

## 12. Built-in plugins 與 Web capability

官方 package 的 builtin WASM plugins 已嵌入 binary，不需要 runtime 網路下載。常用的
內建功能包括 session manager、configuration、layout manager、share 與 status bar。

目前 project 預設交付 `full` variant。它包含 upstream Web Server/Web Client capability，
但不會自動啟動。`zellij web`、token、listen address、port 與 HTTPS 都屬於額外服務設定：

- 公司內網不需要瀏覽器 Web Client 時，不要啟動它。
- 若要讓其他人連線，必須先完成 authentication、HTTPS、listen address、port 與公司資安
  審查。
- `full` 的 Web capability 不代表已完成公司 Windows、ConPTY 或網路政策驗收。
- `no-web` variant 只在明確不需要 Web capability 時使用，不能把兩種 artifact 混用。

外部 plugin 可能需要額外下載或固定 plugin revision；本 portable package 不會在 runtime
自動下載外部 plugins。內網使用時，應另行盤點 plugin source、hash、license 與離線交付方式。

## 13. 常見問題排查

1. 先執行 `zellij --version`，確認呼叫的是 package binary，不是 PATH 中的舊版本。
2. 執行 `zellij setup --check`，確認 config 沒有語法錯誤。
3. 執行 `zellij --help` 或 `zellij <subcommand> --help`，確認目前版本的參數。
4. 快捷鍵沒有反應時，確認是否仍在 Pane/Tab/Scroll/Locked mode；按 `Enter` 或 `Esc`
   回 normal mode，再看 status bar。
5. SSH 斷線後先重新 SSH，再用 `zellij ls` 與 `zellij attach <name>`，不要重複建立同名
   session。
6. Clipboard 在 SSH 中失效時，先檢查 terminal 是否支援 OSC 52；Linux 安裝 `xclip` 或
   `wl-copy` 不能單獨解決 remote Zellij clipboard。
7. Windows 啟動失敗時，先將 package 解壓到短路徑，例如 `C:\Tools\zellij`，再檢查
   Windows Terminal、ConPTY、PowerShell 與 `zellij.exe setup --check`。
8. Yazi、Claude Code、Codex 啟動失敗時，先在相同 shell 直接執行該 command；Zellij
   package 不包含這些工具。
9. 圖片、影片、PDF 預覽失敗時，請依 Yazi package 的 helper 與 terminal protocol 測試；
   Zellij package 本身不包含這些 preview helper。

## 14. 社群常見的使用方式

以下是公開社群討論中反覆出現的工作方式，屬於使用者經驗，不是 Zellij 的強制規則：

- 大型工作以「一個 project、brand、sprint 或調查任務一個 session」管理。
- 短任務留在現有 session 的一兩個 tab；長期工作或不同 repository 再建立新 session。
- 每個 tab 放一個脈絡，例如 editor、build/test、logs、shell、AI CLI 或 Yazi；一個 tab
  通常保持 editor 加一至兩個 command panes，避免畫面太擁擠。
- 用 floating pane 放臨時 command、長時間工作、Yazi file picker 或監控；需要時顯示，
  完成後隱藏，不必一直佔用 tiled layout。
- 對固定的 editor + shell + logs 組合，社群常用 layout template；需要在同一個 tab
  間切換 pane 位置時，則使用 swap layout。
- Session、tab、pane 都命名，並把「detach」與「quit」分開理解；要暫時離開使用
  `Ctrl o`、`d`，不要為了離開 SSH 而關掉整個 session。

這些討論也指出兩個實際限制：Zellij 不會自動替使用者整理混亂的 sessions，而且有些人
會另外使用 sessionizer、fzf 或自訂 script 選擇 project。這些是外部工具，不包含在本
portable package；內網若要加入，必須另外審查來源、版本、hash 與 shell 相依性。

參考討論：

- [Zellij coding workflow discussion](https://www.reddit.com/r/zellij/comments/1h126c2/)
- [Community discussion on sessions, tabs and workstreams](https://www.reddit.com/r/zellij/comments/1q2yley/)
- [Community discussion on tab/pane layouts](https://www.reddit.com/r/zellij/comments/1w0v3sl/)
- [Zellij issue: moving a live pane between sessions](https://github.com/zellij-org/zellij/issues/5118)

## 官方資料來源

- [Zellij Commands](https://zellij.dev/documentation/commands)
- [Zellij Keybindings](https://zellij.dev/documentation/keybindings)
- [Keybinding Presets](https://zellij.dev/documentation/keybinding-presets.html)
- [Basic Functionality](https://zellij.dev/tutorials/basic-functionality/)
- [Session Management](https://zellij.dev/tutorials/session-management/)
- [Session Resurrection](https://zellij.dev/documentation/session-resurrection.html)
- [Creating a Layout](https://zellij.dev/documentation/creating-a-layout.html)
- [CLI Recipes & Scripting](https://zellij.dev/documentation/cli-recipes.html)
- [Zellij FAQ](https://zellij.dev/documentation/faq.html)
- [Zellij Options](https://zellij.dev/documentation/options.html)
- [Web Client](https://zellij.dev/documentation/web-client.html)
