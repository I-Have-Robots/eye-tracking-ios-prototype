//
//  SceneDelegate.swift
//  Eyes Tracking
//
//  Copyright © 2018 virakri. All rights reserved.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // The window and root view controller are instantiated automatically
        // from Main.storyboard via UISceneStoryboardFile in the scene manifest.
        guard scene is UIWindowScene else { return }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // The AR session is paused by the view controller in viewWillDisappear.
    }
}
