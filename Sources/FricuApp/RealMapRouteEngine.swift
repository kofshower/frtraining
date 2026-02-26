import Foundation
import CoreLocation

fileprivate struct RealMapRawPoint {
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double?
}

struct RealMapRoutePoint: Codable, Identifiable {
    var id: Double { cumulativeDistanceKm }
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double?
    var cumulativeDistanceKm: Double
    var gradePercent: Double
}

struct RealMapRoute: Codable {
    var cacheKey: String
    var activityID: UUID
    var activityName: String
    var sourceType: String
    var createdAt: Date
    var points: [RealMapRoutePoint]
    var totalDistanceKm: Double
    var totalElevationGainM: Double

    var polylineCoordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    func distanceOnRoute(for totalDistanceKm: Double) -> Double {
        guard self.totalDistanceKm > 0 else { return 0 }
        let mod = totalDistanceKm.truncatingRemainder(dividingBy: self.totalDistanceKm)
        return mod >= 0 ? mod : (mod + self.totalDistanceKm)
    }

    func coordinate(at totalDistanceKm: Double) -> CLLocationCoordinate2D? {
        guard let point = interpolatedPoint(at: totalDistanceKm) else { return nil }
        return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    func grade(at totalDistanceKm: Double) -> Double {
        interpolatedPoint(at: totalDistanceKm)?.gradePercent ?? 0
    }

    func elevation(at totalDistanceKm: Double) -> Double? {
        interpolatedPoint(at: totalDistanceKm)?.altitudeMeters
    }

    var centerCoordinate: CLLocationCoordinate2D {
        guard !points.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        let lat = points.reduce(0) { $0 + $1.latitude } / Double(points.count)
        let lon = points.reduce(0) { $0 + $1.longitude } / Double(points.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var recommendedCameraDistanceMeters: Double {
        guard points.count >= 2 else { return 1200 }
        let minLat = points.map(\.latitude).min() ?? 0
        let maxLat = points.map(\.latitude).max() ?? 0
        let minLon = points.map(\.longitude).min() ?? 0
        let maxLon = points.map(\.longitude).max() ?? 0
        let spanMeters = Geo.haversineMeters(lat1: minLat, lon1: minLon, lat2: maxLat, lon2: maxLon)
        return min(max(spanMeters * 1.35, 900), 18_000)
    }

    private func interpolatedPoint(at totalDistanceKm: Double) -> RealMapRoutePoint? {
        guard points.count >= 2 else { return points.first }
        let routeDistance = distanceOnRoute(for: totalDistanceKm)
        guard
            let upperIndex = points.firstIndex(where: { $0.cumulativeDistanceKm >= routeDistance }),
            upperIndex > 0
        else {
            return points.last
        }
        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let span = max(0.000_001, upper.cumulativeDistanceKm - lower.cumulativeDistanceKm)
        let t = min(max((routeDistance - lower.cumulativeDistanceKm) / span, 0), 1)
        let latitude = lower.latitude + (upper.latitude - lower.latitude) * t
        let longitude = lower.longitude + (upper.longitude - lower.longitude) * t
        let altitude: Double?
        if let la = lower.altitudeMeters, let ua = upper.altitudeMeters {
            altitude = la + (ua - la) * t
        } else {
            altitude = lower.altitudeMeters ?? upper.altitudeMeters
        }
        let grade = lower.gradePercent + (upper.gradePercent - lower.gradePercent) * t
        return RealMapRoutePoint(
            latitude: latitude,
            longitude: longitude,
            altitudeMeters: altitude,
            cumulativeDistanceKm: routeDistance,
            gradePercent: grade
        )
    }
}

enum RealMapRouteError: LocalizedError {
    case noSourceFile
    case unsupportedFormat
    case routeNotFound

    var errorDescription: String? {
        switch self {
        case .noSourceFile:
            return L10n.choose(
                simplifiedChinese: "该活动没有可用原始文件（FIT/TCX/GPX）。",
                english: "This activity has no raw FIT/TCX/GPX source file."
            )
        case .unsupportedFormat:
            return L10n.choose(
                simplifiedChinese: "仅支持 FIT/TCX/GPX 作为真实地图路线来源。",
                english: "Only FIT/TCX/GPX files are supported for real-map routes."
            )
        case .routeNotFound:
            return L10n.choose(
                simplifiedChinese: "文件中未检测到可用 GPS 轨迹。",
                english: "No usable GPS track was found in the source file."
            )
        }
    }
}

enum RealMapRouteBuilder {
    static func route(for activity: Activity) throws -> RealMapRoute {
        let key = cacheKey(for: activity)
        if let cached = RealMapRouteCache.shared.route(forKey: key) {
            return cached
        }
        guard let encoded = activity.sourceFileBase64, let data = Data(base64Encoded: encoded) else {
            throw RealMapRouteError.noSourceFile
        }
        let fileType = activity.sourceFileType?.lowercased() ?? ""
        let raw: [RealMapRawPoint]
        switch fileType {
        case "fit":
            raw = try FITRoutePointParser.parse(data: data)
        case "tcx":
            raw = try TCXRoutePointParser.parse(data: data)
        case "gpx":
            raw = try GPXRoutePointParser.parse(data: data)
        default:
            throw RealMapRouteError.unsupportedFormat
        }

        let route = try buildRoute(
            cacheKey: key,
            activity: activity,
            sourceType: fileType,
            raw: raw
        )
        RealMapRouteCache.shared.store(route, forKey: key)
        return route
    }

    static func cacheKey(for activity: Activity) -> String {
        let sourceType = activity.sourceFileType?.lowercased() ?? "unknown"
        let byteCount = activity.sourceFileBase64?.count ?? 0
        let prefix = String((activity.sourceFileBase64 ?? "").prefix(96))
        return "\(activity.id.uuidString)|\(sourceType)|\(byteCount)|\(prefix)"
    }

    private static func buildRoute(
        cacheKey: String,
        activity: Activity,
        sourceType: String,
        raw: [RealMapRawPoint]
    ) throws -> RealMapRoute {
        let cleaned = sanitize(raw)
        guard cleaned.count >= 2 else {
            throw RealMapRouteError.routeNotFound
        }

        var points: [RealMapRoutePoint] = []
        points.reserveCapacity(cleaned.count)
        var distanceKm = 0.0
        var elevationGain = 0.0

        for index in cleaned.indices {
            if index > 0 {
                distanceKm += Geo.haversineMeters(
                    lat1: cleaned[index - 1].latitude,
                    lon1: cleaned[index - 1].longitude,
                    lat2: cleaned[index].latitude,
                    lon2: cleaned[index].longitude
                ) / 1000.0
                if
                    let prevAltitude = cleaned[index - 1].altitudeMeters,
                    let altitude = cleaned[index].altitudeMeters,
                    altitude > prevAltitude
                {
                    elevationGain += altitude - prevAltitude
                }
            }
            points.append(
                RealMapRoutePoint(
                    latitude: cleaned[index].latitude,
                    longitude: cleaned[index].longitude,
                    altitudeMeters: cleaned[index].altitudeMeters,
                    cumulativeDistanceKm: distanceKm,
                    gradePercent: 0
                )
            )
        }

        if points.count >= 2 {
            for index in 1..<points.count {
                let segmentDistanceM = max(
                    0.000_001,
                    (points[index].cumulativeDistanceKm - points[index - 1].cumulativeDistanceKm) * 1000.0
                )
                guard segmentDistanceM >= 3 else {
                    points[index].gradePercent = points[index - 1].gradePercent
                    continue
                }
                if
                    let prevAltitude = points[index - 1].altitudeMeters,
                    let altitude = points[index].altitudeMeters
                {
                    let rawGrade = ((altitude - prevAltitude) / segmentDistanceM) * 100.0
                    points[index].gradePercent = min(max(rawGrade, -18.0), 18.0)
                } else {
                    points[index].gradePercent = points[index - 1].gradePercent
                }
            }
            points[0].gradePercent = points[1].gradePercent
        }

        let totalDistanceKm = points.last?.cumulativeDistanceKm ?? 0
        guard totalDistanceKm >= 0.15 else {
            throw RealMapRouteError.routeNotFound
        }

        let activityName = activity.notes.isEmpty
            ? "\(activity.sport.label) \(activity.date.formatted(date: .abbreviated, time: .omitted))"
            : activity.notes
        return RealMapRoute(
            cacheKey: cacheKey,
            activityID: activity.id,
            activityName: activityName,
            sourceType: sourceType,
            createdAt: Date(),
            points: points,
            totalDistanceKm: totalDistanceKm,
            totalElevationGainM: max(0, elevationGain)
        )
    }

    private static func sanitize(_ raw: [RealMapRawPoint]) -> [RealMapRawPoint] {
        guard !raw.isEmpty else { return [] }
        var normalized: [RealMapRawPoint] = []
        normalized.reserveCapacity(raw.count)

        let maxPoints = 4_500
        let step = max(1, Int(ceil(Double(raw.count) / Double(maxPoints))))

        for (idx, point) in raw.enumerated() where idx % step == 0 || idx == raw.count - 1 {
            guard (-90...90).contains(point.latitude), (-180...180).contains(point.longitude) else {
                continue
            }
            if let last = normalized.last {
                let distM = Geo.haversineMeters(
                    lat1: last.latitude,
                    lon1: last.longitude,
                    lat2: point.latitude,
                    lon2: point.longitude
                )
                if distM < 1.5 {
                    continue
                }
            }
            normalized.append(point)
        }
        return normalized
    }
}

final class RealMapRouteCache {
    static let shared = RealMapRouteCache()

    private struct Envelope: Codable {
        var version: Int
        var routes: [String: RealMapRoute]
    }

    private let lock = NSLock()
    private var routesByKey: [String: RealMapRoute] = [:]
    private let fileURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = caches.appendingPathComponent("fricu-real-map-routes-v1.json")
        load()
    }

    func route(forKey key: String) -> RealMapRoute? {
        lock.lock()
        defer { lock.unlock() }
        return routesByKey[key]
    }

    func store(_ route: RealMapRoute, forKey key: String) {
        lock.lock()
        routesByKey[key] = route
        let snapshot = routesByKey
        lock.unlock()
        persist(snapshot: snapshot)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        lock.lock()
        routesByKey = envelope.routes
        lock.unlock()
    }

    private func persist(snapshot: [String: RealMapRoute]) {
        let envelope = Envelope(version: 1, routes: snapshot)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}

private enum GPXRoutePointParser {
    private final class Delegate: NSObject, XMLParserDelegate {
        private var stack: [String] = []
        private var textBuffer = ""
        private var inTrackPoint = false
        private var currentLatitude: Double?
        private var currentLongitude: Double?
        private var currentAltitude: Double?
        private var rows: [RealMapRawPoint] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String : String] = [:]
        ) {
            stack.append(elementName)
            textBuffer = ""
            if elementName.lowercased() == "trkpt" {
                inTrackPoint = true
                currentLatitude = Double(attributeDict["lat"] ?? "")
                currentLongitude = Double(attributeDict["lon"] ?? "")
                currentAltitude = nil
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textBuffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            let local = elementName.lowercased()
            if !value.isEmpty, inTrackPoint, local == "ele" {
                currentAltitude = Double(value)
            }
            if local == "trkpt" {
                inTrackPoint = false
                if let latitude = currentLatitude, let longitude = currentLongitude {
                    rows.append(
                        RealMapRawPoint(
                            latitude: latitude,
                            longitude: longitude,
                            altitudeMeters: currentAltitude
                        )
                    )
                }
            }
            _ = stack.popLast()
            textBuffer = ""
        }

        func points() -> [RealMapRawPoint] { rows }
    }

    static func parse(data: Data) throws -> [RealMapRawPoint] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ActivityImportError.parserFailed(
                parser.parserError?.localizedDescription ?? "GPX route parser failed"
            )
        }
        return delegate.points()
    }
}

