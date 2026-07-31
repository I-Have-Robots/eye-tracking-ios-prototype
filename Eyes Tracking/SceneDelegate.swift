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
        guard let windowScene = scene as? UIWindowScene else { return }

        let navigationController = UINavigationController(rootViewController: MenuViewController())
        navigationController.setNavigationBarHidden(true, animated: false)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // The AR session is paused by the view controller in viewWillDisappear.
    }
}
