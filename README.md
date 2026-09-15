# Jamz Player

Jamz Player 是一個原生 iPhone MP3 播放器，使用 SwiftUI、AVFoundation 與 MediaPlayer 開發，最低支援 iOS 17。介面採繁體中文、深色背景與暖橘色。

## 功能

- 從 HTTPS MP3 直連網址下載音檔，顯示進度並可取消。
- 音檔與封面保存於 App 沙盒，重新開啟 App 或離線時仍可播放。
- 讀取 ID3v2.3／v2.4 的歌名、演出者、專輯與內嵌封面；缺少資料時使用檔名及預設資訊。
- 播放／暫停、進度拖曳、上一首／下一首、關閉循環、單曲循環與全部循環。
- 編輯歌曲的歌名、演出者及專輯；刪除歌曲時一併清理其音檔與封面。
- 15、30、60 分鐘睡眠定時器，支援查看倒數、重設及取消。
- 背景與鎖定畫面播放，提供系統播放資訊與控制；耳機拔除或音訊中斷時暫停。

## 開始使用

### 使用 Xcode

1. 安裝完整 Xcode，並完成授權與 iOS Simulator 元件安裝。
2. 在專案目錄開啟：

   ```sh
   open JamzPlayer.xcodeproj
   ```

3. 選擇 `JamzPlayer` scheme 與 iPhone 模擬器，按 `⌘R` 執行。
4. 安裝到實體 iPhone 時，請在 **Signing & Capabilities** 選擇自己的 Development Team，並使用可用的唯一 Bundle Identifier。專案不包含開發者憑證。

### 使用命令列建置

```sh
xcodebuild -project JamzPlayer.xcodeproj \
  -scheme JamzPlayer \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/jamz-derived \
  CODE_SIGNING_ALLOWED=NO build
```

## 匯入與播放

1. 在音樂庫右上角點擊 **＋**。
2. 貼上可直接下載 MP3 的 HTTPS 網址，按 **下載音樂**。一般網頁、影音平台分享網址及需要登入的網址不在範圍內。
3. 下載完成並通過 MP3 檢查後，歌曲會加入音樂庫，且不會自動播放。
4. 點擊歌曲開始播放；點擊底部迷你播放器可開啟完整播放器。
5. 在歌曲選單中可編輯歌名、演出者與專輯，或刪除歌曲。
6. 播放器可切換循環模式與睡眠定時器。

下載期間請保持 App 開啟。App 不提供背景下載接續、雲端備份、串流平台整合、帳號、自訂播放清單或 ID3 以外的標籤編輯。App 被使用者強制關閉後不會繼續播放；重新開啟後也不會自動播放或恢復舊定時器。

### 播放規則

- 關閉循環：最後一首自然播畢後停止。
- 單曲循環：自然播畢時重播目前歌曲；手動下一首仍會切歌。
- 全部循環：最後一首自然播畢後接回第一首。
- 上一首：目前播放超過 3 秒時回到曲首，否則切到前一首；全部循環時可從第一首回到最後一首。
- 睡眠定時器以實際經過時間計算，暫停與切歌不會重設；到期停止播放，且優先於循環播放。
- 音訊中斷結束後不自動恢復，需手動播放。

## 資料與架構

| 路徑 | 用途 |
| --- | --- |
| `JamzPlayer/App` | App 入口、共用狀態與匯入協調 |
| `JamzPlayer/Models` | 歌曲資料、循環政策與睡眠定時邏輯 |
| `JamzPlayer/Services` | HTTPS 下載、MP3 檢查、ID3 讀寫、本機儲存與音訊控制 |
| `JamzPlayer/Views` | 音樂庫、匯入面板、編輯畫面、迷你播放器與完整播放器 |
| `JamzPlayer/Resources` | App 圖示、預設封面、色彩與 Info.plist |
| `JamzPlayerTests` | XCTest、MP3 測試素材與播放器測試 |

音檔以 UUID 檔名保存於 `Library/Application Support/JamzPlayer/`，`library.json` 保存歌曲索引，封面另存為影像檔。匯入、編輯與刪除使用可復原的檔案變更流程；操作失敗時會保留原有音檔、封面與索引。歌曲編輯只更新歌名、演出者與專輯，並保留音訊及原有封面。

## 執行測試

先列出可用模擬器：

```sh
xcrun simctl list devices available
```

將 `SIMULATOR_UDID` 替換為 iPhone 模擬器 UUID：

```sh
xcodebuild -project JamzPlayer.xcodeproj \
  -scheme JamzPlayer \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  -derivedDataPath /tmp/jamz-derived \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

也可以在 Xcode 按 `⌘U`。測試使用獨立暫存音樂庫，不會修改 App 的既有下載；測試素材位於 `JamzPlayerTests/Fixtures`。

測試涵蓋：HTTPS 網址與安全轉址、取消與網路錯誤、MP3 及 ID3v2.3／v2.4、中文標籤與封面、缺漏資訊回退、持久化、索引損毀、匯入／編輯／刪除失敗回復、三種循環模式與睡眠定時器。
