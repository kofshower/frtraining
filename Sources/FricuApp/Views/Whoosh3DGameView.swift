import SwiftUI

struct Whoosh3DProfilePoint: Identifiable, Equatable {
    let distanceKm: Double
    let elevationM: Double
    var id: Double { distanceKm }
}

struct Whoosh3DRiderSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let distanceKm: Double
    let isPlayer: Bool
    let red: Double
    let green: Double
    let blue: Double
}

enum Whoosh3DCameraMode: String, CaseIterable, Identifiable {
    case chase
    case nearChase
    case side
    case front
    case overhead

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chase:
            return L10n.choose(simplifiedChinese: "跟随", english: "Chase")
        case .nearChase:
            return L10n.choose(simplifiedChinese: "近景", english: "Close")
        case .side:
            return L10n.choose(simplifiedChinese: "侧视", english: "Side")
        case .front:
            return L10n.choose(simplifiedChinese: "前视", english: "Front")
        case .overhead:
            return L10n.choose(simplifiedChinese: "俯视", english: "Overhead")
        }
    }
}

struct WhooshRunnerModelOption: Identifiable, Hashable {
    let id: String        // basename without extension, keep original case for lookup/persistence
    let fileName: String  // actual filename in bundle

    var displayName: String {
        id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCapitalized
    }
}

enum WhooshRunnerModelCatalog {
    static func availableModels(
        preferredExtensions: [String] = ["usda", "usd", "usdz", "scn", "dae"],
        includeDefaultFallback: Bool = true
    ) -> [WhooshRunnerModelOption] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        var chosenByLowerBase: [String: WhooshRunnerModelOption] = [:]

        for ext in preferredExtensions {
            guard let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) else { continue }
            for url in urls {
                let fileName = url.lastPathComponent
                let base = url.deletingPathExtension().lastPathComponent
                let key = base.lowercased()
                if chosenByLowerBase[key] == nil {
                    chosenByLowerBase[key] = WhooshRunnerModelOption(id: base, fileName: fileName)
                }
            }
        }

        let options = Array(chosenByLowerBase.values).sorted { lhs, rhs in
            if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
            return lhs.id < rhs.id
        }

        if !options.isEmpty || !includeDefaultFallback { return options }
        return [WhooshRunnerModelOption(id: "shiba_pup_run_colored", fileName: "shiba_pup_run_colored.usdz")]
    }
}

#if canImport(SceneKit)
import SceneKit
import simd

#if canImport(AppKit)
import AppKit
private typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#endif

struct Whoosh3DGameView: View {
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
    let cameraFOV: Double

    @StateObject private var sceneModel = Whoosh3DSceneModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            SceneView(
                scene: sceneModel.scene,
                pointOfView: sceneModel.cameraNode,
                options: [],
                preferredFramesPerSecond: 60,
                antialiasingMode: .multisampling4X,
                delegate: nil,
                technique: nil
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("WHOOSH 3D")
                    .font(.caption.bold())
                Text(
                    String(
                        format: "Lap %d · %.1f km/h · %.0fW · %.1f%%",
                        currentLap,
                        currentSpeedKPH,
                        currentPowerW,
                        currentGradePercent
                    )
                )
                .font(.caption2.monospacedDigit())
            }
            .padding(10)
            .foregroundStyle(.white)
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
            .padding(10)

            if let modelLoadErrorMessage = sceneModel.modelLoadErrorMessage {
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.choose(simplifiedChinese: "模型加载失败（已回退）", english: "Model Load Failed (Fallback Active)"))
                                .font(.caption.bold())
                            Text(modelLoadErrorMessage)
                                .font(.caption2)
                                .multilineTextAlignment(.leading)
                                .lineLimit(5)
                        }
                        .padding(10)
                        .foregroundStyle(.white)
                        .background(.red.opacity(0.26), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Spacer()
                }
                .padding(10)
                .transition(.opacity)
            }

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(sceneModel.visibleRows) { row in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: row.red, green: row.green, blue: row.blue))
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
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            sceneModel.configureIfNeeded()
            sceneModel.rebuildRoute(profile: profile, totalDistanceKm: totalDistanceKm)
            sceneModel.updateRiders(
                riders: riders,
                totalDistanceKm: totalDistanceKm,
                followPlayer: followPlayer,
                playerAppearance: playerAppearance,
                cameraMode: cameraMode,
                cameraFOV: cameraFOV
            )
        }
        .onChange(of: profile) { _, next in
            sceneModel.rebuildRoute(profile: next, totalDistanceKm: totalDistanceKm)
            sceneModel.updateRiders(
                riders: riders,
                totalDistanceKm: totalDistanceKm,
                followPlayer: followPlayer,
                playerAppearance: playerAppearance,
                cameraMode: cameraMode,
                cameraFOV: cameraFOV
            )
        }
        .onChange(of: totalDistanceKm) { _, next in
            sceneModel.rebuildRoute(profile: profile, totalDistanceKm: next)
            sceneModel.updateRiders(
                riders: riders,
                totalDistanceKm: next,
                followPlayer: followPlayer,
                playerAppearance: playerAppearance,
                cameraMode: cameraMode,
                cameraFOV: cameraFOV
            )
        }
        .onChange(of: riders) { _, next in
            sceneModel.updateRiders(
                riders: next,
                totalDistanceKm: totalDistanceKm,
                followPlayer: followPlayer,
                playerAppearance: playerAppearance,
                cameraMode: cameraMode,
                cameraFOV: cameraFOV
            )
        }
        .onChange(of: followPlayer) { _, next in
            sceneModel.updateRiders(
                riders: riders,
                totalDistanceKm: totalDistanceKm,
                followPlayer: next,
                playerAppearance: playerAppearance,
                cameraMode: cameraMode,
                cameraFOV: cameraFOV
            )
        }
        .onChange(of: playerAppearance.signature) { _, _ in
            sceneModel.updateRiders(
                riders: riders,
                totalDistanceKm: totalDistanceKm,
                followPlayer: followPlayer,
                playerAppearance: playerAppearance,
                cameraMode: cameraMode,
                cameraFOV: cameraFOV
            )
        }
        .onChange(of: cameraMode) { _, _ in
            sceneModel.updateRiders(
                riders: riders,
                totalDistanceKm: totalDistanceKm,
                followPlayer: followPlayer,
                playerAppearance: playerAppearance,
                cameraMode: cameraMode,
                cameraFOV: cameraFOV
            )
        }
        .onChange(of: cameraFOV) { _, _ in
            sceneModel.updateRiders(
                riders: riders,
                totalDistanceKm: totalDistanceKm,
                followPlayer: followPlayer,
                playerAppearance: playerAppearance,
                cameraMode: cameraMode,
                cameraFOV: cameraFOV
            )
        }
    }
}

@MainActor
private final class Whoosh3DSceneModel: ObservableObject {
    private struct RiderUpdateContext {
        let riders: [Whoosh3DRiderSnapshot]
        let totalDistanceKm: Double
        let followPlayer: Bool
        let playerAppearance: TrainerRiderAppearance
        let cameraMode: Whoosh3DCameraMode
        let cameraFOV: Double
    }

