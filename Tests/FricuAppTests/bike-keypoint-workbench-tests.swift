import XCTest
import UniformTypeIdentifiers
@testable import FricuApp

final class BikeKeypointWorkbenchTests: XCTestCase {
    func testDatasetFileDocumentKeepsDocumentAndDeclaresJSONType() {
        let document = BikeKeypointDatasetDocument(
            schema: "fr-training-bike-keypoints-v1",
            keypointNames: ["bb_center", "crank_end", "pedal_center"],
            pedalCenterRatio: 0.62,
            sourceVideos: ["/tmp/source.mov"],
            recordCount: 1,
            records: [
                BikeKeypointDatasetRecord(
                    id: "sample-1",
                    imagePath: "/tmp/sample-1.jpg",
                    videoPath: "/tmp/source.mov",
                    timeSeconds: 1.25,
                    width: 1920,
                    height: 1080,
                    side: "right",
                    quality: 0.88,
                    source: "manual",
                    keypoints: [
                        "bb_center": BikeKeypointDatasetPoint(x: 0.5, y: 0.8, confidence: 0.99)
                    ]
                )
            ]
        )

        let fileDocument = BikeKeypointDatasetFileDocument(document: document)
        XCTAssertEqual(fileDocument.document, document)
        XCTAssertEqual(BikeKeypointDatasetFileDocument.readableContentTypes, [UTType.json])
    }

    func testTrainingHistoryLoaderSortsActiveRunFirstThenNewest() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oldRunDir = tempRoot.appendingPathComponent("run-old", isDirectory: true)
        let newRunDir = tempRoot.appendingPathComponent("run-new", isDirectory: true)
        try FileManager.default.createDirectory(at: oldRunDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newRunDir, withIntermediateDirectories: true)

        let metadata = BikeKeypointTrainingMetadataDocument(
            schema: "fr-training-bike-keypoints-v1",
            keypointNames: ["bb_center", "crank_end", "pedal_center"],
            inputSize: 256,
            heatmapStride: 4,
            consistencyWeight: 0.15,
            bestValidationPixelError: 24.5,
            epochs: 4,
            device: "mps",
            history: [
                BikeKeypointTrainingEpochMetric(
                    epoch: 1,
                    trainLoss: 0.2,
                    valMeanPixelError: 30,
                    valMeanScore: 0.8,
                    valNME: 0.1
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let oldMetadataURL = oldRunDir.appendingPathComponent("best.json")
        let newMetadataURL = newRunDir.appendingPathComponent("best.json")
        try encoder.encode(metadata).write(to: oldMetadataURL)
        try Data("old".utf8).write(to: oldRunDir.appendingPathComponent("best.pt"))
        Thread.sleep(forTimeInterval: 0.02)
        try encoder.encode(metadata).write(to: newMetadataURL)
        try Data("new".utf8).write(to: newRunDir.appendingPathComponent("best.pt"))

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let histories = BikeKeypointTrainingHistoryLoader.loadHistories(
            searchRoots: [tempRoot],
            activeCheckpointPath: oldRunDir.appendingPathComponent("best.pt").path
        )

        XCTAssertEqual(histories.count, 2)
        XCTAssertEqual(histories.first?.runName, "run-old")
        XCTAssertTrue(histories.first?.isActive == true)
        XCTAssertEqual(histories.dropFirst().first?.runName, "run-new")
    }
}
