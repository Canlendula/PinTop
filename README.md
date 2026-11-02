# TopPin 📌

[中文](README.md) | [English](README_EN.md)

> 专为 macOS 打造的高性能、无限制窗口置顶与画中画（PiP）工具。深度适配 **Computer Use** 与 AI 桌面自动化。

![Platform](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Architecture](https://img.shields.io/badge/Arch-Apple%20Silicon%20%2F%20Universal-green)
![License](https://img.shields.io/badge/License-MIT-purple)

---

## 💡 开发背景与痛点

在使用 **Claude Computer Use、OSWorld 或其他桌面自动化 Agent / 脚本** 时，自动化程序会频繁弹出并抢占焦点置顶浏览器或被控窗口，导致用户原本正在查阅的前台工作窗口（代码、文档、终端、IM、监控等）被频繁遮挡打断。

- **Windows 平台**：拥有成熟的第三方置顶工具（如 DeskPins、WindowTop 等）；
- **macOS 平台**：苹果出于系统沙箱与安全性限制，并未向普通第三方应用开放直接修改其他进程窗口层级（Window Level）的 API；
- **现有 macOS 工具**（如 `floatytool.com`）：免费版限制极大（仅允许置顶 1 个窗口、锁定快捷键、锁定不透明度调节，Pro 版强制收费 $9.99）；
- **TopPin**：结合现代 macOS 底层技术（ScreenCaptureKit 硬件加速零拷贝渲染流、CALayer GPU 渲染、Carbon 全局热键、Accessibility 协同调度），彻底解决上述痛点，**完全开源免费且没有任何功能限制**。

---

## ✨ 核心特性

### 1. ⚡️ 硬件加速实时镜像（ScreenCaptureKit 60/30fps）
- 基于 Apple 原生高效的 ScreenCaptureKit 实时提取窗口像素，借助 `IOSurface` 零拷贝技术直接送入 GPU 图层渲染，CPU 占用极低；
- 动态几何同步：原窗口移动、缩放尺寸时，置顶层以 30Hz 自动实时同步位置与分辨率。

### 2. 🤖 深度适配 Computer Use 与 AI 桌面自动化
- **📸 截图防阻挡（Hide from Capture）**：置顶悬浮层采用 `NSWindow.SharingType.none`。当 Agent 截屏或录屏时，**置顶层对 Agent 完全隐形**，确保 AI 视觉模型能够直接“看”到底层实际工作界面，而人类用户的肉眼依然能看清悬浮置顶窗！
- **🎯 自动化模拟点击穿透（Pass Synthetic Clicks）**：当检测到底层或自动化程序派发的虚拟点击事件时，置顶层毫秒级自动穿透，确保不干扰 AI 的正常操作流程。
- **📜 滚轮直接透传（Scroll Forwarding）**：鼠标悬停在置顶层上滑动滚轮时，滚动事件直接派发给目标进程，**无需切换焦点即可快速翻阅原窗口内容**。

### 3. 🎯 灵活的双置顶模式
- **智能遮挡置顶（默认）**：当真实窗口位于最顶层时，完全保持原生响应；一旦有其他窗口（如 Computer Use 弹出的浏览器）覆盖时，悬浮层毫秒级自动浮现置顶！
- **始终悬浮置顶（Always Float）**：无论是否有窗口遮挡，悬浮层始终保持在最前层，特别适合作为画中画或半透明参考窗。

### 4. 🖼 画中画模式与自由拖拽（PiP & Free Drag）
- 支持将置顶窗口缩放为 **75% / 50% / 33% / 25%**；
- 鼠标可直接**按住并拖拽悬浮窗**至屏幕任意位置，打造任意应用的实时画中画监视器；
- 双击置顶层或通过右键菜单可一键切回并激活真实窗口。

### 5. 👻 鼠标穿透与多级透明度调节
- **鼠标穿透（Click-Through）**：悬浮层仅作为视觉显示，所有鼠标点击直接穿透至下层窗口，边看参考资料边写代码；
- **透明度调节**：支持 100%、90%、80%、70%、50%、30% 快速调节。

### 6. ⌨️ 全局快捷键与菜单栏控制
- 包含丰富的系统全局热键，随时随地单手触发；
- 菜单栏图标实时显示当前置顶窗口数量，支持快速选择任意窗口。

---

## ⌨️ 快捷键一览

| 快捷键 | 功能说明 |
| :--- | :--- |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>P</kbd> (`Control + Option + P`) | **置顶 / 取消置顶当前前台窗口** |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>P</kbd> (`Control + Option + Shift + P`) | **一键取消全部置顶** |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>T</kbd> (`Control + Option + T`) | **快速切换最上层置顶窗口的鼠标穿透模式** |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>O</kbd> (`Control + Option + O`) | **快速循环切换不透明度**（100% → 80% → 60% → 40%） |

---

## 🖱 交互手势

- **单击置顶层**：平滑唤醒并激活真实应用窗口；
- **双击置顶层**：快速唤醒真实窗口；
- **拖拽置顶层**：自由移动画中画或悬浮窗口位置；
- **鼠标滚轮**：在置顶层上滚动即可直接翻动原窗口；
- **右键置顶层**：弹出快捷菜单，直接调节画中画比例（100%/75%/50%/33%/25%）、不透明度或恢复默认位置。

---

## 🚀 编译与安装

### 方式 1：直接运行已编译的 App

在终端中执行：
```bash
open ~/Applications/TopPin.app
```
或者在访达（Finder）中进入“应用程序”文件夹，双击运行 **TopPin.app**。

### 方式 2：从源码编译

```bash
cd ~/Desktop/projects/TopPin
./build.sh
```
编译产物位于 `build/TopPin.app`。

---

## 🔐 权限说明

初次运行 TopPin 时，macOS 会提示以下两项系统权限：
1. **屏幕与系统录音权限（Screen Recording）**：TopPin 需要使用 ScreenCaptureKit 实时捕获被置顶窗口的画面进行镜像。在 **系统设置 › 隐私与安全性 › 屏幕与系统录音** 中勾选 TopPin。
2. **辅助功能权限（Accessibility）**：用于在点击置顶层时精确唤醒并聚焦被置顶的目标窗口。在 **系统设置 › 隐私与安全性 › 辅助功能** 中勾选 TopPin。

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。
