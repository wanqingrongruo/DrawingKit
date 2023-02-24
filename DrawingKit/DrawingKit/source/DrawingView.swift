//
//  DrawingView.swift
//  DrawingCat
//
//  Created by roni on 2023/2/7.
//

import Foundation
import UIKit

protocol DrawingRenderLayer: CALayer {

}

protocol DrawingRenderView: UIView {

}

protocol DrawingElement: AnyObject {
    var uuid: UUID { get }
    var translation: CGPoint { get set }
    var isValid: Bool { get }
    var bounds: CGRect { get }

    func setupRenderView(screenSize: CGSize) -> DrawingRenderView?
    func setupRenderLayer() -> DrawingRenderLayer?
    func updatePath(_ point: DrawingPoint, state: DrawingGesturePipeline.DrawingGestureState, zoomScale: CGFloat)

    func draw(in: CGContext, size: CGSize)
}

private enum DrawingOperation {
    case clearAll(CGRect)
    case slice(DrawingSlice)

}

public final class DrawingView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    public var zoomOut: () -> Void = {}

    public struct NavigationState {
        public let canUndo: Bool
        public let canRedo: Bool
        public let canClear: Bool
        public let canZoomOut: Bool
        public let isDrawing: Bool
    }

    enum Action {
        case undo
        case redo
        case clear
        case zoomOut
    }

    enum Tool {
        case pen
        case arrow
        case marker
        case chartlet
        case rainbow
        case neon
        case eraser
        case blur
        case dash
    }

    public struct DrawResult {
        public var image: UIImage? // 只包含笔记的图片, 不包括笔记之外的空白
        public var rectInImage: CGRect? // 图片在 imageSize 大小中的 rect
        public init(image: UIImage?, rectInImage: CGRect?) {
            self.image = image
            self.rectInImage = rectInImage
        }
    }

    var tool: Tool = .pen
    public var toolColor: DrawingColor = DrawingColor(color: .black)
    public var toolBrushSize: CGFloat = 0.25
    private var dashSize: CGFloat? // 对 dash笔起作用

    public var stateUpdated: (NavigationState) -> Void = { _ in }

    public var shouldBegin: (CGPoint) -> Bool = { _ in return true }
    public var getFullImage: () -> UIImage? = { return nil }

    var requestedColorPicker: () -> Void = {}
    var requestedEraserToggle: () -> Void = {}
    var requestedToolsToggle: () -> Void = {}

    private var undoStack: [DrawingOperation] = []
    private var redoStack: [DrawingOperation] = []
    fileprivate var uncommitedElement: DrawingElement?

    // 最终绘制的结果 - 包含图片大小
    public private(set) var drawingImage: UIImage?
    // 最终绘制的结果 - 笔迹图
    public private(set) var resultImage: UIImage?
    public private(set) var contentRect: CGRect?

    private let renderer: UIGraphicsImageRenderer

    private var currentDrawingViewContainer: UIImageView
    private var currentDrawingRenderView: DrawingRenderView?
    private var currentDrawingLayer: DrawingRenderLayer?

    private var metalView: DrawingMetalView?

    let imageSize: CGSize
    private(set) var zoomScale: CGFloat = 1.0

    private var drawingGesturePipeline: DrawingGesturePipeline?

    private var isDrawing = false
    private var drawingGestureStartTimestamp: Double?

    public var screenSize: CGSize

    private var previousPointTimestamp: Double?

    private let pencilInteraction: UIInteraction?

    public func getResult() -> DrawResult {
        return DrawResult(image: resultImage, rectInImage: contentRect)
    }

    // size 是图片的 size.. 不是 DrawingView.frame.size
    public init(size: CGSize) {
        self.imageSize = size
        self.screenSize = size

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        if #available(iOS 12.0, *) {
            format.preferredRange = .standard
        }
        format.opaque = false
        self.renderer = UIGraphicsImageRenderer(size: size, format: format)

        self.currentDrawingViewContainer = UIImageView()
        self.currentDrawingViewContainer.frame = CGRect(origin: .zero, size: size)
        self.currentDrawingViewContainer.contentScaleFactor = 1.0
        self.currentDrawingViewContainer.backgroundColor = .clear
        self.currentDrawingViewContainer.isUserInteractionEnabled = false
        self.currentDrawingViewContainer.clipsToBounds = true

        if #available(iOS 12.1, *) {
            let pencilInteraction = UIPencilInteraction()
            self.pencilInteraction = pencilInteraction
        } else {
            self.pencilInteraction = nil
        }

        super.init(frame: CGRect(origin: .zero, size: size))

        if #available(iOS 12.1, *), let pencilInteraction = self.pencilInteraction as? UIPencilInteraction {
            pencilInteraction.delegate = self
            self.addInteraction(pencilInteraction)
        }

        self.backgroundColor = .clear
        self.contentScaleFactor = 1.0
        self.isExclusiveTouch = true

        self.addSubview(self.currentDrawingViewContainer)

        let drawingGesturePipeline = DrawingGesturePipeline(view: self)
        drawingGesturePipeline.gestureRecognizer?.shouldBegin = { [weak self] point in
            if let strongSelf = self {
                if !strongSelf.shouldBegin(point) {
                    return false
                }
                if strongSelf.undoStack.isEmpty && !strongSelf.hasOpaqueData && strongSelf.tool == .eraser {
                    return false
                }
                if strongSelf.tool == .blur, strongSelf.preparedBlurredImage == nil {
                    return false
                }
                if let uncommitedElement = strongSelf.uncommitedElement as? PenTool, uncommitedElement.isFinishingArrow {
                    return false
                }
                return true
            } else {
                return false
            }
        }
        drawingGesturePipeline.onDrawing = { [weak self] state, point in
            guard let strongSelf = self else {
                return
            }
            let currentTimestamp = CACurrentMediaTime()
            switch state {
            case .began:
                strongSelf.isDrawing = true
                strongSelf.drawingGestureStartTimestamp = currentTimestamp
                strongSelf.previousPointTimestamp = currentTimestamp

                if strongSelf.uncommitedElement != nil {
                    strongSelf.finishDrawing(rect: CGRect(origin: .zero, size: strongSelf.imageSize), synchronous: true)
                }

                if case .marker = strongSelf.tool, let metalView = strongSelf.metalView {
                    metalView.isHidden = false
                }

                if case .chartlet = strongSelf.tool, let metalView = strongSelf.metalView {
                    metalView.isHidden = false
                }

                if case .rainbow = strongSelf.tool, let metalView = strongSelf.metalView {
                    metalView.isHidden = false
                }

                guard let newElement = strongSelf.setupNewElement() else {
                    return
                }

                if let dash = newElement as? DashTool {
                    dash.dashSize = strongSelf.dashSize
                }

                if let renderView = newElement.setupRenderView(screenSize: strongSelf.screenSize) {
                    if let currentDrawingView = strongSelf.currentDrawingRenderView {
                        strongSelf.currentDrawingRenderView = nil
                        currentDrawingView.removeFromSuperview()
                    }
                    if strongSelf.tool == .eraser {
                        strongSelf.currentDrawingViewContainer.removeFromSuperview()
                        strongSelf.currentDrawingViewContainer.backgroundColor = .white

                        renderView.layer.compositingFilter = "xor"

                        strongSelf.currentDrawingViewContainer.addSubview(renderView)
                        strongSelf.mask = strongSelf.currentDrawingViewContainer
                    } else if strongSelf.tool == .blur {
                        strongSelf.currentDrawingViewContainer.mask = renderView
                        strongSelf.currentDrawingViewContainer.image = strongSelf.preparedBlurredImage
                    } else {
                        strongSelf.currentDrawingViewContainer.addSubview(renderView)
                    }
                    strongSelf.currentDrawingRenderView = renderView
                }

                if let renderLayer = newElement.setupRenderLayer() {
                    if let currentDrawingLayer = strongSelf.currentDrawingLayer {
                        strongSelf.currentDrawingLayer = nil
                        currentDrawingLayer.removeFromSuperlayer()
                    }
                    if strongSelf.tool == .eraser {
                        strongSelf.currentDrawingViewContainer.removeFromSuperview()
                        strongSelf.currentDrawingViewContainer.backgroundColor = .white

                        renderLayer.compositingFilter = "xor"

                        strongSelf.currentDrawingViewContainer.layer.addSublayer(renderLayer)
                        strongSelf.mask = strongSelf.currentDrawingViewContainer
                    } else if strongSelf.tool == .blur {
                        strongSelf.currentDrawingViewContainer.layer.mask = renderLayer
                        strongSelf.currentDrawingViewContainer.image = strongSelf.preparedBlurredImage
                    } else {
                        strongSelf.currentDrawingViewContainer.layer.addSublayer(renderLayer)
                    }
                    strongSelf.currentDrawingLayer = renderLayer
                }
                newElement.updatePath(point, state: state, zoomScale: strongSelf.zoomScale)
                strongSelf.uncommitedElement = newElement
                strongSelf.updateInternalState()
            case .changed:
                if let previousPointTimestamp = strongSelf.previousPointTimestamp, currentTimestamp - previousPointTimestamp < 0.016 {
                    return
                }

                strongSelf.previousPointTimestamp = currentTimestamp
                strongSelf.uncommitedElement?.updatePath(point, state: state, zoomScale: strongSelf.zoomScale)
            case .ended, .cancelled:
                strongSelf.isDrawing = false
                strongSelf.uncommitedElement?.updatePath(point, state: state, zoomScale: strongSelf.zoomScale)

                if strongSelf.uncommitedElement?.isValid == true {
                    let bounds = strongSelf.uncommitedElement?.bounds
                    Queue.mainQueue().after(0.05) {
                        if let bounds = bounds {
                            strongSelf.finishDrawing(rect: bounds, synchronous: true)
                        }
                    }
                } else {
                    strongSelf.cancelDrawing()
                }
                strongSelf.updateInternalState()
            }
        }
        self.drawingGesturePipeline = drawingGesturePipeline

        initMetalVew()
    }

    func getBounds(uncommitedElement: DrawingElement?) -> CGRect? {
        guard let uncommitedElement = uncommitedElement else {
            return nil
        }

        let bounds = uncommitedElement.bounds
        if let contentRect = self.contentRect {
            self.contentRect = bounds.union(contentRect)
        } else {
            self.contentRect = bounds
        }

        return self.contentRect
    }

    func initMetalVew() {
        var size = self.imageSize
        if Int(size.width) % 16 != 0 {
            size.width = ceil(size.width / 16.0) * 16.0
        }

        let image = getImage(name: "marker")
        if let metalView = DrawingMetalView(size: size, sources: [image]) {
            metalView.transform = self.currentDrawingViewContainer.transform
            if size.width != self.imageSize.width {
                let scaledSize = size.preciseAspectFilled(self.currentDrawingViewContainer.frame.size)
                metalView.frame = CGRect(origin: .zero, size: scaledSize)
            } else {
                metalView.frame = self.currentDrawingViewContainer.frame
            }
            self.metalView?.removeFromSuperview()
            self.insertSubview(metalView, aboveSubview: self.currentDrawingViewContainer)
            self.metalView = metalView
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setup(withDrawing drawingData: Data?) {
        if let drawingData = drawingData, let image = UIImage(data: drawingData) {
            self.hasOpaqueData = true

            if let context = DrawingContext(size: image.size, scale: 1.0, opaque: false) {
                context.withFlippedContext { context in
                    if let cgImage = image.cgImage {
                        context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))
                    }
                }
                self.drawingImage = context.generateImage() ?? image
            } else {
                self.drawingImage = image
            }
            self.layer.contents = image.cgImage
            self.updateInternalState()
        }
    }

    var hasOpaqueData = false
    public var drawingData: Data? {
        guard !self.undoStack.isEmpty || self.hasOpaqueData else {
            return nil
        }
        return self.drawingImage?.pngData()
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @available(iOS 12.1, *)
    public func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser:
            self.requestedEraserToggle()
        case .showColorPalette:
            self.requestedColorPicker()
        case .switchPrevious:
            self.requestedToolsToggle()
        default:
            break
        }
    }

    private let queue = Queue()
    private func commit(interactive: Bool = false, synchronous: Bool = true, completion: @escaping () -> Void = {}) {
        let currentImage = self.drawingImage
        let uncommitedElement = self.uncommitedElement
        let imageSize = self.imageSize

        let action = {
            let updatedImage = self.renderer.image { context in
                context.cgContext.setBlendMode(.copy)
                context.cgContext.clear(CGRect(origin: .zero, size: imageSize))
                if let image = currentImage {
                    image.draw(at: .zero)
                }
                if let uncommitedElement = uncommitedElement {
                    context.cgContext.setBlendMode(.normal)
                    uncommitedElement.draw(in: context.cgContext, size: imageSize)
                }
            }

            Queue.mainQueue().async {
                self.drawingImage = updatedImage
                self.layer.contents = updatedImage.cgImage

                let bounds = self.getBounds(uncommitedElement: uncommitedElement)
                if let bounds = bounds {
                    self.handleResult(for: bounds)
                }

                if let currentDrawingRenderView = self.currentDrawingRenderView {
                    if case .eraser = self.tool {
                        currentDrawingRenderView.removeFromSuperview()
                        self.mask = nil
                        self.insertSubview(self.currentDrawingViewContainer, at: 0)
                        self.currentDrawingViewContainer.backgroundColor = .clear
                    } else if case .blur = self.tool {
                        self.currentDrawingViewContainer.mask = nil
                        self.currentDrawingViewContainer.image = nil
                    } else {
                        currentDrawingRenderView.removeFromSuperview()
                    }
                    self.currentDrawingRenderView = nil
                }
                if let currentDrawingLayer = self.currentDrawingLayer {
                    if case .eraser = self.tool {
                        currentDrawingLayer.removeFromSuperlayer()
                        self.mask = nil
                        self.insertSubview(self.currentDrawingViewContainer, at: 0)
                        self.currentDrawingViewContainer.backgroundColor = .clear
                    } else if case .blur = self.tool {
                        self.currentDrawingViewContainer.layer.mask = nil
                        self.currentDrawingViewContainer.image = nil
                    } else {
                        currentDrawingLayer.removeFromSuperlayer()
                    }
                    self.currentDrawingLayer = nil
                }

                if self.tool == .marker || self.tool == .chartlet {
                    self.metalView?.clear()
                    self.metalView?.isHidden = true
                }
                completion()
            }
        }
        if synchronous {
            action()
        } else {
            self.queue.async {
                action()
            }
        }
    }

    fileprivate func cancelDrawing() {
        self.uncommitedElement = nil

        if let currentDrawingRenderView = self.currentDrawingRenderView {
            if case .eraser = self.tool {
                currentDrawingRenderView.removeFromSuperview()
                self.mask = nil
                self.insertSubview(self.currentDrawingViewContainer, at: 0)
                self.currentDrawingViewContainer.backgroundColor = .clear
            } else if case .blur = self.tool {
                self.currentDrawingViewContainer.mask = nil
                self.currentDrawingViewContainer.image = nil
            } else {
                currentDrawingRenderView.removeFromSuperview()
            }
            self.currentDrawingRenderView = nil
        }
        if let currentDrawingLayer = self.currentDrawingLayer {
            if self.tool == .eraser {
                currentDrawingLayer.removeFromSuperlayer()
                self.mask = nil
                self.insertSubview(self.currentDrawingViewContainer, at: 0)
                self.currentDrawingViewContainer.backgroundColor = .clear
            } else if self.tool == .blur {
                self.currentDrawingViewContainer.mask = nil
                self.currentDrawingViewContainer.image = nil
            } else {
                currentDrawingLayer.removeFromSuperlayer()
            }
            self.currentDrawingLayer = nil
        }
        if case .marker = self.tool {
            self.metalView?.isHidden = true
        }
        if case .chartlet = self.tool {
            self.metalView?.isHidden = true
        }
        if case .rainbow = self.tool {
            self.metalView?.isHidden = true
        }
    }

    private func slice(for rect: CGRect, and contentRect: CGRect) -> DrawingSlice? {
        if let subImage = self.drawingImage?.cgImage?.cropping(to: rect) {
            return DrawingSlice(image: subImage, rect: rect, contentRect: contentRect)
        }
        return nil
    }

    private func handleResult(for rect: CGRect) {
        if let subImage = self.drawingImage?.cgImage?.cropping(to: rect) {
            resultImage = UIImage(cgImage: subImage)
        } else {
            resultImage = nil
        }
    }

    fileprivate func finishDrawing(rect: CGRect, synchronous: Bool = false) {
        let complete: (Bool) -> Void = { synchronous in
            if let uncommitedElement = self.uncommitedElement, !uncommitedElement.isValid {
                self.uncommitedElement = nil
            }

            let cRect: CGRect
            if let value = self.contentRect {
                cRect = value.union(rect)
            } else {
                cRect = rect
            }
            if !self.undoStack.isEmpty || self.hasOpaqueData, let slice = self.slice(for: rect, and: cRect) {
                self.undoStack.append(.slice(slice))
            } else {
                self.undoStack.append(.clearAll(rect))
            }

            self.commit(interactive: true, synchronous: synchronous)

            self.redoStack.removeAll()
            self.uncommitedElement = nil

            self.updateInternalState()
        }
        if let uncommitedElement = self.uncommitedElement as? PenTool, uncommitedElement.hasArrow {
            uncommitedElement.finishArrow({
                complete(true)
            })
        } else {
            complete(synchronous)
        }
    }

   public func clear() {
        self.uncommitedElement = nil
        self.undoStack.removeAll()
        self.redoStack.removeAll()
        self.hasOpaqueData = false

        let snapshotView = UIImageView(image: self.drawingImage)
        snapshotView.frame = self.bounds
        self.addSubview(snapshotView)

        self.drawingImage = nil
        self.layer.contents = nil
        self.resultImage = nil
        self.contentRect = nil

        Queue.mainQueue().justDispatch {
            snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                snapshotView?.removeFromSuperview()
            })
        }

        self.updateInternalState()

        self.updateBlurredImage()
    }

    private func applySlice(_ slice: DrawingSlice) {
        let updatedImage = self.renderer.image { context in
            context.cgContext.clear(CGRect(origin: .zero, size: imageSize))
            context.cgContext.setBlendMode(.copy)
            if let image = self.drawingImage {
                image.draw(at: .zero)
            }
            if let image = slice.image {
                context.cgContext.translateBy(x: imageSize.width / 2.0, y: imageSize.height / 2.0)
                context.cgContext.scaleBy(x: 1.0, y: -1.0)
                context.cgContext.translateBy(x: -imageSize.width / 2.0, y: -imageSize.height / 2.0)
                context.cgContext.translateBy(x: slice.rect.minX, y: imageSize.height - slice.rect.maxY)
                context.cgContext.draw(image, in: CGRect(origin: .zero, size: slice.rect.size))
            }
        }
        self.drawingImage = updatedImage
        self.layer.contents = updatedImage.cgImage
        self.contentRect = slice.contentRect
        handleResult(for: slice.contentRect)
    }

    public var canUndo: Bool {
        return !self.undoStack.isEmpty
    }

    public var canRedo: Bool {
        return !self.redoStack.isEmpty
    }

    public func undo() {
        guard let lastOperation = self.undoStack.last else {
            return
        }
        switch lastOperation {
        case let .clearAll(rect):
            if let slice = self.slice(for: rect, and: rect) {
                self.redoStack.append(.slice(slice))
            }
            UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve) {
                self.drawingImage = nil
                self.resultImage = nil
                self.contentRect = nil
                self.layer.contents = nil
            }
            self.updateBlurredImage()
        case let .slice(slice):
            if let slice = self.slice(for: slice.rect, and: slice.contentRect) {
                self.redoStack.append(.slice(slice))
            }
            UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve) {
                self.applySlice(slice)
            }
            self.updateBlurredImage()
        }

        self.undoStack.removeLast()

        self.updateInternalState()
    }

    public func redo() {
        guard let lastOperation = self.redoStack.last else {
            return
        }

        switch lastOperation {
            case .clearAll:
                break
            case let .slice(slice):
            if !self.undoStack.isEmpty || self.hasOpaqueData, let slice = self.slice(for: slice.rect, and: slice.contentRect) {
                    self.undoStack.append(.slice(slice))
                } else {
                    self.undoStack.append(.clearAll(slice.rect))
                }
                UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve) {
                    self.applySlice(slice)
                }
                self.updateBlurredImage()
        }

        self.redoStack.removeLast()

        self.updateInternalState()
    }

    private var preparedBlurredImage: UIImage?

    public func updateToolState(_ state: DrawingToolState) {
        let previousTool = self.tool
        switch state {
        case let .pen(brushState):
            self.tool = .pen
            self.toolColor = brushState.color
            self.toolBrushSize = brushState.size
            self.drawingGesturePipeline?.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale)
        case let .dash(brushState):
            self.tool = .dash
            self.toolColor = brushState.color
            self.toolBrushSize = brushState.size
            self.dashSize = brushState.dashSize
            self.drawingGesturePipeline?.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale)
        case let .arrow(brushState):
            self.tool = .arrow
            self.toolColor = brushState.color
            self.toolBrushSize = brushState.size
            self.drawingGesturePipeline?.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale)
        case .marker(let brushState), .rainbow(let brushState):
            self.tool = .marker
            self.toolColor = brushState.color
            self.toolBrushSize = brushState.size

            var size = self.imageSize
            if Int(size.width) % 16 != 0 {
                size.width = ceil(size.width / 16.0) * 16.0
            }

            let bImgs = brushState.images
            var images = bImgs.isEmpty ? [getImage(name: "marker")] : bImgs
            var style: DrawingMetalView.Style = .marker
            if case .rainbow = state {
                self.tool = .rainbow
                style = .rainbow
                images = bImgs.isEmpty ? [getImage(name: "rainbow")] : bImgs
            }
            if let metalView = DrawingMetalView(size: size, sources: images, style: style, dashSize: brushState.dashSize) {
                metalView.transform = self.currentDrawingViewContainer.transform
                if size.width != self.imageSize.width {
                    let scaledSize = size.preciseAspectFilled(self.currentDrawingViewContainer.frame.size)
                    metalView.frame = CGRect(origin: .zero, size: scaledSize)
                } else {
                    metalView.frame = self.currentDrawingViewContainer.frame
                }

                self.metalView?.removeFromSuperview()
                self.insertSubview(metalView, aboveSubview: self.currentDrawingViewContainer)
                self.metalView = metalView
            }
            self.drawingGesturePipeline?.transform = .identity
        case let .chartlet(brushState):
            self.tool = .chartlet
            self.toolColor = brushState.color
            self.toolBrushSize = brushState.size

            var size = self.imageSize
            if Int(size.width) % 16 != 0 {
                size.width = ceil(size.width / 16.0) * 16.0
            }

            let images = brushState.images.isEmpty ? [getImage(name: "stamp")] : brushState.images
            let offset: CGFloat = brushState.images.isEmpty ? 0.5 : brushState.offset
            if let metalView = DrawingMetalView(size: size, sources: images, style: .chartlet, offset: offset, renderStyle: brushState.renderStyle) {
                metalView.transform = self.currentDrawingViewContainer.transform
                if size.width != self.imageSize.width {
                    let scaledSize = size.preciseAspectFilled(self.currentDrawingViewContainer.frame.size)
                    metalView.frame = CGRect(origin: .zero, size: scaledSize)
                } else {
                    metalView.frame = self.currentDrawingViewContainer.frame
                }
                self.metalView?.removeFromSuperview()
                self.insertSubview(metalView, aboveSubview: self.currentDrawingViewContainer)
                self.metalView = metalView
            }

            self.drawingGesturePipeline?.transform = .identity
        case let .neon(brushState):
            self.tool = .neon
            self.toolColor = brushState.color
            self.toolBrushSize = brushState.size
            self.drawingGesturePipeline?.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale)
        case let .blur(blurState):
            self.tool = .blur
            self.toolBrushSize = blurState.size
            self.drawingGesturePipeline?.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale)
        case let .eraser(eraserState):
            self.tool = .eraser
            self.toolBrushSize = eraserState.size
            self.drawingGesturePipeline?.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale)
        }

        if self.tool != previousTool {
            self.updateBlurredImage()
        }
    }

    func getImage(name: String) -> UIImage? {
        let mainBundle = Bundle(for: DrawingView.self)
        guard let path = mainBundle.path(forResource: "DrawingKitBundle", ofType: "bundle"), let bundle = Bundle(path: path) else {
            return nil
        }

        guard let imagePath = bundle.path(forResource: name, ofType: "png") else {
            return nil
        }

        return UIImage(contentsOfFile: imagePath)
    }

    func updateBlurredImage() {
        if case .blur = self.tool {
            Queue.concurrentDefaultQueue().async {
                if let image = self.getFullImage() {
                    Queue.mainQueue().async {
                        self.preparedBlurredImage = image
                    }
                }
            }
        } else {
            self.preparedBlurredImage = nil
        }
    }

    func performAction(_ action: Action) {
        switch action {
        case .undo:
            self.undo()
        case .redo:
            self.redo()
        case .clear:
            self.clear()
        case .zoomOut:
            self.zoomOut()
        }
    }

    private func updateInternalState() {
        self.stateUpdated(NavigationState(
            canUndo: !self.undoStack.isEmpty,
            canRedo: !self.redoStack.isEmpty,
            canClear: !self.undoStack.isEmpty || self.hasOpaqueData,
            canZoomOut: self.zoomScale > 1.0 + .ulpOfOne,
            isDrawing: self.isDrawing
        ))
    }

    public func updateZoomScale(_ scale: CGFloat) {
        self.cancelDrawing()
        self.zoomScale = scale
        self.updateInternalState()
    }

    private func setupNewElement() -> DrawingElement? {
        let scale = 1.0 / self.zoomScale
        let element: DrawingElement?
        switch self.tool {
        case .pen:
            let penTool = PenTool(
                drawingSize: self.imageSize,
                color: self.toolColor,
                lineWidth: self.toolBrushSize * scale,
                hasArrow: false,
                isEraser: false,
                isBlur: false,
                blurredImage: nil
            )
            element = penTool
        case .arrow:
            let penTool = PenTool(
                drawingSize: self.imageSize,
                color: self.toolColor,
                lineWidth: self.toolBrushSize * scale,
                hasArrow: true,
                isEraser: false,
                isBlur: false,
                blurredImage: nil
            )
            element = penTool
        case .dash:
            let dashTool = DashTool(
                drawingSize: self.imageSize,
                color: self.toolColor,
                lineWidth: self.toolBrushSize * scale
            )
            element = dashTool
        case .marker:
            let markerTool = MarkerTool(
                drawingSize: self.imageSize,
                color: self.toolColor,
                lineWidth: self.toolBrushSize * scale
            )
            markerTool.metalView = self.metalView
            element = markerTool
        case .chartlet:
            let chatletTool = CharteltTool(
                drawingSize: self.imageSize,
                color: self.toolColor,
                lineWidth: self.toolBrushSize * scale
            )
            chatletTool.metalView = self.metalView
            element = chatletTool
        case .rainbow:
            let rainbowTool = RainbowTool(
                drawingSize: self.imageSize,
                color: self.toolColor,
                lineWidth: self.toolBrushSize * scale
            )
            rainbowTool.metalView = self.metalView
            element = rainbowTool
        case .neon:
            element = NeonTool(
                drawingSize: self.imageSize,
                color: self.toolColor,
                lineWidth: self.toolBrushSize * scale
            )
        case .blur:
            let penTool = PenTool(
                drawingSize: self.imageSize,
                color: self.toolColor,
                lineWidth: self.toolBrushSize * scale,
                hasArrow: false,
                isEraser: false,
                isBlur: true,
                blurredImage: self.preparedBlurredImage
            )
            element = penTool
        case .eraser:
            let penTool = PenTool(
                drawingSize: self.imageSize,
                color: self.toolColor,
                lineWidth: self.toolBrushSize * scale,
                hasArrow: false,
                isEraser: true,
                isBlur: false,
                blurredImage: nil
            )
            element = penTool
        }
        return element
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        let scale = self.scale
        let transform = CGAffineTransformMakeScale(scale, scale)
        self.currentDrawingViewContainer.transform = transform
        self.currentDrawingViewContainer.frame = self.bounds

        self.drawingGesturePipeline?.transform = CGAffineTransformMakeScale(1.0 / scale, 1.0 / scale)

        if let metalView = self.metalView {
            var size = self.imageSize
            if Int(size.width) % 16 != 0 {
                size.width = ceil(size.width / 16.0) * 16.0
            }
            metalView.transform = transform
            if size.width != self.imageSize.width {
                let scaledSize = size.preciseAspectFilled(self.currentDrawingViewContainer.frame.size)
                metalView.frame = CGRect(origin: .zero, size: scaledSize)
            } else {
                metalView.frame = self.currentDrawingViewContainer.frame
            }
        }
    }

    public var isEmpty: Bool {
        return self.undoStack.isEmpty && !self.hasOpaqueData
    }

    public var scale: CGFloat {
        return self.bounds.width / self.imageSize.width
    }

    public var isTracking: Bool {
        return self.uncommitedElement != nil
    }
}