private enum TCXRoutePointParser {
    private final class Delegate: NSObject, XMLParserDelegate {
        private var stack: [String] = []
        private var textBuffer = ""
        private var inTrackPoint = false
        private var inPosition = false
        private var currentLatitude: Double?
        private var currentLongitude: Double?
        private var currentAltitude: Double?
        private var rows: [RealMapRawPoint] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String : String] = [:]
        ) {
            stack.append(elementName)
            textBuffer = ""
            if elementName == "Trackpoint" {
                inTrackPoint = true
                currentLatitude = nil
                currentLongitude = nil
                currentAltitude = nil
            } else if elementName == "Position" {
                inPosition = true
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textBuffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, inTrackPoint {
                switch elementName {
                case "LatitudeDegrees":
                    if inPosition { currentLatitude = Double(value) }
                case "LongitudeDegrees":
                    if inPosition { currentLongitude = Double(value) }
                case "AltitudeMeters":
                    currentAltitude = Double(value)
                default:
                    break
                }
            }

            if elementName == "Position" {
                inPosition = false
            } else if elementName == "Trackpoint" {
                inTrackPoint = false
                if let latitude = currentLatitude, let longitude = currentLongitude {
                    rows.append(
                        RealMapRawPoint(
                            latitude: latitude,
                            longitude: longitude,
                            altitudeMeters: currentAltitude
                        )
                    )
                }
            }

            _ = stack.popLast()
            textBuffer = ""
        }

        func points() -> [RealMapRawPoint] { rows }
    }

    static func parse(data: Data) throws -> [RealMapRawPoint] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ActivityImportError.parserFailed(
                parser.parserError?.localizedDescription ?? "TCX route parser failed"
            )
        }
        return delegate.points()
    }
}

