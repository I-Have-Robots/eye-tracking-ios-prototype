//
//  GazeTracker.swift
//  Eyes Tracking
//
//  Copyright © 2018 virakri. All rights reserved.
//

import ARKit
import SceneKit
import UIKit

protocol GazeTrackerDelegate: AnyObject {
    /// Called on the main thread with per-eye gaze points in screen coordinates.
    func gazeTracker(_ tracker: GazeTracker,
                     didUpdateLeftGaze leftGaze: CGPoint,
                     rightGaze: CGPoint,
                     faceDistance: Float)
}

/// Wraps an ARSCNView face-tracking session and converts ARKit's per-eye
/// transforms into smoothed, independent left/right screen-space gaze points.
///
/// The gaze ray for each eye is intersected analytically with the phone-screen
/// plane (z = 0 in the camera's local space). The original prototype instead
/// ran hitTestWithSegment against a finite 1 m virtual plane, which silently
/// returned no result whenever the (noisy) ray fell outside it — the gaze
/// point would freeze or never appear unless the head was turned far enough
/// to swing the ray back onto the plane.
///
/// The tracker also renders a tracking-quality visualization into its scene:
/// a wireframe mask fitted to the AR face, and the original demo's blue cone
/// "gazers" on each eye showing where that eye's orientation is pointed.
final class GazeTracker: NSObject {

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    weak var delegate: GazeTrackerDelegate?

    /// Multiplier on how far gaze movement travels on screen. 1.0 maps the
    /// physical screen geometry exactly; the original demo effectively used
    /// 2.0, which overshoots badly once per-eye noise (or glasses) kicks in.
    var sensitivity: CGFloat = 1.5

    private let sceneView: ARSCNView

    private let faceNode = SCNNode()
    private let eyeLNode = SCNNode()
    private let eyeRNode = SCNNode()
    private let lookAtTargetLNode = SCNNode()
    private let lookAtTargetRNode = SCNNode()
    private let virtualPhoneNode = SCNNode()
    private var faceMeshNode: SCNNode?

    // Physical screen metrics calibrated for iPhone X-class devices (see README).
    private let phonePhysicalSize = CGSize(width: 0.0623908297, height: 0.135096943231532)
    private var screenPointSize = UIScreen.main.bounds.size

    private var leftSamples: [CGPoint] = []
    private var rightSamples: [CGPoint] = []
    private let smoothingWindow = 8

    init(sceneView: ARSCNView) {
        self.sceneView = sceneView
        super.init()

        sceneView.delegate = self
        sceneView.automaticallyUpdatesLighting = true

        sceneView.scene.rootNode.addChildNode(faceNode)
        sceneView.scene.rootNode.addChildNode(virtualPhoneNode)
        faceNode.addChildNode(eyeLNode)
        faceNode.addChildNode(eyeRNode)
        eyeLNode.addChildNode(lookAtTargetLNode)
        eyeRNode.addChildNode(lookAtTargetRNode)

        eyeLNode.addChildNode(Self.makeGazerNode())
        eyeRNode.addChildNode(Self.makeGazerNode())

        // Targets 2 m out along each eye's look direction define the gaze rays.
        lookAtTargetLNode.position.z = 2
        lookAtTargetRNode.position.z = 2
    }

