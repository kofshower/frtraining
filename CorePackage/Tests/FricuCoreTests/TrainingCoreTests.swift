import XCTest
@testable import FricuCore

final class TrainingCoreTests: XCTestCase {
    func testTrainingLoadMathHandlesTauGuardsAndSeries() {
        XCTAssertEqual(TrainingLoadMath.nextCTL(previous: 50, tss: 100, tauDays: 0), 50)
        XCTAssertEqual(TrainingLoadMath.nextATL(previous: 50, tss: 100, tauDays: -1), 50)
        XCTAssertEqual(TrainingLoadMath.nextTSB(currentCTL: 60, currentATL: 70), -10)

        let empty = TrainingLoadMath.buildSeries(dailyTSS: [])
        XCTAssertTrue(empty.isEmpty)

        let series = TrainingLoadMath.buildSeries(
            dailyTSS: [0, 60, 100],
            seedCTL: 45,
            seedATL: 50,
            ctlTauDays: 42,
            atlTauDays: 7
        )

        XCTAssertEqual(series.count, 3)
        XCTAssertEqual(series[0].dayIndex, 0)
        XCTAssertEqual(series[0].tss, 0)
        XCTAssertLessThan(series[0].ctl, 45)
        XCTAssertLessThan(series[0].atl, 50)
        XCTAssertEqual(series[2].dayIndex, 2)
        XCTAssertGreaterThan(series[2].ctl, series[1].ctl)
        XCTAssertGreaterThan(series[2].atl, series[1].atl)
        XCTAssertEqual(series[2].tsb, series[2].ctl - series[2].atl, accuracy: 0.0001)
    }

    func testReadinessScoreCoversAllBands() {
        XCTAssertEqual(ReadinessMath.score(tsb: -30, hrvToday: 70, hrvBaseline: 70), 40)
        XCTAssertEqual(ReadinessMath.score(tsb: -20, hrvToday: 70, hrvBaseline: 70), 52)
        XCTAssertEqual(ReadinessMath.score(tsb: -10, hrvToday: 70, hrvBaseline: 70), 62)
        XCTAssertEqual(ReadinessMath.score(tsb: 8, hrvToday: 70, hrvBaseline: 70), 78)
        XCTAssertEqual(ReadinessMath.score(tsb: 20, hrvToday: 70, hrvBaseline: 70), 72)

        XCTAssertEqual(ReadinessMath.score(tsb: 0, hrvToday: 50, hrvBaseline: 70), 54)
        XCTAssertEqual(ReadinessMath.score(tsb: 0, hrvToday: 62, hrvBaseline: 70), 66)
        XCTAssertEqual(ReadinessMath.score(tsb: 0, hrvToday: 80, hrvBaseline: 70), 82)

        XCTAssertEqual(ReadinessMath.score(tsb: -100, hrvToday: 1, hrvBaseline: 100), 16)
        XCTAssertEqual(ReadinessMath.score(tsb: 100, hrvToday: 300, hrvBaseline: 1), 76)
    }

    func testReadinessFocusBands() {
        XCTAssertEqual(ReadinessMath.todayFocus(tsb: -30, hrvToday: 50, hrvBaseline: 70), "Recovery")
        XCTAssertEqual(ReadinessMath.todayFocus(tsb: 5, hrvToday: 70, hrvBaseline: 70), "Quality")
        XCTAssertEqual(ReadinessMath.todayFocus(tsb: 20, hrvToday: 70, hrvBaseline: 70), "Fresh-Key")
        XCTAssertEqual(ReadinessMath.todayFocus(tsb: 0, hrvToday: 90, hrvBaseline: 0), "Quality")
    }

    func testDecouplingMath() throws {
        XCTAssertNil(DecouplingMath.percent(efFirst: 0, efSecond: 1))
        let decoupling = try XCTUnwrap(DecouplingMath.percent(efFirst: 1.2, efSecond: 1.0))
        XCTAssertEqual(decoupling, 16.6666666667, accuracy: 0.0001)

        XCTAssertEqual(DecouplingMath.qualityBand(decouplingPercent: nil), "N/A")
        XCTAssertEqual(DecouplingMath.qualityBand(decouplingPercent: 2), "Excellent")
        XCTAssertEqual(DecouplingMath.qualityBand(decouplingPercent: -7), "Good")
        XCTAssertEqual(DecouplingMath.qualityBand(decouplingPercent: 12), "Watch")
        XCTAssertEqual(DecouplingMath.qualityBand(decouplingPercent: -20), "Risk")
    }

