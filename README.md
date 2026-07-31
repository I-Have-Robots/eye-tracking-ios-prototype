# Eyes Tracking (iOS Prototype)

An ARKit face-tracking prototype that estimates where the user is looking on the
screen using `ARFaceAnchor`'s eye transforms, and overlays a gaze indicator on a
`WKWebView`.

Requires a device with the TrueDepth camera / ARKit face tracking support.

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
