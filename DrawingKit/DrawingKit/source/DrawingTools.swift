//
//  DrawingTools.swift
//  DrawingCat
//
//  Created by roni on 2023/2/7.
//

import Foundation
import UIKit

 class MarkerTool: DrawingElement {
    let uuid: UUID

    let drawingSize: CGSize
    let color: DrawingColor

    let lineWidth: CGFloat

    var translation = CGPoint()

    var points: [CGPoint] = []

    weak var metalView: DrawingMetalView?

    var isValid: Bool {
        return self.points.count > 6
    }

     var brushStyle: DrawingMetalView.BrushType {
         return .marker
     }

    var bounds: CGRect {
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = 0.0
        var maxY: CGFloat = 0.0

        for point in self.points {
            if point.x < minX {
                minX = point.x
            }
            if point.x > maxX {
                maxX = point.x
            }
            if point.y < minY {
                minY = point.y
            }
            if point.y > maxY {
                maxY = point.y
            }
        }

        return normalizeDrawingRect(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -80.0, dy: -80.0), drawingSize: self.drawingSize)
    }

    required init(drawingSize: CGSize, color: DrawingColor, lineWidth: CGFloat) {
        self.uuid = UUID()
        self.drawingSize = drawingSize
        self.color = color
        self.lineWidth = lineWidth
    }

    func setupRenderView(screenSize: CGSize) -> DrawingRenderView? {
        return nil
    }

    func setupRenderLayer() -> DrawingRenderLayer? {
        return nil
    }

    func renderLineWidth() -> CGFloat {
        return max(5, min(drawingSize.width, drawingSize.height) * lineWidth * 0.2)
    }

    private var didSetup = false
    func updatePath(_ point: DrawingPoint, state: DrawingGesturePipeline.DrawingGestureState, zoomScale: CGFloat) {
        let filterDistance: CGFloat = 10.0 / zoomScale
        if let lastPoint = self.points.last, lastPoint.distance(to: point.location) < filterDistance {
        } else {
            self.points.append(point.location)
        }

        self.didSetup = true
        self.metalView?.updated(point, state: state, brush: brushStyle, color: self.color, size: renderLineWidth(), zoomScale: zoomScale)
    }

    func draw(in context: CGContext, size: CGSize) {
        guard !self.points.isEmpty else {
            return
        }
        context.saveGState()

        context.translateBy(x: self.translation.x, y: self.translation.y)

        self.metalView?.drawInContext(context)
        self.metalView?.clear()

        context.restoreGState()
    }
}

class CharteltTool: MarkerTool {

    override var bounds: CGRect {
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = 0.0
        var maxY: CGFloat = 0.0

        for point in self.points {
            if point.x < minX {
                minX = point.x
            }
            if point.x > maxX {
                maxX = point.x
            }
            if point.y < minY {
                minY = point.y
            }
            if point.y > maxY {
                maxY = point.y
            }
        }
        let handlfWidth = -renderLineWidth() / 2
        let rect = normalizeDrawingRect(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).inset(by: UIEdgeInsets(top: handlfWidth, left: handlfWidth, bottom: handlfWidth, right: handlfWidth)), drawingSize: self.drawingSize)
        return rect
    }

    override var brushStyle: DrawingMetalView.BrushType {
        return .chartlet
    }

    override func renderLineWidth() -> CGFloat {
        return max(5, min(drawingSize.width, drawingSize.height) * lineWidth * 0.3)
    }
}

class RainbowTool: MarkerTool {
    override var brushStyle: DrawingMetalView.BrushType {
        return .rainbow
    }
}

final class FillTool: DrawingElement {
    let uuid: UUID

    let drawingSize: CGSize
    let color: DrawingColor
    let isBlur: Bool
    var blurredImage: UIImage?

    var translation = CGPoint()

    var isValid: Bool {
        return true
    }

    var bounds: CGRect {
        return CGRect(origin: .zero, size: self.drawingSize)
    }

    required init(drawingSize: CGSize, color: DrawingColor, blur: Bool, blurredImage: UIImage?) {
        self.uuid = UUID()
        self.drawingSize = drawingSize
        self.color = color
        self.isBlur = blur
        self.blurredImage = blurredImage
    }

    func setupRenderView(screenSize: CGSize) -> DrawingRenderView? {
        return nil
    }

    func setupRenderLayer() -> DrawingRenderLayer? {
        return nil
    }

    func updatePath(_ path: DrawingPoint, state: DrawingGesturePipeline.DrawingGestureState, zoomScale: CGFloat) {
    }

    func draw(in context: CGContext, size: CGSize) {
        context.setShouldAntialias(false)

        context.setBlendMode(.copy)

        if self.isBlur {
            if let blurredImage = self.blurredImage?.cgImage {
                context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
                context.scaleBy(x: 1.0, y: -1.0)
                context.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)
                context.draw(blurredImage, in: CGRect(origin: .zero, size: size))
            }
        } else {
            context.setFillColor(self.color.toCGColor())
            context.fill(CGRect(origin: .zero, size: size))
        }

        context.setBlendMode(.normal)
    }
}

