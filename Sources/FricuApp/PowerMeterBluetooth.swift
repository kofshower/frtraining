import Foundation
import CoreBluetooth
import FricuCore

struct PowerMeterDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let isConnected: Bool
}

final class PowerMeterManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothStateText: String = "Initializing"
    @Published private(set) var discoveredDevices: [PowerMeterDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var livePowerWatts: Int?
    @Published private(set) var liveCadenceRPM: Double?
    @Published private(set) var liveLeftBalancePercent: Double?
    @Published private(set) var liveRightBalancePercent: Double?
    @Published private(set) var liveCyclingPowerMeasurement: CyclingPowerMeasurement?
    @Published private(set) var lastMessage: String?
    var onConnectedDeviceChanged: ((UUID, String?) -> Void)?

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var rssiByPeripheral: [UUID: Int] = [:]
    private var pendingScanRequest = false
    private var preferredAutoConnectDeviceID: UUID?
    private var didAttemptAutoConnectForCurrentScan = false

    private var connectedPeripheral: CBPeripheral?
    private var measurementCharacteristic: CBCharacteristic?

    private struct CrankSample {
        let revs: UInt16
        let eventTime1024: UInt16
    }
    private var lastCrankSample: CrankSample?

    private let cyclingPowerServiceUUID = CBUUID(string: "1818")
    private let cyclingPowerMeasurementUUID = CBUUID(string: "2A63")

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
        lastMessage = "Connecting to \(peripheral.name ?? "Power Meter")..."
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

        central.scanForPeripherals(
            withServices: [cyclingPowerServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        isScanning = true
        lastMessage = "Scanning power meters..."
    }

    private func attemptAutoConnectIfNeeded(for peripheralID: UUID) {
        guard let targetID = preferredAutoConnectDeviceID else { return }
        guard !didAttemptAutoConnectForCurrentScan else { return }
        guard !isConnected else { return }
        guard peripheralID == targetID else { return }
        didAttemptAutoConnectForCurrentScan = true
        lastMessage = "Found preferred power meter, auto-connecting..."
        connect(deviceID: peripheralID)
    }

    private func refreshDiscoveredDevices() {
        discoveredDevices = peripherals.values.map { peripheral in
            PowerMeterDevice(
                id: peripheral.identifier,
                name: peripheral.name ?? "Unknown Power Meter",
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
        measurementCharacteristic = nil
        isConnected = false
        connectedDeviceName = nil
        livePowerWatts = nil
        liveCadenceRPM = nil
        liveLeftBalancePercent = nil
        liveRightBalancePercent = nil
        liveCyclingPowerMeasurement = nil
        lastCrankSample = nil
    }

    private func parseMeasurement(_ data: Data) {
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
            updateCadence(crankRevs: crankRevs, crankEventTime: crankEventTime)
        }
    }

    private func updateCadence(crankRevs: UInt16, crankEventTime: UInt16) {
        let current = CrankSample(revs: crankRevs, eventTime1024: crankEventTime)
        defer { lastCrankSample = current }
        guard let previous = lastCrankSample else { return }

        let deltaRevs = Int(crankRevs &- previous.revs)
        let deltaTimeTicks = Int(crankEventTime &- previous.eventTime1024)
        guard deltaRevs >= 0, deltaTimeTicks > 0 else { return }

        let rpm = Double(deltaRevs) * 60.0 * 1024.0 / Double(deltaTimeTicks)
        if rpm.isFinite, rpm >= 0, rpm <= 220 {
            liveCadenceRPM = rpm
        }
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

extension PowerMeterManager: CBCentralManagerDelegate {
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
        connectedDeviceName = peripheral.name ?? "Power Meter"
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices([cyclingPowerServiceUUID])
        refreshDiscoveredDevices()
        lastMessage = "Connected to \(connectedDeviceName ?? "Power Meter")"
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

extension PowerMeterManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lastMessage = "Discover services failed: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services else { return }
        for service in services where service.uuid == cyclingPowerServiceUUID {
            peripheral.discoverCharacteristics([cyclingPowerMeasurementUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            lastMessage = "Discover characteristics failed: \(error.localizedDescription)"
            return
        }

        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == cyclingPowerMeasurementUUID {
            measurementCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lastMessage = "Read/notify failed: \(error.localizedDescription)"
            return
        }

        guard characteristic.uuid == cyclingPowerMeasurementUUID,
              let data = characteristic.value else { return }
        parseMeasurement(data)
    }
}
