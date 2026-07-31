//
//  CrosshairView.swift
//  Eyes Tracking
//
//  Copyright © 2018 virakri. All rights reserved.
//

import UIKit

/// Aiming assist for one eye: a ring with tick marks and a center dot.
/// The view's bounds set the crosshair size, so it can shrink at high levels.
final class CrosshairView: UIView {

    private let ringLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()

    var isOnTarget = false {
        didSet {
            guard isOnTarget != oldValue else { return }
            ringLayer.lineWidth = isOnTarget ? 3.5 : 2
            alpha = isOnTarget ? 1 : 0.8
        }
    }

    init(color: UIColor) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        alpha = 0.8

        ringLayer.fillColor = nil
        ringLayer.strokeColor = color.cgColor
        ringLayer.lineWidth = 2
        layer.addSublayer(ringLayer)

        dotLayer.fillColor = color.cgColor
        layer.addSublayer(dotLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 2

        let path = UIBezierPath(arcCenter: center,
                                radius: radius,
                                startAngle: 0,
                                endAngle: 2 * .pi,
                                clockwise: true)

        // Four tick marks pointing inward from the ring.
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            let outer = CGPoint(x: center.x + cos(angle) * radius,
                                y: center.y + sin(angle) * radius)
            let inner = CGPoint(x: center.x + cos(angle) * radius * 0.55,
                                y: center.y + sin(angle) * radius * 0.55)
            path.move(to: outer)
            path.addLine(to: inner)
        }
        ringLayer.path = path.cgPath

        dotLayer.path = UIBezierPath(ovalIn: CGRect(x: center.x - 2,
                                                    y: center.y - 2,
                                                    width: 4,
                                                    height: 4)).cgPath
    }
}
