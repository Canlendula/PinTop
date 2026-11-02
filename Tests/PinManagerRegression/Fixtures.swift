import AppKit

// Window snapshots and manually completed capture operations isolate the real PinManager.
enum WindowList {
    static var snapshot: [WindowInfo] = []
    static func onScreen() -> [WindowInfo] { snapshot }
    static func window(_ id: CGWindowID) -> WindowInfo? { snapshot.first { $0.id == id } }
    static func frontmostWindow() -> WindowInfo? { snapshot.first }
}

struct TestSCWindow { let windowID: CGWindowID }

struct SCShareableContent {
    let windows: [TestSCWindow]
    static var paused = false
    static var requests: [CheckedContinuation<SCShareableContent, Error>] = []
    static var requestCount = 0
    static let content = SCShareableContent(windows: [100, 200].map { TestSCWindow(windowID: $0) })

    @MainActor static func excludingDesktopWindows(_ exclude: Bool, onScreenWindowsOnly: Bool) async throws -> SCShareableContent {
        requestCount += 1
        if paused {
            // Deliberately ignore Task cancellation, as a capture API may complete afterwards.
            return try await withCheckedThrowingContinuation { requests.append($0) }
        }
        return content
    }
}

enum Permissions {
    static let hasScreenRecording = true
    static func requestScreenRecording() {}
}

enum Toast {
    static var messages: [String] = []
    static func show(_ text: String, symbol: String) { messages.append(text) }
}

struct TestPanel { func orderFrontRegardless() {} }

final class PinnedWindow {
    static var paused = false
    static var starts: [(PinnedWindow, CheckedContinuation<Void, Never>)] = []
    static var created: [PinnedWindow] = []

    let windowID: CGWindowID
    let pid: pid_t
    var bounds: CGRect
    var title: String
    var displayName: String { title }
    var opacity = 1.0
    var clickThrough = false
    var alwaysFloat: Bool
    var isOverlayVisible = false
    var capturing = false
    var stopped = false
    let panel = TestPanel()
    var onStreamStopped: ((PinnedWindow, Error?) -> Void)?
    var onActivated: ((PinnedWindow) -> Void)?

    init(info: WindowInfo) {
        windowID = info.id
        pid = info.pid
        bounds = info.bounds
        title = info.title
        alwaysFloat = Settings.shared.alwaysFloatByDefault
        Self.created.append(self)
    }

    @MainActor func start(window: TestSCWindow) async throws {
        if Self.paused {
            await withCheckedContinuation { Self.starts.append((self, $0)) }
        }
        capturing = true
    }

    func stop() { stopped = true; capturing = false; isOverlayVisible = false }
    func applySettings() {}
    func applyFrameRate() {}
    func updateBounds(_ newBounds: CGRect) { bounds = newBounds }
    func updateTitle(_ title: String) { self.title = title }
    func setOverlayVisible(_ visible: Bool) { isOverlayVisible = visible }
}