    struct GapRow: Identifiable {
        let id: String
        let name: String
        let gapText: String
        let red: Double
        let green: Double
        let blue: Double
    }

    struct RouteSample {
        let distanceKm: Double
        let position: SCNVector3
    }

    let scene = SCNScene()
    let cameraNode = SCNNode()

    @Published var visibleRows: [GapRow] = []
    @Published var modelLoadErrorMessage: String?

    private let worldNode = SCNNode()
    private let trackNode = SCNNode()
    private let riderContainerNode = SCNNode()
    private let cameraFocusNode = SCNNode()

    private var routeSamples: [RouteSample] = []
    private var riderNodes: [String: SCNNode] = [:]
    private var riderStyleSignatureByID: [String: String] = [:]
    private var lastRiderDistanceByID: [String: Double] = [:]
    private var runnerStridePhaseByID: [String: Double] = [:]
    private var botRunnerModelIDByRiderID: [String: String] = [:]
    private var modelLoadErrorsDuringUpdate: Set<String> = []
    private var lastRiderUpdateContext: RiderUpdateContext?
    private var didConfigure = false
    private var routeRadius: CGFloat = 140
    private var routeTotalDistanceKm: Double = 10

    func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        scene.rootNode.addChildNode(worldNode)
        worldNode.addChildNode(trackNode)
        worldNode.addChildNode(riderContainerNode)
        worldNode.addChildNode(cameraFocusNode)

