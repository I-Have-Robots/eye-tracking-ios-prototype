//
//  GameEngine.swift
//  Eyes Tracking
//
//  Copyright © 2018 virakri. All rights reserved.
//

import UIKit

/// Difficulty parameters for a single level of POP.
struct LevelConfig {
    let number: Int
    let balloonRadius: CGFloat
    /// Points per second the balloon wanders at. 0 = stationary.
    let balloonSpeed: CGFloat
    /// Seconds both eyes must stay converged on the balloon to pop it.
    let dwellTime: TimeInterval
    let crosshairRadius: CGFloat
    let popsToAdvance: Int

    static func forLevel(_ number: Int) -> LevelConfig {
        // Difficulty ramps over the first 8 levels, then stays at maximum.
        let t = CGFloat(min(number - 1, 7)) / 7

        // Crosshairs only start shrinking in the hardest half of the ramp.
        // Kept small so both per-eye crosshairs comfortably fit on screen.
        let crosshairRadius: CGFloat
        if t <= 0.5 {
            crosshairRadius = 26
        } else {
            crosshairRadius = lerp(26, 13, (t - 0.5) * 2)
        }

        return LevelConfig(number: number,
                           balloonRadius: lerp(64, 26, t),
                           balloonSpeed: lerp(0, 140, t),
                           dwellTime: TimeInterval(lerp(0.7, 1.4, t)),
                           crosshairRadius: crosshairRadius,
                           popsToAdvance: 3)
    }
}

protocol GameEngineDelegate: AnyObject {
    func gameEngineDidSpawnBalloon(_ engine: GameEngine)
    func gameEngine(_ engine: GameEngine, didPopBalloonAt position: CGPoint)
    func gameEngine(_ engine: GameEngine, didAdvanceTo level: LevelConfig)
}

/// Pure game logic for POP: balloon movement, convergence detection, dwell
/// timing, scoring, and level progression. Knows nothing about ARKit or views.
final class GameEngine {

    weak var delegate: GameEngineDelegate?

    private(set) var score = 0
    private(set) var level = LevelConfig.forLevel(1)
    private(set) var balloonPosition = CGPoint.zero
    /// 0...1 — how close the current gaze hold is to popping the balloon.
    private(set) var dwellProgress: Double = 0
    private(set) var leftOnTarget = false
    private(set) var rightOnTarget = false
    private(set) var popsThisLevel = 0

    var bothEyesOnTarget: Bool { leftOnTarget && rightOnTarget }

    /// The rect (in screen points) the balloon is allowed to occupy.
    var playfield = CGRect.zero

    private var waypoint = CGPoint.zero

    func start(in playfield: CGRect) {
        self.playfield = playfield
        score = 0
        popsThisLevel = 0
        dwellProgress = 0
        level = .forLevel(1)
        spawnBalloon()
    }

    func update(deltaTime dt: TimeInterval, leftGaze: CGPoint?, rightGaze: CGPoint?) {
        moveBalloon(deltaTime: dt)

        // The crosshair assists aiming: an eye counts as on-target when its
        // gaze point is within the balloon plus half the crosshair radius, so
        // smaller crosshairs at high levels also mean tighter tolerances.
        let hitRadius = level.balloonRadius + level.crosshairRadius / 2
        leftOnTarget = leftGaze.map { $0.distance(to: balloonPosition) <= hitRadius } ?? false
        rightOnTarget = rightGaze.map { $0.distance(to: balloonPosition) <= hitRadius } ?? false

        if bothEyesOnTarget {
            dwellProgress = min(1, dwellProgress + dt / level.dwellTime)
            if dwellProgress >= 1 {
                pop()
            }
        } else {
            // Losing the balloon drains progress faster than it accumulates.
            dwellProgress = max(0, dwellProgress - dt * 1.5 / level.dwellTime)
        }
    }

    // MARK: - Private

    private func pop() {
        score += level.number * 10
        popsThisLevel += 1
        dwellProgress = 0
        let poppedPosition = balloonPosition

        if popsThisLevel >= level.popsToAdvance {
            popsThisLevel = 0
            level = .forLevel(level.number + 1)
            delegate?.gameEngine(self, didAdvanceTo: level)
        }

        delegate?.gameEngine(self, didPopBalloonAt: poppedPosition)
        spawnBalloon()
    }

    private func spawnBalloon() {
        balloonPosition = randomPoint()
        waypoint = randomPoint()
        delegate?.gameEngineDidSpawnBalloon(self)
    }

    private func moveBalloon(deltaTime dt: TimeInterval) {
        guard level.balloonSpeed > 0 else { return }

        let step = level.balloonSpeed * CGFloat(dt)
        let dx = waypoint.x - balloonPosition.x
        let dy = waypoint.y - balloonPosition.y
        let distanceToWaypoint = hypot(dx, dy)

        if distanceToWaypoint <= step {
            balloonPosition = waypoint
            waypoint = randomPoint()
        } else {
            balloonPosition.x += dx / distanceToWaypoint * step
            balloonPosition.y += dy / distanceToWaypoint * step
        }
    }

    private func randomPoint() -> CGPoint {
        let inset = playfield.insetBy(dx: level.balloonRadius, dy: level.balloonRadius)
        guard inset.width > 0, inset.height > 0 else { return CGPoint(x: playfield.midX, y: playfield.midY) }
        return CGPoint(x: CGFloat.random(in: inset.minX...inset.maxX),
                       y: CGFloat.random(in: inset.minY...inset.maxY))
    }
}
