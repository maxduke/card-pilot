import Foundation
import Observation

/// One business date and zone for all date-sensitive presentation.
struct CurrentDay: Equatable, Sendable {
    let today: LocalDate
    let timeZone: TimeZone

    init(now: Date, timeZone: TimeZone) {
        today = LocalDate(date: now, timeZone: timeZone)
        self.timeZone = timeZone
    }
}

@MainActor
@Observable
final class DayClock {
    private(set) var day: CurrentDay

    init(now: Date = .now, timeZone: TimeZone) {
        day = CurrentDay(now: now, timeZone: timeZone)
    }

    func refresh(now: Date = .now, timeZone: TimeZone) {
        let updated = CurrentDay(now: now, timeZone: timeZone)
        if day != updated { day = updated }
    }

    /// Calendar boundaries handle short/long DST days and zones whose day starts after midnight.
    static func nextRefresh(after now: Date, timeZone: TimeZone) -> Date {
        LocalDate.calendar(timeZone: timeZone).dateInterval(of: .day, for: now)!.end
    }

    /// Owned by the active scene's task. Cancellation prevents an old zone's wakeup from publishing.
    func run(
        timeZone: TimeZone,
        now: () -> Date = { .now },
        sleep: (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) async {
        while !Task.isCancelled {
            let instant = now()
            refresh(now: instant, timeZone: timeZone)
            let delay = Self.nextRefresh(after: instant, timeZone: timeZone).timeIntervalSince(instant)
            do { try await sleep(max(delay, 0.01)) }
            catch { return }
        }
    }
}
