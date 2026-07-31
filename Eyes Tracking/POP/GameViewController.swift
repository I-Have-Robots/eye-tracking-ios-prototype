//
//  GameViewController.swift
//  Eyes Tracking
//
//  Copyright © 2018 virakri. All rights reserved.
//

import UIKit
import ARKit

/// Hosts the POP game: wires the GazeTracker to the GameEngine with a
/// CADisplayLink game loop and renders the balloon, crosshairs, and HUD.
final class GameViewController: UIViewController {

    private let engine = GameEngine()
    private var gazeTracker: GazeTracker?

    private let sceneView = ARSCNView()
    private let balloonView = BalloonView()
    private let leftCrosshair = CrosshairView(color: .systemBlue)
    private let rightCrosshair = CrosshairView(color: .systemRed)

    private let scoreLabel = UILabel()
    private let levelLabel = UILabel()
    private let hudStack = UIStackView()
    private let hintLabel = UILabel()
    private let levelToastLabel = UILabel()
    private let quitButton = UIButton(type: .system)

    private let startOverlay = UIView()
    private let startButton = UIButton(type: .system)

    // Setup phase: the AR view goes full screen so the player can check the
    // mesh mask and per-eye gazers, tune sensitivity, and then continue.
    private let setupPanel = UIView()
    private let setupStatusLabel = UILabel()
    private let sensitivitySlider = UISlider()
    private let continueButton = UIButton(type: .system)
    private var sceneViewCornerConstraints: [NSLayoutConstraint] = []
    private var sceneViewFullscreenConstraints: [NSLayoutConstraint] = []

    private static let sensitivityKey = "gazeSensitivity"

    private enum Phase { case idle, setup, calibrating, playing }

    private var displayLink: CADisplayLink?
    private var lastTickTime: CFTimeInterval = 0
    private var latestLeftGaze: CGPoint?
    private var latestRightGaze: CGPoint?
    private var lastGazeUpdateTime: CFTimeInterval = 0
    private var phase = Phase.idle

    /// Gaze points go stale when ARKit stops updating the face anchor (face
    /// out of frame); treat them as absent instead of showing frozen crosshairs.
    private var gazeIsFresh: Bool {
        CACurrentMediaTime() - lastGazeUpdateTime < 0.6
    }

    // Lock-on calibration: while the player stares at the center target we
    // measure each eye's offset from it, then subtract that during play so
    // both crosshairs converge on the true gaze point.
    private let calibrationTarget = BalloonView()
    private var leftCalibrationSamples: [CGPoint] = []
    private var rightCalibrationSamples: [CGPoint] = []
    private var calibrationProgress: Double = 0
    private var leftGazeOffset = CGPoint.zero
    private var rightGazeOffset = CGPoint.zero

