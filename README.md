# LidPulse — MacBook Apple logo light control

**LidPulse is a macOS menu bar app for the illuminated Apple logo on supported MacBook Pro lids.** Set the logo brightness, make it breathe, sync it to music, or use it as a status light for Codex and Claude Code.

[Download the DMG](https://github.com/siumiu1968/LidPulse/releases/latest) · [Product guide](https://siumiu1968.github.io/LidPulse/) · [繁體中文](#繁體中文)

## What it does

| Mode | What the logo does |
| --- | --- |
| **Steady** | Holds your chosen brightness. |
| **Breathe** | Fades up and down at an adjustable pace. |
| **Music** | Pulses to beats detected in the audio your Mac plays. Adjust beat intensity or turn the light off between beats. |
| **Agents** | Glows softly while idle, pulses while Codex or Claude Code is working, and double flashes when an agent needs your attention. |

Turn LidPulse off to return brightness control to macOS, or switch **Logo Light** off to keep the lid light dark while LidPulse is running. A live preview and brightness slider are available in the menu bar. The separate Settings window includes English and Traditional Chinese, Open at Login, and individual agent connections.

On supported hardware, turn on **Keep Logo Lit With Lid Closed** in the menu bar panel to continue the selected mode and brightness while the Mac is awake. Turn it off to let the logo go dark when you close the lid. LidPulse follows your Mac’s sleep settings.

## Compatibility and installation

- Requires an Apple silicon Mac with a supported, physically illuminated lid logo. A Mac without the light cannot gain one through software.
- The hardware controls were tested on a MacBook Pro with a PROLED XDR display (model identifier `Mac17,10`) on macOS 27.2. The app requires macOS 14.2 or newer; Apple’s native Liquid Glass effects require macOS 26 or newer.
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

**LidPulse 係一個 macOS 選單列 App，控制支援機型機蓋上真正嘅發光 Apple Logo。** 可以長亮、熄燈、調較呼吸速度、跟音樂節拍閃動，亦可以用 Logo 燈顯示 Codex 同 Claude Code 嘅狀態。日常控制喺選單列；獨立設定有中英文切換、登入啟動同 AI 連接。

- **下載：** 喺 [GitHub Releases](https://github.com/siumiu1968/LidPulse/releases/latest) 下載 DMG，將 LidPulse 拖入「應用程式」。App 開啟後會出現喺選單列。此版本未經 Apple 公證，macOS 首次開啟下載版時可能會阻擋。
- **支援機型：** 需要有實體發光 Logo 嘅 Apple silicon Mac；已喺 PROLED XDR MacBook Pro（`Mac17,10`、macOS 27.2）實測。
- **合蓋時保留燈效：** 支援嘅機型可以喺主選單開啟「合蓋時保持 Logo 發光」。只要 Mac 仲醒住，合蓋後會沿用目前模式同亮度。關閉開關後，合蓋會熄燈。LidPulse 跟隨 Mac 嘅睡眠設定。
- **最高亮度：** 如果部機仍有限制，按「解除最高亮度限制…」後由 macOS 要求管理員授權。之後可以還原之前嘅限制；平時開 App 唔會問密碼。
- **音樂及 AI 狀態：** 音樂模式需系統音訊權限，音訊只喺本機分析。喺設定可以分開連接 Codex 同 Claude Code；Codex 需審閱同信任 hooks 先會觸發。