        scene.background.contents = PlatformColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 420
        ambient.color = PlatformColor(white: 0.78, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        worldNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .omni
        key.intensity = 950
        key.color = PlatformColor(red: 1, green: 0.97, blue: 0.9, alpha: 1)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(35, 90, 35)
        worldNode.addChildNode(keyNode)

        let rim = SCNLight()
        rim.type = .omni
        rim.intensity = 420
        rim.color = PlatformColor(red: 0.72, green: 0.82, blue: 1, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(-45, 50, -50)
        worldNode.addChildNode(rimNode)

        let camera = SCNCamera()
        camera.fieldOfView = 62
        camera.zFar = 6000
        camera.wantsHDR = true
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 110, 210)
        cameraNode.look(at: SCNVector3Zero)
        worldNode.addChildNode(cameraNode)

        let lookAt = SCNLookAtConstraint(target: cameraFocusNode)
        lookAt.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAt]
        cameraFocusNode.position = SCNVector3Zero
    }

    func rebuildRoute(profile: [Whoosh3DProfilePoint], totalDistanceKm: Double) {
        routeTotalDistanceKm = max(totalDistanceKm, 0.5)
        routeSamples = makeRouteSamples(profile: profile, totalDistanceKm: routeTotalDistanceKm)

        trackNode.childNodes.forEach { $0.removeFromParentNode() }

        let terrain = SCNCylinder(radius: routeRadius * 1.38, height: 1.2)
        terrain.radialSegmentCount = 72
        terrain.firstMaterial?.diffuse.contents = PlatformColor(red: 0.12, green: 0.16, blue: 0.13, alpha: 1)
        terrain.firstMaterial?.specular.contents = PlatformColor(white: 0.12, alpha: 1)
        let terrainNode = SCNNode(geometry: terrain)
        terrainNode.position = SCNVector3(0, -2.5, 0)
        trackNode.addChildNode(terrainNode)

        addRouteSegments()
        addCheckpoints(count: 8)

        for rider in riderNodes.values {
            rider.removeFromParentNode()
        }
        riderNodes.removeAll()
        riderStyleSignatureByID.removeAll()
        lastRiderDistanceByID.removeAll()
        runnerStridePhaseByID.removeAll()
        botRunnerModelIDByRiderID.removeAll()
    }

    func updateRiders(
        riders: [Whoosh3DRiderSnapshot],
        totalDistanceKm: Double,
        followPlayer: Bool,
        playerAppearance: TrainerRiderAppearance,
        cameraMode: Whoosh3DCameraMode,
        cameraFOV: Double
    ) {
        lastRiderUpdateContext = RiderUpdateContext(
            riders: riders,
            totalDistanceKm: totalDistanceKm,
            followPlayer: followPlayer,
            playerAppearance: playerAppearance,
            cameraMode: cameraMode,
            cameraFOV: cameraFOV
        )
        routeTotalDistanceKm = max(totalDistanceKm, 0.5)
        modelLoadErrorsDuringUpdate.removeAll()
        applyCameraFOV(cameraFOV)

        let existing = Set(riderNodes.keys)
        let incoming = Set(riders.map(\.id))
        let removed = existing.subtracting(incoming)
        for id in removed {
            riderNodes[id]?.removeFromParentNode()
            riderNodes[id] = nil
            riderStyleSignatureByID[id] = nil
            lastRiderDistanceByID[id] = nil
            runnerStridePhaseByID[id] = nil
            botRunnerModelIDByRiderID[id] = nil
        }

        for snapshot in riders {
            let styleSignature = signature(for: snapshot, playerAppearance: playerAppearance)
            let riderNode: SCNNode
            if let existingNode = riderNodes[snapshot.id], riderStyleSignatureByID[snapshot.id] == styleSignature {
                riderNode = existingNode
            } else {
                riderNodes[snapshot.id]?.removeFromParentNode()
                let created = makeRiderNode(snapshot, playerAppearance: playerAppearance)
                riderNodes[snapshot.id] = created
                riderStyleSignatureByID[snapshot.id] = styleSignature
                riderContainerNode.addChildNode(created)
                riderNode = created
            }

            let targetPosition = pointOnRoute(distanceKm: snapshot.distanceKm)
            move(node: riderNode, to: targetPosition)
            orient(node: riderNode, distanceKm: snapshot.distanceKm)
            updateRunnerAnimation(for: riderNode, riderID: snapshot.id, distanceKm: snapshot.distanceKm)
        }

        updateLeaderboardRows(riders: riders)
        updateCamera(riders: riders, followPlayer: followPlayer, cameraMode: cameraMode)
        modelLoadErrorMessage = modelLoadErrorsDuringUpdate.isEmpty
            ? nil
            : modelLoadErrorsDuringUpdate.sorted().joined(separator: "\n")
    }

    private func rerenderLastRidersIfAvailable() {
        guard let ctx = lastRiderUpdateContext else { return }
        updateRiders(
            riders: ctx.riders,
            totalDistanceKm: ctx.totalDistanceKm,
            followPlayer: ctx.followPlayer,
            playerAppearance: ctx.playerAppearance,
            cameraMode: ctx.cameraMode,
            cameraFOV: ctx.cameraFOV
        )
    }

    private func applyCameraFOV(_ value: Double) {
        let clamped = max(35, min(value, 110))
        cameraNode.camera?.fieldOfView = CGFloat(clamped)
    }

    private func signature(for rider: Whoosh3DRiderSnapshot, playerAppearance: TrainerRiderAppearance) -> String {
        if rider.isPlayer {
            return "player-\(playerAppearance.signature)"
        }
        let playerModelID = resolvedRunnerModelID(preferredID: playerAppearance.whooshRunnerModelID)
        let botModelID = assignedBotRunnerModelID(for: rider.id, excluding: playerModelID)
        return String(format: "bot-%@-%.3f-%.3f-%.3f", botModelID, rider.red, rider.green, rider.blue)
    }

    private func updateLeaderboardRows(riders: [Whoosh3DRiderSnapshot]) {
        guard !riders.isEmpty else {
            visibleRows = []
            return
        }

        let playerDistance = riders.first(where: { $0.isPlayer })?.distanceKm ?? riders[0].distanceKm
        let sorted = riders.sorted { lhs, rhs in
            if lhs.distanceKm != rhs.distanceKm {
                return lhs.distanceKm > rhs.distanceKm
            }
            return lhs.id < rhs.id
        }

        visibleRows = sorted.prefix(4).map { rider in
            let gap = rider.distanceKm - playerDistance
            let gapText: String
            if rider.isPlayer {
                gapText = L10n.choose(simplifiedChinese: "你", english: "You")
            } else if gap >= 0 {
                gapText = String(format: "+%.0fm", gap * 1000)
            } else {
                gapText = String(format: "%.0fm", gap * 1000)
            }
            return GapRow(
                id: rider.id,
                name: rider.name,
                gapText: gapText,
                red: rider.red,
                green: rider.green,
                blue: rider.blue
            )
        }
    }

    private func addRouteSegments() {
        guard routeSamples.count >= 2 else { return }

        for index in 1..<routeSamples.count {
            let start = routeSamples[index - 1].position
            let end = routeSamples[index].position
            let direction = end - start
            let length = max(0.001, direction.length)

            let road = SCNBox(width: 7.0, height: 0.35, length: length, chamferRadius: 0.07)
            let roadMaterial = SCNMaterial()
            let base: CGFloat = index % 2 == 0 ? 0.18 : 0.20
            roadMaterial.diffuse.contents = PlatformColor(red: base, green: base + 0.02, blue: base + 0.03, alpha: 1)
            roadMaterial.specular.contents = PlatformColor(white: 0.22, alpha: 1)
            roadMaterial.emission.contents = PlatformColor(red: 0.01, green: 0.02, blue: 0.03, alpha: 1)
            road.materials = [roadMaterial]

            let roadNode = SCNNode(geometry: road)
            roadNode.position = (start + end) / 2
            roadNode.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: direction.simd.normalized())
            trackNode.addChildNode(roadNode)

            let centerLine = SCNBox(width: 0.26, height: 0.02, length: length * 0.96, chamferRadius: 0.02)
            centerLine.firstMaterial?.diffuse.contents = PlatformColor(red: 0.95, green: 0.84, blue: 0.3, alpha: 1)
            let centerNode = SCNNode(geometry: centerLine)
            centerNode.position = SCNVector3(0, 0.19, 0)
            roadNode.addChildNode(centerNode)
        }
    }

    private func addCheckpoints(count: Int) {
        guard routeTotalDistanceKm > 0 else { return }
        let safeCount = max(2, count)
        for index in 0..<safeCount {
            let dist = routeTotalDistanceKm * Double(index) / Double(safeCount)
            let position = pointOnRoute(distanceKm: dist)
            let marker = SCNTorus(ringRadius: 4.6, pipeRadius: 0.15)
            marker.firstMaterial?.diffuse.contents = PlatformColor(red: 0.32, green: 0.64, blue: 1.0, alpha: 0.35)
            let node = SCNNode(geometry: marker)
            node.position = position + SCNVector3(0, 0.6, 0)
            node.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
            trackNode.addChildNode(node)
        }
    }

    private func makeRiderNode(
        _ snapshot: Whoosh3DRiderSnapshot,
        playerAppearance: TrainerRiderAppearance
    ) -> SCNNode {
        let playerModelID = resolvedRunnerModelID(preferredID: playerAppearance.whooshRunnerModelID)
        if snapshot.isPlayer {
            let furPalette = shibaFurPalette(playerAppearance.shibaFurColor)
            let harness = color(playerAppearance.shibaHarnessColor.rgb)
            let goggleTint = color(playerAppearance.glassesTint.rgb, alpha: 0.78)
            return makeShibaRunnerNode(
                modelID: playerModelID,
                furPrimary: furPalette.primary,
                furSecondary: furPalette.secondary,
                accent: harness,
                haloColor: PlatformColor(red: 0.12, green: 0.52, blue: 0.98, alpha: 0.55),
                isPlayer: true,
                goggleStyle: playerAppearance.shibaGoggleStyle,
                goggleTint: goggleTint,
                bodyType: playerAppearance.shibaBodyType
            )
        }

        let accent = PlatformColor(
            red: CGFloat(snapshot.red),
            green: CGFloat(snapshot.green),
            blue: CGFloat(snapshot.blue),
            alpha: 1
        )
        let botModelID = assignedBotRunnerModelID(for: snapshot.id, excluding: playerModelID)
        return makeShibaRunnerNode(
            modelID: botModelID,
            furPrimary: PlatformColor(red: 0.79, green: 0.47, blue: 0.20, alpha: 1),
            furSecondary: PlatformColor(red: 0.94, green: 0.90, blue: 0.82, alpha: 1),
            accent: accent,
            haloColor: accent.withAlphaComponent(0.42),
            isPlayer: false,
            goggleStyle: .none,
            goggleTint: PlatformColor(red: 0.55, green: 0.66, blue: 0.86, alpha: 0.72),
            bodyType: .standard
        )
    }

    private func makeShibaRunnerNode(
        modelID: String,
        furPrimary: PlatformColor,
        furSecondary: PlatformColor,
        accent: PlatformColor,
        haloColor: PlatformColor,
        isPlayer: Bool,
        goggleStyle: TrainerShibaGoggleStyle,
        goggleTint: PlatformColor,
        bodyType: TrainerShibaBodyType
    ) -> SCNNode {
        let scene: SCNScene
        if let url = bundledRunnerModelURL(preferredModelID: modelID) {
            let diagnostic = loadSceneWithDiagnostics(url: url)
            if let loaded = diagnostic.scene {
                scene = loaded
            } else {
                recordModelLoadError(
                    modelID: modelID,
                    fileURL: url,
                    isPlayer: isPlayer,
                    reason: diagnostic.reason ?? L10n.choose(
                        simplifiedChinese: "未知加载错误",
                        english: "Unknown load error"
                    )
                )
                return makeProceduralShibaRunnerNode(
                    furPrimary: furPrimary,
                    furSecondary: furSecondary,
                    accent: accent,
                    haloColor: haloColor,
                    isPlayer: isPlayer,
                    goggleStyle: goggleStyle,
                    goggleTint: goggleTint,
                    bodyType: bodyType
                )
            }
        } else {
            recordModelLoadError(
                modelID: modelID,
                fileURL: nil,
                isPlayer: isPlayer,
                reason: L10n.choose(
                    simplifiedChinese: "在资源包中找不到模型文件（已尝试 usda/usd/usdz/scn/dae 和大小写变体）",
                    english: "Model file not found in bundle (tried usda/usd/usdz/scn/dae and case variants)"
                )
            )
            // Fallback to procedural runner so the scene remains usable even when a model file is unsupported.
            return makeProceduralShibaRunnerNode(
                furPrimary: furPrimary,
                furSecondary: furSecondary,
                accent: accent,
                haloColor: haloColor,
                isPlayer: isPlayer,
                goggleStyle: goggleStyle,
                goggleTint: goggleTint,
                bodyType: bodyType
            )
        }

        let shibaNode = SCNNode()
        shibaNode.name = isPlayer ? "runner.player.shiba" : "runner.bot.shiba"

        let sourceChildren = scene.rootNode.childNodes.isEmpty ? [scene.rootNode] : scene.rootNode.childNodes
        for child in sourceChildren {
            shibaNode.addChildNode(child.clone())
        }

        normalizeImportedShibaNode(shibaNode)

        // Adjust material colors based on appearance settings
        shibaNode.enumerateChildNodes { node, _ in
            if let geometry = node.geometry {
                // Heuristic: try to find materials to customize.
                // For Poly Pizza Shiba, material is named "lambert2SG"
                if let material = geometry.materials.first(where: { $0.name?.lowercased().contains("lambert") ?? false }) {
                    material.diffuse.contents = furPrimary
                }
            }
        }

        // Attach accessories to the appropriate node
        if let headNode = shibaNode.childNode(withName: "head", recursively: true) ?? shibaNode.childNode(withName: "Head", recursively: true) {
            addShibaGoggles(
                to: headNode,
                style: goggleStyle,
                strapColor: accent,
                lensColor: goggleTint
            )
        }

        applyShibaBodyType(bodyType, to: shibaNode)

        let halo = SCNTorus(ringRadius: isPlayer ? 1.85 : 1.65, pipeRadius: 0.10)
        halo.firstMaterial?.diffuse.contents = haloColor
        let haloNode = SCNNode(geometry: halo)
        haloNode.name = "dog.halo"
        haloNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        haloNode.position = SCNVector3(0, 1.0, 0) // Adjusted height for imported model
        shibaNode.addChildNode(haloNode)

        let shadow = SCNCylinder(radius: 1.35, height: 0.02)
        shadow.firstMaterial?.diffuse.contents = PlatformColor(white: 0, alpha: 0.20)
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.name = "dog.shadow"
        shadowNode.position = SCNVector3(0, 0.05, 0)
        shibaNode.addChildNode(shadowNode)

        applyRunnerPose(to: shibaNode, phase: 0)
        return shibaNode
    }

    private func normalizeImportedShibaNode(_ node: SCNNode) {
        let (minBox, maxBox) = node.boundingBox
        let sizeX = maxBox.x - minBox.x
        let sizeY = maxBox.y - minBox.y
        let sizeZ = maxBox.z - minBox.z
        let maxDimension = Swift.max(sizeX, Swift.max(sizeY, sizeZ))
        guard maxDimension.isFinite, maxDimension > 0.0001 else { return }

        let targetSize: CGFloat = 3.4
        let scale = targetSize / maxDimension
        node.scale = SCNVector3(scale, scale, scale)

        let centerX = (minBox.x + maxBox.x) * 0.5 * scale
        let minY = minBox.y * scale
        let centerZ = (minBox.z + maxBox.z) * 0.5 * scale
        node.position = SCNVector3(-centerX, -minY, -centerZ)
        node.eulerAngles = SCNVector3(0, Float.pi / 2.0, 0)
    }

    private func makeProceduralShibaRunnerNode(
        furPrimary: PlatformColor,
        furSecondary: PlatformColor,
        accent: PlatformColor,
        haloColor: PlatformColor,
        isPlayer: Bool,
        goggleStyle: TrainerShibaGoggleStyle,
        goggleTint: PlatformColor,
        bodyType: TrainerShibaBodyType
    ) -> SCNNode {
        let root = SCNNode()
        root.name = isPlayer ? "runner.player.shiba" : "runner.bot.shiba"

        let bodyRoot = SCNNode()
        bodyRoot.name = "dog.bodyRoot"
        let body = SCNCapsule(capRadius: 0.62, height: 2.25)
        body.capSegmentCount = 14
        body.firstMaterial?.diffuse.contents = furPrimary
        body.firstMaterial?.specular.contents = PlatformColor(white: 0.22, alpha: 1)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.name = "dog.body"
        bodyNode.position = SCNVector3(0.15, 1.35, 0)
        bodyNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
        bodyRoot.addChildNode(bodyNode)

        let belly = SCNCapsule(capRadius: 0.34, height: 1.42)
        belly.capSegmentCount = 12
        belly.firstMaterial?.diffuse.contents = furSecondary
        let bellyNode = SCNNode(geometry: belly)
        bellyNode.position = SCNVector3(0.10, 1.05, 0)
        bellyNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
        bellyNode.scale = SCNVector3(1.0, 0.8, 0.85)
        bodyRoot.addChildNode(bellyNode)

        let chestBand = SCNTorus(ringRadius: 0.62, pipeRadius: 0.09)
        chestBand.firstMaterial?.diffuse.contents = accent
        let chestBandNode = SCNNode(geometry: chestBand)
        chestBandNode.name = "dog.harness.chest"
        chestBandNode.position = SCNVector3(0.95, 1.36, 0)
        chestBandNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        chestBandNode.scale = SCNVector3(1.0, 0.80, 1.0)
        bodyRoot.addChildNode(chestBandNode)

        let bodyBand = SCNTorus(ringRadius: 0.58, pipeRadius: 0.08)
        bodyBand.firstMaterial?.diffuse.contents = accent
        let bodyBandNode = SCNNode(geometry: bodyBand)
        bodyBandNode.name = "dog.harness.body"
        bodyBandNode.position = SCNVector3(-0.10, 1.34, 0)
        bodyBandNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        bodyBandNode.scale = SCNVector3(1.0, 0.86, 1.0)
        bodyRoot.addChildNode(bodyBandNode)

        let neck = SCNCapsule(capRadius: 0.20, height: 0.78)
        neck.firstMaterial?.diffuse.contents = furPrimary
        let neckNode = SCNNode(geometry: neck)
        neckNode.name = "dog.neck"
        neckNode.position = SCNVector3(1.28, 1.68, 0)
        neckNode.eulerAngles = SCNVector3(0, 0, -0.78)
        bodyRoot.addChildNode(neckNode)

        let headRoot = SCNNode()
        headRoot.name = "dog.headRoot"
        headRoot.position = SCNVector3(1.62, 1.96, 0)
        bodyRoot.addChildNode(headRoot)

        let head = SCNSphere(radius: 0.42)
        head.segmentCount = 16
        head.firstMaterial?.diffuse.contents = furPrimary
        let headNode = SCNNode(geometry: head)
        headNode.name = "dog.head"
        headNode.scale = SCNVector3(1.08, 0.95, 0.95)
        headRoot.addChildNode(headNode)

        let muzzle = SCNCapsule(capRadius: 0.16, height: 0.46)
        muzzle.firstMaterial?.diffuse.contents = furSecondary
        let muzzleNode = SCNNode(geometry: muzzle)
        muzzleNode.position = SCNVector3(0.33, -0.02, 0)
        muzzleNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
        muzzleNode.scale = SCNVector3(1.0, 0.9, 0.8)
        headRoot.addChildNode(muzzleNode)

        let nose = SCNSphere(radius: 0.05)
        nose.firstMaterial?.diffuse.contents = PlatformColor(white: 0.06, alpha: 1)
        let noseNode = SCNNode(geometry: nose)
        noseNode.position = SCNVector3(0.52, -0.01, 0)
        headRoot.addChildNode(noseNode)

        for side in [-1.0 as Float, 1.0 as Float] {
            let ear = SCNCone(topRadius: 0.01, bottomRadius: 0.11, height: 0.34)
            ear.firstMaterial?.diffuse.contents = furPrimary
            let earNode = SCNNode(geometry: ear)
            earNode.name = side < 0 ? "dog.ear.left" : "dog.ear.right"
            earNode.position = SCNVector3(0.03, 0.34, side * 0.16)
            earNode.eulerAngles = SCNVector3(0, 0, side < 0 ? 0.22 : -0.22)
            headRoot.addChildNode(earNode)
        }

        for side in [-1.0 as Float, 1.0 as Float] {
            let eye = SCNSphere(radius: 0.025)
            eye.firstMaterial?.diffuse.contents = PlatformColor(white: 0.04, alpha: 1)
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(0.20, 0.07, side * 0.13)
            headRoot.addChildNode(eyeNode)
        }

        addShibaGoggles(to: headRoot, style: goggleStyle, strapColor: accent, lensColor: goggleTint)

        let tailRoot = SCNNode()
        tailRoot.name = "dog.tailRoot"
        tailRoot.position = SCNVector3(-1.05, 1.72, 0)
        tailRoot.eulerAngles = SCNVector3(0, 0, 1.15)
        bodyRoot.addChildNode(tailRoot)

        let tail = SCNCapsule(capRadius: 0.09, height: 0.72)
        tail.firstMaterial?.diffuse.contents = furPrimary
        let tailNode = SCNNode(geometry: tail)
        tailNode.name = "dog.tail"
        tailNode.position = SCNVector3(0.24, 0, 0)
        tailNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
        tailRoot.addChildNode(tailNode)

        let tailTip = SCNSphere(radius: 0.07)
        tailTip.firstMaterial?.diffuse.contents = furSecondary
        let tailTipNode = SCNNode(geometry: tailTip)
        tailTipNode.position = SCNVector3(0.55, 0, 0)
        tailRoot.addChildNode(tailTipNode)

        let tailWag = SCNAction.repeatForever(
            .sequence([
                .rotateTo(x: 0, y: 0, z: CGFloat(1.00), duration: 0.22),
                .rotateTo(x: 0, y: 0, z: CGFloat(1.28), duration: 0.22)
            ])
        )
        tailWag.timingMode = .easeInEaseOut
        tailRoot.runAction(tailWag, forKey: "tailWag")

        bodyRoot.addChildNode(makeShibaLegNode(name: "dog.leg.frontLeft", color: furPrimary, pawColor: furSecondary, x: 0.82, z: -0.23))
        bodyRoot.addChildNode(makeShibaLegNode(name: "dog.leg.frontRight", color: furPrimary, pawColor: furSecondary, x: 0.82, z: 0.23))
        bodyRoot.addChildNode(makeShibaLegNode(name: "dog.leg.rearLeft", color: furPrimary, pawColor: furSecondary, x: -0.62, z: -0.23))
        bodyRoot.addChildNode(makeShibaLegNode(name: "dog.leg.rearRight", color: furPrimary, pawColor: furSecondary, x: -0.62, z: 0.23))

        root.addChildNode(bodyRoot)

        let shadow = SCNCylinder(radius: 1.35, height: 0.02)
        shadow.firstMaterial?.diffuse.contents = PlatformColor(white: 0, alpha: 0.20)
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.name = "dog.shadow"
        shadowNode.position = SCNVector3(0, 0.05, 0)
        shadowNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
        shadowNode.scale = SCNVector3(1.0, 0.05, 0.65)
        root.addChildNode(shadowNode)

        let halo = SCNTorus(ringRadius: isPlayer ? 1.85 : 1.65, pipeRadius: 0.10)
        halo.firstMaterial?.diffuse.contents = haloColor
        let haloNode = SCNNode(geometry: halo)
        haloNode.name = "dog.halo"
        haloNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        haloNode.position = SCNVector3(0, 0.08, 0)
        root.addChildNode(haloNode)

        applyShibaBodyType(bodyType, to: root)
        applyRunnerPose(to: root, phase: 0)
        return root
    }

    private func recordModelLoadError(
        modelID: String,
        fileURL: URL?,
        isPlayer: Bool,
        reason: String
    ) {
        let role = isPlayer
            ? L10n.choose(simplifiedChinese: "玩家", english: "Player")
            : L10n.choose(simplifiedChinese: "机器人", english: "Bot")
        let filePart = fileURL.map { " (\($0.lastPathComponent))" } ?? ""
        let message = "\(role) \(modelID)\(filePart): \(reason)"
        modelLoadErrorsDuringUpdate.insert(message)
        print("Whoosh3D model load failed -> \(message)")
    }

    private func bundledRunnerModelURL(preferredModelID: String) -> URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        let candidateBaseNames = candidateModelBasenames(for: preferredModelID)
        for ext in ["usda", "usd", "usdz", "scn", "dae"] {
            for base in candidateBaseNames {
                if let url = bundle.url(forResource: base, withExtension: ext) {
                    return url
                }
            }
            if let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                if let matched = urls.first(where: {
                    let lower = $0.deletingPathExtension().lastPathComponent.lowercased()
                    return candidateBaseNames.map { $0.lowercased() }.contains(lower)
                }) {
                    return matched
                }
            }
        }
        return nil
    }

    private func candidateModelBasenames(for preferredModelID: String) -> [String] {
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

    private func resolvedRunnerModelID(preferredID: String) -> String {
        let options = WhooshRunnerModelCatalog.availableModels()
        guard !options.isEmpty else { return "shiba_pup_run_colored" }
        if options.contains(where: { $0.id.caseInsensitiveCompare(preferredID) == .orderedSame }) {
            return options.first(where: { $0.id.caseInsensitiveCompare(preferredID) == .orderedSame })?.id ?? options[0].id
        }
        if let preferredColored = options.first(where: { $0.id.caseInsensitiveCompare("shiba_pup_run_colored") == .orderedSame }) {
            return preferredColored.id
        }
        if let shiba = options.first(where: { $0.id.lowercased().contains("shiba") }) {
            return shiba.id
        }
        return options[0].id
    }

    private func assignedBotRunnerModelID(for riderID: String, excluding playerModelID: String) -> String {
        let options = WhooshRunnerModelCatalog.availableModels().map(\.id)
        guard !options.isEmpty else { return "shiba_pup_run_colored" }

        let pool = options.filter { $0.caseInsensitiveCompare(playerModelID) != .orderedSame }
        let effectivePool = pool.isEmpty ? options : pool

        if let existing = botRunnerModelIDByRiderID[riderID],
           effectivePool.contains(where: { $0.caseInsensitiveCompare(existing) == .orderedSame }) {
            return effectivePool.first(where: { $0.caseInsensitiveCompare(existing) == .orderedSame }) ?? existing
        }

        let idx = stableIndex(for: riderID, modulo: effectivePool.count)
        let chosen = effectivePool[idx]
        botRunnerModelIDByRiderID[riderID] = chosen
        return chosen
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

    private func loadSceneWithDiagnostics(url: URL) -> (scene: SCNScene?, reason: String?) {
        do {
            return (try SCNScene(url: url, options: nil), nil)
        } catch {
            var reasons: [String] = [
                L10n.choose(
                    simplifiedChinese: "SCNScene 解析失败：\(error.localizedDescription)",
                    english: "SCNScene parse failed: \(error.localizedDescription)"
                )
            ]

            if let source = SCNSceneSource(url: url, options: nil) {
                if let scene = source.scene(options: nil) {
                    return (scene, nil)
                } else {
                    reasons.append(
                        L10n.choose(
                            simplifiedChinese: "SCNSceneSource 返回空场景（无法解析）",
                            english: "SCNSceneSource returned nil scene (unable to parse)"
                        )
                    )
                }
            } else {
                reasons.append(
                    L10n.choose(
                        simplifiedChinese: "SCNSceneSource 初始化失败",
                        english: "SCNSceneSource initialization failed"
                    )
                )
            }

            return (nil, reasons.joined(separator: " | "))
        }
    }

    private func makeShibaLegNode(
        name: String,
        color: PlatformColor,
        pawColor: PlatformColor,
        x: Float,
        z: Float
    ) -> SCNNode {
        let root = SCNNode()
        root.name = name
        root.position = SCNVector3(x, 1.0, z)

        let upper = SCNCapsule(capRadius: 0.09, height: 0.56)
        upper.firstMaterial?.diffuse.contents = color
        let upperNode = SCNNode(geometry: upper)
        upperNode.name = "\(name).upper"
        upperNode.position = SCNVector3(0, -0.22, 0)
        root.addChildNode(upperNode)

        let lower = SCNCapsule(capRadius: 0.075, height: 0.50)
        lower.firstMaterial?.diffuse.contents = color
        let lowerNode = SCNNode(geometry: lower)
        lowerNode.name = "\(name).lower"
        lowerNode.position = SCNVector3(0.06, -0.56, 0)
        lowerNode.eulerAngles = SCNVector3(0, 0, -0.12)
        root.addChildNode(lowerNode)

        let paw = SCNSphere(radius: 0.085)
        paw.firstMaterial?.diffuse.contents = pawColor
        let pawNode = SCNNode(geometry: paw)
        pawNode.name = "\(name).paw"
        pawNode.position = SCNVector3(0.13, -0.84, 0)
        pawNode.scale = SCNVector3(1.2, 0.7, 0.9)
        root.addChildNode(pawNode)

        return root
    }

    private func updateRunnerAnimation(for riderNode: SCNNode, riderID: String, distanceKm: Double) {
        let prevDistance = lastRiderDistanceByID[riderID]
        lastRiderDistanceByID[riderID] = distanceKm
        guard let prevDistance else {
            applyRunnerPose(to: riderNode, phase: runnerStridePhaseByID[riderID] ?? 0)
            return
        }

        var deltaKm = distanceKm - prevDistance
        if deltaKm < 0, abs(deltaKm) > routeTotalDistanceKm * 0.5 {
            deltaKm += routeTotalDistanceKm
        }
        let deltaMeters = max(0, deltaKm * 1000.0)
        let strideLengthMeters = 1.2
        let phaseAdvance = (deltaMeters / max(strideLengthMeters, 0.2)) * 2.0 * Double.pi
        let phase = ((runnerStridePhaseByID[riderID] ?? 0) + phaseAdvance).truncatingRemainder(dividingBy: 2.0 * Double.pi)
        runnerStridePhaseByID[riderID] = phase
        applyRunnerPose(to: riderNode, phase: phase)
    }

    private func applyRunnerPose(to riderNode: SCNNode, phase: Double) {
        // This is a heuristic-based animation for imported models.
        // It may look strange, but it's better than a static model.
        // For perfect animation, the model needs a known skeleton structure.
        let phaseF = Float(phase)
        let swing = sin(phaseF)
        let rearSwing = sin(phaseF + .pi)
        let bodyBob = CGFloat(0.06 * (sin(phaseF * 2.0) + 1.0) * 0.5)

        let bodyNode = riderNode.childNode(withName: "body", recursively: true) ?? riderNode
        bodyNode.position.y = 0.04 + bodyBob
        
        if let headNode = riderNode.childNode(withName: "head", recursively: true) {
            headNode.eulerAngles.z = CGFloat(0.04 * sin(phaseF * 2.0 + 0.6))
        }

        let legAmplitude: Float = 0.42
        let kneeAmplitude: Float = 0.22

        // Heuristically find leg nodes and animate them
        setLegPose(riderNode, name: "front_l", hipAngle: legAmplitude * swing, kneeAngle: kneeAmplitude * max(0, -swing))
        setLegPose(riderNode, name: "front_r", hipAngle: legAmplitude * rearSwing, kneeAngle: kneeAmplitude * max(0, -rearSwing))
        setLegPose(riderNode, name: "rear_l", hipAngle: -legAmplitude * rearSwing, kneeAngle: kneeAmplitude * max(0, rearSwing))
        setLegPose(riderNode, name: "rear_r", hipAngle: -legAmplitude * swing, kneeAngle: kneeAmplitude * max(0, swing))
    }

    private func setLegPose(_ root: SCNNode, name: String, hipAngle: Float, kneeAngle: Float) {
        // Find nodes that contain the name, case-insensitively
        let legNodes = root.childNodes(passingTest: { node, _ in
            (node.name?.lowercased().contains(name) ?? false) && (node.name?.lowercased().contains("leg") ?? true)
        })
        
        if let legRoot = legNodes.first {
            legRoot.eulerAngles.z = CGFloat(hipAngle)
            legRoot.position.y += CGFloat(0.03 * cos(hipAngle))
            
            // Try to find a "lower" leg part to bend the knee
            if let lowerLeg = legRoot.childNodes.first(where: { $0.name?.lowercased().contains("lower") ?? false }) {
                lowerLeg.eulerAngles.z = CGFloat(-0.12 + kneeAngle)
            }
        }
    }

    private func shibaFurPalette(_ fur: TrainerShibaFurColor) -> (primary: PlatformColor, secondary: PlatformColor) {
        switch fur {
        case .redWhite:
            return (
                PlatformColor(red: 0.83, green: 0.50, blue: 0.22, alpha: 1),
                PlatformColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1)
            )
        case .sesame:
            return (
                PlatformColor(red: 0.52, green: 0.45, blue: 0.38, alpha: 1),
                PlatformColor(red: 0.91, green: 0.88, blue: 0.80, alpha: 1)
            )
        case .blackTan:
            return (
                PlatformColor(red: 0.19, green: 0.19, blue: 0.21, alpha: 1),
                PlatformColor(red: 0.80, green: 0.60, blue: 0.38, alpha: 1)
            )
        case .cream:
            return (
                PlatformColor(red: 0.93, green: 0.89, blue: 0.78, alpha: 1),
                PlatformColor(red: 0.99, green: 0.97, blue: 0.92, alpha: 1)
            )
        case .darkRed:
            return (
                PlatformColor(red: 0.68, green: 0.34, blue: 0.16, alpha: 1),
                PlatformColor(red: 0.94, green: 0.84, blue: 0.71, alpha: 1)
            )
        }
    }

    private func addShibaGoggles(
        to headRoot: SCNNode,
        style: TrainerShibaGoggleStyle,
        strapColor: PlatformColor,
        lensColor: PlatformColor
    ) {
        guard style != .none else { return }

        let strap = SCNTorus(ringRadius: 0.29, pipeRadius: 0.025)
        strap.firstMaterial?.diffuse.contents = strapColor
        let strapNode = SCNNode(geometry: strap)
        strapNode.name = "dog.goggles.strap"
        strapNode.position = SCNVector3(0.02, 0.06, 0)
        strapNode.eulerAngles = SCNVector3(Float.pi / 2.0, 0, 0)
        strapNode.scale = SCNVector3(0.85, 0.62, 1.0)
        headRoot.addChildNode(strapNode)

        let frameColor = PlatformColor(white: 0.10, alpha: 1)
        switch style {
        case .sport, .wrap:
            let width: CGFloat = style == .wrap ? 0.42 : 0.34
            let height: CGFloat = style == .wrap ? 0.11 : 0.09
            let lens = SCNBox(width: width, height: height, length: 0.22, chamferRadius: 0.045)
            lens.firstMaterial?.diffuse.contents = lensColor
            lens.firstMaterial?.specular.contents = PlatformColor(white: 0.95, alpha: 1)
            let lensNode = SCNNode(geometry: lens)
            lensNode.name = "dog.goggles.lens"
            lensNode.position = SCNVector3(0.28, 0.10, 0)
            lensNode.scale = SCNVector3(1.0, 1.0, style == .wrap ? 1.18 : 1.0)
            headRoot.addChildNode(lensNode)

            let frame = SCNBox(width: width + 0.02, height: height + 0.015, length: 0.235, chamferRadius: 0.05)
            frame.firstMaterial?.diffuse.contents = frameColor
            let frameNode = SCNNode(geometry: frame)
            frameNode.name = "dog.goggles.frame"
            frameNode.position = SCNVector3(0.275, 0.10, 0)
            headRoot.addChildNode(frameNode)
        case .retro:
            for side in [-1.0 as Float, 1.0 as Float] {
                let ring = SCNTorus(ringRadius: 0.055, pipeRadius: 0.013)
                ring.firstMaterial?.diffuse.contents = frameColor
                let ringNode = SCNNode(geometry: ring)
                ringNode.position = SCNVector3(0.28, 0.09, side * 0.07)
                ringNode.eulerAngles = SCNVector3(0, Float.pi / 2.0, 0)
                headRoot.addChildNode(ringNode)

                let lens = SCNSphere(radius: 0.045)
                lens.firstMaterial?.diffuse.contents = lensColor
                lens.firstMaterial?.specular.contents = PlatformColor(white: 0.95, alpha: 1)
                let lensNode = SCNNode(geometry: lens)
                lensNode.position = SCNVector3(0.29, 0.09, side * 0.07)
                lensNode.scale = SCNVector3(0.6, 0.6, 0.32)
                headRoot.addChildNode(lensNode)
            }
            let bridge = SCNCapsule(capRadius: 0.008, height: 0.09)
            bridge.firstMaterial?.diffuse.contents = frameColor
            let bridgeNode = SCNNode(geometry: bridge)
            bridgeNode.position = SCNVector3(0.285, 0.09, 0)
            bridgeNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
            headRoot.addChildNode(bridgeNode)
        case .none:
            break
        }
    }

    private func applyShibaBodyType(_ bodyType: TrainerShibaBodyType, to root: SCNNode) {
        let bodyRootScale: SCNVector3
        let headScale: SCNVector3
        let shadowScaleX: CGFloat
        switch bodyType {
        case .compact:
            bodyRootScale = SCNVector3(0.92, 0.94, 0.92)
            headScale = SCNVector3(0.95, 0.95, 0.95)
            shadowScaleX = 0.90
        case .standard:
            bodyRootScale = SCNVector3(1.0, 1.0, 1.0)
            headScale = SCNVector3(1.0, 1.0, 1.0)
            shadowScaleX = 1.0
        case .athletic:
            bodyRootScale = SCNVector3(1.08, 0.97, 0.92)
            headScale = SCNVector3(0.96, 0.96, 0.96)
            shadowScaleX = 1.05
        case .chunky:
            bodyRootScale = SCNVector3(1.06, 1.08, 1.12)
            headScale = SCNVector3(1.08, 1.05, 1.05)
            shadowScaleX = 1.12
        }

        if let bodyRoot = root.childNode(withName: "dog.bodyRoot", recursively: true) {
            bodyRoot.scale = bodyRootScale
        }
        if let headRoot = root.childNode(withName: "dog.headRoot", recursively: true) {
            headRoot.scale = headScale
        }
        if let shadow = root.childNode(withName: "dog.shadow", recursively: true) {
            shadow.scale.x = shadowScaleX
        }
    }



    private func orient(node: SCNNode, distanceKm: Double) {
        let current = pointOnRoute(distanceKm: distanceKm)
        let ahead = pointOnRoute(distanceKm: distanceKm + max(0.01, routeTotalDistanceKm * 0.004))
        let forward = ahead - current
        let heading = SIMD3<Float>(Float(forward.x), 0, Float(forward.z))
        guard simd_length(heading) > 0.0001 else { return }
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: simd_normalize(heading))
    }

    private func move(node: SCNNode, to target: SCNVector3) {
        if (node.position - target).length < 0.08 {
            node.position = target
            return
        }
        let action = SCNAction.move(to: target, duration: 0.25)
        action.timingMode = .easeInEaseOut
        node.runAction(action, forKey: "move")
    }

    private func updateWheelRotation(for riderNode: SCNNode, riderID: String, distanceKm: Double) {
        let prevDistance = lastRiderDistanceByID[riderID]
        lastRiderDistanceByID[riderID] = distanceKm
        guard let prevDistance else { return }

        var deltaKm = distanceKm - prevDistance
        if deltaKm < 0 {
            // Lap wrap or reset; keep wrap-sized jumps from creating reverse/huge spins.
            if abs(deltaKm) > routeTotalDistanceKm * 0.5 {
                deltaKm += routeTotalDistanceKm
            }
        }
        let deltaMeters = max(0, deltaKm * 1000.0)
        guard deltaMeters > 0.001 else { return }

        // Wheel radius visually matches torus ringRadius ~= 1.45 scene units.
        let wheelRadiusSceneUnits = 1.45
        let wheelCircumference = 2.0 * Double.pi * wheelRadiusSceneUnits
        let radians = deltaMeters / max(wheelCircumference, 0.001) * 2.0 * Double.pi
        guard radians.isFinite else { return }

        riderNode.enumerateChildNodes { child, _ in
            guard let name = child.name, name.hasPrefix("wheel.") else { return }
            child.eulerAngles.x -= CGFloat(radians)
        }
    }

    private func updateCamera(riders: [Whoosh3DRiderSnapshot], followPlayer: Bool, cameraMode: Whoosh3DCameraMode) {
        if followPlayer, let player = riders.first(where: { $0.isPlayer }) {
            let current = pointOnRoute(distanceKm: player.distanceKm)
            let ahead = pointOnRoute(distanceKm: player.distanceKm + max(0.03, routeTotalDistanceKm * 0.01))
            let tangent = (ahead - current).normalized()
            let lateral = SCNVector3(-tangent.z, 0, tangent.x)
            let targetCamera: SCNVector3
            let targetFocus: SCNVector3

            switch cameraMode {
            case .chase:
                targetCamera = current - tangent * 20.0 + lateral * 6.0 + SCNVector3(0, 10.5, 0)
                targetFocus = current + SCNVector3(0, 1.9, 0)
            case .nearChase:
                targetCamera = current - tangent * 12.0 + lateral * 2.4 + SCNVector3(0, 5.0, 0)
                targetFocus = current + tangent * 3.0 + SCNVector3(0, 1.5, 0)
            case .side:
                targetCamera = current + lateral * 16.0 + SCNVector3(0, 7.0, 0)
                targetFocus = current + tangent * 5.0 + SCNVector3(0, 1.5, 0)
            case .front:
                targetCamera = current + tangent * 15.0 + lateral * 1.2 + SCNVector3(0, 5.5, 0)
                targetFocus = current + SCNVector3(0, 1.6, 0)
            case .overhead:
                targetCamera = current + SCNVector3(0, 34.0, 0.01)
                targetFocus = current + tangent * 4.0
            }

            move(node: cameraNode, to: targetCamera)
            move(node: cameraFocusNode, to: targetFocus)
        } else {
            let top = SCNVector3(0, max(120, routeRadius * 0.88), routeRadius * 1.35)
            move(node: cameraNode, to: top)
            move(node: cameraFocusNode, to: SCNVector3Zero)
        }
    }

    private func makeRouteSamples(profile: [Whoosh3DProfilePoint], totalDistanceKm: Double) -> [RouteSample] {
        let sorted = profile.sorted { $0.distanceKm < $1.distanceKm }
        let points: [Whoosh3DProfilePoint]
        if sorted.count >= 6 {
            points = sorted
        } else {
            points = defaultProfile(totalDistanceKm: totalDistanceKm)
        }

        let minElevation = points.map(\.elevationM).min() ?? 0
        let maxElevation = points.map(\.elevationM).max() ?? minElevation
        let elevationRange = max(1.0, maxElevation - minElevation)
        let verticalScale = min(0.9, 26.0 / elevationRange)

        routeRadius = max(95, CGFloat(totalDistanceKm * 12.5))
        var samples: [RouteSample] = []
        samples.reserveCapacity(points.count + 1)

        for point in points {
            let ratio = max(0, min(point.distanceKm / totalDistanceKm, 1))
            let angle = ratio * 2.0 * .pi
            let radiusWave = 1.0 + 0.06 * sin(angle * 3.2)
            let radius = routeRadius * CGFloat(radiusWave)

            let x = CGFloat(cos(angle)) * radius
            let z = CGFloat(sin(angle)) * radius
            let y = CGFloat((point.elevationM - minElevation) * verticalScale)
            samples.append(RouteSample(distanceKm: point.distanceKm, position: SCNVector3(x, y, z)))
        }

        if let first = samples.first, (samples.last?.distanceKm ?? 0) < totalDistanceKm {
            samples.append(RouteSample(distanceKm: totalDistanceKm, position: first.position))
        }

        return deduplicate(samples)
    }

    private func deduplicate(_ samples: [RouteSample]) -> [RouteSample] {
        guard !samples.isEmpty else { return [] }
        var result: [RouteSample] = [samples[0]]
        result.reserveCapacity(samples.count)
        for sample in samples.dropFirst() {
            if abs(sample.distanceKm - (result.last?.distanceKm ?? -1)) > 0.000_001 {
                result.append(sample)
            }
        }
        return result
    }

    private func defaultProfile(totalDistanceKm: Double) -> [Whoosh3DProfilePoint] {
        let count = 72
        return (0...count).map { idx in
            let ratio = Double(idx) / Double(count)
            let distance = ratio * totalDistanceKm
            let rolling = sin(ratio * .pi * 2.0) * 32.0
            let shortWave = sin(ratio * .pi * 7.0) * 8.0
            return Whoosh3DProfilePoint(distanceKm: distance, elevationM: 110 + rolling + shortWave)
        }
    }

    private func pointOnRoute(distanceKm: Double) -> SCNVector3 {
        guard routeSamples.count >= 2 else { return SCNVector3Zero }
        let wrapped = wrappedDistance(distanceKm)

        guard
            let upperIndex = routeSamples.firstIndex(where: { $0.distanceKm >= wrapped }),
            upperIndex > 0
        else {
            return routeSamples.last?.position ?? SCNVector3Zero
        }

        let lower = routeSamples[upperIndex - 1]
        let upper = routeSamples[upperIndex]
        let span = max(0.000_001, upper.distanceKm - lower.distanceKm)
        let t = CGFloat((wrapped - lower.distanceKm) / span)
        return lower.position + (upper.position - lower.position) * t
    }

    private func wrappedDistance(_ distanceKm: Double) -> Double {
        guard routeTotalDistanceKm > 0 else { return 0 }
        let mod = distanceKm.truncatingRemainder(dividingBy: routeTotalDistanceKm)
        return mod >= 0 ? mod : (mod + routeTotalDistanceKm)
    }

    private func color(_ rgb: (Double, Double, Double), alpha: CGFloat = 1) -> PlatformColor {
        PlatformColor(
            red: CGFloat(max(0, min(1, rgb.0))),
            green: CGFloat(max(0, min(1, rgb.1))),
            blue: CGFloat(max(0, min(1, rgb.2))),
            alpha: alpha
        )
    }
}