private enum FITRoutePointParser {
    private struct FieldDef {
        var number: Int
        var size: Int
        var baseType: UInt8
    }

    private struct MessageDef {
        var globalMessageNumber: Int
        var littleEndian: Bool
        var fields: [FieldDef]
    }

    private enum Value {
        case int(Int64)
        case uint(UInt64)
        case double(Double)
        case string(String)

        var int32Value: Int32? {
            switch self {
            case let .int(v):
                return Int32(clamping: v)
            case let .uint(v):
                guard v <= UInt64(UInt32.max) else { return nil }
                return Int32(bitPattern: UInt32(v))
            case let .double(v):
                return Int32(v)
            case .string:
                return nil
            }
        }

        var doubleValue: Double? {
            switch self {
            case let .int(v): return Double(v)
            case let .uint(v): return Double(v)
            case let .double(v): return v
            case .string: return nil
            }
        }
    }

    static func parse(data: Data) throws -> [RealMapRawPoint] {
        let bytes = [UInt8](data)
        guard bytes.count >= 14 else {
            throw ActivityImportError.parserFailed("FIT file too small")
        }
        let headerSize = Int(bytes[0])
        guard headerSize >= 12, bytes.count > headerSize else {
            throw ActivityImportError.parserFailed("Invalid FIT header")
        }
        let dataSize = Int(Byte.decodeUInt32LE(bytes, at: 4))
        let start = headerSize
        let end = min(bytes.count, start + dataSize)
        guard end > start else {
            throw ActivityImportError.parserFailed("FIT contains no data records")
        }

        var definitions: [Int: MessageDef] = [:]
        var cursor = start
        var lastTimestamp: UInt32?
        var rows: [RealMapRawPoint] = []

        while cursor < end {
            let header = bytes[cursor]
            cursor += 1

            if header & 0x80 != 0 {
                let localNum = Int((header >> 5) & 0x03)
                guard let definition = definitions[localNum] else {
                    throw ActivityImportError.parserFailed("FIT compressed header references missing definition")
                }
                var values = try decodeDataMessage(
                    definition: definition,
                    bytes: bytes,
                    cursor: &cursor,
                    end: end
                )
                if let last = lastTimestamp {
                    let offset = UInt32(header & 0x1F)
                    var reconstructed = (last & ~UInt32(0x1F)) + offset
                    if reconstructed < last { reconstructed += 0x20 }
                    lastTimestamp = reconstructed
                    values[253] = .uint(UInt64(reconstructed))
                }
                absorbRouteRecord(definition.globalMessageNumber, values: values, rows: &rows, lastTimestamp: &lastTimestamp)
                continue
            }

            let isDefinition = (header & 0x40) != 0
            let hasDeveloperFields = (header & 0x20) != 0
            let localNum = Int(header & 0x0F)

            if isDefinition {
                guard cursor + 5 <= end else {
                    throw ActivityImportError.parserFailed("FIT definition truncated")
                }
                let architecture = bytes[cursor + 1]
                let littleEndian = architecture == 0
                let globalNum: UInt16 = littleEndian
                    ? Byte.decodeUInt16LE(bytes, at: cursor + 2)
                    : Byte.decodeUInt16BE(bytes, at: cursor + 2)
                let fieldCount = Int(bytes[cursor + 4])
                cursor += 5

                var fields: [FieldDef] = []
                fields.reserveCapacity(fieldCount)
                for _ in 0..<fieldCount {
                    guard cursor + 3 <= end else {
                        throw ActivityImportError.parserFailed("FIT field definition truncated")
                    }
                    fields.append(
                        FieldDef(
                            number: Int(bytes[cursor]),
                            size: Int(bytes[cursor + 1]),
                            baseType: bytes[cursor + 2]
                        )
                    )
                    cursor += 3
                }

                if hasDeveloperFields {
                    guard cursor < end else {
                        throw ActivityImportError.parserFailed("FIT developer field definition truncated")
                    }
                    let devCount = Int(bytes[cursor])
                    cursor += 1
                    let bytesToSkip = devCount * 3
                    guard cursor + bytesToSkip <= end else {
                        throw ActivityImportError.parserFailed("FIT developer fields truncated")
                    }
                    cursor += bytesToSkip
                }

                definitions[localNum] = MessageDef(
                    globalMessageNumber: Int(globalNum),
                    littleEndian: littleEndian,
                    fields: fields
                )
            } else {
                guard let definition = definitions[localNum] else {
                    throw ActivityImportError.parserFailed("FIT data references missing local definition")
                }
                let values = try decodeDataMessage(
                    definition: definition,
                    bytes: bytes,
                    cursor: &cursor,
                    end: end
                )
                absorbRouteRecord(definition.globalMessageNumber, values: values, rows: &rows, lastTimestamp: &lastTimestamp)
            }
        }

        return rows
    }

