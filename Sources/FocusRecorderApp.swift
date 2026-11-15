import AppKit
import Combine
import Darwin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private lazy var store = FocusStore()
    private var lockFD: Int32 = -1
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var historyWindow: NSWindow?
    private var timerWindow: NSWindow?
    private var overlayPanel: NSPanel?
    private var overlayCanvas: FloatingTimerCanvas?
    private var tickTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireInstanceLock() else {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.focusrecorder.mac")
                .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                .activate()
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = makeAppIcon()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 300, height: 390)
        popover.contentViewController = NSHostingController(rootView:
            TimerPopoverView(store: store, openHistory: { [weak self] in self?.showHistory() }))

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.refreshDisplay() }
            }
            .store(in: &subscriptions)

        refreshDisplay()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.store.tick()
                self?.store.checkpoint()
            }
        }
        if let tickTimer { RunLoop.main.add(tickTimer, forMode: .common) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard lockFD >= 0 else { return }
        store.stop()
        Darwin.close(lockFD)
        lockFD = -1
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showTimerWindow()
        return true
    }

    @objc private func statusClicked() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(at: button)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu(at button: NSStatusBarButton) {
        contextMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        if store.active != nil {
            menu.addItem(withTitle: store.isRunning ? "일시정지" : "계속하기",
                         action: #selector(togglePause), keyEquivalent: "")
            menu.addItem(withTitle: "집중 종료", action: #selector(stop), keyEquivalent: "")
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "집중 기록 및 설정", action: #selector(showHistoryAction), keyEquivalent: "")
        menu.addItem(withTitle: store.overlayVisible ? "화면 타이머 숨기기" : "화면 타이머 표시",
                     action: #selector(toggleOverlay), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func togglePause() { store.pauseOrResume() }
    @objc private func stop() { store.stop() }
    @objc private func toggleOverlay() { store.overlayVisible.toggle() }
    @objc private func showHistoryAction() { showHistory() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func showHistory() {
        popover.performClose(nil)
        if historyWindow == nil {
            let controller = NSHostingController(rootView: HistoryView(store: store))
            let window = NSWindow(contentViewController: controller)
            window.title = "집중 기록 및 설정"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 700))
            window.center()
            window.isReleasedWhenClosed = false
            historyWindow = window
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showTimerWindow() {
        if timerWindow == nil {
            let controller = NSHostingController(rootView:
                TimerPopoverView(store: store, openHistory: { [weak self] in self?.showHistory() }))
            let window = NSWindow(contentViewController: controller)
            window.title = "집중 타이머"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 320, height: 350))
            window.center()
            window.isReleasedWhenClosed = false
            timerWindow = window
        }
        timerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshDisplay() {
        guard let button = statusItem?.button else { return }
        let title = TimeText.clock(store.elapsed)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: NSColor.white
        ])
        button.toolTip = store.active == nil
            ? "집중 타이머: 클릭하여 시간 설정"
            : "집중 \(title) / 목표 \(TimeText.clock(store.target))"
        updateOverlay()
    }

    private func updateOverlay() {
        if !store.overlayVisible {
            overlayPanel?.orderOut(nil)
            return
        }
        let title = TimeText.clock(store.elapsed)
        let pointSize = CGFloat(store.overlayFontSize)
        let width = max(80, pointSize * CGFloat(title.count) * 0.7 + 20)
        let height = pointSize + 24
        if overlayPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = false
            panel.hidesOnDeactivate = false
            let canvas = FloatingTimerCanvas(frame: NSRect(x: 0, y: 0, width: width, height: height))
            canvas.autoresizingMask = [.width, .height]
            canvas.onClick = { [weak self] in self?.showTimerWindow() }
            canvas.onMove = { [weak self] center in self?.store.moveOverlay(center: center) }
            canvas.onRightClick = { [weak self] view in
                self?.contextMenu().popUp(positioning: nil,
                                          at: NSPoint(x: view.bounds.midX, y: view.bounds.midY), in: view)
            }
            panel.contentView = canvas
            overlayCanvas = canvas
            overlayPanel = panel
        }
        if let panel = overlayPanel {
            let previousLevel = panel.level
            panel.level = store.alwaysOnTop ? .floating : .normal
            let center: NSPoint
            if panel.isVisible {
                center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            } else {
                center = initialOverlayCenter()
            }
            panel.setFrame(NSRect(x: center.x - width / 2, y: center.y - height / 2,
                                  width: width, height: height), display: true)
            overlayCanvas?.clockText = title
            overlayCanvas?.fontSize = pointSize
            if !panel.isVisible || (store.alwaysOnTop && previousLevel != .floating) {
                if store.alwaysOnTop { panel.orderFrontRegardless() }
                else { panel.orderFront(nil) }
            }
        }
    }

    private func initialOverlayCenter() -> NSPoint {
        if let saved = store.overlayPosition {
            let point = NSPoint(x: saved.centerX, y: saved.centerY)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(point) }) { return point }
        }
        guard let frame = NSScreen.main?.visibleFrame else { return NSPoint(x: 500, y: 700) }
        return NSPoint(x: frame.midX, y: frame.maxY - 45)
    }

    private func acquireInstanceLock() -> Bool {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusRecorder", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch { return false }
        let fd = Darwin.open(folder.appendingPathComponent("instance.lock").path,
                             O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return false }
        guard Darwin.lockf(fd, F_TLOCK, 0) == 0 else {
            Darwin.close(fd)
            return false
        }
        lockFD = fd
        return true
    }

    private func makeAppIcon() -> NSImage {
        let icon = NSImage(size: NSSize(width: 128, height: 128))
        icon.lockFocus()
        let background = NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 112, height: 112),
                                      xRadius: 28, yRadius: 28)
        NSGradient(starting: NSColor(red: 0.14, green: 0.43, blue: 0.94, alpha: 1),
                   ending: NSColor(red: 0.08, green: 0.15, blue: 0.42, alpha: 1))?
            .draw(in: background, angle: -60)
        let ring = NSBezierPath(ovalIn: NSRect(x: 27, y: 27, width: 74, height: 74))
        ring.lineWidth = 7
        NSColor.white.setStroke()
        ring.stroke()
        let hand = NSBezierPath()
        hand.lineWidth = 6
        hand.lineCapStyle = .round
        hand.move(to: NSPoint(x: 64, y: 64))
        hand.line(to: NSPoint(x: 64, y: 88))
        hand.move(to: NSPoint(x: 64, y: 64))
        hand.line(to: NSPoint(x: 80, y: 55))
        hand.stroke()
        icon.unlockFocus()
        return icon
    }
}

@main
struct FocusRecorderApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
