# LidPulse — Glowing Apple logo control for OLED MacBook Pro

**Control the glowing Apple logo on a supported MacBook Pro with PROLED XDR Display.** Dim it or turn it off from the macOS menu bar. Make it breathe, sync it to music, or use it as a status light for Codex and Claude Code.

[Download the DMG](https://github.com/siumiu1968/LidPulse/releases/latest) · [Product guide](https://siumiu1968.github.io/LidPulse/) · [繁體中文](#繁體中文)

## Which new MacBook Pro has the glowing Apple logo?

Apple's 14-inch and 16-inch **MacBook Pro with PROLED XDR Display** use tandem OLED and come with an illuminated lid logo. The separate 14-inch MacBook Pro with M6 uses Liquid Retina XDR. Check the display name when identifying your model. [Apple's PROLED XDR announcement](https://www.apple.com/newsroom/2026/10/apple-unveils-groundbreaking-macbook-pro-with-proled-xdr-display/) · [Apple's M6 announcement](https://www.apple.com/newsroom/2026/10/apple-introduces-the-new-14-inch-macbook-pro-with-m6/)

LidPulse was tested on an M5 Max PROLED XDR MacBook Pro (`Mac17,10`) running macOS 27.2. It requires the physical lid light and a compatible controller. [Apple's guide to the illuminated Apple logo](https://support.apple.com/en-us/149248)

## What it does

| Mode | What the logo does |
| --- | --- |
| **Steady** | Holds your chosen brightness. |
| **Breathe** | Fades up and down at an adjustable pace. |
| **Battery** | Dims as your battery runs down, within your chosen brightness. |
| **Music** | Pulses to beats detected in the audio your Mac plays. Adjust beat intensity or turn the light off between beats. |
| **Agents** | Glows softly while idle, pulses while Codex or Claude Code is working, and double flashes when an agent needs your attention. |

Turn LidPulse off to return brightness control to macOS, or switch **Logo Light** off to keep the lid light dark while LidPulse is running. A live preview and brightness slider are available in the menu bar. The separate Settings window includes English and Traditional Chinese, Open at Login, and individual agent connections.

On supported hardware, turn on **Keep Logo Lit With Lid Closed** in the menu bar panel to continue the selected mode and brightness with the lid closed. Your Mac stays awake for up to 10 minutes per closed-lid session, without administrator approval. Low battery or elevated thermal pressure ends the session early. Turning the option off, disabling the light, or quitting restores normal sleep. Do not put your Mac in a bag while this is enabled.

Use **Check for Updates…** in the menu or Settings to install new releases. Automatic checking and installation are enabled by default and can be changed in Settings. Update feeds and downloads are signed and verified before installation; your settings are preserved. Users on 1.0.x need to install this release once to gain in-app updates.

## Compatibility and installation

- Requires an Apple silicon Mac with a supported, physically illuminated lid logo. The app requires macOS 14.2 or newer. Apple’s native Liquid Glass effects require macOS 26 or newer.
- Open the [latest release](https://github.com/siumiu1968/LidPulse/releases/latest), download the DMG, and drag **LidPulse.app** to **Applications**. Open it and look for the glowing Apple logo in the menu bar.
- This release is ad hoc signed and is **not notarized by Apple**. macOS may block a downloaded copy at first launch.

## Permissions and connections

- **Full Brightness:** If macOS is still limiting the logo’s brightness, choose **Unlock Full Brightness…** in the menu or Settings. macOS asks for administrator approval; its own dialog handles the password or other authentication. LidPulse keeps a backup of the two previous brightness limits and offers **Restore Previous Limits…** afterward. Standard controls and launch do not request administrator approval.
- **Music:** Grant system audio access when macOS asks. LidPulse analyzes audio locally and does not save or upload it.
- **Codex and Claude Code:** Go to **Settings → Agent Connections**, select **Connect**, and restart or open a new agent session if needed. In Codex, review and trust the hooks in **Settings → Hooks**, or use `/hooks` in the CLI. Use the folder button if you use a custom configuration directory. Hooks send local status signals; they do not send prompt text or tool output to LidPulse.

## Build from source

With Xcode and its macOS SDK available:

```sh
./script/build_and_run.sh
./script/package_dmg.sh
```

The second command builds the DMG in `outputs/` without quitting a running copy of the app.

## 繁體中文

**LidPulse 係一個 macOS 選單列 App，可以控制支援嘅 OLED MacBook Pro 機蓋 Apple Logo 燈。** 可以調較亮度、熄燈、設定呼吸或音樂節拍，亦可以用 Logo 燈顯示 Codex 同 Claude Code 嘅狀態。設定有中英文切換、登入啟動同 AI 連接。

- **下載：** 喺 [GitHub Releases](https://github.com/siumiu1968/LidPulse/releases/latest) 下載 DMG，將 LidPulse 拖入「應用程式」。App 開啟後會出現喺選單列。此版本未經 Apple 公證，macOS 首次開啟下載版時可能會阻擋。
- **支援機型：** 睇清楚產品名有冇寫 **PROLED XDR 顯示器**。14 吋同 16 吋 PROLED XDR 版有發光 Logo。LidPulse 已喺 M5 Max 機型（`Mac17,10`、macOS 27.2）實測。同期推出嘅 14 吋 M6 版用 Liquid Retina XDR。 [Apple 發光 Logo 說明](https://support.apple.com/en-us/149248) · [Apple M6 產品公告](https://www.apple.com/newsroom/2026/10/apple-introduces-the-new-14-inch-macbook-pro-with-m6/)
- **合蓋時保留燈效：** 支援嘅機型可以喺主選單開啟「合蓋時保持 Logo 發光」，合蓋後會沿用目前模式同亮度，毋須管理員授權。Mac 每次合蓋保持清醒最多 10 分鐘，低電量或系統報告升溫時會提早停止。關閉此功能、熄 Logo 燈或退出 App 時會恢復正常睡眠。開啟期間請勿將 Mac 放入袋中。
- **最高亮度：** 如果部機仍有限制，按「解除最高亮度限制…」後由 macOS 要求管理員授權。之後可以還原之前嘅限制；平時開 App 唔會問密碼。
- **音樂及 AI 狀態：** 音樂模式需系統音訊權限，音訊只喺本機分析。喺設定可以分開連接 Codex 同 Claude Code；Codex 需審閱同信任 hooks 先會觸發。

- **電量模式：** Logo 會隨電量下降而調暗，並以你設定嘅亮度為上限。
- **App 內更新：** 主選單及設定均可檢查更新；預設會自動檢查、下載及安裝，亦可自行關閉。更新來源同套件均會驗證簽章。舊版 1.0.x 用戶需先手動安裝此版本一次。
