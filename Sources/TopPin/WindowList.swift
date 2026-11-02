import AppKit
import CoreGraphics

/// A lightweight snapshot of a window as reported by the window server (CGWindowList).
struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let ownerName: String
    let title: String
    /// Bounds in global CoreGraphics coordinates (origin = top-left of the primary display).
    let bounds: CGRect
    let layer: Int
    let alpha: Double
    let isOnScreen: Bool

    init?(_ d: [String: Any]) {
        guard let num = d[kCGWindowNumber as String] as? NSNumber,
              let pidNum = d[kCGWindowOwnerPID as String] as? NSNumber,
              let boundsDict = d[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { return nil }
        id = CGWindowID(num.uint32Value)
        pid = pid_t(pidNum.int32Value)
        ownerName = d[kCGWindowOwnerName as String] as? String ?? ""
        title = d[kCGWindowName as String] as? String ?? ""
        self.bounds = bounds
        layer = (d[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        alpha = (d[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        isOnScreen = (d[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
    }

    var displayName: String {
        if title.isEmpty { return ownerName }
        if ownerName.isEmpty { return title }
        return "\(ownerName) — \(title)"
    }

    /// Heuristic: is this a "normal" application window a user might want to pin?
    var isPinCandidate: Bool {
        layer == 0 && alpha > 0.01 && bounds.width >= 60 && bounds.height >= 40
            && pid != ProcessInfo.processInfo.processIdentifier
    }
}

enum WindowList {
    /// All on-screen windows, ordered front-to-back.
    static func onScreen() -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap(WindowInfo.init)
    }

    /// Info about a single window (on-screen or not). `nil` if the window no longer exists.
    static func window(_ id: CGWindowID) -> WindowInfo? {
        guard let raw = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] else { return nil }
        return raw.compactMap(WindowInfo.init).first { $0.id == id }
    }

    /// The front-most normal window of the front-most application (excluding ourselves).
    static func frontmostWindow() -> WindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            // When our own menu is open we may be frontmost: fall back to the top-most candidate.
            return onScreen().first { $0.isPinCandidate }
        }
        let pid = app.processIdentifier
        return onScreen().first { $0.pid == pid && $0.isPinCandidate }
    }

    /// Windows that can be pinned, front-to-back.
    static func pinCandidates() -> [WindowInfo] {
        onScreen().filter { $0.isPinCandidate }
    }
}

enum Geometry {
    /// Height of the primary display (the one whose Cocoa origin is 0,0).
    static var primaryHeight: CGFloat {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        return primary?.frame.height ?? 0
    }

    /// Converts a CoreGraphics global rect (top-left origin) into a Cocoa screen rect (bottom-left origin).
    static func cocoaRect(fromCG r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
