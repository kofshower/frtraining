import SwiftUI

#if canImport(RealityKit)
import RealityKit
#if canImport(AppKit)
import AppKit
private typealias RKPlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
private typealias RKPlatformColor = UIColor
#endif

#if canImport(AppKit)
private final class WhooshCameraInputNSView: NSView {
    var onScrollDelta: ((CGFloat) -> Void)?
    var onMagnifyDelta: ((CGFloat) -> Void)?
    var onDragDelta: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?
    private var lastDragPoint: NSPoint?

    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        onScrollDelta?(event.scrollingDeltaY)
    }

    override func magnify(with event: NSEvent) {
        onMagnifyDelta?(event.magnification)
    }

    override func mouseDown(with event: NSEvent) {
        lastDragPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let last = lastDragPoint ?? p
        lastDragPoint = p
        onDragDelta?(CGSize(width: p.x - last.x, height: p.y - last.y))
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPoint = nil
        onDragEnded?()
    }
}

private struct WhooshMacCameraInputOverlay: NSViewRepresentable {
    let onScrollDelta: (CGFloat) -> Void
    let onMagnifyDelta: (CGFloat) -> Void
    let onDragDelta: (CGSize) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> WhooshCameraInputNSView {
        let v = WhooshCameraInputNSView(frame: .zero)
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        v.onScrollDelta = onScrollDelta
        v.onMagnifyDelta = onMagnifyDelta
        v.onDragDelta = onDragDelta
        v.onDragEnded = onDragEnded
        return v
    }

    func updateNSView(_ nsView: WhooshCameraInputNSView, context: Context) {
        nsView.onScrollDelta = onScrollDelta
        nsView.onMagnifyDelta = onMagnifyDelta
        nsView.onDragDelta = onDragDelta
        nsView.onDragEnded = onDragEnded
    }
}
#endif

enum WhooshPlayerModelQualityMode: String, CaseIterable, Identifiable {
    case high
    case low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high:
            return L10n.choose(simplifiedChinese: "高模", english: "High Poly")
        case .low:
            return L10n.choose(simplifiedChinese: "低模", english: "Low Poly")
        }
    }
}

@MainActor
final class WhooshRealitySceneModel: ObservableObject {
    enum ModelBannerStyle {
        case info
        case warning
    }

    private struct FallbackRunnerPartRefs {
        let body: Entity?
        let torsoTop: Entity?
        let head: Entity?
        let legL: Entity?
        let legR: Entity?
        let armL: Entity?
        let armR: Entity?
    }

    let root = Entity()
    var isSetup = false
    private var riderEntities: [String: Entity] = [:]
    private var roadSegments: [ModelEntity] = []
    private var roadBaseBeds: [ModelEntity] = []
    private var laneStripes: [ModelEntity] = []
    private var roadShoulders: [ModelEntity] = []
    private var vergeStrips: [ModelEntity] = []
    private var edgeLines: [ModelEntity] = []
    private var guardRails: [ModelEntity] = []
    private var routeSigns: [Entity] = []
    private var routeArches: [Entity] = []
    private var routeLengthKm: Double = 1
    private var routeSamples3D: [SIMD3<Float>] = []
    private var routeProgressSamples: [Float] = []
    private let cameraRig = Entity()
    private let cameraEntity = Entity()
    private var smoothedCameraEye: SIMD3<Float>?
    private var smoothedCameraTarget: SIMD3<Float>?
    private var riderWorldPositionByID: [String: SIMD3<Float>] = [:]
    private var riderStridePhaseByID: [String: Float] = [:]
    private var riderLastDistanceKmByID: [String: Double] = [:]
    private var riderLastFrameTimeByID: [String: TimeInterval] = [:]
    private var riderLastAnimationFrameTimeByID: [String: TimeInterval] = [:]
    private var smoothedRiderDistanceKmByID: [String: Double] = [:]
    private var latestRiders: [Whoosh3DRiderSnapshot] = []
    private var riderAssignedModelIDByID: [String: String] = [:]
    private var riderAppliedModelIDByID: [String: String] = [:]
    private var riderUsesFallbackRunnerByID: [String: Bool] = [:]
    private var riderVisualEntityByID: [String: Entity] = [:]
    private var riderVisualBasePositionByID: [String: SIMD3<Float>] = [:]
    private var riderVisualBaseOrientationByID: [String: simd_quatf] = [:]
    private var riderImportedAnimationStartAttemptedByID: Set<String> = []
    private var fallbackRunnerPartsByRiderID: [String: FallbackRunnerPartRefs] = [:]
    private var loadedRunnerTemplateByModelID: [String: Entity] = [:]
    private var loadingRunnerModelIDs: Set<String> = []
    private var modelLoadFailureReasonByModelID: [String: String] = [:]
    private var activeRunnerModelPoolIDs: [String] = []
    private var activeRunnerModelPoolPlayerID: String = ""
    private var cachedPacerAnchors: [WhooshWorldLabelAnchor] = []
    private var lastPacerAnchorProjectionAt: TimeInterval = 0
    private var lastPacerAnchorSignature: Int = 0
    private var reduceRailAndEdgeLODForSideCamera = false
    private var reduceRouteSegmentsForFarCamera = false
    private var playerModelQualityMode: WhooshPlayerModelQualityMode = .high
    private var activeRoadWidthMeters: Float = 1.1
    private var activeGuardRailHeightMeters: Float = 0.24
    private var lastProfileSignature: Int = 0
    private var currentPlayerSpeedKPH: Double = 0
    private var lastHandledRecenterToken: Int = 0
    @Published private(set) var modelBannerText: String?
    @Published private(set) var modelBannerStyle: ModelBannerStyle = .info
    // Keep this empty by default. Unusable models are handled dynamically via load failures.
    private let blockedRunnerModelIDs: Set<String> = []

    func buildBaseSceneIfNeeded() {
        guard !isSetup else { return }

        let ground = ModelEntity(
            mesh: .generateBox(size: [220, 0.25, 220]),
            materials: [SimpleMaterial(color: RKPlatformColor(red: 0.36, green: 0.47, blue: 0.35, alpha: 1), isMetallic: false)]
        )
        ground.position = [0, -0.15, 0]
        root.addChild(ground)

        addBackgroundScenery()

        var cameraComp = PerspectiveCameraComponent()
        cameraComp.fieldOfViewInDegrees = 62
        cameraEntity.components.set(cameraComp)
        cameraRig.addChild(cameraEntity)
        root.addChild(cameraRig)

        isSetup = true
    }