private extension SCNVector3 {
    static func +(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    static func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    static func *(lhs: SCNVector3, rhs: CGFloat) -> SCNVector3 {
        SCNVector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    static func /(lhs: SCNVector3, rhs: CGFloat) -> SCNVector3 {
        SCNVector3(lhs.x / rhs, lhs.y / rhs, lhs.z / rhs)
    }

    var length: CGFloat {
        sqrt(x * x + y * y + z * z)
    }

    func normalized() -> SCNVector3 {
        let len = length
        guard len > 0.000_001 else { return SCNVector3Zero }
        return self / len
    }

    var simd: SIMD3<Float> {
        SIMD3<Float>(Float(x), Float(y), Float(z))
    }
}

private extension SIMD3 where Scalar == Float {
    func normalized() -> SIMD3<Float> {
        let len = simd_length(self)
        guard len > 0.000_001 else { return SIMD3<Float>(0, 0, 1) }
        return self / len
    }
}

#else
struct Whoosh3DGameView: View {
    let profile: [Whoosh3DProfilePoint]
    let totalDistanceKm: Double
    let riders: [Whoosh3DRiderSnapshot]
    let playerAppearance: TrainerRiderAppearance
    let currentSpeedKPH: Double
    let currentPowerW: Double
    let currentGradePercent: Double
    let currentLap: Int
    let followPlayer: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary.opacity(0.35))
            .overlay(
                Text(
                    L10n.choose(
                        simplifiedChinese: "当前平台不支持 3D 场景。",
                        english: "3D scene is unavailable on this platform."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            )
            .frame(height: 220)
    }
}
#endif