    func start() {
        guard Self.isSupported else { return }
        if let screen = sceneView.window?.windowScene?.screen {
            screenPointSize = screen.bounds.size
        }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func pause() {
        sceneView.session.pause()
    }

    // MARK: - Visualization

    /// The blue eye "gazer" from the original demo: a cone sitting on the
    /// eyeball pointing along the eye's orientation, extended with a thin
    /// beam so the pointing direction is obvious at a glance.
    private static func makeGazerNode() -> SCNNode {
        let parentNode = SCNNode()

        let coneGeometry = SCNCone(topRadius: 0.005, bottomRadius: 0, height: 0.2)
        coneGeometry.radialSegmentCount = 3
        coneGeometry.firstMaterial?.diffuse.contents = UIColor.blue
        coneGeometry.firstMaterial?.lightingModel = .constant
        let coneNode = SCNNode(geometry: coneGeometry)
        coneNode.eulerAngles.x = -.pi / 2
        coneNode.position.z = 0.1

        let beamGeometry = SCNCylinder(radius: 0.001, height: 0.5)
        beamGeometry.radialSegmentCount = 6
        beamGeometry.firstMaterial?.diffuse.contents = UIColor.blue.withAlphaComponent(0.7)
        beamGeometry.firstMaterial?.lightingModel = .constant
        let beamNode = SCNNode(geometry: beamGeometry)
        beamNode.eulerAngles.x = -.pi / 2
        beamNode.position.z = 0.25

        parentNode.addChildNode(coneNode)
        parentNode.addChildNode(beamNode)
        return parentNode
    }

    /// Fits a wireframe mask to the AR face by attaching an ARSCNFaceGeometry
    /// to the anchor's node — ARKit then keeps it glued to the face for free.
    private func attachFaceMesh(to anchorNode: SCNNode) {
        guard faceMeshNode?.parent !== anchorNode else { return }
        faceMeshNode?.removeFromParentNode()
        faceMeshNode = nil

        guard let device = sceneView.device,
              let meshGeometry = ARSCNFaceGeometry(device: device) else { return }
        let material = meshGeometry.firstMaterial
        material?.fillMode = .lines
        material?.diffuse.contents = UIColor(white: 1, alpha: 0.7)
        material?.lightingModel = .constant
        let meshNode = SCNNode(geometry: meshGeometry)
        faceMeshNode = meshNode
        anchorNode.addChildNode(meshNode)
    }

    // MARK: - Gaze computation

    private func update(withFaceAnchor anchor: ARFaceAnchor) {
        eyeRNode.simdTransform = anchor.rightEyeTransform
        eyeLNode.simdTransform = anchor.leftEyeTransform

        (faceMeshNode?.geometry as? ARSCNFaceGeometry)?.update(from: anchor.geometry)

        DispatchQueue.main.async { [weak self] in
            self?.publishGaze()
        }
    }

    private func publishGaze() {
        guard let left = screenPoint(forEye: eyeLNode, target: lookAtTargetLNode),
              let right = screenPoint(forEye: eyeRNode, target: lookAtTargetRNode) else { return }

        leftSamples = Array((leftSamples + [left]).suffix(smoothingWindow))
        rightSamples = Array((rightSamples + [right]).suffix(smoothingWindow))

        guard let smoothLeft = leftSamples.averagePoint,
              let smoothRight = rightSamples.averagePoint else { return }

        let distanceL = (eyeLNode.worldPosition - SCNVector3Zero).length()
        let distanceR = (eyeRNode.worldPosition - SCNVector3Zero).length()

        delegate?.gazeTracker(self,
                              didUpdateLeftGaze: smoothLeft,
                              rightGaze: smoothRight,
                              faceDistance: (distanceL + distanceR) / 2)
    }

    private func screenPoint(forEye eyeNode: SCNNode, target: SCNNode) -> CGPoint? {
        // Intersect the eye→target ray with the z = 0 plane of the phone's
        // camera space analytically, so a valid point comes back for every
        // frame in which the eye is looking anywhere toward the screen.
        let eyeLocal = virtualPhoneNode.simdConvertPosition(eyeNode.simdWorldPosition, from: nil)
        let targetLocal = virtualPhoneNode.simdConvertPosition(target.simdWorldPosition, from: nil)

        let deltaZ = targetLocal.z - eyeLocal.z
        guard abs(deltaZ) > .ulpOfOne else { return nil }
        let t = -eyeLocal.z / deltaZ
        guard t > 0 else { return nil } // gaze points away from the screen

        let hitX = CGFloat(eyeLocal.x + t * (targetLocal.x - eyeLocal.x))
        let hitY = CGFloat(eyeLocal.y + t * (targetLocal.y - eyeLocal.y))

        // Points-per-meter mapping scaled by sensitivity, plus the vertical
        // compensation for the camera sitting above the screen center.
        let heightCompensation = screenPointSize.height * (312.0 / 812.0)
        let x = hitX / phonePhysicalSize.width * screenPointSize.width * sensitivity
        let y = hitY / phonePhysicalSize.height * screenPointSize.height * sensitivity + heightCompensation

        return CGPoint(x: screenPointSize.width / 2 + x,
                       y: screenPointSize.height / 2 - y)
    }
}

// MARK: - ARSCNViewDelegate

extension GazeTracker: ARSCNViewDelegate {

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        faceNode.transform = node.transform
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        attachFaceMesh(to: node)
        update(withFaceAnchor: faceAnchor)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        faceNode.transform = node.transform
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        update(withFaceAnchor: faceAnchor)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let pointOfViewTransform = sceneView.pointOfView?.transform else { return }
        virtualPhoneNode.transform = pointOfViewTransform
    }
}