    private func addBackgroundScenery() {
        let meadowColors: [RKPlatformColor] = [
            RKPlatformColor(red: 0.34, green: 0.46, blue: 0.33, alpha: 1),
            RKPlatformColor(red: 0.38, green: 0.52, blue: 0.37, alpha: 1),
            RKPlatformColor(red: 0.31, green: 0.43, blue: 0.31, alpha: 1)
        ]
        for (idx, color) in meadowColors.enumerated() {
            let patch = ModelEntity(
                mesh: .generateBox(size: [180 - Float(idx * 24), 0.04, 86 - Float(idx * 10)]),
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            patch.position = [Float(idx * 8 - 12), -0.01 + Float(idx) * 0.01, -Float(idx * 18 + 6)]
            patch.orientation = simd_quatf(angle: Float(idx) * 0.08 - 0.06, axis: [0, 1, 0])
            root.addChild(patch)
        }

        let ridgeSpecs: [(SIMD3<Float>, SIMD3<Float>, RKPlatformColor)] = [
            ([0, 6.8, -40], [220, 14, 72], RKPlatformColor(red: 0.30, green: 0.39, blue: 0.31, alpha: 1)),
            ([-14, 11.5, -63], [250, 20, 62], RKPlatformColor(red: 0.26, green: 0.34, blue: 0.28, alpha: 1)),
            ([18, 17.5, -88], [300, 28, 55], RKPlatformColor(red: 0.22, green: 0.29, blue: 0.24, alpha: 0.98))
        ]
        for (pos, size, color) in ridgeSpecs {
            let ridge = ModelEntity(
                mesh: .generateBox(size: size),
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            ridge.position = pos
            ridge.orientation = simd_quatf(angle: 0.04, axis: [0, 1, 0])
            root.addChild(ridge)
        }

        // Soft haze bands help separate road from horizon with low render cost.
        for i in 0..<2 {
            let haze = ModelEntity(
                mesh: .generateBox(size: [240 + Float(i * 40), 3.0, 0.3]),
                materials: [SimpleMaterial(color: RKPlatformColor(red: 0.78, green: 0.86, blue: 0.83, alpha: 0.18), isMetallic: false)]
            )
            haze.position = [0, 4.8 + Float(i) * 2.4, -32 - Float(i) * 18]
            root.addChild(haze)
        }

        // Low-count tree line for background depth (kept sparse to avoid frame drops).
        for i in 0..<10 {
            let cluster = Entity()
            let trunk = ModelEntity(
                mesh: .generateBox(size: [0.20, 1.2, 0.20]),
                materials: [SimpleMaterial(color: RKPlatformColor(red: 0.33, green: 0.23, blue: 0.16, alpha: 1), isMetallic: false)]
            )
            trunk.position = [0, 0.6, 0]
            cluster.addChild(trunk)

            let crown = ModelEntity(
                mesh: .generateSphere(radius: 0.72 + Float(i % 3) * 0.08),
                materials: [SimpleMaterial(color: RKPlatformColor(red: 0.25, green: 0.41 + CGFloat(i % 2) * 0.03, blue: 0.25, alpha: 1), isMetallic: false)]
            )
            crown.position = [0, 1.65, 0]
            crown.scale = [1.0, 0.82, 1.0]
            cluster.addChild(crown)

            let x = -62.0 + Float(i) * 13.8
            let z = -18.0 - Float((i * 7) % 5) * 9.0
            cluster.position = [x, 0.0, z]
            cluster.orientation = simd_quatf(angle: Float(i) * 0.21, axis: [0, 1, 0])
            root.addChild(cluster)
        }
    }

    var cameraTargetEntity: Entity { cameraEntity }

    func update(
        profile: [Whoosh3DProfilePoint],
        totalDistanceKm: Double,
        riders: [Whoosh3DRiderSnapshot],
        followPlayer: Bool,
        cameraMode: Whoosh3DCameraMode,
        cameraZoom: Double,
        recenterToken: Int,
        freeCameraEnabled: Bool,
        freeCameraYaw: Double,
        freeCameraPitch: Double,
        roadWidthMeters: Double,
        guardRailHeightMeters: Double,
        playerRunnerModelID: String,
        playerModelQualityMode: WhooshPlayerModelQualityMode,
        frameTime: TimeInterval,
        playerSpeedKPH: Double
    ) {
        latestRiders = riders
        currentPlayerSpeedKPH = max(0, playerSpeedKPH)
        self.playerModelQualityMode = playerModelQualityMode
        if recenterToken != lastHandledRecenterToken {
            lastHandledRecenterToken = recenterToken
            smoothedCameraEye = nil
            smoothedCameraTarget = nil
            lastPacerAnchorSignature = 0
            lastPacerAnchorProjectionAt = 0
        }
        routeLengthKm = max(0.1, totalDistanceKm)
        let resolvedPlayerModelID = resolvedRunnerModelID(preferredID: playerRunnerModelID)
        ensureRunnerModelPool(playerModelID: resolvedPlayerModelID)
        if playerModelQualityMode == .high {
            scheduleRunnerModelLoadIfNeeded(modelID: resolvedPlayerModelID)
        }
        // Preload bot model pool so pacers swap out of fallback promptly instead of staying low-poly.
        for modelID in activeRunnerModelPoolIDs where modelID.caseInsensitiveCompare(resolvedPlayerModelID) != .orderedSame {
            scheduleRunnerModelLoadIfNeeded(modelID: modelID)
        }
        let reducedLOD = (cameraMode == .side)
        if reduceRailAndEdgeLODForSideCamera != reducedLOD {
            reduceRailAndEdgeLODForSideCamera = reducedLOD
            lastProfileSignature = 0
        }
        let reducedRouteSegments = (cameraMode == .front || cameraMode == .overhead)
        if reduceRouteSegmentsForFarCamera != reducedRouteSegments {
            reduceRouteSegmentsForFarCamera = reducedRouteSegments
            lastProfileSignature = 0
        }
        let clampedRoad = Float(min(max(roadWidthMeters, 0.8), 2.4))
        let clampedRail = Float(min(max(guardRailHeightMeters, 0.12), 0.9))
        if abs(activeRoadWidthMeters - clampedRoad) > 0.0001 || abs(activeGuardRailHeightMeters - clampedRail) > 0.0001 {
            activeRoadWidthMeters = clampedRoad
            activeGuardRailHeightMeters = clampedRail
            lastProfileSignature = 0 // force rebuild
        }
        rebuildRouteIfNeeded(profile: profile)
        syncRiders(riders, playerRunnerModelID: resolvedPlayerModelID, frameTime: frameTime)
        if followPlayer {
            if freeCameraEnabled {
                updateFreeOrbitCamera(
                    riders: riders,
                    cameraMode: cameraMode,
                    cameraZoom: cameraZoom,
                    yawOffset: freeCameraYaw,
                    pitchOffset: freeCameraPitch
                )
            } else {
                updateCamera(riders: riders, cameraMode: cameraMode, cameraZoom: cameraZoom)
            }
        } else {
            updateStaticCamera(cameraZoom: cameraZoom)
        }
        refreshModelBanner(playerModelID: resolvedPlayerModelID, riders: riders)
    }

    private func rebuildRouteIfNeeded(profile: [Whoosh3DProfilePoint]) {
        guard !profile.isEmpty else { return }
        let segmentCap = reduceRouteSegmentsForFarCamera ? 48 : 72
        let expected = max(1, min(profile.count - 1, segmentCap))
        let signature = routeSignature(profile: profile, expectedSegments: expected)
        if roadSegments.count == expected, lastProfileSignature == signature { return }
        lastProfileSignature = signature

        roadSegments.forEach { $0.removeFromParent() }
        roadSegments.removeAll()
        roadBaseBeds.forEach { $0.removeFromParent() }
        roadBaseBeds.removeAll()
        laneStripes.forEach { $0.removeFromParent() }
        laneStripes.removeAll()
        roadShoulders.forEach { $0.removeFromParent() }
        roadShoulders.removeAll()
        vergeStrips.forEach { $0.removeFromParent() }
        vergeStrips.removeAll()
        edgeLines.forEach { $0.removeFromParent() }
        edgeLines.removeAll()
        guardRails.forEach { $0.removeFromParent() }
        guardRails.removeAll()
        routeSigns.forEach { $0.removeFromParent() }
        routeSigns.removeAll()
        routeArches.forEach { $0.removeFromParent() }
        routeArches.removeAll()
        routeSamples3D.removeAll()
        routeProgressSamples.removeAll()

        let samples = sampledProfile(profile, limitSegments: expected + 1)
        guard samples.count >= 2 else { return }

        let roadBaseMaterial = SimpleMaterial(color: RKPlatformColor(red: 0.23, green: 0.24, blue: 0.26, alpha: 1), isMetallic: false)
        let roadMaterial = SimpleMaterial(color: RKPlatformColor(red: 0.31, green: 0.33, blue: 0.36, alpha: 1), isMetallic: false)
        let shoulderMaterial = SimpleMaterial(color: RKPlatformColor(red: 0.44, green: 0.45, blue: 0.44, alpha: 1), isMetallic: false)
        let vergeMaterial = SimpleMaterial(color: RKPlatformColor(red: 0.47, green: 0.39, blue: 0.29, alpha: 0.95), isMetallic: false)
        let laneMaterial = SimpleMaterial(color: RKPlatformColor(red: 0.96, green: 0.91, blue: 0.52, alpha: 0.98), isMetallic: false)
        let edgeLineMaterial = SimpleMaterial(color: RKPlatformColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 0.98), isMetallic: false)
        let railMaterial = SimpleMaterial(color: RKPlatformColor(red: 0.68, green: 0.71, blue: 0.74, alpha: 0.95), isMetallic: false)
        let roadWidth = activeRoadWidthMeters
        let shoulderWidth = roadWidth + 0.28
        let baseBedWidth = roadWidth + 0.62
        let vergeWidth = roadWidth + 1.08
        let railHeight = activeGuardRailHeightMeters
        let railOffset = vergeWidth * 0.5 + 0.10
        let edgeLineWidth: Float = 0.05
        let edgeLineInset = max(0.035, roadWidth * 0.045)
        let segmentOverlap: Float = 0.22
        routeSamples3D = buildCurvedRouteSamples(from: samples)
        routeProgressSamples = routeSamples3D.enumerated().map { index, _ in
            Float(index) / Float(max(1, routeSamples3D.count - 1))
        }

        for idx in 1..<samples.count {
            let p0 = routeSamples3D[idx - 1]
            let p1 = routeSamples3D[idx]
            let d = p1 - p0
            let length = max(0.3, simd_length(d))
            let segOrientation = orientation(forSegmentFrom: p0, to: p1)
            let forward = simd_normalize(p1 - p0)
            let side = normalizedOrFallback(simd_cross([0, 1, 0], forward), fallback: [1, 0, 0])
            let mid = (p0 + p1) * 0.5

            let verge = ModelEntity(
                mesh: .generateBox(size: [vergeWidth, 0.035, length + segmentOverlap + 0.18]),
                materials: [vergeMaterial]
            )
            verge.position = mid + [0, 0.008, 0]
            verge.orientation = segOrientation
            root.addChild(verge)
            vergeStrips.append(verge)

            let baseBed = ModelEntity(
                mesh: .generateBox(size: [baseBedWidth, 0.05, length + segmentOverlap + 0.10]),
                materials: [roadBaseMaterial]
            )
            baseBed.position = mid + [0, 0.023, 0]
            baseBed.orientation = segOrientation
            root.addChild(baseBed)
            roadBaseBeds.append(baseBed)

            let seg = ModelEntity(
                mesh: .generateBox(size: [roadWidth, 0.038, length + segmentOverlap]),
                materials: [roadMaterial]
            )
            seg.position = mid + [0, 0.046, 0]
            seg.orientation = segOrientation
            root.addChild(seg)
            roadSegments.append(seg)

            let shoulder = ModelEntity(
                mesh: .generateBox(size: [shoulderWidth, 0.022, length + segmentOverlap + 0.05]),
                materials: [shoulderMaterial]
            )
            shoulder.position = mid + [0, 0.036, 0]
            shoulder.orientation = segOrientation
            root.addChild(shoulder)
            roadShoulders.append(shoulder)

            let drawRailsAndEdgesForThisSegment = !reduceRailAndEdgeLODForSideCamera || (idx % 2 == 0)
            if drawRailsAndEdgesForThisSegment {
                for lineSide: Float in [-1, 1] {
                    let edge = ModelEntity(
                        mesh: .generateBox(size: [edgeLineWidth, 0.004, max(0.22, (length + segmentOverlap) * 0.92)]),
                        materials: [edgeLineMaterial]
                    )
                    edge.position = seg.position + side * (lineSide * (roadWidth * 0.5 - edgeLineInset)) + [0, 0.018, 0]
                    edge.orientation = segOrientation
                    root.addChild(edge)
                    edgeLines.append(edge)
                }

                // Guard rails (left/right) to improve route readability.
                for railSide: Float in [-1, 1] {
                    let rail = ModelEntity(
                        mesh: .generateBox(size: [0.05, railHeight, max(0.25, length + segmentOverlap)]),
                        materials: [railMaterial]
                    )
                    rail.position = mid + side * (railSide * railOffset) + [0, railHeight * 0.5 + 0.05, 0]
                    rail.orientation = segOrientation
                    root.addChild(rail)
                    guardRails.append(rail)
                }
            }

            if idx % 3 == 0 {
                let stripe = ModelEntity(
                    mesh: .generateBox(size: [0.06, 0.004, max(0.20, length * 0.42)]),
                    materials: [laneMaterial]
                )
                stripe.position = seg.position + [0, 0.018, 0]
                stripe.orientation = seg.orientation
                root.addChild(stripe)
                laneStripes.append(stripe)
            }

            // Keep RealityKit scene visually clean: no roadside signs/arches in the simplified renderer.
        }
    }

    private func routeSignature(profile: [Whoosh3DProfilePoint], expectedSegments: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(profile.count)
        hasher.combine(expectedSegments)
        if let first = profile.first {
            hasher.combine(Int(first.distanceKm * 100))
            hasher.combine(Int(first.elevationM * 10))
        }
        if let last = profile.last {
            hasher.combine(Int(last.distanceKm * 100))
            hasher.combine(Int(last.elevationM * 10))
        }
        hasher.combine(Int(activeRoadWidthMeters * 100))
        hasher.combine(Int(activeGuardRailHeightMeters * 100))
        hasher.combine(reduceRailAndEdgeLODForSideCamera)
        hasher.combine(reduceRouteSegmentsForFarCamera)
        return hasher.finalize()
    }

    private func syncRiders(_ riders: [Whoosh3DRiderSnapshot], playerRunnerModelID: String, frameTime: TimeInterval) {
        let playerDistance = riders.first(where: \.isPlayer)?.distanceKm ?? 0
        let visiblePacers: [Whoosh3DRiderSnapshot] = Array(riders
            .filter { !$0.isPlayer }
            .sorted { abs($0.distanceKm - playerDistance) < abs($1.distanceKm - playerDistance) }
            .prefix(3))
        let importedPacerIDs = Set(visiblePacers.map(\.id))
        var visibleRiderIDs = Set<String>()
        if let player = riders.first(where: \.isPlayer) {
            visibleRiderIDs.insert(player.id)
        }
        for pacer in visiblePacers {
            visibleRiderIDs.insert(pacer.id)
        }
        let renderRiders = riders.filter { visibleRiderIDs.contains($0.id) }
        let activeIDs = Set(renderRiders.map { $0.id })
        let resolvedPlayerModelID = playerRunnerModelID

        for rider in renderRiders {
            let usesPlayerModel = rider.isPlayer
            let targetModelID = usesPlayerModel
                ? resolvedPlayerModelID
                : resolvedBotRenderableModelID(for: rider.id, excluding: resolvedPlayerModelID)

            let existing = riderEntities[rider.id]
            let shouldRebuild = existing == nil || riderAppliedModelIDByID[rider.id]?.caseInsensitiveCompare(targetModelID) != .orderedSame
            let entity: Entity
            if shouldRebuild {
                existing?.removeFromParent()
                let rebuilt = makeRiderEntity(
                    rider: rider,
                    preferredModelID: targetModelID,
                    allowImportedModelForPacer: (!rider.isPlayer && importedPacerIDs.contains(rider.id))
                )
                riderAppliedModelIDByID[rider.id] = targetModelID
                riderEntities[rider.id] = rebuilt
                entity = rebuilt
            } else {
                entity = existing!
            }
            riderEntities[rider.id] = entity
            if entity.parent == nil { root.addChild(entity) }

            let displayedDistanceKm = smoothedDistance(for: rider, frameTime: frameTime)
            let progress = Float((displayedDistanceKm / routeLengthKm).truncatingRemainder(dividingBy: 1.0))
            let route = routePose(at: progress)
            let laneOffset: Float = rider.isPlayer ? -(activeRoadWidthMeters * 0.20) : (activeRoadWidthMeters * 0.20)
            let side = simd_normalize(simd_cross([0, 1, 0], route.forward))
            // Model visuals are ground-aligned locally; keep only a small lift above road surface.
            let worldPos = route.position + side * laneOffset + [0, 0.055, 0]
            entity.position = worldPos
            entity.orientation = simd_quatf(from: [0, 0, 1], to: route.forward)
            riderWorldPositionByID[rider.id] = worldPos
            updateRunnerAnimation(entity: entity, riderID: rider.id, distanceKm: displayedDistanceKm, frameTime: frameTime, rider: rider)
        }

        for (id, entity) in riderEntities where !activeIDs.contains(id) {
            entity.removeFromParent()
            riderEntities.removeValue(forKey: id)
            riderWorldPositionByID.removeValue(forKey: id)
            riderStridePhaseByID.removeValue(forKey: id)
            riderLastDistanceKmByID.removeValue(forKey: id)
            riderLastFrameTimeByID.removeValue(forKey: id)
            riderLastAnimationFrameTimeByID.removeValue(forKey: id)
            smoothedRiderDistanceKmByID.removeValue(forKey: id)
            riderAppliedModelIDByID.removeValue(forKey: id)
            riderUsesFallbackRunnerByID.removeValue(forKey: id)
            riderVisualEntityByID.removeValue(forKey: id)
            riderVisualBasePositionByID.removeValue(forKey: id)
            riderVisualBaseOrientationByID.removeValue(forKey: id)
            riderImportedAnimationStartAttemptedByID.remove(id)
            fallbackRunnerPartsByRiderID.removeValue(forKey: id)
        }
    }

    private func smoothedDistance(for rider: Whoosh3DRiderSnapshot, frameTime: TimeInterval) -> Double {
        let target = rider.distanceKm
        let key = rider.id
        guard let current = smoothedRiderDistanceKmByID[key] else {
            smoothedRiderDistanceKmByID[key] = target
            riderLastFrameTimeByID[key] = frameTime
            return target
        }
        let dt = max(0.001, min(0.2, frameTime - (riderLastFrameTimeByID[key] ?? frameTime)))
        riderLastFrameTimeByID[key] = frameTime

        let delta = target - current
        if abs(delta) > 0.15 { // reset/lap sync jump: snap
            smoothedRiderDistanceKmByID[key] = target
            return target
        }

        let alpha = 1.0 - exp(-dt * 14.0)
        let next = current + delta * alpha
        smoothedRiderDistanceKmByID[key] = next
        return next
    }

    private func makeRiderEntity(
        rider: Whoosh3DRiderSnapshot,
        preferredModelID: String,
        allowImportedModelForPacer: Bool
    ) -> Entity {
        let color = RKPlatformColor(
            red: rider.red.clamped(to: 0...1),
            green: rider.green.clamped(to: 0...1),
            blue: rider.blue.clamped(to: 0...1),
            alpha: 1
        )
        let root = Entity()
        root.name = "rider.root"

        let visualBuild = makeRunnerVisualEntity(
            rider: rider,
            preferredModelID: preferredModelID,
            tintColor: color,
            allowImportedModelForPacer: allowImportedModelForPacer
        )
        let visual = visualBuild.entity
        visual.name = "visual"
        alignVisualToGround(visual)
        riderVisualEntityByID[rider.id] = visual
        riderVisualBasePositionByID[rider.id] = visual.position
        riderVisualBaseOrientationByID[rider.id] = visual.orientation
        riderImportedAnimationStartAttemptedByID.remove(rider.id)
        root.addChild(visual)
        riderUsesFallbackRunnerByID[rider.id] = visualBuild.isFallback
        if visualBuild.isFallback {
            fallbackRunnerPartsByRiderID[rider.id] = FallbackRunnerPartRefs(
                body: visual.findEntity(named: "body"),
                torsoTop: visual.findEntity(named: "torsoTop"),
                head: visual.findEntity(named: "head"),
                legL: visual.findEntity(named: "legL"),
                legR: visual.findEntity(named: "legR"),
                armL: visual.findEntity(named: "armL"),
                armR: visual.findEntity(named: "armR")
            )
        } else {
            fallbackRunnerPartsByRiderID.removeValue(forKey: rider.id)
        }

        let shadow = makeGroundShadowEntity(rider: rider)
        shadow.name = "groundShadow"
        root.addChild(shadow)

        return root
    }

    private func alignVisualToGround(_ visual: Entity) {
        let bounds = visual.visualBounds(relativeTo: visual)
        let minY = bounds.center.y - bounds.extents.y * 0.5
        if minY.isFinite {
            visual.position.y -= minY
        }
    }

    private func makeGroundShadowEntity(rider: Whoosh3DRiderSnapshot) -> Entity {
        let radius: Float = rider.isPlayer ? 0.18 : 0.16
        let shadow = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [SimpleMaterial(color: RKPlatformColor(red: 0, green: 0, blue: 0, alpha: 0.16), isMetallic: false)]
        )
        shadow.position = [0, 0.042, 0]
        shadow.scale = [1.20, 0.06, 0.70]
        return shadow
    }

