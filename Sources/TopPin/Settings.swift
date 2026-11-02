import Foundation

/// Persistent user preferences.
final class Settings {
    static let shared = Settings()

    private let d = UserDefaults.standard

    private enum Key {
        static let hideFromCapture = "hideFromCapture"
        static let passSyntheticClicks = "passSyntheticClicks"
        static let forwardScroll = "forwardScroll"
        static let frameRate = "frameRate"
        static let defaultOpacity = "defaultOpacity"
        static let showBorder = "showBorder"
        static let alwaysFloatByDefault = "alwaysFloatByDefault"
    }

    private init() {
        d.register(defaults: [
            Key.hideFromCapture: true,
            Key.passSyntheticClicks: true,
            Key.forwardScroll: true,
            Key.frameRate: 30,
            Key.defaultOpacity: 1.0,
            Key.showBorder: false,
            Key.alwaysFloatByDefault: false,
        ])
    }

    /// Exclude the pinned overlays from screenshots / screen recordings (so Computer Use
    /// agents "see" the real screen underneath instead of the pinned copy).
    var hideFromCapture: Bool {
        get { d.bool(forKey: Key.hideFromCapture) }
        set { d.set(newValue, forKey: Key.hideFromCapture); notify() }
    }

    /// Programmatically generated clicks (e.g. by Computer Use / automation tools) pass
    /// through the pinned overlay to whatever window is underneath.
    var passSyntheticClicks: Bool {
        get { d.bool(forKey: Key.passSyntheticClicks) }
        set { d.set(newValue, forKey: Key.passSyntheticClicks); notify() }
    }

    /// Scrolling over a pinned overlay scrolls the real (covered) window without raising it.
    var forwardScroll: Bool {
        get { d.bool(forKey: Key.forwardScroll) }
        set { d.set(newValue, forKey: Key.forwardScroll); notify() }
    }

    var frameRate: Int {
        get { max(5, min(120, d.integer(forKey: Key.frameRate))) }
        set { d.set(newValue, forKey: Key.frameRate); notify() }
    }

    var defaultOpacity: Double {
        get { max(0.2, min(1, d.double(forKey: Key.defaultOpacity))) }
        set { d.set(newValue, forKey: Key.defaultOpacity); notify() }
    }

    /// Draw a thin accent border around pinned overlays.
    var showBorder: Bool {
        get { d.bool(forKey: Key.showBorder) }
        set { d.set(newValue, forKey: Key.showBorder); notify() }
    }

    /// When true, pinned windows always float on top, even if not occluded by another window.
    var alwaysFloatByDefault: Bool {
        get { d.bool(forKey: Key.alwaysFloatByDefault) }
        set { d.set(newValue, forKey: Key.alwaysFloatByDefault); notify() }
    }

    static let didChange = Notification.Name("TopPinSettingsDidChange")

    private func notify() {
        NotificationCenter.default.post(name: Settings.didChange, object: self)
    }
}
