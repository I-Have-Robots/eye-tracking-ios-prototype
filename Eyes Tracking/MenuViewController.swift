//
//  MenuViewController.swift
//  Eyes Tracking
//
//  Copyright © 2018 virakri. All rights reserved.
//

import UIKit
import ARKit

/// App entry point: launch the POP game or the original gaze-tracking demo.
final class MenuViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)

        let titleLabel = UILabel()
        titleLabel.text = "POP 🎈"
        titleLabel.font = .systemFont(ofSize: 56, weight: .heavy)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Converge your eyes to pop balloons"
        subtitleLabel.font = .systemFont(ofSize: 17)
        subtitleLabel.textColor = UIColor(white: 1, alpha: 0.7)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let playButton = UIButton(type: .system)
        playButton.setTitle("Play", for: .normal)
        playButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        playButton.setTitleColor(.white, for: .normal)
        playButton.backgroundColor = .systemPink
        playButton.layer.cornerRadius = 14
        playButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 64, bottom: 14, right: 64)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        let demoButton = UIButton(type: .system)
        demoButton.setTitle("Eye Tracking Demo", for: .normal)
        demoButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        demoButton.setTitleColor(UIColor(white: 1, alpha: 0.8), for: .normal)
        demoButton.addTarget(self, action: #selector(demoTapped), for: .touchUpInside)

        let footnoteLabel = UILabel()
        footnoteLabel.font = .systemFont(ofSize: 13)
        footnoteLabel.textColor = UIColor(white: 1, alpha: 0.45)
        footnoteLabel.textAlignment = .center
        footnoteLabel.numberOfLines = 0
        if !ARFaceTrackingConfiguration.isSupported {
            footnoteLabel.text = "⚠️ This device does not support TrueDepth face tracking."
            playButton.isEnabled = false
            playButton.alpha = 0.4
            demoButton.isEnabled = false
            demoButton.alpha = 0.4
        } else {
            footnoteLabel.text = "Requires the front TrueDepth camera"
        }

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, playButton, demoButton, footnoteLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(44, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
        ])
    }

    @objc private func playTapped() {
        navigationController?.pushViewController(GameViewController(), animated: true)
    }

    @objc private func demoTapped() {
        guard let demoViewController = UIStoryboard(name: "Main", bundle: nil)
            .instantiateInitialViewController() else { return }
        navigationController?.pushViewController(demoViewController, animated: true)
    }
}
