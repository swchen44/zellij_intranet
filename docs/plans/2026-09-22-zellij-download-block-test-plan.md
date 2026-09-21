# Zellij Windows ZIP 下載阻擋比較與測試計畫

## 目的

公司 Windows Chrome 可以下載 Yazi Windows ZIP，但下載 Zellij Windows ZIP 後似乎在
最後解壓縮階段被公司網路或安全掃描機制阻擋。本計畫不假設原因，先用相同
`zellij.exe` bytes 建立幾個只改變一項或一組明確變因的 diagnostic ZIP，讓公司 Windows
逐一測試下載、解壓與執行。

Diagnostic ZIP 不是正式 release package，不應取代正式的
`zellij-v0.45.1-full-x86_64-pc-windows-msvc.zip`。

## 初步比較

| 項目 | Yazi Windows ZIP | 目前 Zellij Windows ZIP |
| --- | --- | --- |
| 頂層結構 | 一個 top-level directory | ZIP root 直接放檔案 |
| executable 位置 | `.../bin/*.exe`、`.../runtime/bin/file.exe` | `zellij.exe` 在 ZIP root |
| entry 數量 | 560 | 6 |
| 壓縮方式 | 全部 deflate | 全部 deflate |
| 大小 | 約 293 MiB | 約 16 MiB |
| executable 數量 | 23 | 1 |
| 主要 binary | 多個 helper/DLL，含 `yazi`/`ya` | 單一 `zellij.exe` |

因此目前不能把阻擋直接歸因於「ZIP 使用 deflate」；Yazi 也使用 deflate。最值得先測
的是 executable 是否直接位於 ZIP root、是否只有單一 `.exe`、以及是否需要像 Yazi 一樣
用 top-level directory 和 `bin/` 路徑。

## Diagnostic variants

打包腳本：

```sh
python3 packaging/make-download-test-zips.py \
  --source dist/official/zellij-v0.45.1-full-x86_64-pc-windows-msvc.zip \
  --output-dir dist/diagnostic
```

| Variant | 變更 | 解壓後執行指令 | 用來判斷 |
| --- | --- | --- | --- |
| `minimal-flat-deflate` | 只保留 root `zellij.exe`，deflate | `zellij.exe --version` | 是否只要 ZIP 內有單一 root `.exe` 就被擋 |
| `flat-store` | 正常檔案與 root layout，但不壓縮 | `zellij.exe --version` | 壓縮方法是否造成阻擋 |
| `nested-deflate` | 正常檔案放入 top-level directory | `zellij.exe --version` | top-level directory 是否有影響 |
| `nested-bin-deflate` | top-level directory，binary 放 `bin/` | `bin\zellij.exe --version` | 是否需要 Yazi 類似的 executable 路徑 |
| `nested-bin-store` | top-level directory + `bin/`，不壓縮 | `bin\zellij.exe --version` | 同時驗證 path 與 compression |

每個 ZIP 都有同名 `.sha256` 與 `.manifest.json`。manifest 會記錄變因、解壓後 binary
path、package SHA-256，以及所有 variant 共用的 `zellij.exe` SHA-256。

## Windows 測試步驟

請在公司 Windows Terminal/Chrome 逐一測試，每個 variant 使用不同的空白資料夾：

1. 從 GitHub Release 下載 ZIP；記錄 Chrome 顯示的錯誤時機，是下載中、下載完成後、
   Windows Defender 掃描、檔案總管解壓，還是 `Expand-Archive`。
2. 同時下載同名 `.sha256`，用 PowerShell 驗證：

   ```powershell
   Get-FileHash .\<variant>.zip -Algorithm SHA256
   Get-Content .\<variant>.zip.sha256
   ```

3. 用 Windows Explorer 解壓一次，再用 PowerShell 解壓一次：

   ```powershell
   Expand-Archive .\<variant>.zip -DestinationPath .\test-<variant>
   ```

4. 如果 Explorer 失敗，記錄 PowerShell 是否也失敗；不要先改名或手動刪檔案。
5. 解壓成功後執行 manifest 指定的 `test_command`，再執行：

   ```powershell
   .\<path>\zellij.exe setup --check
   ```

6. 記錄結果：download、Explorer extract、PowerShell extract、`--version`、`setup --check`。
7. 若某個 variant 成功，保留該 ZIP、Chrome/Defender 顯示的分類與錯誤訊息，才可判斷
   下一版正式 package 是否要採用 layout 變更。

## 判讀矩陣

| 結果 | 初步推論 |
| --- | --- |
| 所有 variant 都在下載或解壓時被擋 | 可能是公司政策依 binary signature、GitHub asset、repository、publisher 或 Zellij binary 本身阻擋；ZIP layout 不是主因 |
| `minimal-flat-deflate` 也被擋，但只有它失敗 | 單一 root `.exe` 或 binary signature 可能是觸發條件 |
| `nested-deflate` 成功，flat 失敗 | top-level directory/路徑可能影響 scanner 或解壓流程 |
| `nested-bin-deflate` 成功，`nested-deflate` 失敗 | executable 位於 `bin/` 可能影響公司檢查規則 |
| stored 成功，deflate 失敗 | 壓縮方法或公司解壓引擎可能有問題 |
| ZIP 都能解壓，但 `setup --check` 失敗 | 下載/解壓已成功，剩下是 Windows runtime、ConPTY、config 或 binary 問題 |

## 不可由這次測試推論的事項

- 不能因某個變體能下載，就宣稱公司安全掃描允許 Zellij；要保存測試日期、Chrome/Defender
  結果與公司網路政策。
- 不能把 diagnostic variant 直接當正式 package；它們可能沒有正式 package 的
  `README.md` 路徑 contract 或 release naming contract。
- 不能由 macOS 解壓結果推論公司 Windows Explorer、PowerShell 或 Defender 行為。
