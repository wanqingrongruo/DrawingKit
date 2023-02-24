//
//  UIKitUtils.swift
//  DrawingCat
//
//  Created by roni on 2023/2/7.
//

import UIKit
@_implementationOnly import mapoc

public extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xff) / 255.0, green: CGFloat((rgb >> 8) & 0xff) / 255.0, blue: CGFloat(rgb & 0xff) / 255.0, alpha: 1.0)
    }

    convenience init(rgb: UInt32, alpha: CGFloat) {
        self.init(red: CGFloat((rgb >> 16) & 0xff) / 255.0, green: CGFloat((rgb >> 8) & 0xff) / 255.0, blue: CGFloat(rgb & 0xff) / 255.0, alpha: alpha)
    }

    convenience init(argb: UInt32) {
        self.init(red: CGFloat((argb >> 16) & 0xff) / 255.0, green: CGFloat((argb >> 8) & 0xff) / 255.0, blue: CGFloat(argb & 0xff) / 255.0, alpha: CGFloat((argb >> 24) & 0xff) / 255.0)
    }

    convenience init?(hexString: String) {
        let scanner = Scanner(string: hexString)
        if hexString.hasPrefix("#") {
            scanner.scanLocation = 1
        }
        var value: UInt32 = 0
        if scanner.scanHexInt32(&value) {
            if hexString.count > 7 {
                self.init(argb: value)
            } else {
                self.init(rgb: value)
            }
        } else {
            return nil
        }
    }

    var alpha: CGFloat {
        var alpha: CGFloat = 0.0
        if self.getRed(nil, green: nil, blue: nil, alpha: &alpha) {
            return alpha
        } else if self.getWhite(nil, alpha: &alpha) {
            return alpha
        } else {
            return 0.0
        }
    }

    var rgb: UInt32 {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        if self.getRed(&red, green: &green, blue: &blue, alpha: nil) {
            return (UInt32(max(0.0, red) * 255.0) << 16) | (UInt32(max(0.0, green) * 255.0) << 8) | (UInt32(max(0.0, blue) * 255.0))
        } else if self.getWhite(&red, alpha: nil) {
            return (UInt32(max(0.0, red) * 255.0) << 16) | (UInt32(max(0.0, red) * 255.0) << 8) | (UInt32(max(0.0, red) * 255.0))
        } else {
            return 0
        }
    }

    var argb: UInt32 {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        if self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (UInt32(alpha * 255.0) << 24) | (UInt32(max(0.0, red) * 255.0) << 16) | (UInt32(max(0.0, green) * 255.0) << 8) | (UInt32(max(0.0, blue) * 255.0))
        } else if self.getWhite(&red, alpha: &alpha) {
            return (UInt32(max(0.0, alpha) * 255.0) << 24) | (UInt32(max(0.0, red) * 255.0) << 16) | (UInt32(max(0.0, red) * 255.0) << 8) | (UInt32(max(0.0, red) * 255.0))
        } else {
            return 0
        }
    }

    var hsb: (h: CGFloat, s: CGFloat, b: CGFloat) {
        var hue: CGFloat = 0.0
        var saturation: CGFloat = 0.0
        var brightness: CGFloat = 0.0
        if self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil) {
            return (hue, saturation, brightness)
        } else {
            return (0.0, 0.0, 0.0)
        }
    }

    var lightness: CGFloat {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        if self.getRed(&red, green: &green, blue: &blue, alpha: nil) {
            return 0.2126 * red + 0.7152 * green + 0.0722 * blue
        } else if self.getWhite(&red, alpha: nil) {
            return red
        } else {
            return 0.0
        }
    }

    func withMultipliedBrightnessBy(_ factor: CGFloat) -> UIColor {
        var hue: CGFloat = 0.0
        var saturation: CGFloat = 0.0
        var brightness: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return UIColor(hue: hue, saturation: saturation, brightness: max(0.0, min(1.0, brightness * factor)), alpha: alpha)
    }

    func withMultiplied(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> UIColor {
        var hueValue: CGFloat = 0.0
        var saturationValue: CGFloat = 0.0
        var brightnessValue: CGFloat = 0.0
        var alphaValue: CGFloat = 0.0
        self.getHue(&hueValue, saturation: &saturationValue, brightness: &brightnessValue, alpha: &alphaValue)

        return UIColor(hue: max(0.0, min(1.0, hueValue * hue)), saturation: max(0.0, min(1.0, saturationValue * saturation)), brightness: max(0.0, min(1.0, brightnessValue * brightness)), alpha: alphaValue)
    }

    func mixedWith(_ other: UIColor, alpha: CGFloat) -> UIColor {
        let alpha = min(1.0, max(0.0, alpha))
        let oneMinusAlpha = 1.0 - alpha

        var r1: CGFloat = 0.0
        var r2: CGFloat = 0.0
        var g1: CGFloat = 0.0
        var g2: CGFloat = 0.0
        var b1: CGFloat = 0.0
        var b2: CGFloat = 0.0
        var a1: CGFloat = 0.0
        var a2: CGFloat = 0.0
        if self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1) &&
            other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        {
            let r = r1 * oneMinusAlpha + r2 * alpha
            let g = g1 * oneMinusAlpha + g2 * alpha
            let b = b1 * oneMinusAlpha + b2 * alpha
            let a = a1 * oneMinusAlpha + a2 * alpha
            return UIColor(red: r, green: g, blue: b, alpha: a)
        }
        return self
    }

    func blitOver(_ other: UIColor, alpha: CGFloat) -> UIColor {
        let alpha = min(1.0, max(0.0, alpha))

        var r1: CGFloat = 0.0
        var r2: CGFloat = 0.0
        var g1: CGFloat = 0.0
        var g2: CGFloat = 0.0
        var b1: CGFloat = 0.0
        var b2: CGFloat = 0.0
        var a1: CGFloat = 0.0
        var a2: CGFloat = 0.0
        if self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1) &&
            other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        {
            let resultingAlpha = max(0.0, min(1.0, alpha * a1))
            let oneMinusResultingAlpha = 1.0 - resultingAlpha

            let r = r1 * resultingAlpha + r2 * oneMinusResultingAlpha
            let g = g1 * resultingAlpha + g2 * oneMinusResultingAlpha
            let b = b1 * resultingAlpha + b2 * oneMinusResultingAlpha
            let a: CGFloat = 1.0
            return UIColor(red: r, green: g, blue: b, alpha: a)
        }
        return self
    }

    func withMultipliedAlpha(_ alpha: CGFloat) -> UIColor {
        var r1: CGFloat = 0.0
        var g1: CGFloat = 0.0
        var b1: CGFloat = 0.0
        var a1: CGFloat = 0.0
        if self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1) {
            return UIColor(red: r1, green: g1, blue: b1, alpha: max(0.0, min(1.0, a1 * alpha)))
        }
        return self
    }

    func interpolateTo(_ color: UIColor, fraction: CGFloat) -> UIColor? {
        let f = min(max(0, fraction), 1)

        var r1: CGFloat = 0.0
        var r2: CGFloat = 0.0
        var g1: CGFloat = 0.0
        var g2: CGFloat = 0.0
        var b1: CGFloat = 0.0
        var b2: CGFloat = 0.0
        var a1: CGFloat = 0.0
        var a2: CGFloat = 0.0
        if self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1) &&
            color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) {
            let r: CGFloat = CGFloat(r1 + (r2 - r1) * f)
            let g: CGFloat = CGFloat(g1 + (g2 - g1) * f)
            let b: CGFloat = CGFloat(b1 + (b2 - b1) * f)
            let a: CGFloat = CGFloat(a1 + (a2 - a1) * f)

            return UIColor(red: r, green: g, blue: b, alpha: a)
        } else {
            return self
        }
    }

    private var colorComponents: (r: Int32, g: Int32, b: Int32) {
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        if self.getRed(&r, green: &g, blue: &b, alpha: nil) {
            return (Int32(max(0.0, r) * 255.0), Int32(max(0.0, g) * 255.0), Int32(max(0.0, b) * 255.0))
        } else if self.getWhite(&r, alpha: nil) {
            return (Int32(max(0.0, r) * 255.0), Int32(max(0.0, r) * 255.0), Int32(max(0.0, r) * 255.0))
        }
        return (0, 0, 0)
    }

    func distance(to other: UIColor) -> Int32 {
        let e1 = self.colorComponents
        let e2 = other.colorComponents
        let rMean = (e1.r + e2.r) / 2
        let r = e1.r - e2.r
        let g = e1.g - e2.g
        let b = e1.b - e2.b
        return ((512 + rMean) * r * r) >> 8 + 4 * g * g + ((767 - rMean) * b * b) >> 8
    }

    static func average(of colors: [UIColor]) -> UIColor {
        var sr: CGFloat = 0.0
        var sg: CGFloat = 0.0
        var sb: CGFloat = 0.0
        var sa: CGFloat = 0.0

        for color in colors {
            var r: CGFloat = 0.0
            var g: CGFloat = 0.0
            var b: CGFloat = 0.0
            var a: CGFloat = 0.0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            sr += r
            sg += g
            sb += b
            sa += a
        }

        return UIColor(red: sr / CGFloat(colors.count), green: sg / CGFloat(colors.count), blue: sb / CGFloat(colors.count), alpha: sa / CGFloat(colors.count))
    }
}

public extension UIView {
    static func animationDurationFactor() -> Double {
        return animationDurationFactorImpl()
    }
}

public func makeSpringAnimation(_ keyPath: String) -> CABasicAnimation {
    return makeSpringAnimationImpl(keyPath)
}

public func makeSpringBounceAnimation(_ keyPath: String, _ initialVelocity: CGFloat, _ damping: CGFloat) -> CABasicAnimation {
    return makeSpringBounceAnimationImpl(keyPath, initialVelocity, damping)
}

public extension CGSize {
    func fitted(_ size: CGSize) -> CGSize {
        var fittedSize = self
        if fittedSize.width > size.width {
            fittedSize = CGSize(width: size.width, height: floor((fittedSize.height * size.width / max(fittedSize.width, 1.0))))
        }
        if fittedSize.height > size.height {
            fittedSize = CGSize(width: floor((fittedSize.width * size.height / max(fittedSize.height, 1.0))), height: size.height)
        }
        return fittedSize
    }
}