    func testPowerCurveMath() {
        XCTAssertNil(PowerCurveMath.peakAverage(samples: [100, 200], windowSec: 0))
        XCTAssertNil(PowerCurveMath.peakAverage(samples: [100, 200], windowSec: 3))

        let peak5 = PowerCurveMath.peakAverage(samples: [100, 200, 300, 400, 500, 300, 200], windowSec: 5)
        XCTAssertEqual(peak5, 340)

        let flat = PowerCurveMath.peakAverage(samples: [150, 150, 150, 150], windowSec: 2)
        XCTAssertEqual(flat, 150)
    }

    func testCyclingPowerParserParsesFullFlagPayload() throws {
        let flags: UInt16 = 0x1FFF
        let maxExtremeAngleRaw: UInt32 = 2000
        let minExtremeAngleRaw: UInt32 = 1000
        let extremePacked = maxExtremeAngleRaw | (minExtremeAngleRaw << 12)

        var payload: [UInt8] = []
        payload.append(UInt8(flags & 0xFF))
        payload.append(UInt8((flags >> 8) & 0xFF))
        payload.append(contentsOf: int16Bytes(250)) // instantaneous power
        payload.append(120) // pedal balance => 60%
        payload.append(contentsOf: uint16Bytes(320)) // accumulated torque => 10Nm
        payload.append(contentsOf: uint32Bytes(123_456)) // wheel revs
        payload.append(contentsOf: uint16Bytes(2_048)) // wheel event time
        payload.append(contentsOf: uint16Bytes(200)) // crank revs
        payload.append(contentsOf: uint16Bytes(1_024)) // crank event time
        payload.append(contentsOf: int16Bytes(900)) // max force
        payload.append(contentsOf: int16Bytes(-450)) // min force
        payload.append(contentsOf: int16Bytes(640)) // max torque => 20Nm
        payload.append(contentsOf: int16Bytes(-160)) // min torque => -5Nm
        payload.append(UInt8(extremePacked & 0xFF))
        payload.append(UInt8((extremePacked >> 8) & 0xFF))
        payload.append(UInt8((extremePacked >> 16) & 0xFF))
        payload.append(contentsOf: uint16Bytes(360)) // 180 deg
        payload.append(contentsOf: uint16Bytes(600)) // 300 deg
        payload.append(contentsOf: uint16Bytes(1_234)) // accumulated energy

        let measurement = try XCTUnwrap(CyclingPowerMeasurementParser.parse(Data(payload)))
        XCTAssertEqual(measurement.flags.rawValue, flags)
        XCTAssertEqual(measurement.instantaneousPowerWatts, 250)

        XCTAssertEqual(try XCTUnwrap(measurement.pedalPowerBalancePercent), 60, accuracy: 0.001)
        XCTAssertEqual(measurement.pedalPowerBalanceReferenceIsRight, true)
        XCTAssertEqual(try XCTUnwrap(measurement.estimatedLeftBalancePercent), 40, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(measurement.estimatedRightBalancePercent), 60, accuracy: 0.001)

        XCTAssertEqual(try XCTUnwrap(measurement.accumulatedTorqueNm), 10, accuracy: 0.001)
        XCTAssertEqual(measurement.accumulatedTorqueSource, .crankBased)
        XCTAssertEqual(measurement.cumulativeWheelRevolutions, 123_456)
        XCTAssertEqual(measurement.lastWheelEventTime1024, 2_048)
        XCTAssertEqual(measurement.cumulativeCrankRevolutions, 200)
        XCTAssertEqual(measurement.lastCrankEventTime1024, 1_024)

        XCTAssertEqual(measurement.maximumForceNewton, 900)
        XCTAssertEqual(measurement.minimumForceNewton, -450)
        XCTAssertEqual(try XCTUnwrap(measurement.maximumTorqueNm), 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(measurement.minimumTorqueNm), -5, accuracy: 0.001)

        XCTAssertEqual(try XCTUnwrap(measurement.maximumAngleDegrees), Double(maxExtremeAngleRaw) * 360.0 / 4096.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(measurement.minimumAngleDegrees), Double(minExtremeAngleRaw) * 360.0 / 4096.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(measurement.topDeadSpotAngleDegrees), 180, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(measurement.bottomDeadSpotAngleDegrees), 300, accuracy: 0.001)
        XCTAssertEqual(measurement.accumulatedEnergyKJ, 1_234)
        XCTAssertTrue(measurement.offsetCompensationIndicator)
    }

    func testCyclingPowerParserPowerOnlyPayload() throws {
        let flags: UInt16 = 0
        let payload: [UInt8] = [
            UInt8(flags & 0xFF),
            UInt8((flags >> 8) & 0xFF),
            0x96, 0x00 // 150W
        ]
        let measurement = try XCTUnwrap(CyclingPowerMeasurementParser.parse(Data(payload)))
        XCTAssertEqual(measurement.instantaneousPowerWatts, 150)
        XCTAssertNil(measurement.pedalPowerBalancePercent)
        XCTAssertNil(measurement.accumulatedTorqueNm)
        XCTAssertNil(measurement.cumulativeWheelRevolutions)
        XCTAssertFalse(measurement.offsetCompensationIndicator)
    }

