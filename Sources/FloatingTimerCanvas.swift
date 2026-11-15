import AppKit

/// Transparent, draggable timer surface. A click opens the controls; a drag moves the panel.
final class FloatingTimerCanvas: NSView {
    var clockText = "00:00" { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 32 { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onMove: ((NSPoint) -> Void)?
    var onRightClick: ((FloatingTimerCanvas) -> Void)?

    private var mouseDownScreenPoint: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var didDrag = false

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .shadow: shadow
        ]
        let size = (clockText as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2,
                             y: (bounds.height - size.height) / 2)
        (clockText as NSString).draw(at: origin, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreenPoint = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownScreenPoint, let origin = windowOriginAtMouseDown,
              let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        if abs(dx) > 3 || abs(dy) > 3 { didDrag = true }
        guard didDrag else { return }
        let proposed = NSPoint(x: origin.x + dx, y: origin.y + dy)
        let screen = NSScreen.screens.first { $0.frame.contains(current) } ?? window.screen
        if let frame = screen?.frame {
            let maxX = max(frame.minX, frame.maxX - window.frame.width)
            let maxY = max(frame.minY, frame.maxY - window.frame.height)
            window.setFrameOrigin(NSPoint(x: min(max(proposed.x, frame.minX), maxX),
                                          y: min(max(proposed.y, frame.minY), maxY)))
        } else {
            window.setFrameOrigin(proposed)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag, let window {
            onMove?(NSPoint(x: window.frame.midX, y: window.frame.midY))
        } else {
            onClick?()
        }
        mouseDownScreenPoint = nil
        windowOriginAtMouseDown = nil
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(self)
    }
}