private extension CGSize {
    func preciseAspectFilled(_ size: CGSize) -> CGSize {
        let scale = max(size.width / max(1.0, self.width), size.height / max(1.0, self.height))
        return CGSize(width: self.width * scale, height: self.height * scale)
    }
}

private class DrawingSlice {
    private static let queue = Queue()

    var _image: CGImage?

    let uuid: UUID
    var image: CGImage? {
        if let image = self._image {
            return image
        } else if let data = try? Data(contentsOf: URL(fileURLWithPath: self.path)) {
            return UIImage(data: data)?.cgImage
        } else {
            return nil
        }
    }
    let rect: CGRect
    let path: String
    let contentRect: CGRect

    init(image: CGImage, rect: CGRect, contentRect: CGRect) {
        self.uuid = UUID()

        self._image = image
        self.rect = rect
        self.contentRect = contentRect
        self.path = NSTemporaryDirectory() + "/drawing_\(uuid.hashValue).slice"

        DrawingSlice.queue.after(2.0) {
            let image = UIImage(cgImage: image)
            if let data = image.pngData() as? NSData {
                try? data.write(toFile: self.path)
                Queue.mainQueue().async {
                    self._image = nil
                }
            }
        }
    }

    deinit {
        try? FileManager.default.removeItem(atPath: self.path)
    }
}

