# TopPin 📌

[中文](README.md) | [English](README_EN.md)

> High-performance, unrestricted window pinning and Picture-in-Picture (PiP) utility for macOS. Engineered for **Computer Use** and AI desktop automation.

![Platform](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Architecture](https://img.shields.io/badge/Arch-Apple%20Silicon%20%2F%20Universal-green)
![License](https://img.shields.io/badge/License-MIT-purple)

---

## 💡 Background & Motivation

When working with **Claude Computer Use, OSWorld, or automated desktop agents/scripts**, automated programs frequently spawn, activate, and pop browser windows or target apps to the foreground. This constantly buries and interrupts the user's active workspace (code editors, reference documents, terminal logs, team chats, or dashboards).

- **Windows**: Offers mature third-party pin tools (e.g., DeskPins, WindowTop);
- **macOS**: Due to system sandboxing and Window Server security policies, Apple does not provide a public API for third-party apps to change the Window Level of another process;
- **Existing macOS Utilities** (such as `floatytool.com`): The free tier is severely crippled (limited to 1 window, locked hotkeys, locked opacity slider, forcing a $9.99 Pro license);
- **TopPin**: Solves this completely by leveraging modern low-level macOS technologies (hardware-accelerated ScreenCaptureKit zero-copy stream, CALayer GPU rendering, Carbon global hotkeys, and Accessibility coordination). **Completely free, open-source, and unrestricted.**

---

## ✨ Key Features

### 1. ⚡️ Hardware-Accelerated Live Mirroring (ScreenCaptureKit 60/30fps)
- Extracts window pixels in real time via Apple's ScreenCaptureKit framework, streaming directly to GPU rendering surfaces through zero-copy `IOSurface` with near-zero CPU overhead;
- Real-time geometric tracking: window moves and resize actions are synchronized dynamically at 30Hz.

### 2. 🤖 Tailored for Computer Use & AI Desktop Automation
- **📸 Hide from Screen Capture**: Pinned overlays use `NSWindow.SharingType.none`. When an AI agent takes screenshots or screen recordings, **the overlay is completely invisible to the capture stream**. Vision models inspect the actual desktop unimpeded, while human users continue to view the pinned window seamlessly!
- **🎯 Pass Synthetic Clicks**: When automated or synthetic mouse clicks (programmatic events) are detected, the overlay passes them straight through in milliseconds without obstructing automation workflows.
- **📜 Direct Scroll Forwarding**: Hovering over a pinned overlay and scrolling mouse wheels forwards the scroll event straight to the target process **without needing to raise or switch window focus**.

### 3. 🎯 Dual Pinning Modes
- **Smart Occlusion Pinning (Default)**: When your real window is frontmost, you interact with it 100% natively. As soon as another window (e.g., a browser opened by Computer Use) covers it, the floating overlay appears instantly!
- **Always Float (PiP)**: Keeps the window floating above all standard application windows at all times, ideal for reference documents or live monitor thumbnails.

### 4. 🖼 Picture-in-Picture & Free Dragging (PiP)
- Scale pinned windows to **75% / 50% / 33% / 25%**;
- Click and drag the overlay freely to any corner of the screen;
- Double-click the overlay or use the right-click menu to instantly restore and focus the real application window.

### 5. 👻 Click-Through Transparency & Multi-level Opacity
- **Click-Through Mode**: Makes the overlay mouse-transparent so all mouse clicks pass through to whatever app is underneath, allowing you to code beneath reference notes;
- **Opacity Control**: Easily adjust opacity to 100%, 90%, 80%, 70%, 50%, or 30%.

### 6. ⌨️ Global Shortcuts & Menu Bar Dashboard
- Comprehensive Carbon-registered global hotkeys operable from any workspace;
- Menu bar status item displays the count of currently pinned windows with per-window controls.

---

## ⌨️ Global Shortcuts

| Shortcut | Action |
| :--- | :--- |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>P</kbd> (`Control + Option + P`) | **Pin / Unpin current frontmost window** |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>P</kbd> (`Control + Option + Shift + P`) | **Unpin all windows** |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>T</kbd> (`Control + Option + T`) | **Toggle click-through on frontmost pinned window** |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>O</kbd> (`Control + Option + O`) | **Cycle opacity** (100% → 80% → 60% → 40%) |

---

## 🖱 Mouse Gestures

- **Single Click**: Smoothly brings the real application window to the front;
- **Double Click**: Instantly raises and focuses the real window;
- **Click & Drag**: Freely relocates the floating/PiP window;
- **Mouse Scroll**: Scrolls the real window directly without focus switching;
- **Right Click**: Opens context menu for quick adjustments (scaling, opacity, click-through, reset position).

---

## 🚀 Building & Installation

### Option 1: Run the Precompiled App

Launch via Terminal:
```bash
open ~/Applications/TopPin.app
```
Or locate **TopPin.app** in Finder under `~/Applications` and double-click to launch.

### Option 2: Build from Source

```bash
cd ~/Desktop/projects/TopPin
./build.sh
```
The compiled output will be generated at `build/TopPin.app`.

---

## 🔐 System Permissions

On first launch, macOS requires two permissions:
1. **Screen Recording Permission**: Required by ScreenCaptureKit to stream live window frames. Enable TopPin under **System Settings › Privacy & Security › Screen & System Audio Recording**.
2. **Accessibility Permission**: Required to bring the real application window to focus when clicking the overlay. Enable TopPin under **System Settings › Privacy & Security › Accessibility**.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
