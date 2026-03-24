import Foundation
import XCTest
@testable import FricuApp

final class TrainingWorkspaceSnapshotTests: XCTestCase {
    func testSnapshotSummarizesUpcomingAndUnscheduledWorkouts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        let now = date(2026, 3, 24, 8, 0, calendar: calendar)

        let workouts = [
            PlannedWorkout(
                id: UUID(uuidString: "F30DDA2A-A727-4A8A-A847-7A62A1B0174B")!,
                createdAt: date(2026, 3, 20, 9, 0, calendar: calendar),
                name: "Past Tempo",
                sport: .cycling,
                segments: [WorkoutSegment(minutes: 60, intensityPercentFTP: 88)],
                scheduledDate: date(2026, 3, 23, 7, 0, calendar: calendar)
            ),
            PlannedWorkout(
                id: UUID(uuidString: "4D217C1A-9F5E-4A78-9E14-5A50E8AEE9D4")!,
                createdAt: date(2026, 3, 21, 9, 0, calendar: calendar),
                name: "Threshold Builder",
                sport: .cycling,
                segments: [WorkoutSegment(minutes: 75, intensityPercentFTP: 96)],
                scheduledDate: date(2026, 3, 25, 7, 0, calendar: calendar)
            ),
            PlannedWorkout(
                id: UUID(uuidString: "06F9C4B7-7F0F-4DF0-B3D5-0267F7904B4B")!,
                createdAt: date(2026, 3, 22, 9, 0, calendar: calendar),
                name: "Long Run",
                sport: .running,
                segments: [WorkoutSegment(minutes: 90, intensityPercentFTP: 80)],
                scheduledDate: date(2026, 4, 2, 7, 0, calendar: calendar)
            ),
            PlannedWorkout(
                id: UUID(uuidString: "AE69E5E9-1D86-4343-AB0A-C58C3C55E440")!,
                createdAt: date(2026, 3, 23, 9, 0, calendar: calendar),
                name: "Camp Day",
                sport: .cycling,
                segments: [WorkoutSegment(minutes: 120, intensityPercentFTP: 72)],
                scheduledDate: date(2026, 4, 10, 7, 0, calendar: calendar)
            ),
            PlannedWorkout(
                id: UUID(uuidString: "2D6A6E6F-0AF6-4867-86E9-0FE67F98E9F4")!,
                createdAt: date(2026, 3, 24, 6, 0, calendar: calendar),
                name: "Unscheduled Recovery",
                sport: .cycling,
                segments: [WorkoutSegment(minutes: 45, intensityPercentFTP: 55)],
                scheduledDate: nil
            )
        ]

        let snapshot = TrainingOverviewSnapshot(
            workouts: workouts,
            activities: [],
            profile: .default,
            now: now,
            calendar: calendar,
            templateCount: 12
        )

        XCTAssertEqual(snapshot.totalPlannedMinutes, 390)
        XCTAssertEqual(snapshot.thisWeekScheduledCount, 2)
        XCTAssertEqual(snapshot.nextTwoWeeksMinutes, 165)
        XCTAssertEqual(snapshot.unscheduledWorkouts.count, 1)
        XCTAssertEqual(snapshot.upcomingScheduledWorkouts.count, 3)
        XCTAssertEqual(snapshot.templateCount, 12)
        XCTAssertEqual(snapshot.nextWorkout?.name, "Threshold Builder")
        XCTAssertEqual(snapshot.recentLibraryWorkouts.first?.name, "Unscheduled Recovery")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return calendar.date(from: components)!
    }
}
