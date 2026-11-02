import AppKit

setbuf(stdout, nil)
var passed = 0
var failed = 0
let manager = PinManager.shared

func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    if condition() { passed += 1; print("PASS \(name)") }
    else { failed += 1; print("FAIL \(name)") }
}

func finish() -> Never {
    manager.unpinAll()
    UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
    print("RESULT passed=\(passed) failed=\(failed)")
    exit(failed == 0 ? 0 : 1)
}

func window(_ id: UInt32 = 100, pid: Int32 = 90001, x: CGFloat = 100, layer: Int = 0, alpha: Double = 1) -> WindowInfo {
    WindowInfo([
        kCGWindowNumber as String: id,
        kCGWindowOwnerPID as String: pid,
        kCGWindowName as String: "Window \(id)",
        kCGWindowBounds as String: CGRect(x: x, y: 100, width: 600, height: 400).dictionaryRepresentation,
        kCGWindowLayer as String: layer,
        kCGWindowAlpha as String: alpha,
        kCGWindowIsOnscreen as String: true,
    ])!
}

@MainActor func nextTurn() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

@MainActor func pin(_ info: WindowInfo = window()) async -> PinnedWindow {
    await withCheckedContinuation { continuation in
        manager.onChange = {
            manager.onChange = nil
            continuation.resume()
        }
        manager.pin(info)
    }
    return manager.pin(for: info.id)!
}

func reset() {
    manager.unpinAll()
    WindowList.snapshot = [window(), window(200, x: 1000)]
    Settings.shared.alwaysFloatByDefault = false
    SCShareableContent.paused = false
    SCShareableContent.requestCount = 0
    PinnedWindow.paused = false
    PinnedWindow.created.removeAll()
    Toast.messages.removeAll()
}

