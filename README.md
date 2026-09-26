# ScreenCam

A tiny macOS menu bar app for quick screen recordings with a floating webcam bubble.

- Records the whole screen (whichever display your mouse is on) at native resolution, 60fps, with your microphone
- A round, mirrored webcam bubble floats on top of everything. Drag it anywhere, and it's captured in the recording
- Start/stop from anywhere with **⌃⌥⌘R**, or from the menu bar icon
- Recordings save to `~/Movies/ScreenCam <date> at <time>.mov`, and Finder reveals the file when you stop

## Requirements

macOS 15 or later and the Xcode command line tools (`xcode-select --install`).

## Build & run

```sh
./build.sh
open ScreenCam.app
```

On first launch, allow camera and microphone access. The first recording asks for **Screen & System Audio Recording** permission. Enable it in System Settings, then quit and reopen ScreenCam.

If you have an Apple Development certificate, `build.sh` signs with it so permissions survive rebuilds. Otherwise it ad-hoc signs, and macOS may ask again after each rebuild.

## Menu

- **Start/Stop Recording** (⌃⌥⌘R)
- **Hide/Show Webcam**
- **Webcam Size**: Small, Medium, Large, Huge
- **Open Recordings Folder**

## Icon

The app icon is drawn in code by `icon/make_icon.swift`. To regenerate it:

```sh
xcrun swiftc icon/make_icon.swift -o /tmp/make_icon
/tmp/make_icon icon/AppIcon.iconset
iconutil -c icns icon/AppIcon.iconset -o icon/AppIcon.icns
```
