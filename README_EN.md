# TopPin 📌

[中文](README.md) | [English](README_EN.md)

Keep reference material, terminals, or videos above other windows. TopPin is a free, open-source window pinning and picture-in-picture utility for macOS that lives in your menu bar.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Architecture](https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-supported-green)
![License](https://img.shields.io/badge/License-MIT-purple)

## Installation

Requires **macOS 14.0 or later**. Supports Apple Silicon and Intel Macs.

### Direct download

1. Download the macOS package from [GitHub Releases](https://github.com/Canlendula/PinTop/releases).
2. Unzip it and drag **TopPin.app** into your Applications folder.
3. Open TopPin and look for the pin icon in the menu bar.

### Homebrew

Homebrew support is planned. Installation commands will be added once it is available.

## Getting started

1. On first launch, grant Screen Recording and Accessibility permissions when prompted.
2. Focus the window you want to pin and press **⌃⌥P** (Control + Option + P). You can also choose a window from the menu bar's window picker.
3. Use the menu bar to adjust pinning mode, picture-in-picture scale, opacity, and click-through.
4. Press **⌃⌥P** again to unpin the current window, or **⌃⌥⇧P** to unpin all windows.

TopPin displays a live mirror of each pinned window. Click the mirror to return to the original window and interact with it.

## Features

- **Smart pinning:** By default, the overlay appears when another window covers the original. When the original is unobstructed, use it directly.
- **Always float:** Enable it for individual windows to keep reference material or a picture-in-picture view visible.
- **Multiple windows:** Pin several windows at once. The menu bar shows the current count.
- **Picture-in-picture:** Choose 100%, 75%, 50%, 33%, or 25% scale and drag the overlay to another position.
- **Opacity:** Choose 100%, 90%, 80%, 70%, 50%, or 30% opacity.
- **Click-through:** Keep the overlay visible while clicking the window underneath.
- **Scroll forwarding:** Scroll over the overlay to scroll the original window without switching to it first.
- **Automation options:** Pass simulated clicks through the overlay and control its visibility in screenshots and recordings when working with Computer Use.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| **⌃⌥P** · Control + Option + P | Pin / unpin the current window |
| **⌃⌥⇧P** · Control + Option + Shift + P | Unpin all windows |
| **⌃⌥T** · Control + Option + T | Toggle click-through for the frontmost pinned window |
| **⌃⌥O** · Control + Option + O | Cycle opacity: 100% → 80% → 60% → 40% |

## Mouse controls

| Action | Result |
| --- | --- |
| Click / double-click the overlay | Switch to the original window |
| Drag the overlay | Move its floating position |
| Scroll over the overlay | Scroll the original window |
| Right-click the overlay | Adjust scale, opacity, click-through, or unpin the window |

When click-through is enabled, use the menu bar or shortcuts to control the pinned window.

## Settings

Open Settings from the menu bar pin icon to adjust:

- Default floating mode and opacity for new pins. Changing a default preserves the choices made for existing pins.
- Simulated click-through, scroll forwarding, and visibility in screenshots and recordings.
- Overlay borders, refresh rate (15 / 30 / 60 fps), and launch at login.

## Permissions

TopPin needs two permissions:

| Permission | Purpose |
| --- | --- |
| Screen Recording | Display live content from pinned windows |
| Accessibility | Switch to the original window when you click its overlay |

Manage these permissions in **System Settings › Privacy & Security**. Reopen TopPin when macOS prompts you after changing a permission.

## Feedback and license

Report problems or suggest features through [GitHub Issues](https://github.com/Canlendula/PinTop/issues).

TopPin is free and open-source under the [MIT License](LICENSE).
