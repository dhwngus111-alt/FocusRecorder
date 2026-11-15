import Foundation

@main
struct CoreTests {
    static func main() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let running = ActiveSession(startedAt: start, targetSeconds: 1500,
                                    elapsedBeforePause: 0, resumedAt: start)
        assert(running.elapsed(at: start) == 0)
        assert(running.elapsed(at: start.addingTimeInterval(61.9)) == 61)
        assert(!running.record(at: start.addingTimeInterval(1499)).succeeded)
        assert(running.record(at: start.addingTimeInterval(1500)).succeeded)
        assert(running.record(at: start.addingTimeInterval(1505)).actualSeconds == 1500)

        let paused = ActiveSession(startedAt: start, targetSeconds: 1500,
                                   elapsedBeforePause: 300, resumedAt: nil)
        assert(paused.elapsed(at: start.addingTimeInterval(5000)) == 300)

        let calendar = Calendar(identifier: .gregorian)
        let a = FocusRecord(startedAt: start, endedAt: start.addingTimeInterval(600),
                            targetSeconds: 1500, actualSeconds: 600, succeeded: false)
        let b = FocusRecord(startedAt: start.addingTimeInterval(3600),
                            endedAt: start.addingTimeInterval(5400),
                            targetSeconds: 1800, actualSeconds: 1800, succeeded: true)
        let nextDay = start.addingTimeInterval(86_400)
        let c = FocusRecord(startedAt: nextDay, endedAt: nextDay.addingTimeInterval(900),
                            targetSeconds: 1800, actualSeconds: 900, succeeded: false)
        assert(FocusStatistics.average(on: start, from: [a, b, c], calendar: calendar) == 1200)
        assert(FocusStatistics.records(on: start, from: [a, b, c], calendar: calendar).count == 2)
        assert(FocusStatistics.average(on: start.addingTimeInterval(-86_400),
                                       from: [a, b, c], calendar: calendar) == nil)
        var mondayCalendar = Calendar(identifier: .gregorian)
        mondayCalendar.firstWeekday = 2
        mondayCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = mondayCalendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        let nextMonday = monday.addingTimeInterval(7 * 86_400)
        let thisWeek = FocusRecord(startedAt: monday, endedAt: monday.addingTimeInterval(600),
                                   targetSeconds: 900, actualSeconds: 600, succeeded: false)
        let anotherWeek = FocusRecord(startedAt: nextMonday,
                                      endedAt: nextMonday.addingTimeInterval(1800),
                                      targetSeconds: 1800, actualSeconds: 1800, succeeded: true)
        assert(FocusStatistics.weekAverage(containing: monday, from: [thisWeek, anotherWeek],
                                           calendar: mondayCalendar) == 600)
        assert(TimeText.clock(0) == "00:00")
        assert(TimeText.clock(3661) == "01:01:01")
        print("Core tests passed")
    }
}
