import Foundation

struct FocusRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var targetSeconds: Int
    var actualSeconds: Int
    var succeeded: Bool

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date, targetSeconds: Int, actualSeconds: Int, succeeded: Bool) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.targetSeconds = targetSeconds
        self.actualSeconds = actualSeconds
        self.succeeded = succeeded
    }
}

struct ActiveSession: Codable {
    var startedAt: Date
    var targetSeconds: Int
    var elapsedBeforePause: TimeInterval
    var resumedAt: Date?

    func elapsed(at date: Date) -> Int {
        let running = resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return max(0, Int(elapsedBeforePause + running))
    }

    func record(at date: Date) -> FocusRecord {
        let actual = min(targetSeconds, elapsed(at: date))
        return FocusRecord(startedAt: startedAt, endedAt: date, targetSeconds: targetSeconds,
                           actualSeconds: actual, succeeded: actual >= targetSeconds)
    }
}

enum FocusStatistics {
    static func records(on day: Date, from records: [FocusRecord], calendar: Calendar = .current) -> [FocusRecord] {
        records.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func average(on day: Date, from records: [FocusRecord], calendar: Calendar = .current) -> Int? {
        average(Self.records(on: day, from: records, calendar: calendar))
    }

    static func weekAverage(containing date: Date, from records: [FocusRecord], calendar: Calendar = .current) -> Int? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        return average(records.filter { week.contains($0.startedAt) })
    }

    private static func average(_ records: [FocusRecord]) -> Int? {
        guard !records.isEmpty else { return nil }
        return Int((Double(records.reduce(0) { $0 + $1.actualSeconds }) / Double(records.count)).rounded())
    }
}

enum TimeText {
    static func clock(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let remaining = safe % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, remaining)
            : String(format: "%02d:%02d", minutes, remaining)
    }

    static func duration(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        if safe == 0 { return "0초" }
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let remainder = safe % 60
        return [hours > 0 ? "\(hours)시간" : nil,
                minutes > 0 ? "\(minutes)분" : nil,
                remainder > 0 ? "\(remainder)초" : nil]
            .compactMap { $0 }.joined(separator: " ")
    }
}
