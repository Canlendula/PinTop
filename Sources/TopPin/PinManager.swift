import AppKit
import ScreenCaptureKit

/// Owns all pinned windows and keeps their overlays in sync with the real windows.
final class PinManager {
    static let shared = PinManager()

    private(set) var pins: [PinnedWindow] = []
    private var pending = Set<CGWindowID>()
    private var timer: Timer?
    private var lastStack: [CGWindowID] = []
    private let myPID = ProcessInfo.processInfo.processIdentifier

    /// Called whenever the set of pins changes.
    var onChange: (() -> Void)?

    private init() {
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.pins.forEach {
                $0.applySettings()
                $0.applyFrameRate()
            }
            self?.tick()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tick()
        }
    }

    func pin(for id: CGWindowID) -> PinnedWindow? { pins.first { $0.windowID == id } }

    func frontmostPinnedWindow() -> PinnedWindow? {
        let list = WindowList.onScreen()
        for w in list {
            if let p = pin(for: w.id) { return p }
        }
        return pins.last
    }

    // MARK: - Public actions

    func toggleFrontmostWindow() {
        guard let w = WindowList.frontmostWindow() else {
            Toast.show("没有找到可置顶的窗口", symbol: "exclamationmark.triangle")
            return
        }
        if let p = pin(for: w.id) {
            unpin(p)
            Toast.show("已取消置顶：\(p.displayName)", symbol: "pin.slash")
        } else {
            pin(w)
        }
    }

    func toggleClickThroughFrontmost() {
        guard let p = frontmostPinnedWindow() else {
            Toast.show("当前没有置顶窗口", symbol: "info.circle")
            return
        }
        p.clickThrough.toggle()
        Toast.show("\(p.displayName)：穿透已\(p.clickThrough ? "开启" : "关闭")",
                   symbol: p.clickThrough ? "cursorarrow.and.square.on.square.dashed" : "cursorarrow.rays")
        onChange?()
    }

    func cycleOpacityFrontmost() {
        guard let p = frontmostPinnedWindow() else {
            Toast.show("当前没有置顶窗口", symbol: "info.circle")
            return
        }
        let opacities: [Double] = [1.0, 0.8, 0.6, 0.4]
        let current = p.opacity
        let next = opacities.first(where: { $0 < current - 0.05 }) ?? 1.0
        p.opacity = next
        Toast.show("\(p.displayName)：不透明度 \(Int(next * 100))%", symbol: "circle.lefthalf.filled")
        onChange?()
    }

    func pin(_ info: WindowInfo) {
        guard pin(for: info.id) == nil, !pending.contains(info.id) else { return }
        guard Permissions.hasScreenRecording else {
            Permissions.requestScreenRecording()
            return
        }
        pending.insert(info.id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pending.remove(info.id) }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let scWindow = content.windows.first(where: { $0.windowID == info.id }) else {
                    Toast.show("无法捕获该窗口", symbol: "exclamationmark.triangle")
                    return
                }
                let p = PinnedWindow(info: info)
                p.onStreamStopped = { [weak self] p, _ in self?.unpin(p) }
                p.onActivated = { [weak self] _ in self?.tick() }
                try await p.start(window: scWindow)
                self.pins.append(p)
                self.startTimerIfNeeded()
                self.tick()
                self.onChange?()
                Toast.show("已置顶：\(p.displayName)", symbol: "pin.fill")
            } catch {
                NSLog("TopPin: failed to pin window \(info.id): \(error)")
                Toast.show("置顶失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle")
            }
        }
    }

    func unpin(_ p: PinnedWindow) {
        guard let idx = pins.firstIndex(where: { $0 === p }) else { return }
        pins.remove(at: idx)
        p.stop()
        lastStack.removeAll { $0 == p.windowID }
        if pins.isEmpty { stopTimer() }
        onChange?()
    }

    func unpinAll() {
        let all = pins
        pins.removeAll()
        all.forEach { $0.stop() }
        lastStack.removeAll()
        stopTimer()
        onChange?()
    }

    // MARK: - Sync loop

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.005
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let r = a.intersection(b)
        return !r.isNull && r.width * r.height > 64
    }

    func tick() {
        guard !pins.isEmpty else { return }
        let list = WindowList.onScreen()

        var index: [CGWindowID: Int] = [:]
        var occluded: [CGWindowID: Bool] = [:]
        var gone: [PinnedWindow] = []

        for p in pins {
            guard let idx = list.firstIndex(where: { $0.id == p.windowID }) else {
                // Minimized, hidden, on another Space, or closed.
                if WindowList.window(p.windowID) == nil { gone.append(p) }
                continue
            }
            let w = list[idx]
            index[p.windowID] = idx
            p.updateBounds(w.bounds)
            p.updateTitle(w.title)

            var covered = false
            for o in list[..<idx] {
                // Only normal windows of *other* apps count; the pinned app's own sheets,
                // popovers and dialogs must stay usable on top of it.
                guard o.layer == 0, o.alpha > 0.01, o.pid != myPID, o.pid != p.pid else { continue }
                if PinManager.overlaps(o.bounds, w.bounds) { covered = true; break }
            }
            occluded[p.windowID] = covered
        }

        // A visible overlay of a pin that is *behind* another pinned window would cover that
        // window's real copy, so that window has to show its overlay too (and above it).
        var changed = true
        var guardCount = 0
        while changed && guardCount < 16 {
            changed = false
            guardCount += 1
            for a in pins where occluded[a.windowID] == false {
                guard let ia = index[a.windowID] else { continue }
                for b in pins where b !== a && occluded[b.windowID] == true {
                    guard let ib = index[b.windowID], ib > ia else { continue }
                    if PinManager.overlaps(a.bounds, b.bounds) {
                        occluded[a.windowID] = true
                        changed = true
                        break
                    }
                }
            }
        }

        for p in pins {
            let shouldShow = p.alwaysFloat || Settings.shared.alwaysFloatByDefault || (occluded[p.windowID] ?? false)
            p.setOverlayVisible(shouldShow)
        }

        // Keep overlay stacking consistent with the real windows' z-order.
        let shown = pins.filter { $0.isOverlayVisible }
            .sorted { (index[$0.windowID] ?? 0) > (index[$1.windowID] ?? 0) } // back to front
        let stack = shown.map(\.windowID)
        if stack != lastStack {
            if shown.count > 1 {
                for p in shown { p.panel.orderFrontRegardless() }
            }
            lastStack = stack
        }

        if !gone.isEmpty {
            gone.forEach { unpin($0) }
        }
    }
}