    private func makeRunnerVisualEntity(
        rider: Whoosh3DRiderSnapshot,
        preferredModelID: String,
        tintColor: RKPlatformColor,
        allowImportedModelForPacer: Bool
    ) -> (entity: Entity, isFallback: Bool) {
        if !rider.isPlayer && !allowImportedModelForPacer {
            return (makeFallbackLowPolyRunner(rider: rider, tintColor: tintColor), true)
        }
        if rider.isPlayer && playerModelQualityMode == .low {
            return (makeFallbackLowPolyRunner(rider: rider, tintColor: tintColor), true)
        }

        if let template = loadedRunnerTemplateByModelID[preferredModelID] {
            let clone = template.clone(recursive: true)
            clone.position = [0, 0.0, 0]
            let scale: Float = rider.isPlayer ? 0.52 : 0.46
            clone.scale = [scale, scale, scale]
            return (clone, false)
        }

        scheduleRunnerModelLoadIfNeeded(modelID: preferredModelID)
        return (makeFallbackLowPolyRunner(rider: rider, tintColor: tintColor), true)
    }

    private func makeFallbackLowPolyRunner(rider: Whoosh3DRiderSnapshot, tintColor: RKPlatformColor) -> Entity {
        let root = Entity()
        let body = ModelEntity(
            mesh: .generateBox(size: [rider.isPlayer ? 0.32 : 0.28, rider.isPlayer ? 0.52 : 0.44, rider.isPlayer ? 0.20 : 0.18]),
            materials: [SimpleMaterial(color: tintColor, isMetallic: false)]
        )
        body.name = "body"
        body.position = [0, 0.28, 0]
        root.addChild(body)

        let torsoTop = ModelEntity(
            mesh: .generateSphere(radius: rider.isPlayer ? 0.18 : 0.16),
            materials: [SimpleMaterial(color: tintColor, isMetallic: false)]
        )
        torsoTop.name = "torsoTop"
        torsoTop.position = [0, rider.isPlayer ? 0.54 : 0.47, 0]
        root.addChild(torsoTop)

        let head = ModelEntity(
            mesh: .generateSphere(radius: rider.isPlayer ? 0.14 : 0.12),
            materials: [SimpleMaterial(color: RKPlatformColor(red: 0.95, green: 0.88, blue: 0.76, alpha: 1), isMetallic: false)]
        )
        head.name = "head"
        head.position = [0, rider.isPlayer ? 0.68 : 0.58, 0]
        root.addChild(head)

        let limbMaterial = SimpleMaterial(color: RKPlatformColor(white: 0.16, alpha: 1), isMetallic: false)
        for (name, x, y, z, isArm) in [
            ("legL", -0.10 as Float, 0.02 as Float, 0.02 as Float, false),
            ("legR",  0.10 as Float, 0.02 as Float, -0.02 as Float, false),
            ("armL", -0.20 as Float, 0.34 as Float, 0.00 as Float, true),
            ("armR",  0.20 as Float, 0.34 as Float, 0.00 as Float, true)
        ] {
            let limb = ModelEntity(
                mesh: .generateBox(size: [isArm ? 0.06 : 0.07, isArm ? 0.28 : 0.34, isArm ? 0.06 : 0.07]),
                materials: [limbMaterial]
            )
            limb.name = name
            limb.position = [x, y, z]
            root.addChild(limb)
        }
        return root
    }