    private static func absorbRouteRecord(
        _ globalMessageNumber: Int,
        values: [Int: Value],
        rows: inout [RealMapRawPoint],
        lastTimestamp: inout UInt32?
    ) {
        guard globalMessageNumber == 20 else { return }

        if case let .uint(raw)? = values[253] {
            lastTimestamp = UInt32(raw)
        } else if case let .int(raw)? = values[253], raw >= 0 {
            lastTimestamp = UInt32(raw)
        }

        guard
            let latRaw = values[0]?.int32Value,
            let lonRaw = values[1]?.int32Value
        else {
            return
        }
        let lat = Double(latRaw) * (180.0 / 2_147_483_648.0)
        let lon = Double(lonRaw) * (180.0 / 2_147_483_648.0)

        let altitude: Double? = {
            let raw = values[78]?.doubleValue ?? values[2]?.doubleValue
            guard let raw, raw.isFinite else { return nil }
            return raw / 5.0 - 500.0
        }()

        rows.append(
            RealMapRawPoint(
                latitude: lat,
                longitude: lon,
                altitudeMeters: altitude
            )
        )
    }

    private static func decodeDataMessage(
        definition: MessageDef,
        bytes: [UInt8],
        cursor: inout Int,
        end: Int
    ) throws -> [Int: Value] {
        var values: [Int: Value] = [:]
        for field in definition.fields {
            guard cursor + field.size <= end else {
                throw ActivityImportError.parserFailed("FIT data field truncated")
            }
            let fieldBytes = Array(bytes[cursor..<(cursor + field.size)])
            cursor += field.size
            if let decoded = decodeField(bytes: fieldBytes, baseType: field.baseType, littleEndian: definition.littleEndian) {
                values[field.number] = decoded
            }
        }
        return values
    }

