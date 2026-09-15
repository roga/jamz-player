## Overview

在音樂庫新增歌曲長按選單，提供「編輯」與「刪除」。編輯歌名、演出者及專輯並寫回 App 內 MP3 的 ID3 標籤；刪除須經確認，並清除相關本機檔案、音樂庫紀錄及播放狀態。

## Scope

- `JamzPlayer/Views/LibraryView.swift`：長按選單、編輯入口、刪除確認及操作結果提示。
- `JamzPlayer/Views/SongEditView.swift`：新增三項歌曲資訊的編輯表單，提供儲存與取消。
- `JamzPlayer/App/LibraryStore.swift`：協調編輯、刪除、操作狀態及錯誤訊息。
- `JamzPlayer/Services/LibraryRepository.swift`：同步保存 MP3 與索引，刪除歌曲及相關檔案，處理失敗復原。
- `JamzPlayer/Services/MP3MetadataWriter.swift`：新增 ID3 寫入功能，保留音訊、封面與其他標籤。
- `JamzPlayer/Services/PlayerStore.swift`：同步目前歌曲資訊與佇列，清理被刪除歌曲的播放狀態。
- `JamzPlayer/Services/SystemPlaybackBridge.swift`：必要時調整系統播放資訊更新與清除。
- `JamzPlayerTests/JamzPlayerTests.swift`、`JamzPlayerTests/Fixtures/`：新增標籤寫回、刪除、播放同步及失敗處理測試與測試素材。
- `JamzPlayer.xcodeproj/project.pbxproj`：將新增程式及測試素材納入專案。

## Requirements

- [V] R1: 長按音樂庫內歌曲，依序顯示「編輯」「刪除」兩個選項；一般點按維持播放行為，長按不誤觸播放。
- [V] R2: 編輯表單預填歌名、演出者、專輯，僅提供這三項資訊的編輯及儲存、取消操作；取消或未儲存關閉時不變更資料。
- [V] R3: 儲存時將三項資訊寫回 App 內 MP3 的 ID3 標籤並同步音樂庫索引，支援中文、既有 ID3v2.3／v2.4 及無標籤 MP3；保留音訊內容、內嵌封面、封面副本及其他既有標籤。無法安全處理的檔案須顯示錯誤並保留原檔。
- [V] R4: 編輯成功後更新音樂庫、播放器及系統播放資訊；編輯目前歌曲時維持播放／暫停狀態及進度。
- [V] R5: 選擇刪除後顯示含歌曲名稱的確認提示，說明將刪除本機音檔，提供「刪除」與「取消」；取消或關閉提示不刪除任何資料。
- [V] R6: 確認刪除後移除該歌曲的音樂庫紀錄、App 內 MP3 及專屬封面副本，更新歌曲數量與播放佇列；其他歌曲不受影響，重新啟動後仍維持刪除結果。
- [V] R7: 刪除目前播放或暫停的歌曲時，停止播放並清除目前歌曲、進度、睡眠計時及系統播放資訊，隱藏迷你播放器，不自動播放下一首；刪除其他歌曲時維持目前播放狀態。
- [V] R8: 編輯及刪除失敗時顯示對應錯誤，不呈現成功結果；以可復原的檔案與索引更新流程避免半完成資料，並防止重複提交或與匯入操作互相覆蓋。

## Acceptance Criteria

- [ ] AC1: 在音樂庫長按任一歌曲，可見依序排列的「編輯」「刪除」；長按不開始播放，一般點按仍可播放。
- [ ] AC2: 開啟編輯可見預填的三個欄位且沒有封面編輯；修改後取消或未儲存關閉，再次開啟仍為原資料，MP3 及索引未變更。
  Evidence: `SongEditView.swift` only exposes the three fields and dismisses without calling save on cancel; UI interaction not independently exercised.
- [V] AC3: 對 ID3v2.3、ID3v2.4 及無標籤的測試 MP3 儲存中文資訊後，直接重新讀取 MP3 可取得三項新值，重開音樂庫亦一致；音訊內容、既有封面及其他標籤保持完整，歌曲仍可播放。
  Evidence: targeted XCTest `testEditsWriteChineseTagsAndPreserveAudioAndArtwork` passed for all three fixtures.
- [V] AC4: 播放或暫停一首歌曲時編輯並儲存，音樂庫、迷你播放器、播放器及系統播放資訊顯示新資料，播放狀態及進度不重置。
  Evidence: targeted XCTest `testEditingCurrentSongKeepsPlaybackAndRefreshesSystemInfo` passed.
- [V] AC5: 選擇刪除會先顯示歌曲名稱與確認提示；取消或關閉提示後，歌曲、音檔、封面、索引及播放狀態均未改變。
  Evidence: `LibraryView.swift` defines a destructive confirmation alert with song title and Cancel action; cancellation is UI-only.
- [V] AC6: 確認刪除非目前歌曲後，其 MP3、專屬封面副本與索引紀錄均不存在，佇列及歌曲數量更新，其他歌曲繼續正常播放；重開 App 後歌曲不再出現。
  Evidence: XCTest `testDeleteRemovesOnlySelectedSongAndItsFiles` and `testDeletingOtherSongPreservesCurrentPlayback` passed.
- [V] AC7: 刪除目前播放及目前暫停的歌曲，均清除播放器與系統播放資訊及睡眠計時，不自動換曲；刪除最後一首後顯示音樂庫空白狀態。
  Evidence: XCTest `testDeletingCurrentSongClearsPlayingAndPausedState` passed for playing and paused states.
- [V] AC8: 模擬標籤無法安全寫入、檔案操作或索引儲存失敗，操作顯示錯誤，原歌曲資料可復原且未誤刪其他歌曲；連續提交及匯入期間操作不造成重複變更或資料遺失。
  Evidence: full XCTest run passed 26 tests, including mutation rollback, interrupted-journal recovery, and store mutation serialization tests.