    private func updateRunnerAnimation(
        entity: Entity,
        riderID: String,
        distanceKm: Double,
        frameTime: TimeInterval,
        rider: Whoosh3DRiderSnapshot
    ) {
        let previousDistance = riderLastDistanceKmByID[riderID]
        let previousTime = riderLastAnimationFrameTimeByID[riderID]
        riderLastAnimationFrameTimeByID[riderID] = frameTime
        riderLastDistanceKmByID[riderID] = distanceKm

        var phase = riderStridePhaseByID[riderID] ?? 0
        var animationSpeedMetersPerSec = Float(rider.isPlayer ? max(0, currentPlayerSpeedKPH / 3.6) : 0)
        if let previousDistance {
            var deltaKm = distanceKm - previousDistance
            if deltaKm < 0, abs(deltaKm) > routeLengthKm * 0.5 {
                deltaKm += routeLengthKm
            }
            let deltaMeters = max(0, deltaKm * 1000.0)
            let dt = max(0.001, min(0.1, frameTime - (previousTime ?? frameTime)))
            animationSpeedMetersPerSec = max(animationSpeedMetersPerSec, Float(deltaMeters / dt))
            phase += Float(deltaMeters / 1.35) * (.pi * 2)
            if deltaMeters < 0.01, rider.isPlayer, currentPlayerSpeedKPH > 0.5 {
                let predictedMeters = (currentPlayerSpeedKPH / 3.6) * dt
                phase += Float(predictedMeters / 1.35) * (.pi * 2)
                animationSpeedMetersPerSec = max(animationSpeedMetersPerSec, Float(currentPlayerSpeedKPH / 3.6))
            }
        }
        riderStridePhaseByID[riderID] = phase

        let strideIntensity = min(1.35, max(0.15, animationSpeedMetersPerSec / 4.2))
        let legAngle: Float = sin(phase) * (0.65 + 0.20 * strideIntensity)
        let armAngle: Float = -sin(phase) * (0.75 + 0.25 * strideIntensity)
        let bob: Float = max(0, sin(phase * 2)) * (0.018 + 0.020 * strideIntensity)
        let roll: Float = sin(phase) * (0.025 + 0.020 * strideIntensity)
        let pitchPulse: Float = sin(phase * 2) * 0.018
        let lateralSway: Float = sin(phase) * (0.004 + 0.008 * strideIntensity)
        let foreAftSway: Float = cos(phase) * (0.004 + 0.010 * strideIntensity)

        if let visual = riderVisualEntityByID[riderID] {
            if riderUsesFallbackRunnerByID[riderID] != true {
                ensureImportedModelAnimationStartedIfAvailable(riderID: riderID)
            }
            let basePos = riderVisualBasePositionByID[riderID] ?? visual.position
            let baseOri = riderVisualBaseOrientationByID[riderID] ?? visual.orientation
            visual.position = basePos + [lateralSway, bob, foreAftSway]
            let lean = simd_quatf(angle: 0.16 + pitchPulse, axis: [1, 0, 0])
            let rollQ = simd_quatf(angle: roll, axis: [0, 0, 1])
            visual.orientation = baseOri * lean * rollQ
        }

        let parts = fallbackRunnerPartsByRiderID[riderID]
        if let body = parts?.body {
            body.position.y = 0.28 + bob
        }
        if let torsoTop = parts?.torsoTop {
            torsoTop.position.y = 0.54 + bob
        }
        if let head = parts?.head {
            head.position.y = 0.68 + bob
        }
        parts?.legL?.orientation = simd_quatf(angle: legAngle, axis: [1, 0, 0])
        parts?.legR?.orientation = simd_quatf(angle: -legAngle, axis: [1, 0, 0])
        parts?.armL?.orientation = simd_quatf(angle: armAngle, axis: [1, 0, 0])
        parts?.armR?.orientation = simd_quatf(angle: -armAngle, axis: [1, 0, 0])
    }

