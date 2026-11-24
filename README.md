# DroidMirror

Mirror and control an Android phone from your Mac, iPhone Mirroring style. Native Swift app (AppKit + SwiftUI),
using [scrcpy](https://github.com/Genymobile/scrcpy)'s server on the phone. No app or root needed on the phone.

## Features
- Phone screen in a phone-shaped window, GPU-decoded (H.264 via VideoToolbox)
- Click and drag = touch and swipe, trackpad/mouse scrolling, keyboard typing
- Right-click or Esc = Back; top bar has Back / Home / Recents / phone-screen toggle and more
- Phone audio on the Mac (Android 11+)
- Clipboard sync both ways; ⌘V pastes your Mac clipboard on the phone, ⌘C copies from the phone
- Drop files on the window: APKs install, everything else goes to Download
- USB or Wi-Fi (wireless debugging pairing built in), auto-reconnect, menu bar icon

## Setup
1. On the phone: enable Developer options, then **USB debugging** (and **Wireless debugging** for Wi-Fi).
2. Open DroidMirror. Plug in the phone and allow the debugging prompt, or pair/connect over Wi-Fi in the Phones window.
3. Click **Mirror**.

The app is ad-hoc signed. After downloading, run once: `xattr -dr com.apple.quarantine /Applications/DroidMirror.app`

## Shortcuts
| Key | Action |
|---|---|
| Esc / right-click | Back |
| ⇧⌘H | Home |
| ⇧⌘A | Recent apps |
| ⇧⌘N / ⇧⌘S | Notifications / Quick settings |
| ⌘R | Rotate |
| ⇧⌘O | Phone screen off/on |
| ⌘↑ / ⌘↓ | Volume |
| ⌘P | Power button |

## Build
`./scripts/package.sh` on macOS with Xcode. It bundles scrcpy-server 5.0.1 (Apache 2.0) and adb from Google's platform-tools.
