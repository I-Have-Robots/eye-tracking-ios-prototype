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
/// This is the same virtual-screen hit-testing approach as the original
/// prototype's ViewController, extracted so the game and the demo can share it.
final class GazeTracker: NSObject {

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    weak var delegate: GazeTrackerDelegate?

    private let sceneView: ARSCNView

    private let faceNode = SCNNode()
    private let eyeLNode = SCNNode()
    private let eyeRNode = SCNNode()
    private let lookAtTargetLNode = SCNNode()
    private let lookAtTargetRNode = SCNNode()
    private let virtualPhoneNode = SCNNode()

    private let virtualScreenNode: SCNNode = {
        let screenGeometry = SCNPlane(width: 1, height: 1)
        screenGeometry.firstMaterial?.isDoubleSided = true
        // The plane sits exactly at the camera so it is never rendered,
        // but it remains hit-testable for the gaze ray segments.
        return SCNNode(geometry: screenGeometry)
    }()

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
        virtualPhoneNode.addChildNode(virtualScreenNode)
        faceNode.addChildNode(eyeLNode)
        faceNode.addChildNode(eyeRNode)
        eyeLNode.addChildNode(lookAtTargetLNode)
        eyeRNode.addChildNode(lookAtTargetRNode)

        // Targets 2 m out along each eye's look direction define the gaze ray segments.
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

    // MARK: - Gaze computation

    private func update(withFaceAnchor anchor: ARFaceAnchor) {
        eyeRNode.simdTransform = anchor.rightEyeTransform
        eyeLNode.simdTransform = anchor.leftEyeTransform

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
        let hits = virtualPhoneNode.hitTestWithSegment(from: target.worldPosition,
                                                       to: eyeNode.worldPosition,
                                                       options: nil)
        guard let hit = hits.first else { return nil }

        // Same mapping as the original prototype, parameterized on the actual
        // screen point size. The 312/812 term compensates the vertical origin.
        let heightCompensation = screenPointSize.height * (312.0 / 812.0)
        let x = CGFloat(hit.localCoordinates.x) / (phonePhysicalSize.width / 2) * screenPointSize.width
        let y = CGFloat(hit.localCoordinates.y) / (phonePhysicalSize.height / 2) * screenPointSize.height + heightCompensation

        return CGPoint(x: screenPointSize.width / 2 + x,
                       y: screenPointSize.height / 2 - y)
    }
}

// MARK: - ARSCNViewDelegate

extension GazeTracker: ARSCNViewDelegate {

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        faceNode.transform = node.transform
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
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