    private func ensureImportedModelAnimationStartedIfAvailable(riderID: String) {
        guard !riderImportedAnimationStartAttemptedByID.contains(riderID) else { return }
        guard let visual = riderVisualEntityByID[riderID] else { return }
        riderImportedAnimationStartAttemptedByID.insert(riderID)

        guard let animatedEntity = firstEntityWithAvailableAnimation(in: visual),
              let animation = animatedEntity.availableAnimations.first else { return }
        _ = animatedEntity.playAnimation(animation, transitionDuration: 0.12, startsPaused: false)
    }

    private func firstEntityWithAvailableAnimation(in root: Entity) -> Entity? {
        if !root.availableAnimations.isEmpty { return root }
        for child in root.children {
            if let entity = firstEntityWithAvailableAnimation(in: child) {
                return entity
            }
        }
        return nil
    }

    private func buildCurvedRouteSamples(from samples: [Whoosh3DProfilePoint]) -> [SIMD3<Float>] {
        let total = max(routeLengthKm, 0.1)
        let ampBase = Float(min(12.0, max(5.0, total * 1.8)))
        let ampSecondary = ampBase * 0.45
        let seed = Float((samples.count % 17) + Int(total.rounded())) * 0.07

        return samples.map { point in
            let p = Float(point.distanceKm / total)
            let x = p * 86.0 - 43.0
            let z = sin((p * 2.2 + seed) * .pi) * ampBase
                + sin((p * 5.3 + seed * 1.7) * .pi) * ampSecondary
            let y = max(0.04, Float(point.elevationM) * 0.05)
            return SIMD3<Float>(x, y, z)
        }
    }

    private func orientation(forSegmentFrom a: SIMD3<Float>, to b: SIMD3<Float>) -> simd_quatf {
        let forward = simd_normalize(b - a)
        guard simd_length(forward) > 0.0001 else { return simd_quatf() }

        let yaw = atan2f(forward.x, forward.z)
        let flatLen = max(0.0001, hypotf(forward.x, forward.z))
        let pitch = -atan2f(forward.y, flatLen)
        return simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    private func routePose(at progress: Float) -> (position: SIMD3<Float>, forward: SIMD3<Float>) {
        guard routeSamples3D.count >= 2 else {
            return (SIMD3<Float>(0, 0.1, 0), SIMD3<Float>(0, 0, 1))
        }
        let p = min(max(progress, 0), 0.9999)
        let scaled = p * Float(routeSamples3D.count - 1)
        let i0 = Int(floor(scaled))
        let i1 = min(routeSamples3D.count - 1, i0 + 1)
        let t = scaled - Float(i0)
        let pos = routeSamples3D[i0] * (1 - t) + routeSamples3D[i1] * t

        let prev = routeSamples3D[max(0, i0 - 1)]
        let next = routeSamples3D[min(routeSamples3D.count - 1, i1 + 1)]
        let fwd = simd_normalize(next - prev)
        return (pos, simd_length(fwd) > 0.0001 ? fwd : SIMD3<Float>(0, 0, 1))
    }

    private func resolvedRunnerModelID(preferredID: String) -> String {
        let options = WhooshRunnerModelCatalog.availableModels(
            preferredExtensions: ["usdz"],
            includeDefaultFallback: false
        ).filter { !blockedRunnerModelIDs.contains($0.id.lowercased()) }
        guard !options.isEmpty else { return preferredID }
        if let matched = options.first(where: { $0.id.caseInsensitiveCompare(preferredID) == .orderedSame }) {
            return matched.id
        }
        if let preferredColored = options.first(where: { $0.id.caseInsensitiveCompare("shiba_pup_run_colored") == .orderedSame }) {
            return preferredColored.id
        }
        if let shiba = options.first(where: { $0.id.localizedCaseInsensitiveContains("shiba") }) {
            return shiba.id
        }
        return options[0].id
    }

    private func assignedBotRunnerModelID(for riderID: String, excluding playerModelID: String) -> String {
        ensureRunnerModelPool(playerModelID: playerModelID)
        let allIDs = activeRunnerModelPoolIDs
        guard !allIDs.isEmpty else { return playerModelID }
        let filtered = allIDs.filter { $0.caseInsensitiveCompare(playerModelID) != .orderedSame }
        let pool = filtered.isEmpty ? allIDs : filtered

        if let existing = riderAssignedModelIDByID[riderID],
           let match = pool.first(where: { $0.caseInsensitiveCompare(existing) == .orderedSame }) {
            return match
        }

        let idx = stableIndex(for: riderID, modulo: pool.count)
        let chosen = pool[idx]
        riderAssignedModelIDByID[riderID] = chosen
        return chosen
    }

    private func resolvedBotRenderableModelID(for riderID: String, excluding playerModelID: String) -> String {
        let assigned = assignedBotRunnerModelID(for: riderID, excluding: playerModelID)
        let assignedKey = assigned.lowercased()
        // If assigned model is available or still loading, keep it.
        if loadedRunnerTemplateByModelID.keys.contains(where: { $0.caseInsensitiveCompare(assigned) == .orderedSame }) {
            return assigned
        }
        if loadingRunnerModelIDs.contains(assignedKey) {
            return assigned
        }
        // If the assigned model failed, try another model from the active bot pool before giving up to fallback.
        if modelLoadFailureReasonByModelID[assignedKey] != nil {
            let candidates = activeRunnerModelPoolIDs.filter { $0.caseInsensitiveCompare(playerModelID) != .orderedSame }
            for candidate in candidates {
                let key = candidate.lowercased()
                if modelLoadFailureReasonByModelID[key] != nil { continue }
                riderAssignedModelIDByID[riderID] = candidate
                scheduleRunnerModelLoadIfNeeded(modelID: candidate)
                return candidate
            }
        }
        scheduleRunnerModelLoadIfNeeded(modelID: assigned)
        return assigned
    }

    private func ensureRunnerModelPool(playerModelID: String) {
        if activeRunnerModelPoolPlayerID.caseInsensitiveCompare(playerModelID) == .orderedSame,
           !activeRunnerModelPoolIDs.isEmpty {
            return
        }
        let allUSDZ = WhooshRunnerModelCatalog.availableModels(
            preferredExtensions: ["usdz"],
            includeDefaultFallback: false
        )
        .map(\.id)
        .filter { !blockedRunnerModelIDs.contains($0.lowercased()) }

        guard !allUSDZ.isEmpty else {
            activeRunnerModelPoolIDs = [playerModelID]
            activeRunnerModelPoolPlayerID = playerModelID
            riderAssignedModelIDByID.removeAll()
            return
        }

        let resolvedPlayer = allUSDZ.first(where: { $0.caseInsensitiveCompare(playerModelID) == .orderedSame }) ?? playerModelID
        let remaining = allUSDZ.filter { $0.caseInsensitiveCompare(resolvedPlayer) != .orderedSame }
        let shuffled = remaining.shuffled()
        let botChoices = Array(shuffled.prefix(3))
        activeRunnerModelPoolIDs = [resolvedPlayer] + botChoices
        activeRunnerModelPoolPlayerID = resolvedPlayer

        // Reset bot assignments when pool changes so bots re-pick from the new 4-model pool.
        riderAssignedModelIDByID.removeAll()
    }

    private func stableIndex(for text: String, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash % UInt64(modulo))
    }