    private static func decodeField(bytes: [UInt8], baseType: UInt8, littleEndian: Bool) -> Value? {
        let type = baseType & 0x1F
        switch type {
        case 0, 2, 10, 13:
            guard let first = bytes.first, first != 0xFF else { return nil }
            return .uint(UInt64(first))
        case 1:
            guard let first = bytes.first, first != 0x7F else { return nil }
            return .int(Int64(Int8(bitPattern: first)))
        case 7:
            let chars = bytes.prefix { $0 != 0 }
            guard !chars.isEmpty else { return nil }
            return .string(String(decoding: chars, as: UTF8.self))
        case 131:
            guard bytes.count >= 2 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt16LE(bytes, at: 0) : Byte.decodeUInt16BE(bytes, at: 0)
            if raw == 0x7FFF { return nil }
            return .int(Int64(Int16(bitPattern: raw)))
        case 132, 139:
            guard bytes.count >= 2 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt16LE(bytes, at: 0) : Byte.decodeUInt16BE(bytes, at: 0)
            if raw == 0xFFFF { return nil }
            return .uint(UInt64(raw))
        case 133:
            guard bytes.count >= 4 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt32LE(bytes, at: 0) : Byte.decodeUInt32BE(bytes, at: 0)
            if raw == 0x7FFFFFFF { return nil }
            return .int(Int64(Int32(bitPattern: raw)))
        case 134, 140:
            guard bytes.count >= 4 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt32LE(bytes, at: 0) : Byte.decodeUInt32BE(bytes, at: 0)
            if raw == 0xFFFFFFFF { return nil }
            return .uint(UInt64(raw))
        case 136:
            guard bytes.count >= 4 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt32LE(bytes, at: 0) : Byte.decodeUInt32BE(bytes, at: 0)
            return .double(Double(Float(bitPattern: raw)))
        case 137:
            guard bytes.count >= 8 else { return nil }
            let raw = littleEndian ? Byte.decodeUInt64LE(bytes, at: 0) : Byte.decodeUInt64BE(bytes, at: 0)
            return .double(Double(bitPattern: raw))
        default:
            return nil
        }
    }
}
