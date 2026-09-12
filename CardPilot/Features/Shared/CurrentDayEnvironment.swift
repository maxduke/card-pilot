import SwiftUI

private struct CurrentDayKey: EnvironmentKey {
    static var defaultValue: CurrentDay {
        CurrentDay(now: .now, timeZone: CardPilotUI.homeTimeZone)
    }
}

extension EnvironmentValues {
    var currentDay: CurrentDay {
        get { self[CurrentDayKey.self] }
        set { self[CurrentDayKey.self] = newValue }
    }
}
