# 測試素材

這些素材由本專案合成，沒有取用商業歌曲。每個 MP3 約兩秒。

- `id3v23.mp3`：ID3v2.3、UTF-16 中文文字與 JPEG APIC 封面。
- `id3v24.mp3`：ID3v2.4、UTF-8 中文文字與 JPEG APIC 封面。
- `partial.mp3`：只有歌名及封面，測試演出者／專輯回退。
- `untagged.mp3`：沒有 ID3，測試檔名回退。
- `silence.mp3`：無標籤靜音，用於實際播放器測試。
- `invalid.mp3`：HTML 文字，測試副檔名偽裝。

標籤預期為「夜色節奏」、「Jamz 測試演出者」、「離線時光」。部分標籤素材的歌名為「只有歌名」。封面是自行繪製的橘色唱片圖。

素材以 Python 3、lameenc 1.8.1、Pillow 11.3.0 產生；這些套件不是 App 或執行 XCTest 的依賴。
