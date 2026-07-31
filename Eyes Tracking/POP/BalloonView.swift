//
//  BalloonView.swift
//  Eyes Tracking
//
//  Copyright © 2018 virakri. All rights reserved.
//

import UIKit

/// The pop target: a balloon with a circular dwell-progress ring around it.
/// Also reused as the calibration lock-on target by swapping the emoji.
final class BalloonView: UIView {

    private let emojiLabel = UILabel()
    private let progressTrackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    var emoji: String = "🎈" {
        didSet { emojiLabel.text = emoji }
    }

    /// 0...1 dwell progress shown as a ring filling clockwise from the top.
    var progress: CGFloat = 0 {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = max(0, min(1, progress))
            CATransaction.commit()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        emojiLabel.text = "🎈"
        emojiLabel.textAlignment = .center
        emojiLabel.adjustsFontSizeToFitWidth = true
        addSubview(emojiLabel)

        progressTrackLayer.fillColor = nil
        progressTrackLayer.strokeColor = UIColor(white: 1, alpha: 0.25).cgColor
        progressTrackLayer.lineWidth = 3
        layer.addSublayer(progressTrackLayer)

        progressLayer.fillColor = nil
        progressLayer.strokeColor = UIColor.systemYellow.cgColor
        progressLayer.lineWidth = 4
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0
        layer.addSublayer(progressLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emojiLabel.frame = bounds
        emojiLabel.font = .systemFont(ofSize: bounds.height * 0.85)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 + 6
        let ringPath = UIBezierPath(arcCenter: center,
                                    radius: radius,
                                    startAngle: -.pi / 2,
                                    endAngle: 3 * .pi / 2,
                                    clockwise: true)
        progressTrackLayer.path = ringPath.cgPath
        progressLayer.path = ringPath.cgPath
    }

    func animateSpawn() {
        transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        UIView.animate(withDuration: 0.35,
                       delay: 0,
                       usingSpringWithDamping: 0.6,
                       initialSpringVelocity: 0.5,
                       options: [],
                       animations: { self.transform = .identity })
    }
}
