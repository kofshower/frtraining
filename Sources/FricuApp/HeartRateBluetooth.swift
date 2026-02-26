import Foundation
import CoreBluetooth
import FricuCore

struct HeartRateDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let isConnected: Bool
}

struct HeartRateTrendPoint: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

final class HeartRateMonitorManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothStateText: String = "Initializing"
    @Published private(set) var discoveredDevices: [HeartRateDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var liveHeartRateBPM: Int?
    @Published private(set) var oneMinuteAverageHeartRateBPM: Double?
    @Published private(set) var liveRRIntervalMS: Double?
    @Published private(set) var liveHRVRMSSDMS: Double?
    @Published private(set) var liveHRVSDNNMS: Double?
    @Published private(set) var liveHRVPNN50Percent: Double?
    @Published private(set) var liveHRVSampleCount: Int = 0
    @Published private(set) var rrTrendPoints: [HeartRateTrendPoint] = []
    @Published private(set) var hrvRMSSDTrendPoints: [HeartRateTrendPoint] = []
    @Published private(set) var energyTrendPoints: [HeartRateTrendPoint] = []
    @Published private(set) var liveEnergyExpendedKJ: Int?
    @Published private(set) var liveHeartRateMeasurement: HeartRateMeasurement?
    @Published private(set) var bodySensorLocation: HeartRateBodySensorLocation?
    @Published private(set) var controlPointAvailable = false
    @Published private(set) var heartRateRawCharacteristicHex: [String: String] = [:]
    @Published private(set) var lastMessage: String?
    var onConnectedDeviceChanged: ((UUID, String?) -> Void)?

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var rssiByPeripheral: [UUID: Int] = [:]
    private var pendingScanRequest = false
    private var preferredAutoConnectDeviceID: UUID?
    private var didAttemptAutoConnectForCurrentScan = false

    private var connectedPeripheral: CBPeripheral?
    private var heartRateMeasurementCharacteristic: CBCharacteristic?
    private var bodySensorLocationCharacteristic: CBCharacteristic?
    private var controlPointCharacteristic: CBCharacteristic?
    private var heartRateSamples: [(timestamp: Date, bpm: Int)] = []
    private var rrSamples: [(timestamp: Date, rrMS: Double)] = []
    private let trendWindowSeconds: TimeInterval = 10 * 60

    private let heartRateServiceUUID = CBUUID(string: "180D")
    private let heartRateMeasurementUUID = CBUUID(string: "2A37")
    private let bodySensorLocationUUID = CBUUID(string: "2A38")
    private let heartRateControlPointUUID = CBUUID(string: "2A39")

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
        lastMessage = "Connecting to \(peripheral.name ?? "HR Monitor")..."
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
        didAttemptAutoConnectForCurrentScan = false

        central.scanForPeripherals(withServices: [heartRateServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        lastMessage = "Scanning heart rate monitors..."
    }

    private func attemptAutoConnectIfNeeded(for peripheralID: UUID) {
        guard let targetID = preferredAutoConnectDeviceID else { return }
        guard !didAttemptAutoConnectForCurrentScan else { return }
        guard !isConnected else { return }
        guard peripheralID == targetID else { return }
        didAttemptAutoConnectForCurrentScan = true
        lastMessage = "Found preferred HR monitor, auto-connecting..."
        connect(deviceID: peripheralID)
    }

    private func refreshDiscoveredDevices() {
        discoveredDevices = peripherals.values.map { peripheral in
            HeartRateDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? "Unknown HR Monitor",
                rssi: rssiByPeripheral[peripheral.identifier] ?? -99,
                isConnected: peripheral.identifier == connectedPeripheral?.identifier
            )
        }
        .sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected && !rhs.isConnected }
            if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
            return lhs.name < rhs.name
        }
    }

    private func resetConnectionState() {
        connectedPeripheral = nil
        heartRateMeasurementCharacteristic = nil
        bodySensorLocationCharacteristic = nil
        controlPointCharacteristic = nil
        isConnected = false
        connectedDeviceName = nil
        liveHeartRateBPM = nil
        liveRRIntervalMS = nil
        liveHRVRMSSDMS = nil
        liveHRVSDNNMS = nil
        liveHRVPNN50Percent = nil
        liveHRVSampleCount = 0
        rrTrendPoints = []
        hrvRMSSDTrendPoints = []
        energyTrendPoints = []
        liveEnergyExpendedKJ = nil
        liveHeartRateMeasurement = nil
        bodySensorLocation = nil
        controlPointAvailable = false
        heartRateRawCharacteristicHex = [:]
        oneMinuteAverageHeartRateBPM = nil
        heartRateSamples = []
        rrSamples = []
    }

    private func recordHeartRateSample(_ bpm: Int, at timestamp: Date = Date()) {
        heartRateSamples.append((timestamp, bpm))

        let cutoff = timestamp.addingTimeInterval(-60)
        heartRateSamples.removeAll { $0.timestamp < cutoff }

        guard !heartRateSamples.isEmpty else {
            oneMinuteAverageHeartRateBPM = nil
            return
        }

        let sum = heartRateSamples.reduce(0) { $0 + $1.bpm }
        oneMinuteAverageHeartRateBPM = Double(sum) / Double(heartRateSamples.count)
    }

    private func parseHeartRateMeasurement(_ data: Data) {
        guard let rawMeasurement = HeartRateParsers.parseMeasurement(data) else { return }
        let measurement = mergedHeartRateMeasurement(current: rawMeasurement, previous: liveHeartRateMeasurement)
        liveHeartRateMeasurement = measurement
        liveHeartRateBPM = rawMeasurement.heartRateBPM

        if let latestRR = rawMeasurement.latestRRIntervalMS {
            liveRRIntervalMS = latestRR
            appendTrendPoint(value: latestRR, to: &rrTrendPoints)
        }
        recordRRIntervals(rawMeasurement.rrIntervalsMS)
        if let energy = rawMeasurement.energyExpendedKJ {
            liveEnergyExpendedKJ = energy
            appendTrendPoint(value: Double(energy), to: &energyTrendPoints)
        }
        recordHeartRateSample(rawMeasurement.heartRateBPM)
    }

    private func parseBodySensorLocation(_ data: Data) {
        guard let location = HeartRateParsers.parseBodySensorLocation(data) else { return }
        bodySensorLocation = location
    }

    private func updateRawCharacteristicHex(uuid: CBUUID, data: Data) {
        heartRateRawCharacteristicHex[uuid.uuidString.uppercased()] = data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func recordRRIntervals(_ rrIntervalsMS: [Double], at timestamp: Date = Date()) {
        guard !rrIntervalsMS.isEmpty else { return }
        rrSamples.append(contentsOf: rrIntervalsMS.map { (timestamp: timestamp, rrMS: $0) })

        let cutoff = timestamp.addingTimeInterval(-300)
        rrSamples.removeAll { $0.timestamp < cutoff }

        let metrics = HeartRateVariabilityMath.metrics(rrIntervalsMS: rrSamples.map(\.rrMS))
        liveHRVSampleCount = metrics?.sampleCount ?? 0
        liveHRVRMSSDMS = metrics?.rmssdMS
        liveHRVSDNNMS = metrics?.sdnnMS
        liveHRVPNN50Percent = metrics?.pnn50Percent
        if let rmssd = metrics?.rmssdMS {
            appendTrendPoint(value: rmssd, at: timestamp, to: &hrvRMSSDTrendPoints)
        }
    }

    private func appendTrendPoint(
        value: Double,
        at timestamp: Date = Date(),
        to points: inout [HeartRateTrendPoint]
    ) {
        points.append(.init(timestamp: timestamp, value: value))
        let cutoff = timestamp.addingTimeInterval(-trendWindowSeconds)
        points.removeAll { $0.timestamp < cutoff }
    }

    private func mergedHeartRateMeasurement(
        current: HeartRateMeasurement,
        previous: HeartRateMeasurement?
    ) -> HeartRateMeasurement {
        let previousRR1024 = previous?.rrIntervals1024 ?? []
        let previousRRMS = previous?.rrIntervalsMS ?? []
        let mergedRR1024 = current.rrIntervals1024.isEmpty ? previousRR1024 : current.rrIntervals1024
        let mergedRRMS = current.rrIntervalsMS.isEmpty ? previousRRMS : current.rrIntervalsMS

        return HeartRateMeasurement(
            flags: current.flags,
            heartRateBPM: current.heartRateBPM,
            valueIsUInt16: current.valueIsUInt16,
            sensorContactSupported: current.sensorContactSupported,
            sensorContactDetected: current.sensorContactDetected,
            energyExpendedKJ: current.energyExpendedKJ ?? previous?.energyExpendedKJ,
            rrIntervals1024: mergedRR1024,
            rrIntervalsMS: mergedRRMS,
            latestRRIntervalMS: current.latestRRIntervalMS ?? previous?.latestRRIntervalMS
        )
    }
}