    private func scheduleRunnerModelLoadIfNeeded(modelID: String) {
        guard loadedRunnerTemplateByModelID[modelID] == nil else { return }
        guard loadingRunnerModelIDs.insert(modelID.lowercased()).inserted else { return }
        modelLoadFailureReasonByModelID.removeValue(forKey: modelID.lowercased())

        Task.detached(priority: .userInitiated) {
            guard #available(macOS 15.0, iOS 18.0, *) else {
                _ = await MainActor.run { self.loadingRunnerModelIDs.remove(modelID.lowercased()) }
                return
            }
            let result = await Self.loadRunnerTemplateOffMain(modelID: modelID)
            await MainActor.run {
                self.loadingRunnerModelIDs.remove(modelID.lowercased())
                if let template = result.entity {
                    self.modelLoadFailureReasonByModelID.removeValue(forKey: modelID.lowercased())
                    self.loadedRunnerTemplateByModelID[modelID] = Self.normalizeLoadedRunnerEntity(template)
                    // Force re-create riders to swap fallback primitives for the loaded model.
                    self.riderAppliedModelIDByID.removeAll()
                } else {
                    self.modelLoadFailureReasonByModelID[modelID.lowercased()] = result.reason ?? "unknown"
                    print("WhooshRealityKit model load failed -> \(modelID): \(result.reason ?? "unknown")")
                }
                self.refreshModelBanner(playerModelID: self.resolvedRunnerModelID(preferredID: modelID), riders: self.latestRiders)
            }
        }
    }

    private func refreshModelBanner(playerModelID: String, riders: [Whoosh3DRiderSnapshot]) {
        if playerModelQualityMode == .low {
            if modelBannerText != nil { modelBannerText = nil }
            modelBannerStyle = .info
            return
        }
        let playerKey = playerModelID.lowercased()
        let playerIsLoaded = loadedRunnerTemplateByModelID.keys.contains { $0.caseInsensitiveCompare(playerModelID) == .orderedSame }
        let playerIsLoading = loadingRunnerModelIDs.contains(playerKey)
        let playerFailure = modelLoadFailureReasonByModelID[playerKey]

        var botFailureCount = 0
        for rider in riders where !rider.isPlayer {
            guard let modelID = riderAppliedModelIDByID[rider.id] ?? riderAssignedModelIDByID[rider.id] else { continue }
            if modelLoadFailureReasonByModelID[modelID.lowercased()] != nil {
                botFailureCount += 1
            }
        }

        let text: String?
        let style: ModelBannerStyle
        if let playerFailure {
            let botPart = botFailureCount > 0 ? "，机器人失败 \(botFailureCount)" : ""
            text = "玩家模型加载失败（已回退低模）: \(playerModelID) · \(playerFailure)\(botPart)"
            style = .warning
        } else if playerIsLoading && !playerIsLoaded {
            let botPart = botFailureCount > 0 ? "，机器人失败 \(botFailureCount)" : ""
            text = "正在加载玩家模型：\(playerModelID)（临时使用低模）\(botPart)"
            style = .info
        } else if botFailureCount > 0 {
            text = "玩家模型已加载，机器人模型失败 \(botFailureCount)（已回退低模）"
            style = .warning
        } else {
            text = nil
            style = .info
        }

        if modelBannerText != text { modelBannerText = text }
        if modelBannerStyle != style { modelBannerStyle = style }
    }

    @available(macOS 15.0, iOS 18.0, *)
    nonisolated private static func loadRunnerTemplateOffMain(modelID: String) async -> (entity: Entity?, reason: String?) {
        guard let url = bundledRunnerModelURLStatic(preferredModelID: modelID) else {
            return (nil, "model not found in bundle")
        }

        do {
            let loaded = try await Entity(contentsOf: url)
            return (loaded, nil)
        } catch {
            return (nil, "entity load failed: \(error.localizedDescription)")
        }
    }

    nonisolated private static func bundledRunnerModelURLStatic(preferredModelID: String) -> URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        let candidateBaseNames = candidateModelBasenamesStatic(for: preferredModelID)
        for ext in ["usdz"] {
            for base in candidateBaseNames {
                if let url = bundle.url(forResource: base, withExtension: ext) {
                    return url
                }
            }
            if let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil),
               let matched = urls.first(where: { url in
                   let lower = url.deletingPathExtension().lastPathComponent.lowercased()
                   return candidateBaseNames.contains(where: { $0.lowercased() == lower })
               }) {
                return matched
            }
        }
        return nil
    }

    nonisolated private static func candidateModelBasenamesStatic(for preferredModelID: String) -> [String] {
        var names: [String] = []
        let preferred = preferredModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty {
            names.append(preferred)
            names.append(preferred.replacingOccurrences(of: " ", with: "_"))
            names.append(preferred.replacingOccurrences(of: " ", with: "-"))
        }
        names.append(contentsOf: ["Shiba_inu", "shiba_inu", "Shiba_Inu", "shibaInu"])
        var dedup: [String] = []
        var seen = Set<String>()
        for name in names where !name.isEmpty {
            let key = name.lowercased()
            if seen.insert(key).inserted { dedup.append(name) }
        }
        return dedup
    }

    @MainActor
    private static func normalizeLoadedRunnerEntity(_ entity: Entity) -> Entity {
        let root = Entity()
        let clone = entity.clone(recursive: true)
        let bounds = clone.visualBounds(relativeTo: nil)
        let extents = bounds.extents
        let maxExtent = max(extents.x, max(extents.y, extents.z))
        if maxExtent > 0.0001 {
            let scale = 1.0 / maxExtent
            clone.scale = [scale, scale, scale]
            let minY = bounds.center.y - extents.y * 0.5
            clone.position = [
                -bounds.center.x * scale,
                -minY * scale,
                -bounds.center.z * scale
            ]
        }
        root.addChild(clone)
        return root
    }

    private func updateStaticCamera(cameraZoom: Double) {
        setCameraFOV(62)
        let zoom = Float(cameraZoom.clamped(to: 0.6...2.4))
        let eye = SIMD3<Float>(0, 26 * zoom, 34 * zoom)
        let target = SIMD3<Float>(0, 0, 0)
        applySmoothedCamera(eye: eye, target: target, smoothing: 0.12)
    }

    private func updateCamera(riders: [Whoosh3DRiderSnapshot], cameraMode: Whoosh3DCameraMode, cameraZoom: Double) {
        setCameraFOV(62)
        guard let player = riders.first(where: \.isPlayer) else {
            updateStaticCamera(cameraZoom: cameraZoom)
            return
        }
        let progress = Float((player.distanceKm / routeLengthKm).truncatingRemainder(dividingBy: 1.0))
        let route = routePose(at: progress)
        let side = simd_normalize(simd_cross([0, 1, 0], route.forward))
        let up = SIMD3<Float>(0, 1, 0)
        let riderPos = route.position + [0, 0.7, 0]

        let zoom = Float(cameraZoom.clamped(to: 0.6...2.4))
        let eyeTarget: (SIMD3<Float>, SIMD3<Float>) = {
            switch cameraMode {
            case .chase:
                return (
                    riderPos - route.forward * (8.5 * zoom) + up * (3.0 * zoom) + side * (0.2 * zoom),
                    riderPos + route.forward * max(4.5, 9.0 * min(zoom, 1.6)) + up * 0.5
                )
            case .nearChase:
                return (
                    riderPos - route.forward * (4.0 * zoom) + up * (1.9 * zoom) + side * (0.1 * zoom),
                    riderPos + route.forward * max(3.0, 5.5 * min(zoom, 1.7)) + up * 0.3
                )
            case .side:
                return (
                    riderPos + side * (6.0 * zoom) + up * (2.2 * zoom),
                    riderPos + route.forward * max(2.0, 4.5 * min(zoom, 1.5)) + up * 0.2
                )
            case .front:
                return (
                    riderPos + route.forward * (7.0 * zoom) + up * (2.0 * zoom),
                    riderPos + up * 0.5
                )
            case .overhead:
                return (
                    riderPos - route.forward * (2.0 * zoom) + up * (14.0 * zoom),
                    riderPos + route.forward * max(2.0, 5.0 * min(zoom, 1.4))
                )
            }
        }()

        applySmoothedCamera(eye: eyeTarget.0, target: eyeTarget.1, smoothing: 0.28)
    }

    private func updateFreeOrbitCamera(
        riders: [Whoosh3DRiderSnapshot],
        cameraMode: Whoosh3DCameraMode,
        cameraZoom: Double,
        yawOffset: Double,
        pitchOffset: Double
    ) {
        setCameraFOV(62)
        guard let player = riders.first(where: \.isPlayer) else {
            updateStaticCamera(cameraZoom: cameraZoom)
            return
        }
        let progress = Float((player.distanceKm / routeLengthKm).truncatingRemainder(dividingBy: 1.0))
        let route = routePose(at: progress)
        let riderPos = route.position + [0, 0.7, 0]
        let target = riderPos + SIMD3<Float>(0, 0.35, 0)
        let zoom = Float(cameraZoom.clamped(to: 0.6...2.4))

        let baseDistance: Float
        let basePitch: Float
        switch cameraMode {
        case .chase: baseDistance = 9.0; basePitch = 0.28
        case .nearChase: baseDistance = 5.0; basePitch = 0.22
        case .side: baseDistance = 7.0; basePitch = 0.16
        case .front: baseDistance = 8.0; basePitch = 0.22
        case .overhead: baseDistance = 14.0; basePitch = 1.05
        }

        let headingYaw = atan2f(route.forward.x, route.forward.z)
        let yaw = headingYaw + Float(yawOffset)
        let pitch = min(max(basePitch + Float(pitchOffset), -0.25), 1.25)
        let dist = baseDistance * zoom

        let cosPitch = cosf(pitch)
        let dir = SIMD3<Float>(
            sinf(yaw) * cosPitch,
            sinf(pitch),
            cosf(yaw) * cosPitch
        )
        let eye = target + dir * dist
        applySmoothedCamera(eye: eye, target: target, smoothing: 0.20)
    }

    private func setCameraFOV(_ value: Double) {
        var comp = cameraEntity.components[PerspectiveCameraComponent.self] ?? PerspectiveCameraComponent()
        comp.fieldOfViewInDegrees = Float(min(max(value, 20), 130))
        cameraEntity.components.set(comp)
    }

    private func applySmoothedCamera(eye: SIMD3<Float>, target: SIMD3<Float>, smoothing: Float) {
        let alpha = min(max(smoothing, 0.02), 0.95)
        if let currentEye = smoothedCameraEye, let currentTarget = smoothedCameraTarget {
            smoothedCameraEye = currentEye * (1 - alpha) + eye * alpha
            smoothedCameraTarget = currentTarget * (1 - alpha) + target * alpha
        } else {
            smoothedCameraEye = eye
            smoothedCameraTarget = target
        }
        cameraRig.look(
            at: smoothedCameraTarget ?? target,
            from: smoothedCameraEye ?? eye,
            relativeTo: root
        )
    }

    func pacerLabelAnchors(in size: CGSize) -> [WhooshWorldLabelAnchor] {
        guard size.width > 1, size.height > 1 else { return [] }
        guard let eye = smoothedCameraEye, let target = smoothedCameraTarget else { return [] }
        let now = ProcessInfo.processInfo.systemUptime
        let signature = pacerAnchorSignature(viewport: size, eye: eye, target: target, riders: latestRiders)
        if signature == lastPacerAnchorSignature, (now - lastPacerAnchorProjectionAt) < 0.12 {
            return cachedPacerAnchors
        }
        lastPacerAnchorProjectionAt = now
        lastPacerAnchorSignature = signature

        let playerDistance = latestRiders.first(where: \.isPlayer)?.distanceKm ?? 0
        let visiblePacers: [Whoosh3DRiderSnapshot] = Array(latestRiders
            .filter { !$0.isPlayer }
            .sorted { abs($0.distanceKm - playerDistance) < abs($1.distanceKm - playerDistance) }
            .prefix(3))

        let anchors: [WhooshWorldLabelAnchor] = visiblePacers.compactMap { rider -> WhooshWorldLabelAnchor? in
            guard !rider.isPlayer else { return nil }
            guard let base = riderWorldPositionByID[rider.id] else { return nil }
            let world = base + SIMD3<Float>(0, 0.95, 0)
            guard let point = project(world: world, eye: eye, target: target, fovDegrees: cameraFOVDegrees(), viewport: size) else {
                return nil
            }
            let gapMeters = Int(((rider.distanceKm - playerDistance) * 1000).rounded())
            let gapText = gapMeters >= 0 ? "+\(gapMeters)m" : "\(gapMeters)m"
            return WhooshWorldLabelAnchor(
                id: rider.id,
                name: rider.name,
                gapText: gapText,
                tint: Color(red: rider.red, green: rider.green, blue: rider.blue),
                point: point
            )
        }
        cachedPacerAnchors = anchors
        return anchors
    }

    private func pacerAnchorSignature(
        viewport: CGSize,
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        riders: [Whoosh3DRiderSnapshot]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(Int(viewport.width.rounded()))
        hasher.combine(Int(viewport.height.rounded()))
        hasher.combine(Int(eye.x * 10))
        hasher.combine(Int(eye.y * 10))
        hasher.combine(Int(eye.z * 10))
        hasher.combine(Int(target.x * 10))
        hasher.combine(Int(target.y * 10))
        hasher.combine(Int(target.z * 10))
        for rider in riders {
            hasher.combine(rider.id)
            hasher.combine(Int((rider.distanceKm * 100).rounded()))
        }
        return hasher.finalize()
    }

    private func cameraFOVDegrees() -> Double {
        if let comp = cameraEntity.components[PerspectiveCameraComponent.self] {
            return Double(comp.fieldOfViewInDegrees)
        }
        return 62
    }

    private func project(
        world: SIMD3<Float>,
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        fovDegrees: Double,
        viewport: CGSize
    ) -> CGPoint? {
        let worldUp = SIMD3<Float>(0, 1, 0)
        let forward = normalizedOrFallback(target - eye, fallback: [0, 0, 1])
        let right = normalizedOrFallback(simd_cross(forward, worldUp), fallback: [1, 0, 0])
        let up = normalizedOrFallback(simd_cross(right, forward), fallback: [0, 1, 0])

        let rel = world - eye
        let cx = simd_dot(rel, right)
        let cy = simd_dot(rel, up)
        let cz = simd_dot(rel, forward)
        guard cz > 0.1 else { return nil }

        let aspect = Float(max(0.1, viewport.width / viewport.height))
        let f = Float(1.0 / tan((fovDegrees * .pi / 180) * 0.5))
        let ndcX = (cx / cz) * (f / aspect)
        let ndcY = (cy / cz) * f
        guard abs(ndcX) <= 1.15, abs(ndcY) <= 1.15 else { return nil }

        let x = (CGFloat(ndcX) * 0.5 + 0.5) * viewport.width
        let y = (1 - (CGFloat(ndcY) * 0.5 + 0.5)) * viewport.height
        return CGPoint(x: x, y: y)
    }

    private func makeRouteSignEntity(index: Int) -> Entity {
        let signRoot = Entity()
        let pole = ModelEntity(
            mesh: .generateBox(size: [0.05, 0.8, 0.05]),
            materials: [SimpleMaterial(color: RKPlatformColor(white: 0.78, alpha: 1), isMetallic: true)]
        )
        pole.position = [0, 0.4, 0]
        signRoot.addChild(pole)

        let hue = Double((index % 60)) / 60.0
        let plateColor = RKPlatformColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1)
        let plate = ModelEntity(
            mesh: .generateBox(size: [0.42, 0.24, 0.03]),
            materials: [SimpleMaterial(color: plateColor, isMetallic: false)]
        )
        plate.position = [0, 0.86, 0]
        signRoot.addChild(plate)
        return signRoot
    }

    private func makeRouteArchEntity(index: Int) -> Entity {
        let archRoot = Entity()
        let hue = Double(index % 90) / 90.0
        let color = RKPlatformColor(hue: hue, saturation: 0.65, brightness: 0.96, alpha: 0.95)
        let mat = SimpleMaterial(color: color, isMetallic: false)
        let capMat = SimpleMaterial(color: RKPlatformColor.white.withAlphaComponent(0.70), isMetallic: false)

        for x: Float in [-0.65, 0.65] {
            let post = ModelEntity(mesh: .generateBox(size: [0.08, 1.45, 0.08]), materials: [mat])
            post.position = [x, 0.72, 0]
            archRoot.addChild(post)
        }
        let beam = ModelEntity(mesh: .generateBox(size: [1.45, 0.10, 0.10]), materials: [mat])
        beam.position = [0, 1.42, 0]
        archRoot.addChild(beam)

        let cap = ModelEntity(mesh: .generateBox(size: [1.22, 0.14, 0.04]), materials: [capMat])
        cap.position = [0, 1.42, -0.05]
        archRoot.addChild(cap)
        return archRoot
    }

    private func normalizedOrFallback(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let len = simd_length(v)
        if len < 0.0001 { return fallback }
        return v / len
    }

    private func sampledProfile(_ profile: [Whoosh3DProfilePoint], limitSegments: Int) -> [Whoosh3DProfilePoint] {
        guard profile.count > limitSegments else { return profile }
        let step = Double(profile.count - 1) / Double(max(1, limitSegments - 1))
        var out: [Whoosh3DProfilePoint] = []
        out.reserveCapacity(limitSegments)
        for i in 0..<limitSegments {
            let idx = Int((Double(i) * step).rounded())
            out.append(profile[min(max(0, idx), profile.count - 1)])
        }
        return out
    }
}

