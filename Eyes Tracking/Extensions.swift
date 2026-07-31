//
//  SCNVectorExtension.swift
//  Face-based Game Prototype
//
//  Created by VIRAKRI JINANGKUL on 10/31/17.
//  Copyright © 2017 VIRAKRI JINANGKUL. All rights reserved.
//

import SceneKit

extension SCNVector3 {
    func length() -> Float {
        return sqrtf(x * x + y * y + z * z)
    }
}

func - (l: SCNVector3, r: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(l.x - r.x, l.y - r.y, l.z - r.z)
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        return hypot(x - other.x, y - other.y)
    }
}

extension Collection where Element == CGPoint {
    /// Mean of a list of points. Used to smooth recent gaze samples.
    var averagePoint: CGPoint? {
        guard !isEmpty else {
            return nil
        }

        let sum = reduce(CGPoint.zero) { current, next -> CGPoint in
            return CGPoint(x: current.x + next.x, y: current.y + next.y)
        }

        return CGPoint(x: sum.x / CGFloat(count), y: sum.y / CGFloat(count))
    }
}

func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
    return from + (to - from) * min(max(t, 0), 1)
}

extension Collection where Element == CGFloat, Index == Int {
    /// Return the mean of a list of CGFloat. Used with `recentVirtualObjectDistances`.
    var average: CGFloat? {
        guard !isEmpty else {
            return nil
        }
        
        let sum = reduce(CGFloat(0)) { current, next -> CGFloat in
            return current + next
        }
        
        return sum / CGFloat(count)
    }
}
