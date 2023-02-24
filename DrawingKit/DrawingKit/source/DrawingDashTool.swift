//
//  DrawingDashTool.swift
//  DrawingKit
//
//  Created by roni on 2023/2/23.
//

import Foundation
import UIKit

final class DashTool: DrawingElement {
    class RenderView: UIView, DrawingRenderView {
        private weak var element: DashTool?
        private var drawScale = CGSize(width: 1.0, height: 1.0)

        let strokeLayer = SimpleShapeLayer()

        func setup(element: DashTool, size: CGSize, screenSize: CGSize, lineWith: CGFloat, lineDashPattern: [NSNumber]) {
            self.element = element

            self.backgroundColor = .clear
            self.isOpaque = false
            self.contentScaleFactor = 1.0

            let strokeColor = element.color.toUIColor()
            let bounds = CGRect(origin: .zero, size: size)
            self.frame = bounds

            self.strokeLayer.frame = bounds
            self.strokeLayer.contentsScale = 1.0
            self.strokeLayer.lineWidth = lineWith
            self.strokeLayer.strokeColor = strokeColor.cgColor
            self.strokeLayer.fillColor = UIColor.clear.cgColor
            self.strokeLayer.lineDashPattern = lineDashPattern
            self.strokeLayer.lineJoin = .round
            self.strokeLayer.lineCap = .round

            self.layer.addSublayer(self.strokeLayer)
        }

        fileprivate func updatePath(_ path: CGPath) {
            self.strokeLayer.path = path
        }
    }

    let uuid: UUID
    let drawingSize: CGSize
    let color: DrawingColor
    let renderLineWidth: CGFloat
    var dashSize: CGFloat? {
        didSet {
            if var value = dashSize {
                value = max(0, value)
                lineDashPattern = [NSNumber(value: renderLineWidth * 2), NSNumber(value: renderLineWidth * 2 * value)]
            } else {
                lineDashPattern = [NSNumber(value: renderLineWidth * 2)]
            }
        }
    }
    let renderColor: UIColor
    var lineDashPattern: [NSNumber]

    private var path = UIBezierPath()
    fileprivate var renderPath: CGPath?

    var translation: CGPoint = .zero

    private weak var currentRenderView: DrawingRenderView?

    var isValid: Bool {
        return self.renderPath != nil
    }

    var bounds: CGRect {
        if let renderPath = self.renderPath {
            return normalizeDrawingRect(renderPath.boundingBoxOfPath.insetBy(dx: -self.renderLineWidth - 30.0, dy: -self.renderLineWidth - 30.0), drawingSize: self.drawingSize)
        } else {
            return .zero
        }
    }

    required init(drawingSize: CGSize, color: DrawingColor, lineWidth: CGFloat) {
        self.uuid = UUID()
        self.drawingSize = drawingSize
        self.color = color
        let minLineWidth = max(1.0, max(drawingSize.width, drawingSize.height) * 0.001)
        let maxLineWidth = max(10.0, max(drawingSize.width, drawingSize.height) * 0.04)
        let lineWidth = minLineWidth + (maxLineWidth - minLineWidth) * lineWidth * 0.75
        self.renderLineWidth = lineWidth
        self.renderColor = color.withUpdatedAlpha(1.0).toUIColor()
        self.lineDashPattern = [NSNumber(value: lineWidth * 2)]
    }

    func setupRenderView(screenSize: CGSize) -> DrawingRenderView? {
        let view = RenderView()
        view.setup(element: self, size: self.drawingSize, screenSize: screenSize, lineWith: renderLineWidth, lineDashPattern: lineDashPattern)
        self.currentRenderView = view
        return view
    }

    func setupRenderLayer() -> DrawingRenderLayer? {
        return nil
    }

    func updatePath(_ point: DrawingPoint, state: DrawingGesturePipeline.DrawingGestureState, zoomScale: CGFloat) {
        guard self.addPoint(point, state: state, zoomScale: zoomScale) || state == .ended else {
            return
        }

        if let currentRenderView = self.currentRenderView as? RenderView {
            let path = self.path.cgPath.mutableCopy()
            if let renderPath = path?.copy() {
                self.renderPath = renderPath
                currentRenderView.updatePath(renderPath)
            }
        }
    }

    func draw(in context: CGContext, size: CGSize) {
        guard let path = self.renderPath else {
            return
        }
        context.saveGState()

        context.translateBy(x: self.translation.x, y: self.translation.y)
        context.setBlendMode(.normal)

        let fillColor: UIColor = self.color.toUIColor()

        context.addPath(path)
        context.setFillColor(fillColor.cgColor)
        context.setStrokeColor(fillColor.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(renderLineWidth)
        context.setLineDash(phase: 0, lengths: lineDashPattern.map({ CGFloat($0.floatValue) }))

        context.drawPath(using: .stroke)

        context.restoreGState()
    }

    private var points: [CGPoint] = []
    private var pointPtr = 0

    private func addPoint(_ point: DrawingPoint, state: DrawingGesturePipeline.DrawingGestureState, zoomScale: CGFloat) -> Bool {
        points.append(point.location)
        path = UIBezierPath()
        for (index, point) in points.enumerated() {
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return true
    }
}



