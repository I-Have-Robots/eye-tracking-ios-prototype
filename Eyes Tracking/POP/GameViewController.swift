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
    private let hintLabel = UILabel()
    private let levelToastLabel = UILabel()
    private let quitButton = UIButton(type: .system)

    private let startOverlay = UIView()
    private let startButton = UIButton(type: .system)

    private var displayLink: CADisplayLink?
    private var lastTickTime: CFTimeInterval = 0
    private var latestLeftGaze: CGPoint?
    private var latestRightGaze: CGPoint?
    private var isPlaying = false

    private let popHaptics = UIImpactFeedbackGenerator(style: .medium)

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)

        engine.delegate = self
        setupGameLayer()
        setupHUD()
        setupStartOverlay()

        if GazeTracker.isSupported {
            let tracker = GazeTracker(sceneView: sceneView)
            tracker.delegate = self
            gazeTracker = tracker
        }
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
        if isPlaying {
            engine.playfield = playfieldRect()
        }
    }

    // MARK: - Setup

    private func setupGameLayer() {
        balloonView.isHidden = true
        view.addSubview(balloonView)

        leftCrosshair.isHidden = true
        rightCrosshair.isHidden = true
        view.addSubview(leftCrosshair)
        view.addSubview(rightCrosshair)

        // Small AR face preview, like the original demo.
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.layer.cornerRadius = 16
        sceneView.clipsToBounds = true
        view.addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            sceneView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            sceneView.widthAnchor.constraint(equalToConstant: 84),
            sceneView.heightAnchor.constraint(equalToConstant: 112),
        ])
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

        let hudStack = UIStackView(arrangedSubviews: [scoreLabel, levelLabel])
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
            hintLabel.trailingAnchor.constraint(equalTo: sceneView.leadingAnchor, constant: -12),

            levelToastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            levelToastLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            quitButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            quitButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            quitButton.widthAnchor.constraint(equalToConstant: 44),
            quitButton.heightAnchor.constraint(equalToConstant: 44),
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
            Look at the balloon and hold your gaze to pop it.

            🔵 Left eye · 🔴 Right eye
            Both crosshairs must be on the balloon.

            Balloons shrink and move as you level up —
            and at the hardest levels, so do your crosshairs.
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

        isPlaying = true
        balloonView.isHidden = false
        engine.start(in: playfieldRect())

        lastTickTime = 0
        displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopGameLoop() {
        displayLink?.invalidate()
        displayLink = nil
        isPlaying = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTickTime = now }
        guard lastTickTime > 0 else { return }

        // Clamp dt so a hitch doesn't teleport the balloon or insta-pop.
        let dt = min(now - lastTickTime, 1.0 / 20.0)
        engine.update(deltaTime: dt, leftGaze: latestLeftGaze, rightGaze: latestRightGaze)
        syncViews()
    }

    private func syncViews() {
        let level = engine.level

        let balloonSize = level.balloonRadius * 2
        balloonView.bounds = CGRect(x: 0, y: 0, width: balloonSize, height: balloonSize)
        balloonView.center = engine.balloonPosition
        balloonView.progress = CGFloat(engine.dwellProgress)

        let crosshairSize = level.crosshairRadius * 2
        let crosshairs: [(CrosshairView, CGPoint?, Bool)] = [
            (leftCrosshair, latestLeftGaze, engine.leftOnTarget),
            (rightCrosshair, latestRightGaze, engine.rightOnTarget),
        ]
        for (crosshair, gaze, onTarget) in crosshairs {
            crosshair.bounds = CGRect(x: 0, y: 0, width: crosshairSize, height: crosshairSize)
            if let gaze = gaze {
                crosshair.center = gaze
                crosshair.isHidden = false
            } else {
                crosshair.isHidden = true
            }
            crosshair.isOnTarget = onTarget
        }

        scoreLabel.text = "\(engine.score)"
        levelLabel.text = "Level \(level.number)"

        if latestLeftGaze == nil || latestRightGaze == nil {
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