    func testCyclingPowerParserRejectsShortPayload() {
        XCTAssertNil(CyclingPowerMeasurementParser.parse(Data([0x00, 0x00, 0x10])))
    }

    func testCyclingPowerParserIgnoresInvalidPedalBalanceByte() throws {
        let flags: UInt16 = CyclingPowerMeasurementFlags.pedalPowerBalancePresent.rawValue
            | CyclingPowerMeasurementFlags.pedalPowerBalanceReference.rawValue
        let payload: [UInt8] = [
            UInt8(flags & 0xFF),
            UInt8((flags >> 8) & 0xFF),
            0xC8, 0x00, // 200W
            0xFF // invalid/reserved for 0.5% pedal balance (valid max is 200)
        ]
        let measurement = try XCTUnwrap(CyclingPowerMeasurementParser.parse(Data(payload)))
        XCTAssertNil(measurement.pedalPowerBalancePercent)
        XCTAssertNil(measurement.pedalPowerBalanceReferenceIsRight)
        XCTAssertNil(measurement.estimatedLeftBalancePercent)
        XCTAssertNil(measurement.estimatedRightBalancePercent)
    }

    func testFitnessMachineIndoorBikeParsesFullFields() throws {
        let flags: UInt16 = 0b0001_1111_1111_1110 // avg speed + all optional fields, instantaneous speed present
        var payload: [UInt8] = []
        payload.append(UInt8(flags & 0xFF))
        payload.append(UInt8((flags >> 8) & 0xFF))
        payload.append(contentsOf: uint16Bytes(3_280)) // inst speed 32.80 kph
        payload.append(contentsOf: uint16Bytes(3_150)) // avg speed 31.50 kph
        payload.append(contentsOf: uint16Bytes(180)) // inst cadence 90rpm
        payload.append(contentsOf: uint16Bytes(170)) // avg cadence 85rpm
        payload.append(0x40); payload.append(0xE2); payload.append(0x01) // distance 123_456m
        payload.append(contentsOf: int16Bytes(30)) // resistance level
        payload.append(contentsOf: int16Bytes(250)) // inst power
        payload.append(contentsOf: int16Bytes(240)) // avg power
        payload.append(contentsOf: uint16Bytes(720)) // total kcal
        payload.append(contentsOf: uint16Bytes(950)) // kcal/h
        payload.append(12) // kcal/min
        payload.append(156) // hr
        payload.append(10) // met=1.0
        payload.append(contentsOf: uint16Bytes(3660)) // elapsed sec
        payload.append(contentsOf: uint16Bytes(600)) // remaining sec

        let parsed = try XCTUnwrap(FitnessMachineParsers.parseIndoorBikeData(Data(payload)))
        XCTAssertEqual(parsed.flags.rawValue, flags)
        XCTAssertEqual(try XCTUnwrap(parsed.instantaneousSpeedKPH), 32.8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed.averageSpeedKPH), 31.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed.instantaneousCadenceRPM), 90, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed.averageCadenceRPM), 85, accuracy: 0.001)
        XCTAssertEqual(parsed.totalDistanceMeters, 123_456)
        XCTAssertEqual(parsed.resistanceLevel, 30)
        XCTAssertEqual(parsed.instantaneousPowerWatts, 250)
        XCTAssertEqual(parsed.averagePowerWatts, 240)
        XCTAssertEqual(parsed.totalEnergyKCal, 720)
        XCTAssertEqual(parsed.energyPerHourKCal, 950)
        XCTAssertEqual(parsed.energyPerMinuteKCal, 12)
        XCTAssertEqual(parsed.heartRateBPM, 156)
        XCTAssertEqual(try XCTUnwrap(parsed.metabolicEquivalent), 1.0, accuracy: 0.0001)
        XCTAssertEqual(parsed.elapsedTimeSec, 3660)
        XCTAssertEqual(parsed.remainingTimeSec, 600)
    }

    func testFitnessMachineFeatureAndRangeAndStatusParser() throws {
        let featureData = Data(uint32Bytes(0xAABBCCDD) + uint32Bytes(0x00112233))
        let feature = try XCTUnwrap(FitnessMachineParsers.parseFitnessMachineFeature(featureData))
        XCTAssertEqual(feature.machineFeaturesRaw, 0xAABBCCDD)
        XCTAssertEqual(feature.targetSettingFeaturesRaw, 0x00112233)

        let rangeData = Data(int16Bytes(-10) + int16Bytes(250) + uint16Bytes(5))
        let range = try XCTUnwrap(FitnessMachineParsers.parseSupportedRange(rangeData))
        XCTAssertEqual(range.minimum, -10)
        XCTAssertEqual(range.maximum, 250)
        XCTAssertEqual(range.increment, 5)

        let status = try XCTUnwrap(FitnessMachineParsers.parseFitnessMachineStatus(Data([0x08, 0x96, 0x00])))
        XCTAssertEqual(status.opCode, 0x08)
        XCTAssertEqual(status.parameterBytes, [0x96, 0x00])

        let training = try XCTUnwrap(FitnessMachineParsers.parseTrainingStatus(Data([0x05])))
        XCTAssertEqual(training.statusCode, 0x05)
        XCTAssertEqual(training.stringCode, "high_intensity")
        XCTAssertEqual(FitnessMachineParsers.trainingStatusStringCode(0x40), "unknown_64")
    }

    func testHeartRateMeasurementParserCoversAllFields() throws {
        // Flags: uint16 value + sensor contact supported/detected + energy + RR intervals.
        let flags: UInt8 = 0b0001_1111
        let rr1: UInt16 = 1_024 // 1000ms
        let rr2: UInt16 = 820 // ~801ms
        let payload = Data([
            flags,
            0xC8, 0x00, // 200 bpm (uint16)
            0x7B, 0x00, // energy 123kJ
            UInt8(rr1 & 0xFF), UInt8((rr1 >> 8) & 0xFF),
            UInt8(rr2 & 0xFF), UInt8((rr2 >> 8) & 0xFF)
        ])

        let parsed = try XCTUnwrap(HeartRateParsers.parseMeasurement(payload))
        XCTAssertEqual(parsed.flags.rawValue, flags)
        XCTAssertEqual(parsed.heartRateBPM, 200)
        XCTAssertTrue(parsed.valueIsUInt16)
        XCTAssertTrue(parsed.sensorContactSupported)
        XCTAssertEqual(parsed.sensorContactDetected, true)
        XCTAssertEqual(parsed.energyExpendedKJ, 123)
        XCTAssertEqual(parsed.rrIntervals1024, [rr1, rr2])
        XCTAssertEqual(parsed.rrIntervalsMS.count, 2)
        XCTAssertEqual(parsed.rrIntervalsMS[0], 1000, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed.latestRRIntervalMS), Double(rr2) * 1000 / 1024, accuracy: 0.001)
    }

    func testHeartRateBodySensorLocationParser() throws {
        XCTAssertEqual(try XCTUnwrap(HeartRateParsers.parseBodySensorLocation(Data([0x01]))), .chest)
        XCTAssertEqual(try XCTUnwrap(HeartRateParsers.parseBodySensorLocation(Data([0x04]))), .hand)
        XCTAssertEqual(try XCTUnwrap(HeartRateParsers.parseBodySensorLocation(Data([0x77]))), .unknown(0x77))
        XCTAssertNil(HeartRateParsers.parseBodySensorLocation(Data()))
    }

    func testHeartRateMeasurementParserRejectsShortPayload() {
        XCTAssertNil(HeartRateParsers.parseMeasurement(Data()))
        XCTAssertNil(HeartRateParsers.parseMeasurement(Data([0x01])))
    }

    func testHeartRateVariabilityMetricsFromRR() throws {
        let rr: [Double] = [1000, 950, 1050, 1000, 980]
        let metrics = try XCTUnwrap(HeartRateVariabilityMath.metrics(rrIntervalsMS: rr, minimumCount: 5))
        XCTAssertEqual(metrics.sampleCount, 5)
        XCTAssertEqual(metrics.meanRRMS, 996, accuracy: 0.001)
        XCTAssertEqual(metrics.rmssdMS, 62.048, accuracy: 0.001)
        XCTAssertEqual(metrics.sdnnMS, 36.469, accuracy: 0.001)
        XCTAssertEqual(metrics.pnn50Percent, 25.0, accuracy: 0.001)
        XCTAssertEqual(metrics.minRRMS, 950, accuracy: 0.001)
        XCTAssertEqual(metrics.maxRRMS, 1050, accuracy: 0.001)
    }

    func testHeartRateVariabilitySanitizeAndMinimumCount() {
        let dirty: [Double] = [1000, 4000, 980, 200, 970, 1400]
        let clean = HeartRateVariabilityMath.sanitizeRRIntervals(dirty)
        XCTAssertEqual(clean, [1000, 980, 970], "Out-of-range and jump artifacts should be filtered")
        XCTAssertNil(HeartRateVariabilityMath.metrics(rrIntervalsMS: clean, minimumCount: 5))
    }

    private func uint16Bytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private func uint32Bytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }

    private func int16Bytes(_ value: Int16) -> [UInt8] {
        let raw = UInt16(bitPattern: value)
        return uint16Bytes(raw)
    }
}
