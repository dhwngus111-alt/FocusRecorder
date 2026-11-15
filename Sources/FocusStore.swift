import AppKit
import Foundation

private struct SavedState: Codable {
    var records: [FocusRecord]
    var active: ActiveSession?
    var overlayVisible: Bool
    var overlayFontSize: Double
    var alwaysOnTop: Bool?
    var overlayPosition: OverlayPosition?
}

struct OverlayPosition: Codable, Equatable {
    var centerX: Double
    var centerY: Double
}

@MainActor
final class FocusStore: ObservableObject {
    @Published private(set) var records: [FocusRecord] = []
    @Published private(set) var active: ActiveSession?
    @Published private(set) var now = Date()
    @Published var overlayVisible = true { didSet { save() } }
    @Published var overlayFontSize = 32.0 { didSet { save() } }
    @Published var alwaysOnTop = true { didSet { save() } }
    private(set) var overlayPosition: OverlayPosition? { didSet { save() } }

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusRecorder", isDirectory: true)
        fileURL = support.appendingPathComponent("sessions.json")
        load()
        recoverSession()
    }

    var elapsed: Int { active?.elapsed(at: now) ?? 0 }
    var target: Int { active?.targetSeconds ?? 0 }
    var isRunning: Bool { active?.resumedAt != nil }

    func moveOverlay(center: NSPoint) {
        overlayPosition = OverlayPosition(centerX: Double(center.x), centerY: Double(center.y))
    }

    func tick() {
        now = Date()
        if let session = active, session.elapsed(at: now) >= session.targetSeconds {
            finish(at: now)
        }
    }

    func start(minutes: Int) {
        guard (1...1440).contains(minutes), active == nil else { return }
        let date = Date()
        now = date
        active = ActiveSession(startedAt: date, targetSeconds: minutes * 60,
                               elapsedBeforePause: 0, resumedAt: date)
        save()
    }

    func pauseOrResume() {
        guard var session = active else { return }
        let date = Date()
        if let resumedAt = session.resumedAt {
            session.elapsedBeforePause += max(0, date.timeIntervalSince(resumedAt))
            session.resumedAt = nil
        } else {
            session.resumedAt = date
        }
        active = session
        now = date
        save()
    }

    func stop() {
        guard active != nil else { return }
        finish(at: Date())
    }

    private func finish(at date: Date) {
        guard let session = active else { return }
        let record = session.record(at: date)
        records.append(record)
        active = nil
        now = date
        save()
    }

    private func recoverSession() {
        guard let session = active else { return }
        // After an unexpected exit, retain only the time observed by the last save.
        // A normally running session is checkpointed once each second.
        let date = Date()
        let elapsed = min(session.targetSeconds, Int(session.elapsedBeforePause))
        records.append(FocusRecord(startedAt: session.startedAt, endedAt: date,
                                   targetSeconds: session.targetSeconds, actualSeconds: elapsed,
                                   succeeded: elapsed >= session.targetSeconds))
        active = nil
        save()
    }

    func checkpoint() {
        guard var session = active, let resumedAt = session.resumedAt else { return }
        let date = Date()
        session.elapsedBeforePause += max(0, date.timeIntervalSince(resumedAt))
        session.resumedAt = date
        active = session
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        records = state.records
        active = state.active
        overlayVisible = state.overlayVisible
        overlayFontSize = state.overlayFontSize
        alwaysOnTop = state.alwaysOnTop ?? true
        overlayPosition = state.overlayPosition
    }

    private func save() {
        let state = SavedState(records: records, active: active,
                               overlayVisible: overlayVisible, overlayFontSize: overlayFontSize,
                               alwaysOnTop: alwaysOnTop, overlayPosition: overlayPosition)
        guard let data = try? JSONEncoder().encode(state) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("FocusRecorder could not save records: %@", error.localizedDescription)
        }
    }
}
