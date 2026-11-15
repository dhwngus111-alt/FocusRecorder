import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = FocusStore()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var historyWindow: NSWindow?
    private var timerWindow: NSWindow?
    private var overlayPanel: NSPanel?
    private var tickTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 300, height: 330)
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
        store.stop()
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
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
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
        let font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(store.menuFontSize), weight: .semibold)
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
        if overlayPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            let view = NSHostingView(rootView:
                FloatingTimerView(store: store, onClick: { [weak self] in self?.showTimerWindow() }))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = view
            panel.setFrame(NSRect(x: 0, y: 0, width: 200, height: 100), display: true)
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: frame.midX - 100, y: frame.maxY - 75))
            }
            overlayPanel = panel
        }
        let width = max(110, CGFloat(store.overlayFontSize) * CGFloat(TimeText.clock(store.elapsed).count) * 0.7 + 20)
        let height = CGFloat(store.overlayFontSize) + 24
        if let panel = overlayPanel {
            var frame = panel.frame
            frame.size = NSSize(width: width, height: height)
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
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
