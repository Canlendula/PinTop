import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private let manager = PinManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateStatusIcon()

        manager.onChange = { [weak self] in self?.updateStatusIcon() }

        let mods = controlKey | optionKey
        // ⌃⌥P: Toggle pin frontmost window
        if let hk = HotKey(keyCode: kVK_ANSI_P, modifiers: mods, handler: {
            PinManager.shared.toggleFrontmostWindow()
        }) {
            hotKeys.append(hk)
        }
        // ⌃⌥⇧P: Unpin all
        if let hk = HotKey(keyCode: kVK_ANSI_P, modifiers: mods | shiftKey, handler: {
            let n = PinManager.shared.pins.count
            PinManager.shared.unpinAll()
            if n > 0 { Toast.show("已取消全部置顶", symbol: "pin.slash") }
        }) {
            hotKeys.append(hk)
        }
        // ⌃⌥T: Toggle click-through on frontmost pinned window
        if let hk = HotKey(keyCode: kVK_ANSI_T, modifiers: mods, handler: {
            PinManager.shared.toggleClickThroughFrontmost()
        }) {
            hotKeys.append(hk)
        }
        // ⌃⌥O: Cycle opacity on frontmost pinned window
        if let hk = HotKey(keyCode: kVK_ANSI_O, modifiers: mods, handler: {
            PinManager.shared.cycleOpacityFrontmost()
        }) {
            hotKeys.append(hk)
        }

        if !Permissions.hasScreenRecording {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Permissions.requestScreenRecording() }
        } else if !Permissions.hasAccessibility {
            AX.requestTrust()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.unpinAll()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let active = !manager.pins.isEmpty
        let image = NSImage(systemSymbolName: active ? "pin.fill" : "pin", accessibilityDescription: "TopPin")
        image?.isTemplate = true
        button.image = image
        button.title = active ? " \(manager.pins.count)" : ""
        button.imagePosition = .imageLeading
        button.toolTip = active ? "TopPin：已置顶 \(manager.pins.count) 个窗口" : "TopPin：窗口置顶"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let front = WindowList.frontmostWindow()
        let toggleTitle: String
        if let front, manager.pin(for: front.id) != nil {
            toggleTitle = "取消置顶当前窗口"
        } else {
            toggleTitle = "置顶当前窗口"
        }
        let toggle = item(toggleTitle, #selector(toggleFrontmost))
        toggle.keyEquivalent = "p"
        toggle.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(toggle)

        let chooser = NSMenuItem(title: "选择窗口置顶", action: nil, keyEquivalent: "")
        chooser.submenu = windowChooserMenu()
        menu.addItem(chooser)

        menu.addItem(.separator())

        if manager.pins.isEmpty {
            let none = NSMenuItem(title: "暂无置顶窗口", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            let header = NSMenuItem(title: "已置顶（\(manager.pins.count)）", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for p in manager.pins {
                let mi = NSMenuItem(title: truncate(p.displayName), action: nil, keyEquivalent: "")
                mi.image = appIcon(pid: p.pid)
                mi.submenu = pinMenu(for: p)
                menu.addItem(mi)
            }
            let all = item("取消全部置顶", #selector(unpinAll))
            all.keyEquivalent = "p"
            all.keyEquivalentModifierMask = [.control, .option, .shift]
            menu.addItem(all)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        settings.submenu = settingsMenu()
        menu.addItem(settings)

        if !Permissions.hasScreenRecording || !Permissions.hasAccessibility {
            menu.addItem(.separator())
            if !Permissions.hasScreenRecording {
                let mi = item("⚠️ 授予屏幕录制权限…", #selector(openScreenRecording))
                menu.addItem(mi)
            }
            if !Permissions.hasAccessibility {
                let mi = item("⚠️ 授予辅助功能权限…", #selector(openAccessibility))
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("关于 TopPin", #selector(showAbout)))
        let quit = item("退出 TopPin", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func windowChooserMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        let candidates = WindowList.pinCandidates()
        if candidates.isEmpty {
            let none = NSMenuItem(title: "没有可置顶的窗口", action: nil, keyEquivalent: "")
            none.isEnabled = false
            m.addItem(none)
        }
        for w in candidates {
            let mi = item(truncate(w.displayName), #selector(pinWindow(_:)))
            mi.representedObject = NSNumber(value: w.id)
            mi.image = appIcon(pid: w.pid)
            mi.state = manager.pin(for: w.id) != nil ? .on : .off
            m.addItem(mi)
        }
        return m
    }

    private func pinMenu(for p: PinnedWindow) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        let id = NSNumber(value: p.windowID)

        let show = item("切换到该窗口", #selector(focusPinned(_:)))
        show.representedObject = id
        m.addItem(show)

        let float = item("始终悬浮置顶", #selector(toggleAlwaysFloat(_:)))
        float.representedObject = id
        float.state = p.alwaysFloat ? .on : .off
        m.addItem(float)

        let through = item("鼠标穿透（仅显示，不可点击）", #selector(toggleClickThrough(_:)))
        through.representedObject = id
        through.state = p.clickThrough ? .on : .off
        through.keyEquivalent = "t"
        through.keyEquivalentModifierMask = [.control, .option]
        m.addItem(through)

        let scaleItem = NSMenuItem(title: "画中画缩放", action: nil, keyEquivalent: "")
        let sm = NSMenu()
        sm.autoenablesItems = false
        let scales: [(String, CGFloat)] = [("100%（原尺寸）", 1.0), ("75%", 0.75), ("50%", 0.5), ("33%", 0.33), ("25%", 0.25)]
        for (label, val) in scales {
            let si = item(label, #selector(setScale(_:)))
            si.representedObject = [id, NSNumber(value: Double(val))]
            si.state = abs(p.scale - val) < 0.03 ? .on : .off
            sm.addItem(si)
        }
        scaleItem.submenu = sm
        m.addItem(scaleItem)

        let opacity = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        opacity.keyEquivalent = "o"
        opacity.keyEquivalentModifierMask = [.control, .option]
        let om = NSMenu()
        for v in [1.0, 0.9, 0.8, 0.7, 0.5, 0.3] {
            let oi = item("\(Int(v * 100))%", #selector(setOpacity(_:)))
            oi.representedObject = [id, NSNumber(value: v)]
            oi.state = abs(p.opacity - v) < 0.01 ? .on : .off
            om.addItem(oi)
        }
        opacity.submenu = om
        m.addItem(opacity)

        if p.customOrigin != nil || p.scale < 0.99 {
            let reset = item("恢复默认位置与尺寸", #selector(resetPinned(_:)))
            reset.representedObject = id
            m.addItem(reset)
        }

        m.addItem(.separator())
        let un = item("取消置顶", #selector(unpinOne(_:)))
        un.representedObject = id
        m.addItem(un)
        return m
    }

    private func settingsMenu() -> NSMenu {
        let s = Settings.shared
        let m = NSMenu()
        m.autoenablesItems = false

        let defFloat = item("默认始终悬浮置顶（关闭则为智能遮挡时置顶）", #selector(toggleAlwaysFloatByDefault))
        defFloat.state = s.alwaysFloatByDefault ? .on : .off
        m.addItem(defFloat)

        let hide = item("置顶层不出现在截图/录屏中（推荐配合 Computer Use）", #selector(toggleHideFromCapture))
        hide.state = s.hideFromCapture ? .on : .off
        m.addItem(hide)

        let synth = item("自动化点击穿透（程序模拟的点击穿过置顶层）", #selector(toggleSynthetic))
        synth.state = s.passSyntheticClicks ? .on : .off
        m.addItem(synth)

        let scroll = item("在置顶层上滚动时直接滚动原窗口", #selector(toggleScroll))
        scroll.state = s.forwardScroll ? .on : .off
        m.addItem(scroll)

        let border = item("显示置顶边框", #selector(toggleBorder))
        border.state = s.showBorder ? .on : .off
        m.addItem(border)

        let fps = NSMenuItem(title: "刷新帧率", action: nil, keyEquivalent: "")
        let fm = NSMenu()
        for v in [15, 30, 60] {
            let fi = item("\(v) fps", #selector(setFPS(_:)))
            fi.representedObject = NSNumber(value: v)
            fi.state = s.frameRate == v ? .on : .off
            fm.addItem(fi)
        }
        fps.submenu = fm
        m.addItem(fps)

        let op = NSMenuItem(title: "新置顶窗口的默认不透明度", action: nil, keyEquivalent: "")
        let om = NSMenu()
        for v in [1.0, 0.9, 0.8, 0.7, 0.5] {
            let oi = item("\(Int(v * 100))%", #selector(setDefaultOpacity(_:)))
            oi.representedObject = NSNumber(value: v)
            oi.state = abs(s.defaultOpacity - v) < 0.01 ? .on : .off
            om.addItem(oi)
        }
        op.submenu = om
        m.addItem(op)

        m.addItem(.separator())
        let login = item("登录时启动", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(login)
        return m
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        return mi
    }

    private func truncate(_ s: String, _ n: Int = 60) -> String {
        s.count > n ? String(s.prefix(n - 1)) + "…" : s
    }

    private var iconCache: [pid_t: NSImage] = [:]
    private func appIcon(pid: pid_t) -> NSImage? {
        if let img = iconCache[pid] { return img }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 16, height: 16)
        iconCache[pid] = icon
        return icon
    }

    private func pin(from sender: NSMenuItem) -> PinnedWindow? {
        guard let n = sender.representedObject as? NSNumber else { return nil }
        return manager.pin(for: CGWindowID(n.uint32Value))
    }

    // MARK: - Actions

    @objc private func toggleFrontmost() { manager.toggleFrontmostWindow() }
    @objc private func unpinAll() { manager.unpinAll() }

    @objc private func pinWindow(_ sender: NSMenuItem) {
        guard let n = sender.representedObject as? NSNumber else { return }
        let id = CGWindowID(n.uint32Value)
        if let p = manager.pin(for: id) { manager.unpin(p); return }
        guard let info = WindowList.window(id) else { return }
        manager.pin(info)
    }

    @objc private func focusPinned(_ sender: NSMenuItem) { pin(from: sender)?.bringRealWindowToFront() }
    @objc private func unpinOne(_ sender: NSMenuItem) { if let p = pin(from: sender) { manager.unpin(p) } }

    @objc private func toggleAlwaysFloat(_ sender: NSMenuItem) {
        guard let p = pin(from: sender) else { return }
        p.alwaysFloat.toggle()
        manager.tick()
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        guard let p = pin(from: sender) else { return }
        p.clickThrough.toggle()
    }

    @objc private func setScale(_ sender: NSMenuItem) {
        guard let arr = sender.representedObject as? [NSNumber], arr.count == 2,
              let p = manager.pin(for: CGWindowID(arr[0].uint32Value)) else { return }
        p.scale = CGFloat(arr[1].doubleValue)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let arr = sender.representedObject as? [NSNumber], arr.count == 2,
              let p = manager.pin(for: CGWindowID(arr[0].uint32Value)) else { return }
        p.opacity = arr[1].doubleValue
    }

    @objc private func resetPinned(_ sender: NSMenuItem) {
        pin(from: sender)?.resetPositionAndScale()
    }

    @objc private func toggleAlwaysFloatByDefault() { Settings.shared.alwaysFloatByDefault.toggle() }
    @objc private func toggleHideFromCapture() { Settings.shared.hideFromCapture.toggle() }
    @objc private func toggleSynthetic() { Settings.shared.passSyntheticClicks.toggle() }
    @objc private func toggleScroll() { Settings.shared.forwardScroll.toggle() }
    @objc private func toggleBorder() { Settings.shared.showBorder.toggle() }

    @objc private func setFPS(_ sender: NSMenuItem) {
        if let n = sender.representedObject as? NSNumber { Settings.shared.frameRate = n.intValue }
    }

    @objc private func setDefaultOpacity(_ sender: NSMenuItem) {
        if let n = sender.representedObject as? NSNumber { Settings.shared.defaultOpacity = n.doubleValue }
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改登录项"
            alert.informativeText = "\(error.localizedDescription)\n\n提示：请先把 TopPin.app 放到“应用程序”文件夹中再试。"
            NSApp.activate()
            alert.runModal()
        }
    }

    @objc private func openScreenRecording() {
        Permissions.requestScreenRecording()
        Permissions.openScreenRecordingSettings()
    }

    @objc private func openAccessibility() {
        AX.requestTrust()
        Permissions.openAccessibilitySettings()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "TopPin 1.0.0"
        alert.informativeText = """
        轻量高效的 macOS 原生窗口置顶与画中画工具。

        【快捷键】
        • ⌃⌥P：置顶 / 取消置顶当前窗口
        • ⌃⌥⇧P：取消全部置顶
        • ⌃⌥T：快速切换鼠标穿透（可穿透点击下层窗口）
        • ⌃⌥O：快速切换不透明度（100% / 80% / 60% / 40%）

        【交互特性】
        • 单击置顶层：平滑切换到真实窗口进行操作
        • 拖拽置顶层：自由摆放悬浮位置或画中画窗口
        • 滚轮滚动：直接穿透滚动原窗口内容
        • 右键置顶层：快捷菜单（缩放比例、透明度、穿透等）
        • 针对 Computer Use 深度优化：支持截图防阻挡与自动化点击穿透。
        """
        NSApp.activate()
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
