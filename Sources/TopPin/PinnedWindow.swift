import AppKit
import CoreMedia
import QuartzCore
import ScreenCaptureKit

/// Borderless, non-activating panel that floats above normal windows and never takes focus.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Displays the live captured frames of the pinned window and routes mouse input.
final class OverlayView: NSView {
    weak var pin: PinnedWindow?
    let imageLayer = CALayer()

    private var initialDragLocation: NSPoint?
    private var initialPanelOrigin: NSPoint?
    private var hasDragged = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = false
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        imageLayer.frame = bounds
        imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "contentsRect": NSNull()]
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if Settings.shared.passSyntheticClicks, PinnedWindow.isSynthetic(event) {
            pin?.forwardThrough(event)
            return
        }
        if event.clickCount >= 2 {
            pin?.bringRealWindowToFront()
            return
        }
        initialDragLocation = NSEvent.mouseLocation
        initialPanelOrigin = window?.frame.origin
        hasDragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        if Settings.shared.passSyntheticClicks, PinnedWindow.isSynthetic(event) {
            pin?.forwardThrough(event)
            return
        }
        guard let initMouse = initialDragLocation, let initOrigin = initialPanelOrigin, let win = window else { return }
        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - initMouse.x
        let dy = currentMouse.y - initMouse.y
        if abs(dx) > 2 || abs(dy) > 2 {
            hasDragged = true
            let newOrigin = NSPoint(x: initOrigin.x + dx, y: initOrigin.y + dy)
            win.setFrameOrigin(newOrigin)
            pin?.customOrigin = newOrigin
        }
    }

    override func mouseUp(with event: NSEvent) {
        if Settings.shared.passSyntheticClicks, PinnedWindow.isSynthetic(event) {
            pin?.forwardThrough(event)
            return
        }
        if !hasDragged {
            // Simple click without drag brings real window to front
            pin?.bringRealWindowToFront()
        }
        initialDragLocation = nil
        initialPanelOrigin = nil
        hasDragged = false
    }

    override func rightMouseDown(with event: NSEvent) {
        if Settings.shared.passSyntheticClicks, PinnedWindow.isSynthetic(event) {
            pin?.forwardThrough(event)
            return
        }
        if let pin = pin {
            let menu = pin.makeContextMenu()
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        if Settings.shared.passSyntheticClicks, PinnedWindow.isSynthetic(event) {
            pin?.forwardThrough(event)
            return
        }
        pin?.bringRealWindowToFront()
    }

    override func scrollWheel(with event: NSEvent) {
        pin?.handleScroll(event)
    }
}

/// One pinned window: owns the ScreenCaptureKit stream and the floating overlay that mirrors it.
final class PinnedWindow: NSObject, SCStreamOutput, SCStreamDelegate {
    let windowID: CGWindowID
    let pid: pid_t
    let ownerName: String
    private(set) var title: String

    let panel: OverlayPanel
    private let view: OverlayView
    private var stream: SCStream?
    private var config = SCStreamConfiguration()
    private let sampleQueue: DispatchQueue
    private var pointPixelScale: CGFloat = 2

    /// Last known bounds of the real window (CG coordinates).
    private(set) var bounds: CGRect = .zero
    private var captureSize: CGSize = .zero
    private var pendingResize: DispatchWorkItem?

    private(set) var isOverlayVisible = false
    private var hasFrame = false
    /// Do not show the overlay before this time (used right after raising the real window).
    private var suppressUntil: Date = .distantPast
    private var passthroughRestore: DispatchWorkItem?

    var opacity: Double { didSet { panel.alphaValue = CGFloat(opacity) } }
    /// When true the overlay is display-only and every click goes to whatever is underneath.
    var clickThrough = false { didSet { applyMouseMode() } }
    /// When true the overlay always stays visible regardless of occlusion.
    var alwaysFloat = false
    /// Picture-in-picture scale factor (1.0 = original size, 0.5 = half size, etc.).
    var scale: CGFloat = 1.0 {
        didSet {
            applySettings()
            updatePanelFrame()
        }
    }
    /// Custom origin when dragged by user.
    var customOrigin: NSPoint? = nil {
        didSet {
            applySettings()
            updatePanelFrame()
        }
    }

    var onStreamStopped: ((PinnedWindow, Error?) -> Void)?
    /// Called when the user clicks the overlay (so the manager can update all overlays).
    var onActivated: ((PinnedWindow) -> Void)?

    init(info: WindowInfo) {
        windowID = info.id
        pid = info.pid
        ownerName = info.ownerName
        title = info.title
        bounds = info.bounds
        opacity = Settings.shared.defaultOpacity
        alwaysFloat = Settings.shared.alwaysFloatByDefault
        sampleQueue = DispatchQueue(label: "TopPin.capture.\(info.id)", qos: .userInteractive)

        let frame = Geometry.cocoaRect(fromCG: info.bounds)
        panel = OverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        view = OverlayView(frame: NSRect(origin: .zero, size: frame.size))
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.alphaValue = CGFloat(opacity)
        panel.title = "TopPin – \(info.displayName)"
        view.pin = self
        panel.contentView = view
        applySettings()
    }

