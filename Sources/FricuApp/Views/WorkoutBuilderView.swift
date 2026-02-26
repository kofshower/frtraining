import SwiftUI

struct WorkoutBuilderView: View {
    @EnvironmentObject private var store: AppStore

    @State private var workoutName = ""
    @State private var sport: SportType = .cycling
    @State private var hasScheduleDate = false
    @State private var scheduleDate = Date()
    @State private var segments: [WorkoutSegment] = [
        WorkoutSegment(minutes: 10, intensityPercentFTP: 55, note: "Warm-up"),
        WorkoutSegment(minutes: 5, intensityPercentFTP: 95, note: "Tempo")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Workout Builder")
                    .font(.largeTitle.bold())

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Workout name", text: $workoutName)

                        Picker("Sport", selection: $sport) {
                            ForEach(SportType.allCases) { sport in
                                Text(sport.label).tag(sport)
                            }
                        }
                        .appDropdownTheme()

                        Toggle("Set workout date", isOn: $hasScheduleDate)
                        if hasScheduleDate {
                            DatePicker("Workout Date", selection: $scheduleDate, displayedComponents: .date)
                        }

                        ForEach(segments.indices, id: \.self) { index in
                            SegmentEditor(segment: $segments[index]) {
                                segments.remove(at: index)
                            }
                        }

                        HStack {
                            Button("Add Segment") {
                                segments.append(WorkoutSegment(minutes: 4, intensityPercentFTP: 105, note: "Threshold"))
                            }

                            Spacer()

                            Text(
                                L10n.choose(
                                    simplifiedChinese: "总计 \(segments.reduce(0) { $0 + $1.minutes }) 分钟",
                                    english: "Total \(segments.reduce(0) { $0 + $1.minutes }) min"
                                )
                            )
                                .foregroundStyle(.secondary)

                            Button("Save Workout") {
                                store.saveWorkout(
                                    name: workoutName,
                                    sport: sport,
                                    segments: segments,
                                    scheduledDate: hasScheduleDate ? scheduleDate : nil
                                )
                                workoutName = ""
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Saved Workout Library") {
                    if store.athleteScopedPlannedWorkouts.isEmpty {
                        ContentUnavailableView("No workouts yet", systemImage: "tray")
                            .frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(store.athleteScopedPlannedWorkouts) { workout in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(workout.name)
                                            .font(.headline)
                                        Spacer()
                                        Text(workout.sport.label)
                                            .foregroundStyle(.secondary)
                                        Button("Delete", role: .destructive) {
                                            store.deleteWorkout(workout)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    Text(
                                        L10n.choose(
                                            simplifiedChinese: "\(workout.totalMinutes) 分钟 · \(workout.segments.count) 段",
                                            english: "\(workout.totalMinutes) min · \(workout.segments.count) segments"
                                        )
                                    )
                                        .foregroundStyle(.secondary)
                                    if let date = workout.scheduledDate {
                                        Text(
                                            L10n.choose(
                                                simplifiedChinese: "已安排：\(date.formatted(date: .abbreviated, time: .omitted))",
                                                english: "Scheduled: \(date.formatted(date: .abbreviated, time: .omitted))"
                                            )
                                        )
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct SegmentEditor: View {
    @Binding var segment: WorkoutSegment
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Segment note", text: $segment.note)
                Stepper("\(segment.minutes) min", value: $segment.minutes, in: 1...90)
                    .frame(width: 150)
                Stepper("\(segment.intensityPercentFTP)% FTP", value: $segment.intensityPercentFTP, in: 30...180)
                    .frame(width: 190)
                Button("Remove", role: .destructive, action: onDelete)
                    .buttonStyle(.borderless)
            }

            Divider()
        }
    }
}
