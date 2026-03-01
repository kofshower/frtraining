import Foundation
import CoreBluetooth
import FricuCore

enum TrainerVendor: String {
    case wahoo
    case garmin
    case other

    var label: String {
        switch self {
        case .wahoo: return "Wahoo"
        case .garmin: return "Garmin/Tacx"
        case .other: return "Other"
        }
    }
}

enum TrainerExecutionMode: String, CaseIterable, Identifiable {
    case erg = "ERG"
    case crs = "CRS"
    case pgmf = "PGMF"
    case simulation = "SIM"
    case realMap = "REAL MAP"

    var id: String { rawValue }
}

struct TrainerDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let vendor: TrainerVendor
    let rssi: Int
    let isConnected: Bool
    let supportsERG: Bool
    let supportsPower: Bool
}

final class SmartTrainerManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothStateText: String = "Initializing"
    @Published private(set) var discoveredDevices: [TrainerDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var connectedVendor: TrainerVendor = .other
    @Published private(set) var ergAvailable = false
    @Published private(set) var powerTelemetryAvailable = false

    @Published private(set) var livePowerWatts: Int?
    @Published private(set) var liveCadenceRPM: Double?
    @Published private(set) var liveSpeedKPH: Double?
    @Published private(set) var liveLeftBalancePercent: Double?
    @Published private(set) var liveRightBalancePercent: Double?
    @Published private(set) var liveIndoorBikeData: IndoorBikeDataMeasurement?
    @Published private(set) var liveFitnessMachineStatus: FitnessMachineStatusEvent?
    @Published private(set) var liveTrainingStatus: FitnessMachineTrainingStatus?
    @Published private(set) var fitnessMachineFeatureSet: FitnessMachineFeatureSet?
    @Published private(set) var fitnessMachineSupportedResistanceRange: FitnessMachineSupportedRange?
    @Published private(set) var fitnessMachineSupportedPowerRange: FitnessMachineSupportedRange?
    @Published private(set) var fitnessMachineRawCharacteristicHex: [String: String] = [:]
    @Published private(set) var liveCyclingPowerMeasurement: CyclingPowerMeasurement?
    @Published private(set) var ergTargetWatts: Int?
    @Published private(set) var executionMode: TrainerExecutionMode = .erg
    @Published private(set) var targetGradePercent: Double?
    @Published private(set) var programPhase: String?
    @Published private(set) var simulationActivityName: String?
    @Published private(set) var simulationProgress: Double = 0
    @Published private(set) var simulationSpeedMultiplier: Double = 1
    @Published private(set) var lastMessage: String?
    var onConnectedDeviceChanged: ((UUID, String?) -> Void)?

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var rssiByPeripheral: [UUID: Int] = [:]
    private var pendingScanRequest = false
    private var preferredAutoConnectDeviceID: UUID?
    private var didAttemptAutoConnectForCurrentScan = false

    private var connectedPeripheral: CBPeripheral?
    private var indoorBikeDataCharacteristic: CBCharacteristic?
    private var trainingStatusCharacteristic: CBCharacteristic?
    private var controlPointCharacteristic: CBCharacteristic?
    private var fitnessMachineStatusCharacteristic: CBCharacteristic?
    private var fitnessMachineFeatureCharacteristic: CBCharacteristic?
    private var supportedResistanceRangeCharacteristic: CBCharacteristic?
    private var supportedPowerRangeCharacteristic: CBCharacteristic?
    private var cyclingPowerMeasurementCharacteristic: CBCharacteristic?
    private var cscMeasurementCharacteristic: CBCharacteristic?

    private var commandQueue: [Data] = []
    private var writingControlPoint = false
    private var controlAcquired = false
    private var workoutProgramTask: Task<Void, Never>?
    private var activitySimulationTask: Task<Void, Never>?

    private struct Capability {
        var vendor: TrainerVendor = .other
        var hasFTMS = false
        var hasCyclingPower = false
        var hasCSC = false
    }

    private struct CrankSample {
        let revs: UInt16
        let eventTime1024: UInt16
    }

    private var capabilityByPeripheral: [UUID: Capability] = [:]
    private var lastCrankByPeripheral: [UUID: CrankSample] = [:]

    private let ftmsServiceUUID = CBUUID(string: "1826")
    private let indoorBikeDataUUID = CBUUID(string: "2AD2")
    private let trainingStatusUUID = CBUUID(string: "2AD3")
    private let controlPointUUID = CBUUID(string: "2AD9")
    private let fitnessMachineStatusUUID = CBUUID(string: "2ADA")
    private let fitnessMachineFeatureUUID = CBUUID(string: "2ACC")
    private let supportedResistanceRangeUUID = CBUUID(string: "2AD6")
    private let supportedPowerRangeUUID = CBUUID(string: "2AD8")

    private let cyclingPowerServiceUUID = CBUUID(string: "1818")
    private let cyclingPowerMeasurementUUID = CBUUID(string: "2A63")

    private let cscServiceUUID = CBUUID(string: "1816")
    private let cscMeasurementUUID = CBUUID(string: "2A5B")

    override init() {
        super.init()
        bluetoothStateText = "Idle"
    }

    func startScan() {
        guard let central = ensureCentralManager() else { return }
        guard central.state == .poweredOn else {
            pendingScanRequest = true
            lastMessage = "Bluetooth not ready yet, waiting..."
            return
        }

        pendingScanRequest = false
        performScan()
    }

    func stopScan() {
        central?.stopScan()
        pendingScanRequest = false
        isScanning = false
    }

    func connect(deviceID: UUID) {
        guard let central = ensureCentralManager() else { return }
        guard let peripheral = peripherals[deviceID] else { return }
        stopScan()
        lastMessage = "Connecting to \(peripheral.name ?? "Trainer")..."
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let connectedPeripheral, let central else { return }
        central.cancelPeripheralConnection(connectedPeripheral)
    }

    func setPreferredAutoConnectDeviceID(_ deviceID: UUID?) {
        preferredAutoConnectDeviceID = deviceID
    }

    func startAutoConnectIfPossible() {
        guard preferredAutoConnectDeviceID != nil else { return }
        guard !isConnected else { return }
        if !isScanning {
            startScan()
        }
    }

    private var isAppBundleLaunch: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private func ensureCentralManager() -> CBCentralManager? {
        guard isAppBundleLaunch else {
            bluetoothStateText = "Needs App Bundle"
            lastMessage = "Launch with ./scripts/run-dev.sh to enable Bluetooth permissions."
            return nil
        }

        if central == nil {
            bluetoothStateText = "Initializing"
            central = CBCentralManager(delegate: self, queue: nil)
        }
        return central
    }

    private func performScan() {
        guard let central else { return }

        discoveredDevices = []
        peripherals = [:]
        rssiByPeripheral = [:]
        capabilityByPeripheral = [:]
        didAttemptAutoConnectForCurrentScan = false

        // Scan all devices and filter smart trainers by advertised services and brand tokens.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        lastMessage = "Scanning Wahoo / Garmin / FTMS trainers..."
    }

    private func attemptAutoConnectIfNeeded(for peripheralID: UUID) {
        guard let targetID = preferredAutoConnectDeviceID else { return }
        guard !didAttemptAutoConnectForCurrentScan else { return }
        guard !isConnected else { return }
        guard peripheralID == targetID else { return }
        didAttemptAutoConnectForCurrentScan = true
        lastMessage = "Found preferred trainer, auto-connecting..."
        connect(deviceID: peripheralID)
    }

    func setErgTargetPower(_ watts: Int, mode: TrainerExecutionMode = .erg) {
        executionMode = mode
        guard ergAvailable else {
            lastMessage = "ERG unavailable on this connection (FTMS control point not found)."
            return
        }

        let clipped = max(0, min(2000, watts))
        ergTargetWatts = clipped

        // FTMS sequence: request control (0x00), start/resume (0x07), set target power (0x05 + sint16 watts)
        if !controlAcquired {
            enqueueCommand(Data([0x00]))
        }

        enqueueCommand(Data([0x07]))
        let value = Int16(clipped)
        let low = UInt8(truncatingIfNeeded: value)
        let high = UInt8(truncatingIfNeeded: value >> 8)
        enqueueCommand(Data([0x05, low, high]))
    }

    func setCRSGrade(percent: Double) {
        executionMode = .crs
        guard ergAvailable else {
            lastMessage = "CRS unavailable on this connection."
            return
        }

        // FTMS indoor simulation command (default wind/crr/cw, custom grade).
        let clipped = max(-25.0, min(25.0, percent))
        targetGradePercent = clipped
        if !controlAcquired {
            enqueueCommand(Data([0x00]))
        }
        enqueueCommand(Data([0x07]))

        let windSpeed = Int16(0) // m/s * 1000
        let grade = Int16((clipped * 100.0).rounded()) // percent * 100
        let crr = UInt8(4) // 0.0004
        let cw = UInt8(51) // 0.51 kg/m

        let wsLo = UInt8(truncatingIfNeeded: windSpeed)
        let wsHi = UInt8(truncatingIfNeeded: windSpeed >> 8)
        let gLo = UInt8(truncatingIfNeeded: grade)
        let gHi = UInt8(truncatingIfNeeded: grade >> 8)
        enqueueCommand(Data([0x11, wsLo, wsHi, gLo, gHi, crr, cw]))
        lastMessage = String(format: "CRS grade %.1f%% applied", clipped)
    }

    func startPGMFProgram(segments: [WorkoutSegment], ftpWatts: Int) {
        guard !segments.isEmpty else {
            lastMessage = "PGMF requires at least one segment."
            return
        }
        guard ergAvailable else {
            lastMessage = "PGMF unavailable on this connection."
            return
        }

        executionMode = .pgmf
        workoutProgramTask?.cancel()
        stopActivitySimulation()
        let steps = segments
        let ftp = max(80, ftpWatts)

        workoutProgramTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.programPhase = "PGMF running (1/\(steps.count))"
                self.lastMessage = "PGMF started"
            }

            for (idx, segment) in steps.enumerated() {
                if Task.isCancelled { break }
                let target = Int((Double(ftp) * Double(segment.intensityPercentFTP) / 100.0).rounded())
                await MainActor.run {
                    self.programPhase = "PGMF \(idx + 1)/\(steps.count): \(segment.note)"
                    self.setErgTargetPower(target, mode: .pgmf)
                }

                let sleepSec = max(5, segment.minutes * 60)
                for _ in 0..<sleepSec {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                if Task.isCancelled { break }
            }

            await MainActor.run {
                if Task.isCancelled {
                    self.programPhase = "PGMF cancelled"
                    self.lastMessage = "PGMF cancelled"
                } else {
                    self.programPhase = "PGMF completed"
                    self.lastMessage = "PGMF completed"
                }
            }
        }
    }

    func stopPGMFProgram() {
        workoutProgramTask?.cancel()
        workoutProgramTask = nil
        if executionMode == .pgmf {
            programPhase = "PGMF stopped"
        }
    }

    func startActivitySimulation(activity: Activity, fallbackFTPWatts: Int, speedMultiplier: Double) {
        guard ergAvailable else {
            lastMessage = "Simulation requires ERG-capable trainer."
            return
        }

        let phases = buildSimulationPhases(activity: activity, fallbackFTPWatts: fallbackFTPWatts)
        guard !phases.isEmpty else {
            lastMessage = "Activity has no usable power pattern for simulation."
            return
        }

        executionMode = .simulation
        stopPGMFProgram()
        activitySimulationTask?.cancel()
        simulationActivityName = activity.notes.isEmpty ? "\(activity.sport.label) \(activity.date.formatted(date: .abbreviated, time: .omitted))" : activity.notes
        simulationProgress = 0
        simulationSpeedMultiplier = max(0.25, min(40, speedMultiplier))
        programPhase = "SIM running (1/\(phases.count))"
        lastMessage = "Simulation started"

        let totalDuration = phases.reduce(0) { $0 + $1.durationSec }

        activitySimulationTask = Task { [weak self] in
            guard let self else { return }
            var elapsed = 0

            for (idx, phase) in phases.enumerated() {
                if Task.isCancelled { break }
                let elapsedSnapshot = elapsed
                await MainActor.run {
                    self.programPhase = "SIM \(idx + 1)/\(phases.count): \(phase.label)"
                    self.setErgTargetPower(phase.targetPower, mode: .simulation)
                    self.simulationProgress = totalDuration > 0 ? Double(elapsedSnapshot) / Double(totalDuration) : 0
                }

                let simulatedSec = max(1.0, Double(phase.durationSec) / max(0.25, self.simulationSpeedMultiplier))
                let ticks = max(1, Int(simulatedSec.rounded()))
                for _ in 0..<ticks {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }

                elapsed += phase.durationSec
            }

            await MainActor.run {
                if Task.isCancelled {
                    self.programPhase = "SIM cancelled"
                    self.lastMessage = "Simulation cancelled"
                } else {
                    self.simulationProgress = 1.0
                    self.programPhase = "SIM completed"
                    self.lastMessage = "Simulation completed"
                }
            }
        }
    }

    func stopActivitySimulation() {
        activitySimulationTask?.cancel()
        activitySimulationTask = nil
        simulationProgress = 0
        simulationActivityName = nil
        simulationSpeedMultiplier = 1
        if executionMode == .simulation {
            programPhase = "SIM stopped"
        }
    }

    func stopErg() {
        guard ergAvailable else {
            lastMessage = "ERG unavailable on this connection."
            return
        }

        // FTMS stop/pause command.
        enqueueCommand(Data([0x08, 0x01]))
        stopPGMFProgram()
        stopActivitySimulation()
    }

    private func enqueueCommand(_ data: Data) {
        commandQueue.append(data)
        flushControlPointQueue()
    }

    private func flushControlPointQueue() {
        guard !writingControlPoint else { return }
        guard let connectedPeripheral, let controlPointCharacteristic else { return }
        guard !commandQueue.isEmpty else { return }

        writingControlPoint = true
        let command = commandQueue.removeFirst()
        connectedPeripheral.writeValue(command, for: controlPointCharacteristic, type: .withResponse)
    }

    private func refreshDiscoveredDevices() {
        let rows = peripherals.values.map { peripheral -> TrainerDevice in
            let cap = capabilityByPeripheral[peripheral.identifier] ?? Capability(vendor: detectVendor(name: peripheral.name ?? ""), hasFTMS: false, hasCyclingPower: false, hasCSC: false)
            return TrainerDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? "Unknown Trainer",
                vendor: cap.vendor,
                rssi: rssiByPeripheral[peripheral.identifier] ?? -99,
                isConnected: peripheral.identifier == connectedPeripheral?.identifier,
                supportsERG: cap.hasFTMS,
                supportsPower: cap.hasFTMS || cap.hasCyclingPower || cap.hasCSC
            )
        }

        discoveredDevices = rows.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected && !rhs.isConnected }
            if lhs.supportsERG != rhs.supportsERG { return lhs.supportsERG && !rhs.supportsERG }
            if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
            return lhs.name < rhs.name
        }
    }

    private func resetConnectionState() {
        connectedPeripheral = nil
        isConnected = false
        connectedDeviceName = nil
        connectedVendor = .other

        indoorBikeDataCharacteristic = nil
        trainingStatusCharacteristic = nil
        controlPointCharacteristic = nil
        fitnessMachineStatusCharacteristic = nil
        fitnessMachineFeatureCharacteristic = nil
        supportedResistanceRangeCharacteristic = nil
        supportedPowerRangeCharacteristic = nil
        cyclingPowerMeasurementCharacteristic = nil
        cscMeasurementCharacteristic = nil

        commandQueue = []
        writingControlPoint = false
        controlAcquired = false
        workoutProgramTask?.cancel()
        workoutProgramTask = nil
        activitySimulationTask?.cancel()
        activitySimulationTask = nil
        executionMode = .erg
        targetGradePercent = nil
        programPhase = nil
        simulationActivityName = nil
        simulationProgress = 0
        simulationSpeedMultiplier = 1

        ergAvailable = false
        powerTelemetryAvailable = false

        livePowerWatts = nil
        liveCadenceRPM = nil
        liveSpeedKPH = nil
        liveLeftBalancePercent = nil
        liveRightBalancePercent = nil
        liveIndoorBikeData = nil
        liveFitnessMachineStatus = nil
        liveTrainingStatus = nil
        fitnessMachineFeatureSet = nil
        fitnessMachineSupportedResistanceRange = nil
        fitnessMachineSupportedPowerRange = nil
        fitnessMachineRawCharacteristicHex = [:]
        liveCyclingPowerMeasurement = nil
    }

    private func updateConnectionCapabilities(for peripheral: CBPeripheral) {
        let cap = capabilityByPeripheral[peripheral.identifier] ?? Capability(vendor: detectVendor(name: peripheral.name ?? ""), hasFTMS: false, hasCyclingPower: false, hasCSC: false)
        connectedVendor = cap.vendor
        ergAvailable = (controlPointCharacteristic != nil) || cap.hasFTMS
        powerTelemetryAvailable = indoorBikeDataCharacteristic != nil || cyclingPowerMeasurementCharacteristic != nil || cscMeasurementCharacteristic != nil
    }

    private func detectVendor(name: String) -> TrainerVendor {
        let value = name.lowercased()
        if value.contains("wahoo") || value.contains("kickr") {
            return .wahoo
        }
        if value.contains("garmin") || value.contains("tacx") || value.contains("neo") || value.contains("flux") {
            return .garmin
        }
        return .other
    }

    private func shouldKeepDiscoveredDevice(name: String, serviceUUIDs: [CBUUID]) -> Bool {
        let vendor = detectVendor(name: name)
        if vendor != .other {
            return true
        }

        let set = Set(serviceUUIDs)
        if set.contains(ftmsServiceUUID) || set.contains(cyclingPowerServiceUUID) || set.contains(cscServiceUUID) {
            return true
        }

        return false
    }

    private func mergeCapability(peripheralID: UUID, name: String, serviceUUIDs: [CBUUID]) {
        var cap = capabilityByPeripheral[peripheralID] ?? Capability()
        cap.vendor = (cap.vendor == .other) ? detectVendor(name: name) : cap.vendor

        let set = Set(serviceUUIDs)
        if set.contains(ftmsServiceUUID) { cap.hasFTMS = true }
        if set.contains(cyclingPowerServiceUUID) { cap.hasCyclingPower = true }
        if set.contains(cscServiceUUID) { cap.hasCSC = true }

        capabilityByPeripheral[peripheralID] = cap
    }

    private func parseIndoorBikeData(_ data: Data) {
        guard let rawMeasurement = FitnessMachineParsers.parseIndoorBikeData(data) else { return }
        let measurement = mergedIndoorBikeData(current: rawMeasurement, previous: liveIndoorBikeData)
        liveIndoorBikeData = measurement
        if let speed = measurement.instantaneousSpeedKPH {
            liveSpeedKPH = speed
        }
        if let cadence = measurement.instantaneousCadenceRPM {
            liveCadenceRPM = cadence
        }
        if let power = measurement.instantaneousPowerWatts {
            livePowerWatts = power
        }
    }

    private func parseFitnessMachineStatus(_ data: Data) {
        guard let status = FitnessMachineParsers.parseFitnessMachineStatus(data) else { return }
        liveFitnessMachineStatus = status
    }

    private func parseTrainingStatus(_ data: Data) {
        guard let status = FitnessMachineParsers.parseTrainingStatus(data) else { return }
        liveTrainingStatus = status
    }

    private func parseFitnessMachineReadValue(_ data: Data, uuid: CBUUID) {
        if uuid == fitnessMachineFeatureUUID {
            fitnessMachineFeatureSet = FitnessMachineParsers.parseFitnessMachineFeature(data)
            return
        }
        if uuid == supportedResistanceRangeUUID {
            fitnessMachineSupportedResistanceRange = FitnessMachineParsers.parseSupportedRange(data)
            return
        }
        if uuid == supportedPowerRangeUUID {
            fitnessMachineSupportedPowerRange = FitnessMachineParsers.parseSupportedRange(data)
            return
        }
    }

    private func updateFitnessMachineRawValue(uuid: CBUUID, data: Data) {
        let key = uuid.uuidString.uppercased()
        fitnessMachineRawCharacteristicHex[key] = hexString(from: data)
    }

    private func hexString(from data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func parseCyclingPowerMeasurement(_ data: Data, peripheralID: UUID) {
        guard let rawMeasurement = CyclingPowerMeasurementParser.parse(data) else { return }
        let measurement = mergedCyclingPowerMeasurement(current: rawMeasurement, previous: liveCyclingPowerMeasurement)
        liveCyclingPowerMeasurement = measurement
        livePowerWatts = rawMeasurement.instantaneousPowerWatts
        if rawMeasurement.flags.contains(.pedalPowerBalancePresent) {
            if let left = rawMeasurement.estimatedLeftBalancePercent,
               let right = rawMeasurement.estimatedRightBalancePercent {
                liveLeftBalancePercent = left
                liveRightBalancePercent = right
            } else {
                liveLeftBalancePercent = nil
                liveRightBalancePercent = nil
            }
        }

        if let crankRevs = rawMeasurement.cumulativeCrankRevolutions,
           let crankEventTime = rawMeasurement.lastCrankEventTime1024 {
            updateCadence(peripheralID: peripheralID, crankRevs: crankRevs, crankEventTime: crankEventTime)
        }
    }

    private func parseCSCMeasurement(_ data: Data, peripheralID: UUID) {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return }

        let flags = bytes[0]
        var index = 1

        func readUInt16() -> UInt16? {
            guard index + 2 <= bytes.count else { return nil }
            defer { index += 2 }
            return UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
        }

        func readUInt32() -> UInt32? {
            guard index + 4 <= bytes.count else { return nil }
            defer { index += 4 }
            return UInt32(bytes[index])
                | (UInt32(bytes[index + 1]) << 8)
                | (UInt32(bytes[index + 2]) << 16)
                | (UInt32(bytes[index + 3]) << 24)
        }

        if (flags & 0x01) != 0 {
            _ = readUInt32(); _ = readUInt16()
        }

        if (flags & 0x02) != 0,
           let crankRevs = readUInt16(),
           let crankEventTime = readUInt16()
        {
            updateCadence(peripheralID: peripheralID, crankRevs: crankRevs, crankEventTime: crankEventTime)
        }
    }

    private func updateCadence(peripheralID: UUID, crankRevs: UInt16, crankEventTime: UInt16) {
        let current = CrankSample(revs: crankRevs, eventTime1024: crankEventTime)
        defer { lastCrankByPeripheral[peripheralID] = current }

        guard let previous = lastCrankByPeripheral[peripheralID] else { return }

        let deltaRevs = Int(crankRevs &- previous.revs)
        let deltaTimeTicks = Int(crankEventTime &- previous.eventTime1024)
        guard deltaRevs >= 0, deltaTimeTicks > 0 else { return }

        let rpm = Double(deltaRevs) * 60.0 * 1024.0 / Double(deltaTimeTicks)
        if rpm.isFinite, rpm >= 0, rpm <= 220 {
            liveCadenceRPM = rpm
        }
    }

    private func parseControlPointResponse(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 3 else { return }

        // FTMS response code: [0x80, requestOpCode, resultCode]
        if bytes[0] == 0x80 {
            let requestOp = bytes[1]
            let result = bytes[2]

            if requestOp == 0x00 {
                controlAcquired = (result == 0x01)
            }

            if result == 0x01 {
                if requestOp == 0x05 {
                    lastMessage = "ERG target applied"
                }
            } else {
                lastMessage = "Trainer command failed (op \(requestOp), code \(result))"
            }
        }
    }

    private struct SimulationPhase {
        var label: String
        var durationSec: Int
        var targetPower: Int
    }

    private func buildSimulationPhases(activity: Activity, fallbackFTPWatts: Int) -> [SimulationPhase] {
        let ftp = max(80, fallbackFTPWatts)

        if !activity.intervals.isEmpty {
            var phases: [SimulationPhase] = []
            for effort in activity.intervals {
                let duration = max(5, effort.durationSec)
                let rawPower = effort.actualPower ?? effort.targetPower ?? activity.normalizedPower ?? Int(Double(ftp) * 0.72)
                let target = max(60, min(1200, rawPower))
                phases.append(SimulationPhase(label: effort.name, durationSec: duration, targetPower: target))
            }
            if !phases.isEmpty { return phases }
        }

        let duration = max(120, activity.durationSec)
        let chunkSec = 45
        let chunkCount = max(1, Int(ceil(Double(duration) / Double(chunkSec))))
        let np = activity.normalizedPower ?? Int(Double(ftp) * 0.70)

        var phases: [SimulationPhase] = []
        phases.reserveCapacity(chunkCount)
        for index in 0..<chunkCount {
            let ratio = Double(index) / Double(max(1, chunkCount - 1))
            let waveA = sin(ratio * 2 * .pi * 3.2)
            let waveB = sin(ratio * 2 * .pi * 8.4)
            let surge = index % 16 < 2 ? 0.16 : 0
            let power = Double(np) * (1.0 + 0.09 * waveA + 0.04 * waveB + surge)
            let remaining = duration - index * chunkSec
            let phaseDuration = max(5, min(chunkSec, remaining))
            let target = max(60, min(1200, Int(power.rounded())))
            phases.append(SimulationPhase(label: "Segment \(index + 1)", durationSec: phaseDuration, targetPower: target))
        }
        return phases
    }

    private func mergedIndoorBikeData(
        current: IndoorBikeDataMeasurement,
        previous: IndoorBikeDataMeasurement?
    ) -> IndoorBikeDataMeasurement {
        IndoorBikeDataMeasurement(
            flags: current.flags,
            instantaneousSpeedKPH: current.instantaneousSpeedKPH ?? previous?.instantaneousSpeedKPH,
            averageSpeedKPH: current.averageSpeedKPH ?? previous?.averageSpeedKPH,
            instantaneousCadenceRPM: current.instantaneousCadenceRPM ?? previous?.instantaneousCadenceRPM,
            averageCadenceRPM: current.averageCadenceRPM ?? previous?.averageCadenceRPM,
            totalDistanceMeters: current.totalDistanceMeters ?? previous?.totalDistanceMeters,
            resistanceLevel: current.resistanceLevel ?? previous?.resistanceLevel,
            instantaneousPowerWatts: current.instantaneousPowerWatts ?? previous?.instantaneousPowerWatts,
            averagePowerWatts: current.averagePowerWatts ?? previous?.averagePowerWatts,
            totalEnergyKCal: current.totalEnergyKCal ?? previous?.totalEnergyKCal,
            energyPerHourKCal: current.energyPerHourKCal ?? previous?.energyPerHourKCal,
            energyPerMinuteKCal: current.energyPerMinuteKCal ?? previous?.energyPerMinuteKCal,
            heartRateBPM: current.heartRateBPM ?? previous?.heartRateBPM,
            metabolicEquivalent: current.metabolicEquivalent ?? previous?.metabolicEquivalent,
            elapsedTimeSec: current.elapsedTimeSec ?? previous?.elapsedTimeSec,
            remainingTimeSec: current.remainingTimeSec ?? previous?.remainingTimeSec
        )
    }

    private func mergedCyclingPowerMeasurement(
        current: CyclingPowerMeasurement,
        previous: CyclingPowerMeasurement?
    ) -> CyclingPowerMeasurement {
        CyclingPowerMeasurement(
            flags: current.flags,
            instantaneousPowerWatts: current.instantaneousPowerWatts,
            pedalPowerBalancePercent: current.pedalPowerBalancePercent ?? previous?.pedalPowerBalancePercent,
            pedalPowerBalanceReferenceIsRight: current.pedalPowerBalanceReferenceIsRight ?? previous?.pedalPowerBalanceReferenceIsRight,
            estimatedLeftBalancePercent: current.estimatedLeftBalancePercent ?? previous?.estimatedLeftBalancePercent,
            estimatedRightBalancePercent: current.estimatedRightBalancePercent ?? previous?.estimatedRightBalancePercent,
            accumulatedTorqueNm: current.accumulatedTorqueNm ?? previous?.accumulatedTorqueNm,
            accumulatedTorqueSource: current.accumulatedTorqueSource ?? previous?.accumulatedTorqueSource,
            cumulativeWheelRevolutions: current.cumulativeWheelRevolutions ?? previous?.cumulativeWheelRevolutions,
            lastWheelEventTime1024: current.lastWheelEventTime1024 ?? previous?.lastWheelEventTime1024,
            cumulativeCrankRevolutions: current.cumulativeCrankRevolutions ?? previous?.cumulativeCrankRevolutions,
            lastCrankEventTime1024: current.lastCrankEventTime1024 ?? previous?.lastCrankEventTime1024,
            maximumForceNewton: current.maximumForceNewton ?? previous?.maximumForceNewton,
            minimumForceNewton: current.minimumForceNewton ?? previous?.minimumForceNewton,
            maximumTorqueNm: current.maximumTorqueNm ?? previous?.maximumTorqueNm,
            minimumTorqueNm: current.minimumTorqueNm ?? previous?.minimumTorqueNm,
            maximumAngleDegrees: current.maximumAngleDegrees ?? previous?.maximumAngleDegrees,
            minimumAngleDegrees: current.minimumAngleDegrees ?? previous?.minimumAngleDegrees,
            topDeadSpotAngleDegrees: current.topDeadSpotAngleDegrees ?? previous?.topDeadSpotAngleDegrees,
            bottomDeadSpotAngleDegrees: current.bottomDeadSpotAngleDegrees ?? previous?.bottomDeadSpotAngleDegrees,
            accumulatedEnergyKJ: current.accumulatedEnergyKJ ?? previous?.accumulatedEnergyKJ,
            offsetCompensationIndicator: current.offsetCompensationIndicator
        )
    }
}