Task { @MainActor in
    reset()
    let p = await pin()
    WindowList.snapshot = [window()]
    manager.tick()
    expect(!p.isOverlayVisible, "uncovered window uses its real window")
    WindowList.snapshot = [window(101), window()]
    manager.tick()
    expect(p.isOverlayVisible, "same-app normal window triggers the overlay")
    WindowList.snapshot = [window(101, pid: 90002), window()]
    manager.tick()
    expect(p.isOverlayVisible, "other-app normal window still triggers the overlay")
    WindowList.snapshot = [window(101, x: 1000), window()]
    manager.tick()
    expect(!p.isOverlayVisible, "non-overlapping same-app window is ignored")
    WindowList.snapshot = [window(101, pid: ProcessInfo.processInfo.processIdentifier), window()]
    manager.tick()
    expect(!p.isOverlayVisible, "TopPin's own windows are ignored")
    WindowList.snapshot = [window(101, alpha: 0), window()]
    manager.tick()
    expect(!p.isOverlayVisible, "invisible windows are ignored")
    WindowList.snapshot = [window(101, layer: 3), window()]
    manager.tick()
    expect(!p.isOverlayVisible, "non-normal window layers are ignored")

    WindowList.snapshot = [window(), window(200, x: 1000)]
    Settings.shared.alwaysFloatByDefault = true
    expect(!p.alwaysFloat && !p.isOverlayVisible, "changing the default preserves existing smart-mode pins")
    let newPin = await pin(window(200, x: 1000))
    expect(newPin.alwaysFloat && newPin.isOverlayVisible, "new pins use the enabled floating default")
    newPin.alwaysFloat = false
    manager.tick()
    expect(!newPin.isOverlayVisible, "per-window floating can be disabled while the default is enabled")
    newPin.alwaysFloat = true
    Settings.shared.alwaysFloatByDefault = false
    expect(newPin.alwaysFloat && newPin.isOverlayVisible, "changing the default preserves existing floating pins")
    p.alwaysFloat = false
    WindowList.snapshot = [window(101), window(), window(200)]
    manager.tick()
    expect(p.isOverlayVisible, "disabling always-float preserves smart occlusion mode")

    reset()
    SCShareableContent.paused = true
    manager.pin(window())
    await nextTurn()
    let enumeration = SCShareableContent.requests.removeFirst()
    manager.unpinAll()
    enumeration.resume(returning: SCShareableContent.content)
    await nextTurn()
    expect(manager.pins.isEmpty, "cancel during enumeration prevents a late pin")
    expect(PinnedWindow.created.isEmpty, "cancelled enumeration never starts capture")
    expect(Toast.messages.isEmpty, "cancelled enumeration produces no success or failure toast")

    reset()
    PinnedWindow.paused = true
    manager.pin(window())
    await nextTurn()
    let (startingPin, start) = PinnedWindow.starts.removeFirst()
    manager.unpinAll()
    start.resume()
    await nextTurn()
    expect(manager.pins.isEmpty, "cancel during capture startup prevents a late pin")
    expect(startingPin.stopped && !startingPin.capturing, "late capture startup is stopped")
    expect(Toast.messages.isEmpty, "cancelled startup produces no success or failure toast")

    reset()
    SCShareableContent.paused = true
    manager.pin(window())
    await nextTurn()
    let oldRequest = SCShareableContent.requests.removeFirst()
    manager.unpinAll()
    manager.pin(window())
    await nextTurn()
    expect(SCShareableContent.requests.count == 1, "immediate repin starts a replacement request")
    if SCShareableContent.requests.isEmpty {
        oldRequest.resume(returning: SCShareableContent.content)
        await nextTurn()
        finish()
    }
    let newRequest = SCShareableContent.requests.removeFirst()
    oldRequest.resume(returning: SCShareableContent.content)
    await nextTurn()
    expect(manager.pins.isEmpty, "old cancelled request cannot replace a new pending request")
    manager.pin(window())
    await nextTurn()
    expect(SCShareableContent.requestCount == 2, "old cleanup preserves the new request's duplicate protection")
    newRequest.resume(returning: SCShareableContent.content)
    await nextTurn()
    expect(manager.pins.count == 1, "immediate repin succeeds exactly once")
    while !SCShareableContent.requests.isEmpty {
        SCShareableContent.requests.removeFirst().resume(returning: SCShareableContent.content)
    }
    await nextTurn()

    reset()
    SCShareableContent.paused = true
    manager.pin(window())
    await nextTurn()
    let lateRequest = SCShareableContent.requests.removeFirst()
    manager.unpinAll()
    manager.pin(window())
    await nextTurn()
    SCShareableContent.requests.removeFirst().resume(returning: SCShareableContent.content)
    await nextTurn()
    let replacement = manager.pin(for: 100)!
    lateRequest.resume(returning: SCShareableContent.content)
    await nextTurn()
    expect(manager.pins.count == 1 && manager.pin(for: 100) === replacement, "new pin survives old request completing afterwards")

    reset()
    SCShareableContent.paused = true
    manager.pin(window())
    await nextTurn()
    let cancelledFailure = SCShareableContent.requests.removeFirst()
    manager.unpinAll()
    cancelledFailure.resume(throwing: NSError(domain: "TestCapture", code: 1))
    await nextTurn()
    expect(manager.pins.isEmpty && Toast.messages.isEmpty, "cancelled capture failure stays cancelled")

    manager.pin(window())
    await nextTurn()
    SCShareableContent.requests.removeFirst().resume(throwing: NSError(domain: "TestCapture", code: 2))
    await nextTurn()
    expect(manager.pins.isEmpty && Toast.messages.count == 1, "uncancelled capture failure is still reported")
    SCShareableContent.paused = false
    let retried = await pin()
    expect(manager.pins.count == 1, "failed initialization releases the pending request for retry")
    manager.unpinAll()
    expect(manager.pins.isEmpty && retried.stopped, "unpin-all still stops active captures")

    finish()
}
RunLoop.main.run()
