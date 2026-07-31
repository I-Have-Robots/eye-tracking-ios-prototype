# Eyes Tracking (iOS Prototype)

An ARKit face-tracking prototype that estimates where the user is looking on the
screen using `ARFaceAnchor`'s eye transforms. It now ships two experiences,
selectable from a menu at launch:

- **POP 🎈** — an eye-tracking game (see below).
- **Eye Tracking Demo** — the original gaze-indicator-over-WKWebView prototype.

Requires a device with the TrueDepth camera / ARKit face tracking support.

## POP — the game

The game starts with a **lock-on phase**: stare at the 🎯 target in the center
of the screen until its ring fills. While you hold steady, each eye's gaze
offset from the target is measured and then subtracted during play, so both
crosshairs converge on where you're actually looking instead of drifting far
apart. Crosshairs are clamped to the screen edge so neither can ever wander
fully off screen.

Then a balloon appears. Pop it by *converging both eyes on it*: the blue
crosshair tracks your left eye's gaze, the red crosshair tracks your right
eye's gaze, and both must sit on the balloon. Hold the gaze for the dwell time
and the balloon pops, scoring `level × 10` points. Pop 3 balloons to advance a
level. Losing the balloon drains dwell progress, shown as a yellow ring.

Difficulty ramps over the first 8 levels:

| Parameter        | Level 1 | Level 8+ |
|------------------|---------|----------|
| Balloon radius   | 64 pt   | 26 pt    |
| Balloon movement | still   | 140 pt/s wander |
| Dwell time       | 0.7 s   | 1.4 s    |
| Crosshair radius | 26 pt   | 13 pt (shrinks only in the hardest half of the ramp) |

Smaller crosshairs are not just cosmetic — an eye counts as on-target within
the balloon radius plus half the crosshair radius, so the aim tolerance
tightens with them.

### Architecture

```
AppDelegate / SceneDelegate      UIScene lifecycle; programmatic window
MenuViewController               Entry menu: Play POP / demo
ViewController (+ storyboard)    Original gaze demo, unchanged behavior
POP/
  GazeTracker                    ARKit face tracking → smoothed per-eye screen
                                 gaze points (delegate callbacks, main thread)
  GameEngine                     Pure game logic: levels, balloon wander,
                                 convergence detection, dwell timing, score
  GameViewController             CADisplayLink game loop, HUD, AR preview,
                                 pop effects and haptics
  BalloonView / CrosshairView    Render the target and per-eye aim assists
```

`GazeTracker` and `GameEngine` are deliberately independent: the tracker knows
nothing about the game, and the engine is plain UIKit geometry with no ARKit
imports, so it can be unit-tested or re-skinned without a device.

## Dependencies & security

This project uses **no third-party libraries** — no CocoaPods, Swift Package
Manager, or Carthage dependencies. It relies only on Apple system frameworks
(UIKit, ARKit, SceneKit, WebKit), so there are no dependency vulnerabilities to
patch; security fixes for those frameworks arrive with OS updates.

## iOS 27 readiness

Apps built with the iOS 27 SDK **must** adopt the UIScene-based lifecycle or
they will fail to launch. This project has been migrated accordingly:

- `SceneDelegate` (`UIWindowSceneDelegate`) added, with
  `UIApplicationSceneManifest` declared in `Info.plist`.
- `AppDelegate` slimmed down to app-level events and scene configuration;
  `@UIApplicationMain` replaced with `@main`.
- `SWIFT_VERSION` updated from 4.2 to 5.0.
- `IPHONEOS_DEPLOYMENT_TARGET` raised from 12.0 to 16.0 (face-tracking-capable
  devices all support this).
- `UIRequiredDeviceCapabilities` updated from `armv7` (obsolete, 32-bit) to
  `arm64`.
- Crash-prone force unwraps in the render loop replaced with `guard let`.

## Known limitations / suggested next steps

- **SceneKit is deprecated as of iOS 26.** `ARSCNView` still works, but Apple's
  strategic direction is RealityKit (`RealityView` / `ARView`). A future
  rewrite should replace the SceneKit scene graph and
  `hitTestWithSegment(from:to:options:)` math with RealityKit equivalents.
- **Screen geometry is hardcoded for iPhone X** (`phoneScreenSize`,
  `phoneScreenPointSize`, and the `heightCompensation` constant). Gaze mapping
  will be inaccurate on other devices; these should be derived from the current
  `UIWindowScene`'s screen metrics and a per-device physical-size table.
- **Storyboard UI** could be migrated to SwiftUI, but this is optional — UIKit
  and storyboards remain fully supported.