extension HeartRateMonitorManager: CBCentralManagerDelegate {
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
        peripherals[peripheral.identifier] = peripheral
        rssiByPeripheral[peripheral.identifier] = RSSI.intValue
        refreshDiscoveredDevices()
        attemptAutoConnectIfNeeded(for: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        preferredAutoConnectDeviceID = peripheral.identifier
        connectedDeviceName = peripheral.name ?? "HR Monitor"
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices([heartRateServiceUUID])
        refreshDiscoveredDevices()
        lastMessage = "Connected to \(connectedDeviceName ?? "HR Monitor")"
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

extension HeartRateMonitorManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lastMessage = "Discover services failed: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services else { return }
        for service in services where service.uuid == heartRateServiceUUID {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            lastMessage = "Discover characteristics failed: \(error.localizedDescription)"
            return
        }

        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case heartRateMeasurementUUID:
                heartRateMeasurementCharacteristic = characteristic
            case bodySensorLocationUUID:
                bodySensorLocationCharacteristic = characteristic
            case heartRateControlPointUUID:
                controlPointCharacteristic = characteristic
                let writable = characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)
                controlPointAvailable = writable
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
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lastMessage = "Read/notify failed: \(error.localizedDescription)"
            return
        }

        guard let data = characteristic.value else { return }

        if characteristic.service?.uuid == heartRateServiceUUID {
            updateRawCharacteristicHex(uuid: characteristic.uuid, data: data)
        }

        if characteristic.uuid == heartRateMeasurementUUID {
            parseHeartRateMeasurement(data)
            return
        }

        if characteristic.uuid == bodySensorLocationUUID {
            parseBodySensorLocation(data)
            return
        }
    }
}
