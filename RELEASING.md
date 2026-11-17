# 發佈更新

1. 更新 `script/Info.plist` 嘅顯示版本，並遞增 `CFBundleVersion`。
2. 加入 `docs/release-notes/<版本>.md`，執行 `swift test -c release`。
3. 執行 `./script/prepare_update.sh`，產生 DMG 同已簽署嘅 `docs/appcast.xml`。
4. 將 DMG 上傳至 GitHub Release `v<版本>`，先確認下載正常，再同步程式碼同更新來源至 `main`。
5. 等待 GitHub Pages 發佈，再用 App 嘅「檢查更新」驗證。

簽署工具會使用本機鑰匙圈嘅 `local.lidpulse` 帳戶。私鑰毋須匯出，亦唔可以上傳至倉庫。發佈套件後如有任何修改，必須重新打包、簽署及驗證；已發佈版本唔應覆寫。