extension SmartTrainerManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bluetoothStateText = "Bluetooth On"
            lastMessage = "Ready"
            if pendingScanRequest {
                pendingScanRequest = false
                performScan()
            }
        case .poweredOff:
            bluetoothStateText = "Bluetooth Off"
            isScanning = false
            pendingScanRequest = false
        case .unauthorized:
            bluetoothStateText = "Bluetooth Unauthorized"
            isScanning = false
            pendingScanRequest = false
        case .unsupported:
            bluetoothStateText = "Bluetooth Unsupported"
            isScanning = false
            pendingScanRequest = false
        case .resetting:
            bluetoothStateText = "Bluetooth Resetting"
            isScanning = false
        case .unknown:
            bluetoothStateText = "Bluetooth Unknown"
            isScanning = false
        @unknown default:
            bluetoothStateText = "Bluetooth Unknown"
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []

        guard shouldKeepDiscoveredDevice(name: advName, serviceUUIDs: serviceUUIDs) else {
            return
        }

        peripherals[peripheral.identifier] = peripheral
        rssiByPeripheral[peripheral.identifier] = RSSI.intValue
        mergeCapability(peripheralID: peripheral.identifier, name: advName, serviceUUIDs: serviceUUIDs)
        refreshDiscoveredDevices()
        attemptAutoConnectIfNeeded(for: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        isConnected = true
        preferredAutoConnectDeviceID = peripheral.identifier
        connectedDeviceName = peripheral.name ?? "Trainer"
        connectedVendor = capabilityByPeripheral[peripheral.identifier]?.vendor ?? detectVendor(name: connectedDeviceName ?? "")
        peripheral.delegate = self

        peripheral.discoverServices([ftmsServiceUUID, cyclingPowerServiceUUID, cscServiceUUID])

        refreshDiscoveredDevices()
        lastMessage = "Connected to \(connectedDeviceName ?? "Trainer") [\(connectedVendor.label)]"
        onConnectedDeviceChanged?(peripheral.identifier, peripheral.name)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lastMessage = "Connect failed: \(error?.localizedDescription ?? "unknown")"
        resetConnectionState()
        refreshDiscoveredDevices()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let reason = error?.localizedDescription
        resetConnectionState()
        refreshDiscoveredDevices()
        lastMessage = reason == nil ? "Disconnected" : "Disconnected: \(reason!)"
    }
}

