//
//  Chartlet.swift
//  DrawingCat
//
//  Created by roni on 2023/2/9.
//

import Foundation
import UIKit
import Metal

/// not implemented yet
class Chartlet {

    public var index: Int = 0

    public var center: CGPoint

    public var size: CGSize

    public var textureID: String

    public var angle: CGFloat?

    /// a weak refreance to canvas
    public weak var canvas: DrawingMetalView?

    init(center: CGPoint, size: CGSize, textureID: String, angle: CGFloat, canvas: DrawingMetalView?) {
        self.canvas = canvas
        self.center = center
        self.size = size
        self.textureID = textureID
        self.angle = angle
    }

    /// draw self with printer of canvas
    public func drawSelf(on target: Drawable?) {
        canvas?.chartletBrush?.render(chartlet: self, on: target)
    }

    lazy var vertex_buffer: MTLBuffer? = {
        let scale: CGFloat = canvas?.contentScaleFactor ?? UIScreen.main.nativeScale

        let center = self.center * scale
        let ratio = scale * 0.5
        let halfSize = CGSize(width: self.size.width * ratio, height: self.size.height * ratio);
        let angle = self.angle ?? 0
        let vertexes = [
            Vertex(position: CGPoint(x: center.x - halfSize.width, y: center.y - halfSize.height).rotatedBy(angle, anchor: center),
                   texCoord: CGPoint(x: 0, y: 0)),
            Vertex(position: CGPoint(x: center.x + halfSize.width , y: center.y - halfSize.height).rotatedBy(angle, anchor: center),
                   texCoord: CGPoint(x: 1, y: 0)),
            Vertex(position: CGPoint(x: center.x - halfSize.width , y: center.y + halfSize.height).rotatedBy(angle, anchor: center),
                   texCoord: CGPoint(x: 0, y: 1)),
            Vertex(position: CGPoint(x: center.x + halfSize.width , y: center.y + halfSize.height).rotatedBy(angle, anchor: center),
                   texCoord: CGPoint(x: 1, y: 1)),
        ]
        return canvas?.device?.makeBuffer(bytes: vertexes, length: MemoryLayout<Vertex>.stride * 4, options: .cpuCacheModeWriteCombined)
    }()

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case index
        case center
        case size
        case texture
        case angle
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        let centerInts = try container.decode([Int].self, forKey: .center)
        center = CGPoint.make(from: centerInts)
        let sizeInts = try container.decode([Int].self, forKey: .size)
        size = CGSize.make(from: sizeInts)
        textureID = try container.decode(String.self, forKey: .texture)
        angle = try? container.decode(CGFloat.self, forKey: .angle)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(center.encodeToInts(), forKey: .center)
        try container.encode(size.encodeToInts(), forKey: .size)
        try container.encode(textureID, forKey: .texture)
        if let angle = self.angle {
            try container.encode(angle, forKey: .angle)
        }
    }
}

// MARK: - Point Utils
extension CGPoint {

    func between(min: CGPoint, max: CGPoint) -> CGPoint {
        return CGPoint(x: x.valueBetween(min: min.x, max: max.x),
                       y: y.valueBetween(min: min.y, max: max.y))
    }

    // MARK: - Codable utils
    static func make(from ints: [Int]) -> CGPoint {
        return CGPoint(x: CGFloat(ints.first ?? 0) / 10, y: CGFloat(ints.last ?? 0) / 10)
    }

    func encodeToInts() -> [Int] {
        return [Int(x * 10), Int(y * 10)]
    }

    func rotatedBy(_ angle: CGFloat, anchor: CGPoint) -> CGPoint {
        let point = self - anchor
        let a = Double(-angle)
        let x = Double(point.x)
        let y = Double(point.y)
        let x_ = x * cos(a) - y * sin(a);
        let y_ = x * sin(a) + y * cos(a);
        return CGPoint(x: CGFloat(x_), y: CGFloat(y_)) + anchor
    }
}

extension CGSize {
    // MARK: - Codable utils
    static func make(from ints: [Int]) -> CGSize {
        return CGSize(width: CGFloat(ints.first ?? 0) / 10, height: CGFloat(ints.last ?? 0) / 10)
    }

    func encodeToInts() -> [Int] {
        return [Int(width * 10), Int(height * 10)]
    }
}

extension Comparable {
    func valueBetween(min: Self, max: Self) -> Self {
        if self > max {
            return max
        } else if self < min {
            return min
        }
        return self
    }
}
