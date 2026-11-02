import AppKit
import ApplicationServices

enum Permissions {
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            let alert = NSAlert()
            alert.messageText = "需要“屏幕与系统录音”权限"
            alert.informativeText = "TopPin 通过实时镜像窗口内容来实现置顶，需要屏幕录制权限。\n\n请在 系统设置 › 隐私与安全性 › 屏幕与系统录音 中勾选 TopPin，然后重新打开 TopPin。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { openScreenRecordingSettings() }
        }
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}

/// Small transient HUD used for feedback (e.g. after using the global hot key).
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, symbol: String) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let effect = panel.contentView as? NSVisualEffectView,
              let stack = effect.subviews.first as? NSStackView,
              let icon = stack.arrangedSubviews.first as? NSImageView,
              let label = stack.arrangedSubviews.last as? NSTextField else { return }
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        label.stringValue = text.count > 60 ? String(text.prefix(58)) + "…" : text

        let size = stack.fittingSize
        let w = size.width + 32, h = max(44, size.height + 20)
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let vf = screen?.visibleFrame {
            panel.setFrame(NSRect(x: vf.midX - w / 2, y: vf.maxY - h - 40, width: w, height: h), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.sharingType = .none

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let icon = NSImageView()
        icon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        icon.contentTintColor = .systemOrange
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])
        p.contentView = effect
        return p
    }
}