extension SmartTrainerManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lastMessage = "Discover services failed: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services else { return }
        for service in services {
            switch service.uuid {
            case ftmsServiceUUID:
                mergeCapability(peripheralID: peripheral.identifier, name: peripheral.name ?? "", serviceUUIDs: [ftmsServiceUUID])
                // Discover all FTMS characteristics so every readable field can be surfaced.
                peripheral.discoverCharacteristics(nil, for: service)
            case cyclingPowerServiceUUID:
                mergeCapability(peripheralID: peripheral.identifier, name: peripheral.name ?? "", serviceUUIDs: [cyclingPowerServiceUUID])
                peripheral.discoverCharacteristics([cyclingPowerMeasurementUUID], for: service)
            case cscServiceUUID:
                mergeCapability(peripheralID: peripheral.identifier, name: peripheral.name ?? "", serviceUUIDs: [cscServiceUUID])
                peripheral.discoverCharacteristics([cscMeasurementUUID], for: service)
            default:
                break
            }
        }

        refreshDiscoveredDevices()
        updateConnectionCapabilities(for: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            lastMessage = "Discover characteristics failed: \(error.localizedDescription)"
            return
        }

        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case indoorBikeDataUUID:
                indoorBikeDataCharacteristic = characteristic
            case trainingStatusUUID:
                trainingStatusCharacteristic = characteristic
            case controlPointUUID:
                controlPointCharacteristic = characteristic
            case fitnessMachineStatusUUID:
                fitnessMachineStatusCharacteristic = characteristic
            case fitnessMachineFeatureUUID:
                fitnessMachineFeatureCharacteristic = characteristic
            case supportedResistanceRangeUUID:
                supportedResistanceRangeCharacteristic = characteristic
            case supportedPowerRangeUUID:
                supportedPowerRangeCharacteristic = characteristic
            case cyclingPowerMeasurementUUID:
                cyclingPowerMeasurementCharacteristic = characteristic
            case cscMeasurementUUID:
                cscMeasurementCharacteristic = characteristic
            default:
                break
            }

            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }

            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        updateConnectionCapabilities(for: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lastMessage = "Read/notify failed: \(error.localizedDescription)"
            return
        }

        guard let data = characteristic.value else { return }

        if characteristic.service?.uuid == ftmsServiceUUID {
            updateFitnessMachineRawValue(uuid: characteristic.uuid, data: data)
            parseFitnessMachineReadValue(data, uuid: characteristic.uuid)
        }

        if characteristic.uuid == indoorBikeDataUUID {
            parseIndoorBikeData(data)
            return
        }

        if characteristic.uuid == trainingStatusUUID {
            parseTrainingStatus(data)
            return
        }

        if characteristic.uuid == cyclingPowerMeasurementUUID {
            parseCyclingPowerMeasurement(data, peripheralID: peripheral.identifier)
            return
        }

        if characteristic.uuid == cscMeasurementUUID {
            parseCSCMeasurement(data, peripheralID: peripheral.identifier)
            return
        }

        if characteristic.uuid == controlPointUUID {
            parseControlPointResponse(data)
            return
        }

        if characteristic.uuid == fitnessMachineStatusUUID {
            parseFitnessMachineStatus(data)
            if let status = liveFitnessMachineStatus {
                lastMessage = "Trainer status updated (0x\(String(format: "%02X", status.opCode)))"
            } else {
                lastMessage = "Trainer status updated"
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lastMessage = "Write failed: \(error.localizedDescription)"
        }

        writingControlPoint = false
        flushControlPointQueue()
    }
}