struct WhooshWorldLabelAnchor: Identifiable {
    let id: String
    let name: String
    let gapText: String
    let tint: Color
    let point: CGPoint
}

private struct WhooshPacerRow: Identifiable {
    let id: String
    let name: String
    let gapText: String
    let tint: Color
}

private struct WhooshFPSBadge: View {
    @State private var lastFrameDate: Date?
    @State private var smoothedFPS: Double = 0

    var body: some View {
        TimelineView(.animation) { context in
            Text("\(Int(smoothedFPS.rounded())) FPS")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.45), in: Capsule())
                .onAppear {
                    if lastFrameDate == nil { lastFrameDate = context.date }
                }
                .onChange(of: context.date) { _, newDate in
                    updateFPS(now: newDate)
                }
        }
    }

    private func updateFPS(now: Date) {
        guard let last = lastFrameDate else {
            lastFrameDate = now
            return
        }
        let dt = now.timeIntervalSince(last)
        lastFrameDate = now
        guard dt > 0.0001 else { return }
        let fps = 1.0 / dt
        if smoothedFPS == 0 {
            smoothedFPS = fps
        } else {
            smoothedFPS = smoothedFPS * 0.88 + fps * 0.12
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct WhooshRealityKitView: View {
    let profile: [Whoosh3DProfilePoint]
    let totalDistanceKm: Double
    let riders: [Whoosh3DRiderSnapshot]
    let playerAppearance: TrainerRiderAppearance
    let currentSpeedKPH: Double
    let currentPowerW: Double
    let currentGradePercent: Double
    let currentLap: Int
    let followPlayer: Bool
    let cameraMode: Whoosh3DCameraMode
    @Binding var cameraZoom: Double
    let recenterToken: Int
    let roadWidthMeters: Double
    let guardRailHeightMeters: Double
    let playerModelQualityMode: WhooshPlayerModelQualityMode

    @StateObject private var sceneModel = WhooshRealitySceneModel()
    @State private var freeCameraEnabled = false
    @State private var freeCameraYaw: Double = 0
    @State private var freeCameraPitch: Double = 0
    @State private var pinchStartZoom: Double?
    @State private var lastDragTranslation: CGSize = .zero

    var body: some View {
        Group {
            if #available(macOS 15.0, iOS 18.0, *) {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                    realityContent(frameTime: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary.opacity(0.35))
                    .overlay(
                        VStack(spacing: 8) {
                            Text("RealityKit")
                                .font(.caption.weight(.semibold))
                            Text(
                                L10n.choose(
                                    simplifiedChinese: "当前系统版本不支持 RealityKit 实验渲染器（需要 macOS 15+ / iOS 18+）。",
                                    english: "RealityKit experimental renderer requires macOS 15+ / iOS 18+."
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        }
                        .padding(12)
                    )
                    .frame(height: 220)
            }
        }
        .onChange(of: recenterToken) { _, _ in
            freeCameraEnabled = false
            freeCameraYaw = 0
            freeCameraPitch = 0
            lastDragTranslation = .zero
            pinchStartZoom = nil
        }
    }

    private var pacerRowsBelowGame: [WhooshPacerRow] {
        let playerDistance = riders.first(where: \.isPlayer)?.distanceKm ?? 0
        return Array(riders
            .filter { !$0.isPlayer }
            .sorted { abs($0.distanceKm - playerDistance) < abs($1.distanceKm - playerDistance) }
            .prefix(3))
        .map { rider in
            let gapMeters = Int(((rider.distanceKm - playerDistance) * 1000).rounded())
            let gapText = gapMeters >= 0 ? "+\(gapMeters)m" : "\(gapMeters)m"
            return WhooshPacerRow(
                id: rider.id,
                name: rider.name,
                gapText: gapText,
                tint: Color(red: rider.red, green: rider.green, blue: rider.blue)
            )
        }
    }

    @available(macOS 15.0, iOS 18.0, *)
    @ViewBuilder
    private func realityContent(frameTime: TimeInterval) -> some View {
        let model = sceneModel
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                GeometryReader { _ in
                    ZStack(alignment: .topLeading) {
                        LinearGradient(
                            colors: [
                                Color(red: 0.27, green: 0.35, blue: 0.47),
                                Color(red: 0.22, green: 0.29, blue: 0.39)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        RealityView { content in
                            model.buildBaseSceneIfNeeded()
                            content.add(model.root)
                            content.camera = .virtual
                            content.cameraTarget = model.cameraTargetEntity
                            content.renderingEffects.motionBlur = .disabled
                            content.renderingEffects.depthOfField = .disabled
                            content.renderingEffects.cameraGrain = .disabled
                            content.renderingEffects.dynamicRange = .standard
                        } update: { _ in
                            model.update(
                                profile: profile,
                                totalDistanceKm: totalDistanceKm,
                                riders: riders,
                                followPlayer: followPlayer,
                                cameraMode: cameraMode,
                                cameraZoom: cameraZoom,
                                recenterToken: recenterToken,
                                freeCameraEnabled: freeCameraEnabled,
                                freeCameraYaw: freeCameraYaw,
                                freeCameraPitch: freeCameraPitch,
                                roadWidthMeters: roadWidthMeters,
                                guardRailHeightMeters: guardRailHeightMeters,
                                playerRunnerModelID: playerAppearance.whooshRunnerModelID,
                                playerModelQualityMode: playerModelQualityMode,
                                frameTime: frameTime,
                                playerSpeedKPH: currentSpeedKPH
                            )
                        }

#if canImport(AppKit)
                        WhooshMacCameraInputOverlay(
                            onScrollDelta: { deltaY in
                                let next = (cameraZoom + Double(deltaY) * 0.003).clamped(to: 0.6...2.4)
                                if abs(next - cameraZoom) > 0.0001 { cameraZoom = next }
                            },
                            onMagnifyDelta: { magnification in
                                let next = (cameraZoom * (1.0 - Double(magnification))).clamped(to: 0.6...2.4)
                                if abs(next - cameraZoom) > 0.0001 { cameraZoom = next }
                            },
                            onDragDelta: { delta in
                                freeCameraEnabled = true
                                freeCameraYaw += Double(delta.width) * 0.010
                                freeCameraPitch += Double(-delta.height) * 0.006
                                freeCameraPitch = freeCameraPitch.clamped(to: -0.45...0.85)
                            },
                            onDragEnded: { }
                        )
                        .allowsHitTesting(true)
#endif
                    }
                }
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if pinchStartZoom == nil { pinchStartZoom = cameraZoom }
                            let base = pinchStartZoom ?? cameraZoom
                            cameraZoom = (base / Double(value)).clamped(to: 0.6...2.4)
                        }
                        .onEnded { _ in
                            pinchStartZoom = nil
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let dx = value.translation.width - lastDragTranslation.width
                            let dy = value.translation.height - lastDragTranslation.height
                            lastDragTranslation = value.translation
                            freeCameraEnabled = true
                            freeCameraYaw += Double(dx) * 0.010
                            freeCameraPitch += Double(-dy) * 0.006
                            freeCameraPitch = freeCameraPitch.clamped(to: -0.45...0.85)
                        }
                        .onEnded { _ in
                            lastDragTranslation = .zero
                        }
                )

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RealityKit")
                            .font(.caption.weight(.semibold))
                        Text(
                            L10n.choose(
                                simplifiedChinese: "实验渲染器（先迁赛道/点位，后续补相机跟拍与模型动画）",
                                english: "Experimental renderer (route/rider positions first; camera/model animation comes next)"
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        Text("Lap \(currentLap) · \(Int(currentSpeedKPH.rounded())) km/h · \(Int(currentPowerW.rounded()))W · \(String(format: "%.1f", currentGradePercent))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 6) {
                        WhooshFPSBadge()
                        if let banner = model.modelBannerText {
                            Text(banner)
                                .font(.caption2)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    (model.modelBannerStyle == .warning
                                        ? Color.red.opacity(0.75)
                                        : Color.black.opacity(0.45)),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .frame(maxWidth: 560, alignment: .trailing)
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(10)
            }

            if !pacerRowsBelowGame.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pacerRowsBelowGame) { row in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(row.tint)
                                    .frame(width: 8, height: 8)
                                Text(row.name)
                                    .font(.caption2)
                                Text(row.gapText)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(row.tint.opacity(0.55), lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
        }
    }
}

#else
struct WhooshRealityKitView: View {
    let profile: [Whoosh3DProfilePoint]
    let totalDistanceKm: Double
    let riders: [Whoosh3DRiderSnapshot]
    let playerAppearance: TrainerRiderAppearance
    let currentSpeedKPH: Double
    let currentPowerW: Double
    let currentGradePercent: Double
    let currentLap: Int
    let followPlayer: Bool
    let cameraMode: Whoosh3DCameraMode
    @Binding var cameraZoom: Double
    let recenterToken: Int
    let roadWidthMeters: Double
    let guardRailHeightMeters: Double
    let playerModelQualityMode: WhooshPlayerModelQualityMode

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary.opacity(0.35))
            .overlay(
                Text(
                    L10n.choose(
                        simplifiedChinese: "当前平台不支持 RealityKit 视图。",
                        english: "RealityKit view is unavailable on this platform."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            )
            .frame(height: 220)
    }
}
#endif