    var displayName: String {
        if title.isEmpty { return ownerName }
        return "\(ownerName) — \(title)"
    }

    // MARK: - Capture

    func start(window scWindow: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        pointPixelScale = CGFloat(filter.pointPixelScale)
        if pointPixelScale <= 0 { pointPixelScale = 2 }

        let cfg = SCStreamConfiguration()
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.capturesAudio = false
        cfg.queueDepth = 5
        cfg.ignoreShadowsSingleWindow = true
        cfg.shouldBeOpaque = false
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Settings.shared.frameRate))
        let size = scWindow.frame.size
        cfg.width = max(1, Int((size.width * pointPixelScale).rounded()))
        cfg.height = max(1, Int((size.height * pointPixelScale).rounded()))
        captureSize = size
        config = cfg

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await s.startCapture()
        stream = s
    }

    func stop() {
        pendingResize?.cancel()
        passthroughRestore?.cancel()
        let s = stream
        stream = nil
        s?.stopCapture { _ in }
        panel.orderOut(nil)
        panel.close()
        isOverlayVisible = false
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let statusRaw = info[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }

        let pxW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let pxH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        var contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let rectDict = info[.contentRect] as? NSDictionary,
           let rect = CGRect(dictionaryRepresentation: rectDict as CFDictionary),
           pxW > 0, pxH > 0, rect.width > 0, rect.height > 0 {
            let scale = (info[.scaleFactor] as? CGFloat) ?? pointPixelScale
            let r = CGRect(x: rect.minX * scale / pxW, y: rect.minY * scale / pxH,
                           width: rect.width * scale / pxW, height: rect.height * scale / pxH)
            if r.width > 0.05, r.height > 0.05, r.maxX <= 1.001, r.maxY <= 1.001 {
                contentsRect = r
            }
        }

        let surface = surfaceRef
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.view.imageLayer.contents = surface
            self.view.imageLayer.contentsRect = contentsRect
            CATransaction.commit()
            if !self.hasFrame {
                self.hasFrame = true
                self.panel.invalidateShadow()
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stream = nil
            self.onStreamStopped?(self, error)
        }
    }

    // MARK: - Frame Calculation

    func targetFrame() -> NSRect {
        let base = Geometry.cocoaRect(fromCG: bounds)
        let scaledSize = NSSize(width: max(120, base.width * scale), height: max(80, base.height * scale))
        if let origin = customOrigin {
            return NSRect(origin: origin, size: scaledSize)
        } else {
            // Keep top-left corner position stable when scaling
            let y = base.maxY - scaledSize.height
            return NSRect(x: base.minX, y: y, width: scaledSize.width, height: scaledSize.height)
        }
    }

    func updatePanelFrame() {
        panel.setFrame(targetFrame(), display: true)
        panel.invalidateShadow()
    }

    func resetPositionAndScale() {
        customOrigin = nil
        scale = 1.0
        applySettings()
        updatePanelFrame()
    }

    // MARK: - Geometry / visibility (driven by PinManager)

    func updateTitle(_ t: String) {
        if !t.isEmpty { title = t }
    }

    func updateBounds(_ newBounds: CGRect) {
        guard newBounds != bounds else { return }
        let sizeChanged = newBounds.size != bounds.size
        bounds = newBounds
        updatePanelFrame()
        if sizeChanged { scheduleCaptureResize() }
    }

    private func scheduleCaptureResize() {
        pendingResize?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyCaptureSize() }
        pendingResize = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func applyCaptureSize() {
        guard let stream, bounds.size != captureSize else { return }
        captureSize = bounds.size
        config.width = max(1, Int((bounds.width * pointPixelScale).rounded()))
        config.height = max(1, Int((bounds.height * pointPixelScale).rounded()))
        stream.updateConfiguration(config) { _ in }
        panel.invalidateShadow()
    }

    func applyFrameRate() {
        guard let stream else { return }
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Settings.shared.frameRate))
        stream.updateConfiguration(config) { _ in }
    }

    func applySettings() {
        panel.sharingType = Settings.shared.hideFromCapture ? .none : .readOnly
        if Settings.shared.showBorder || scale < 0.99 || customOrigin != nil {
            view.layer?.borderWidth = 2
            view.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.9).cgColor
            view.layer?.cornerRadius = 10
            view.layer?.masksToBounds = true
        } else {
            view.layer?.borderWidth = 0
            view.layer?.cornerRadius = 0
            view.layer?.masksToBounds = false
        }
        applyMouseMode()
    }

    private func applyMouseMode() {
        if passthroughRestore == nil {
            panel.ignoresMouseEvents = clickThrough
        }
    }

    var isSuppressed: Bool { Date() < suppressUntil }

    /// Shows or hides the overlay. Returns true if the visibility actually changed.
    @discardableResult
    func setOverlayVisible(_ visible: Bool) -> Bool {
        let shouldShow = visible && hasFrame && !isSuppressed
        guard shouldShow != isOverlayVisible else { return false }
        isOverlayVisible = shouldShow
        if shouldShow {
            updatePanelFrame()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
        return true
    }

    // MARK: - Input

    static func isSynthetic(_ event: NSEvent) -> Bool {
        guard let cg = event.cgEvent else { return false }
        return cg.getIntegerValueField(.eventSourceUnixProcessID) != 0
    }

    func handleScroll(_ event: NSEvent) {
        if Settings.shared.passSyntheticClicks, PinnedWindow.isSynthetic(event) {
            forwardThrough(event)
            return
        }
        guard Settings.shared.forwardScroll, let cg = event.cgEvent?.copy() else { return }
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        cg.postToPid(pid)
    }

    func forwardThrough(_ event: NSEvent) {
        guard let cg = event.cgEvent?.copy() else { return }
        panel.ignoresMouseEvents = true
        passthroughRestore?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.passthroughRestore = nil
            self.applyMouseMode()
        }
        passthroughRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        cg.post(tap: .cghidEventTap)
    }

    func bringRealWindowToFront() {
        suppressUntil = Date().addingTimeInterval(0.6)
        isOverlayVisible = false
        panel.orderOut(nil)
        if !AX.isTrusted { AX.requestTrust() }
        AX.raise(pid: pid, windowID: windowID)
        onActivated?(self)
    }

    // MARK: - Context Menu

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: displayName)
        menu.autoenablesItems = false

        let focus = NSMenuItem(title: "切换到该窗口", action: #selector(contextFocus), keyEquivalent: "")
        focus.target = self
        menu.addItem(focus)

        let float = NSMenuItem(title: "始终悬浮置顶", action: #selector(contextToggleAlwaysFloat), keyEquivalent: "")
        float.target = self
        float.state = alwaysFloat ? .on : .off
        menu.addItem(float)

        let through = NSMenuItem(title: "鼠标穿透（不可点击）", action: #selector(contextToggleClickThrough), keyEquivalent: "")
        through.target = self
        through.state = clickThrough ? .on : .off
        menu.addItem(through)

        menu.addItem(.separator())

        let scaleItem = NSMenuItem(title: "画中画缩放", action: nil, keyEquivalent: "")
        let sm = NSMenu()
        sm.autoenablesItems = false
        let scales: [(String, CGFloat)] = [("100%（原尺寸）", 1.0), ("75%", 0.75), ("50%", 0.5), ("33%", 0.33), ("25%", 0.25)]
        for (label, val) in scales {
            let si = NSMenuItem(title: label, action: #selector(contextSetScale(_:)), keyEquivalent: "")
            si.target = self
            si.representedObject = NSNumber(value: Double(val))
            si.state = abs(scale - val) < 0.03 ? .on : .off
            sm.addItem(si)
        }
        scaleItem.submenu = sm
        menu.addItem(scaleItem)

        let opItem = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        let om = NSMenu()
        om.autoenablesItems = false
        for v in [1.0, 0.9, 0.8, 0.7, 0.5, 0.3] {
            let oi = NSMenuItem(title: "\(Int(v * 100))%", action: #selector(contextSetOpacity(_:)), keyEquivalent: "")
            oi.target = self
            oi.representedObject = NSNumber(value: v)
            oi.state = abs(opacity - v) < 0.02 ? .on : .off
            om.addItem(oi)
        }
        opItem.submenu = om
        menu.addItem(opItem)

        if customOrigin != nil || scale < 0.99 {
            let reset = NSMenuItem(title: "恢复默认位置与尺寸", action: #selector(contextReset), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }

        menu.addItem(.separator())
        let unpin = NSMenuItem(title: "取消置顶", action: #selector(contextUnpin), keyEquivalent: "")
        unpin.target = self
        menu.addItem(unpin)

        return menu
    }

    @objc private func contextFocus() { bringRealWindowToFront() }
    @objc private func contextToggleAlwaysFloat() { alwaysFloat.toggle(); PinManager.shared.tick() }
    @objc private func contextToggleClickThrough() { clickThrough.toggle() }
    @objc private func contextSetScale(_ sender: NSMenuItem) {
        if let num = sender.representedObject as? NSNumber { scale = CGFloat(num.doubleValue) }
    }
    @objc private func contextSetOpacity(_ sender: NSMenuItem) {
        if let num = sender.representedObject as? NSNumber { opacity = num.doubleValue }
    }
    @objc private func contextReset() { resetPositionAndScale() }
    @objc private func contextUnpin() { PinManager.shared.unpin(self) }
}
