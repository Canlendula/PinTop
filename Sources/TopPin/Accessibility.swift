import AppKit
import ApplicationServices

/// Private but long-stable HIServices SPI that maps an AXUIElement window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt asking the user to grant Accessibility access.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func windowElement(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for w in windows {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(w, &id) == .success, id == windowID { return w }
        }
        return nil
    }

    /// Brings a specific window of another application to the front and activates that app.
    @discardableResult
    static func raise(pid: pid_t, windowID: CGWindowID) -> Bool {
        var ok = false
        if let w = windowElement(pid: pid, windowID: windowID) {
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            ok = AXUIElementPerformAction(w, kAXRaiseAction as CFString) == .success
        }
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
        return ok
    }
}