    private let popHaptics = UIImpactFeedbackGenerator(style: .medium)

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)

        engine.delegate = self
        setupGameLayer()
        setupHUD()
        setupConfigurationUI()
        setupStartOverlay()

        if GazeTracker.isSupported {
            let tracker = GazeTracker(sceneView: sceneView)
            tracker.delegate = self
            tracker.sensitivity = savedSensitivity
            gazeTracker = tracker
        }
        sensitivitySlider.value = Float(savedSensitivity)
    }

    private var savedSensitivity: CGFloat {
        let stored = UserDefaults.standard.object(forKey: Self.sensitivityKey) as? Double
        return CGFloat(stored ?? 1.5)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        gazeTracker?.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopGameLoop()
        gazeTracker?.pause()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        switch phase {
        case .playing:
            engine.playfield = playfieldRect()
        case .calibrating:
            calibrationTarget.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        case .idle, .setup:
            break
        }
    }

    // MARK: - Setup

    private func setupGameLayer() {
        balloonView.isHidden = true
        view.addSubview(balloonView)

        calibrationTarget.emoji = "🎯"
        calibrationTarget.isHidden = true
        view.addSubview(calibrationTarget)

        // The AR face view: full screen during the setup phase so the mesh
        // mask and eye gazers are easy to line up, then a small corner
        // preview during calibration and play, like the original demo.
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.layer.cornerRadius = 16
        sceneView.clipsToBounds = true
        view.addSubview(sceneView)
        sceneViewCornerConstraints = [
            sceneView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            sceneView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            sceneView.widthAnchor.constraint(equalToConstant: 84),
            sceneView.heightAnchor.constraint(equalToConstant: 112),
        ]
        sceneViewFullscreenConstraints = [
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]
        NSLayoutConstraint.activate(sceneViewCornerConstraints)

        // Crosshairs sit above the AR view so they stay visible while it is
        // full screen during setup.
        leftCrosshair.isHidden = true
        rightCrosshair.isHidden = true
        view.addSubview(leftCrosshair)
        view.addSubview(rightCrosshair)
    }

    private func setupHUD() {
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 44, weight: .bold)
        scoreLabel.textColor = .white
        scoreLabel.textAlignment = .center
        scoreLabel.text = "0"

        levelLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        levelLabel.textColor = UIColor(white: 1, alpha: 0.7)
        levelLabel.textAlignment = .center
        levelLabel.text = "Level 1"

        hudStack.addArrangedSubview(scoreLabel)
        hudStack.addArrangedSubview(levelLabel)
        hudStack.axis = .vertical
        hudStack.spacing = 2
        hudStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hudStack)

        hintLabel.font = .systemFont(ofSize: 15, weight: .medium)
        hintLabel.textColor = UIColor(white: 1, alpha: 0.6)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.text = "Converge both eyes on the balloon"
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        levelToastLabel.font = .systemFont(ofSize: 34, weight: .heavy)
        levelToastLabel.textColor = .systemYellow
        levelToastLabel.textAlignment = .center
        levelToastLabel.alpha = 0
        levelToastLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(levelToastLabel)

        quitButton.setTitle("✕", for: .normal)
        quitButton.titleLabel?.font = .systemFont(ofSize: 26, weight: .semibold)
        quitButton.tintColor = UIColor(white: 1, alpha: 0.7)
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        quitButton.addTarget(self, action: #selector(quitTapped), for: .touchUpInside)
        view.addSubview(quitButton)

        NSLayoutConstraint.activate([
            hudStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hudStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            hintLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            hintLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            // Keeps clear of the corner AR preview; not anchored to the AR
            // view itself since that goes full screen during setup.
            hintLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -112),

            levelToastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            levelToastLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            quitButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            quitButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            quitButton.widthAnchor.constraint(equalToConstant: 44),
            quitButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupConfigurationUI() {
        setupPanel.backgroundColor = UIColor(white: 0, alpha: 0.6)
        setupPanel.layer.cornerRadius = 20
        setupPanel.isHidden = true
        setupPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(setupPanel)

        let titleLabel = UILabel()
        titleLabel.text = "Eye Tracking Setup"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        setupStatusLabel.font = .systemFont(ofSize: 15)
        setupStatusLabel.textColor = UIColor(white: 1, alpha: 0.9)
        setupStatusLabel.textAlignment = .center
        setupStatusLabel.numberOfLines = 0

        let sliderLabel = UILabel()
        sliderLabel.text = "Gaze sensitivity"
        sliderLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        sliderLabel.textColor = UIColor(white: 1, alpha: 0.9)
        sliderLabel.textAlignment = .center

        sensitivitySlider.minimumValue = 0.5
        sensitivitySlider.maximumValue = 2.5
        sensitivitySlider.addTarget(self, action: #selector(sensitivityChanged), for: .valueChanged)

        continueButton.setTitle("Continue", for: .normal)
        continueButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        continueButton.setTitleColor(.white, for: .normal)
        continueButton.backgroundColor = .systemPink
        continueButton.layer.cornerRadius = 12
        continueButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 40, bottom: 10, right: 40)
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, setupStatusLabel, sliderLabel, sensitivitySlider, continueButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.setCustomSpacing(6, after: sliderLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        setupPanel.addSubview(stack)

        NSLayoutConstraint.activate([
            setupPanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            setupPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            setupPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            stack.topAnchor.constraint(equalTo: setupPanel.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: setupPanel.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: setupPanel.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: setupPanel.trailingAnchor, constant: -20),

            sensitivitySlider.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func setupStartOverlay() {
        startOverlay.backgroundColor = UIColor(white: 0, alpha: 0.75)
        startOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(startOverlay)

        let titleLabel = UILabel()
        titleLabel.text = "POP 🎈"
        titleLabel.font = .systemFont(ofSize: 54, weight: .heavy)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        let instructionsLabel = UILabel()
        instructionsLabel.numberOfLines = 0
        instructionsLabel.textAlignment = .center
        instructionsLabel.textColor = UIColor(white: 1, alpha: 0.85)
        instructionsLabel.font = .systemFont(ofSize: 17)
        if GazeTracker.isSupported {
            instructionsLabel.text = """
            First, set up tracking: a mesh mask locks
            onto your face and blue beams show where
            each eye is pointed. Tune the sensitivity
            until the crosshairs follow your gaze.

            Then stare at the center 🎯 to lock on —
            and the game begins.

            🔵 Left eye · 🔴 Right eye
            Get both crosshairs on the balloon and
            hold your gaze to pop it.
            """
        } else {
            instructionsLabel.text = "This game requires a device with TrueDepth face tracking (ARKit)."
        }

        startButton.setTitle("Start", for: .normal)
        startButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        startButton.setTitleColor(.white, for: .normal)
        startButton.backgroundColor = .systemPink
        startButton.layer.cornerRadius = 14
        startButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 48, bottom: 12, right: 48)
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        startButton.isEnabled = GazeTracker.isSupported
        startButton.alpha = GazeTracker.isSupported ? 1 : 0.4

        let stack = UIStackView(arrangedSubviews: [titleLabel, instructionsLabel, startButton])
        stack.axis = .vertical
        stack.spacing = 28
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        startOverlay.addSubview(stack)

        NSLayoutConstraint.activate([
            startOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            startOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            startOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            startOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.centerXAnchor.constraint(equalTo: startOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: startOverlay.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: startOverlay.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: startOverlay.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Game loop

    @objc private func startTapped() {
        UIView.animate(withDuration: 0.3, animations: { self.startOverlay.alpha = 0 }) { _ in
            self.startOverlay.isHidden = true
        }

        beginSetup()

        lastTickTime = 0
        displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink?.add(to: .main, forMode: .common)
    }

    // MARK: - Setup phase

    private func beginSetup() {
        phase = .setup
        balloonView.isHidden = true
        calibrationTarget.isHidden = true
        hudStack.isHidden = true
        hintLabel.isHidden = true

        NSLayoutConstraint.deactivate(sceneViewCornerConstraints)
        NSLayoutConstraint.activate(sceneViewFullscreenConstraints)
        sceneView.layer.cornerRadius = 0
        view.layoutIfNeeded()

        setupPanel.isHidden = false
        view.bringSubviewToFront(setupPanel)
        view.bringSubviewToFront(quitButton)
    }

    private func updateSetup() {
        let tracked = gazeIsFresh
        layoutCrosshairs(left: tracked ? latestLeftGaze : nil,
                         right: tracked ? latestRightGaze : nil,
                         radius: LevelConfig.forLevel(1).crosshairRadius,
                         leftOn: false, rightOn: false)

        if tracked {
            setupStatusLabel.text = """
            Mask locked. The blue beams show where each eye points; \
            🔵/🔴 are where that lands on screen. Look around — if the \
            rings move too far or too little, adjust the sensitivity.
            """
        } else {
            setupStatusLabel.text = "Hold the phone at arm's length and center your face until the mesh mask appears."
        }
        continueButton.isEnabled = tracked
        continueButton.alpha = tracked ? 1 : 0.5
    }

    @objc private func sensitivityChanged() {
        gazeTracker?.sensitivity = CGFloat(sensitivitySlider.value)
        UserDefaults.standard.set(Double(sensitivitySlider.value), forKey: Self.sensitivityKey)
    }

    @objc private func continueTapped() {
        setupPanel.isHidden = true
        hudStack.isHidden = false
        hintLabel.isHidden = false

        NSLayoutConstraint.deactivate(sceneViewFullscreenConstraints)
        NSLayoutConstraint.activate(sceneViewCornerConstraints)
        UIView.animate(withDuration: 0.35) {
            self.sceneView.layer.cornerRadius = 16
            self.view.layoutIfNeeded()
        }

        beginCalibration()
    }

    private func beginCalibration() {
        phase = .calibrating
        calibrationProgress = 0
        leftCalibrationSamples = []
        rightCalibrationSamples = []
        leftGazeOffset = .zero
        rightGazeOffset = .zero

        balloonView.isHidden = true
        calibrationTarget.bounds = CGRect(x: 0, y: 0, width: 72, height: 72)
        calibrationTarget.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        calibrationTarget.progress = 0
        calibrationTarget.isHidden = false
        calibrationTarget.animateSpawn()
    }

    private func startPlaying() {
        phase = .playing
        calibrationTarget.isHidden = true
        balloonView.isHidden = false
        engine.start(in: playfieldRect())
    }

    private func stopGameLoop() {
        displayLink?.invalidate()
        displayLink = nil
        phase = .idle
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTickTime = now }
        guard lastTickTime > 0 else { return }

        // Clamp dt so a hitch doesn't teleport the balloon or insta-pop.
        let dt = min(now - lastTickTime, 1.0 / 20.0)

        switch phase {
        case .idle:
            break
        case .setup:
            updateSetup()
        case .calibrating:
            updateCalibration(deltaTime: dt)
        case .playing:
            engine.update(deltaTime: dt, leftGaze: correctedLeftGaze, rightGaze: correctedRightGaze)
            syncViews()
        }
    }

    // MARK: - Lock-on calibration

    private var correctedLeftGaze: CGPoint? {
        guard gazeIsFresh, let gaze = latestLeftGaze else { return nil }
        return CGPoint(x: gaze.x + leftGazeOffset.x, y: gaze.y + leftGazeOffset.y)
    }

    private var correctedRightGaze: CGPoint? {
        guard gazeIsFresh, let gaze = latestRightGaze else { return nil }
        return CGPoint(x: gaze.x + rightGazeOffset.x, y: gaze.y + rightGazeOffset.y)
    }

    private func updateCalibration(deltaTime dt: TimeInterval) {
        let fresh = gazeIsFresh

        // Show the raw crosshairs (clamped on-screen) so the player can watch
        // them settle while staring at the target.
        layoutCrosshairs(left: fresh ? latestLeftGaze : nil,
                         right: fresh ? latestRightGaze : nil,
                         radius: LevelConfig.forLevel(1).crosshairRadius,
                         leftOn: false, rightOn: false)

        guard fresh, let left = latestLeftGaze, let right = latestRightGaze else {
            hintLabel.text = "Face the camera so it can find your eyes"
            return
        }
        hintLabel.text = "Stare at the 🎯 to lock on your eyes"

        let window = 30
        leftCalibrationSamples = Array((leftCalibrationSamples + [left]).suffix(window))
        rightCalibrationSamples = Array((rightCalibrationSamples + [right]).suffix(window))

        guard leftCalibrationSamples.count == window,
              let meanLeft = leftCalibrationSamples.averagePoint,
              let meanRight = rightCalibrationSamples.averagePoint else { return }

        // A steady gaze is all that's needed — every recent sample close to
        // its own mean. Where the raw points sit doesn't matter, since the
        // measured offset corrects that.
        let steadyTolerance: CGFloat = 60
        let steady = leftCalibrationSamples.allSatisfy { $0.distance(to: meanLeft) < steadyTolerance }
            && rightCalibrationSamples.allSatisfy { $0.distance(to: meanRight) < steadyTolerance }

        if steady {
            calibrationProgress = min(1, calibrationProgress + dt / 1.5)
        } else {
            calibrationProgress = max(0, calibrationProgress - dt / 1.5)
        }
        calibrationTarget.progress = CGFloat(calibrationProgress)

        if calibrationProgress >= 1 {
            let center = calibrationTarget.center
            leftGazeOffset = CGPoint(x: center.x - meanLeft.x, y: center.y - meanLeft.y)
            rightGazeOffset = CGPoint(x: center.x - meanRight.x, y: center.y - meanRight.y)
            startPlaying()
        }
    }

    private func syncViews() {
        let level = engine.level

        let balloonSize = level.balloonRadius * 2
        balloonView.bounds = CGRect(x: 0, y: 0, width: balloonSize, height: balloonSize)
        balloonView.center = engine.balloonPosition
        balloonView.progress = CGFloat(engine.dwellProgress)

        layoutCrosshairs(left: correctedLeftGaze, right: correctedRightGaze,
                         radius: level.crosshairRadius,
                         leftOn: engine.leftOnTarget, rightOn: engine.rightOnTarget)

        scoreLabel.text = "\(engine.score)"
        levelLabel.text = "Level \(level.number)"

        if correctedLeftGaze == nil || correctedRightGaze == nil {
            hintLabel.text = "Face the camera so it can find your eyes"
        } else if engine.bothEyesOnTarget {
            hintLabel.text = "Hold it…"
        } else if engine.leftOnTarget || engine.rightOnTarget {
            hintLabel.text = "Almost — get both crosshairs on the balloon"
        } else {
            hintLabel.text = "Converge both eyes on the balloon"
        }
    }

    private func playfieldRect() -> CGRect {
        let safe = view.bounds.inset(by: view.safeAreaInsets)
        return safe.inset(by: UIEdgeInsets(top: 96, left: 24, bottom: 152, right: 24))
    }

    private func layoutCrosshairs(left: CGPoint?, right: CGPoint?, radius: CGFloat, leftOn: Bool, rightOn: Bool) {
        let size = radius * 2
        let crosshairs: [(CrosshairView, CGPoint?, Bool)] = [
            (leftCrosshair, left, leftOn),
            (rightCrosshair, right, rightOn),
        ]
        for (crosshair, gaze, onTarget) in crosshairs {
            crosshair.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            if let gaze = gaze {
                // Clamp to the screen edge so a wandering eye's crosshair
                // never disappears entirely.
                crosshair.center = clampToView(gaze, inset: radius)
                crosshair.isHidden = false
            } else {
                crosshair.isHidden = true
            }
            crosshair.isOnTarget = onTarget
        }
    }

    private func clampToView(_ point: CGPoint, inset: CGFloat) -> CGPoint {
        return CGPoint(x: min(max(point.x, inset), view.bounds.width - inset),
                       y: min(max(point.y, inset), view.bounds.height - inset))
    }

    // MARK: - Effects

    private func showPopEffect(at position: CGPoint) {
        let burst = UILabel()
        burst.text = "💥"
        burst.font = .systemFont(ofSize: engine.level.balloonRadius * 2)
        burst.sizeToFit()
        burst.center = position
        burst.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        view.addSubview(burst)

        UIView.animate(withDuration: 0.45, animations: {
            burst.transform = CGAffineTransform(scaleX: 1.6, y: 1.6)
            burst.alpha = 0
        }) { _ in
            burst.removeFromSuperview()
        }
    }

    private func showLevelToast(_ levelNumber: Int) {
        levelToastLabel.text = "Level \(levelNumber)!"
        levelToastLabel.alpha = 0
        levelToastLabel.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)

        UIView.animate(withDuration: 0.3, animations: {
            self.levelToastLabel.alpha = 1
            self.levelToastLabel.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.4, delay: 0.9, options: [], animations: {
                self.levelToastLabel.alpha = 0
            })
        }
    }

    @objc private func quitTapped() {
        stopGameLoop()
        if let navigationController = navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}

// MARK: - GazeTrackerDelegate

extension GameViewController: GazeTrackerDelegate {

    func gazeTracker(_ tracker: GazeTracker,
                     didUpdateLeftGaze leftGaze: CGPoint,
                     rightGaze: CGPoint,
                     faceDistance: Float) {
        latestLeftGaze = leftGaze
        latestRightGaze = rightGaze
        lastGazeUpdateTime = CACurrentMediaTime()
    }
}

// MARK: - GameEngineDelegate

extension GameViewController: GameEngineDelegate {

    func gameEngineDidSpawnBalloon(_ engine: GameEngine) {
        balloonView.center = engine.balloonPosition
        balloonView.animateSpawn()
    }

    func gameEngine(_ engine: GameEngine, didPopBalloonAt position: CGPoint) {
        popHaptics.impactOccurred()
        showPopEffect(at: position)
    }

    func gameEngine(_ engine: GameEngine, didAdvanceTo level: LevelConfig) {
        showLevelToast(level.number)
    }
}
