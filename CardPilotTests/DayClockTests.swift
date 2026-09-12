import Observation
import XCTest
@testable import CardPilot

@MainActor
final class DayClockTests: XCTestCase {
    private func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testHomeMidnightAcrossZonesAndYearBoundary() {
        for identifier in ["Asia/Shanghai", "Asia/Hong_Kong", "America/Los_Angeles", "Asia/Kathmandu", "Pacific/Kiritimati"] {
            let zone = TimeZone(identifier: identifier)!
            let midnight = try! LocalDate(rawValue: 20270101).date(in: zone)
            let clock = DayClock(now: midnight.addingTimeInterval(-1), timeZone: zone)
            XCTAssertEqual(clock.day.today.rawValue, 20261231, identifier)
            XCTAssertEqual(DayClock.nextRefresh(after: midnight.addingTimeInterval(-1), timeZone: zone), midnight)
            clock.refresh(now: midnight, timeZone: zone)
            XCTAssertEqual(clock.day.today.rawValue, 20270101, identifier)
        }
    }

    func testNextBoundaryUsesCalendarAcrossDSTAndSkippedMidnight() {
        let newYork = TimeZone(identifier: "America/New_York")!
        for (date, hours) in [(20260308, 23.0), (20261101, 25.0)] {
            let start = try! LocalDate(rawValue: date).date(in: newYork)
            XCTAssertEqual(DayClock.nextRefresh(after: start, timeZone: newYork).timeIntervalSince(start), hours * 3600)
        }
        let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
        let before = instant("2018-11-04T02:59:59Z")
        let boundary = DayClock.nextRefresh(after: before, timeZone: saoPaulo)
        XCTAssertEqual(boundary, instant("2018-11-04T03:00:00Z"))
        XCTAssertEqual(LocalDate(date: boundary, timeZone: saoPaulo).rawValue, 20181104)
        XCTAssertGreaterThan(DayClock.nextRefresh(after: boundary, timeZone: saoPaulo), boundary)
    }

    func testForegroundRefreshCatchesUpMultipleDaysAndClockMovingBackward() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let clock = DayClock(now: instant("2026-09-30T15:59:59Z"), timeZone: zone)
        clock.refresh(now: instant("2026-10-04T16:00:00Z"), timeZone: zone)
        XCTAssertEqual(clock.day.today.rawValue, 20261005)
        clock.refresh(now: instant("2026-09-30T15:00:00Z"), timeZone: zone)
        XCTAssertEqual(clock.day.today.rawValue, 20260930)
    }

    func testChangingHomeZoneCanMoveDateInEitherDirection() {
        let now = instant("2026-09-12T16:30:00Z")
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        let clock = DayClock(now: now, timeZone: shanghai)
        XCTAssertEqual(clock.day.today.rawValue, 20260913)
        clock.refresh(now: now, timeZone: losAngeles)
        XCTAssertEqual(clock.day.today.rawValue, 20260912)
        XCTAssertEqual(clock.day.timeZone, losAngeles)
        clock.refresh(now: now, timeZone: shanghai)
        XCTAssertEqual(clock.day.today.rawValue, 20260913)
    }

    func testSameDateDoesNotPublishUnlessZoneChanges() {
        let now = instant("2026-09-12T00:00:00Z")
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let clock = DayClock(now: now, timeZone: zone)
        let unchanged = expectation(description: "same date stays stable")
        unchanged.isInverted = true
        withObservationTracking { _ = clock.day } onChange: { unchanged.fulfill() }
        clock.refresh(now: now.addingTimeInterval(60), timeZone: zone)
        wait(for: [unchanged], timeout: 0.01)

        let otherClock = DayClock(now: now, timeZone: zone)
        let changed = expectation(description: "zone change invalidates presentation")
        withObservationTracking { _ = otherClock.day } onChange: { changed.fulfill() }
        otherClock.refresh(now: now, timeZone: TimeZone(identifier: "Asia/Hong_Kong")!)
        XCTAssertEqual(otherClock.day.timeZone.identifier, "Asia/Hong_Kong")
        wait(for: [changed], timeout: 1)
    }

    func testRunningClockRefreshesAtMidnightAndSchedulesFollowingDay() async {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var now = instant("2026-09-30T15:59:59Z")
        let clock = DayClock(now: now, timeZone: zone)
        var delays: [TimeInterval] = []
        await clock.run(timeZone: zone, now: { now }, sleep: { delay in
            delays.append(delay)
            if delays.count == 1 { now = now.addingTimeInterval(delay) }
            else { throw CancellationError() }
        })
        XCTAssertEqual(delays, [1, 86400])
        XCTAssertEqual(clock.day.today.rawValue, 20261001)
    }

    func testCancelledWakeupCannotOverwriteNewZone() async {
        let now = instant("2026-09-12T16:30:00Z")
        let oldZone = TimeZone(identifier: "Asia/Shanghai")!
        let newZone = TimeZone(identifier: "America/Los_Angeles")!
        let clock = DayClock(now: now, timeZone: oldZone)
        let sleeping = expectation(description: "old scene task is asleep")
        var continuation: CheckedContinuation<Void, Never>?
        let task = Task {
            await clock.run(timeZone: oldZone, now: { now }, sleep: { _ in
                await withCheckedContinuation { continuation = $0; sleeping.fulfill() }
            })
        }
        await fulfillment(of: [sleeping], timeout: 2)
        task.cancel()
        clock.refresh(now: now, timeZone: newZone)
        continuation?.resume()
        await task.value
        XCTAssertEqual(clock.day.today.rawValue, 20260912)
        XCTAssertEqual(clock.day.timeZone, newZone)
    }
}
