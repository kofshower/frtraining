import Foundation

/// Persists activity-level FIT backups when server synchronization fails.
///
/// The backup is deterministic per activity id so repeated failures overwrite the
/// same file instead of generating unbounded files.
struct ActivityOfflineBackupWriter {
    private let fileManager: FileManager
    private let backupDirectory: URL

    /// Creates a backup writer rooted at a caller-provided directory.
    /// - Parameters:
    ///   - fileManager: File manager used for filesystem operations.
    ///   - backupDirectory: Directory where `.fit` files are written.
    init(fileManager: FileManager = .default, backupDirectory: URL) {
        self.fileManager = fileManager
        self.backupDirectory = backupDirectory
    }

    /// Writes FIT backups for activities that do not already include source FIT payloads.
    /// - Parameter activities: Activities to back up.
    /// - Returns: Written FIT file URLs.
    func backup(activities: [Activity]) throws -> [URL] {
        try ensureBackupDirectoryExists()
        var writtenURLs: [URL] = []

        for activity in activities {
            if hasExistingFITPayload(activity) {
                continue
            }
            let fitData = makeFITData(from: activity)
            let targetURL = fileURL(for: activity)
            try fitData.write(to: targetURL, options: .atomic)
            writtenURLs.append(targetURL)
        }

        return writtenURLs
    }

    private func ensureBackupDirectoryExists() throws {
        if fileManager.fileExists(atPath: backupDirectory.path) {
            return
        }
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    }

    private func hasExistingFITPayload(_ activity: Activity) -> Bool {
        let type = activity.sourceFileType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasFitType = type == "fit" || type == "fit.gz"
        return hasFitType && activity.sourceFileBase64 != nil
    }

    private func fileURL(for activity: Activity) -> URL {
        backupDirectory.appendingPathComponent("\(activity.id.uuidString.lowercased()).fit")
    }

    private func makeFITData(from activity: Activity) -> Data {
        let clampedDuration = max(activity.durationSec, 1)
        let endDate = activity.date.addingTimeInterval(TimeInterval(clampedDuration))
        let summary = LiveRideSummary(
            startDate: activity.date,
            endDate: endDate,
            sport: activity.sport,
            totalElapsedSec: clampedDuration,
            totalTimerSec: clampedDuration,
            totalDistanceMeters: max(activity.distanceKm, 0) * 1_000.0,
            averageHeartRate: activity.avgHeartRate,
            maxHeartRate: activity.avgHeartRate,
            averagePower: activity.normalizedPower,
            maxPower: activity.normalizedPower,
            normalizedPower: activity.normalizedPower
        )

        let distanceMeters = max(activity.distanceKm, 0) * 1_000.0
        let samples = [
            LiveRideSample(
                timestamp: activity.date,
                powerWatts: activity.normalizedPower,
                heartRateBPM: activity.avgHeartRate,
                cadenceRPM: nil,
                speedKPH: nil,
                distanceMeters: 0,
                leftBalancePercent: nil,
                rightBalancePercent: nil
            ),
            LiveRideSample(
                timestamp: endDate,
                powerWatts: activity.normalizedPower,
                heartRateBPM: activity.avgHeartRate,
                cadenceRPM: nil,
                speedKPH: nil,
                distanceMeters: distanceMeters,
                leftBalancePercent: nil,
                rightBalancePercent: nil
            )
        ]

        return LiveRideFITWriter.export(samples: samples, summary: summary)
    }
}
