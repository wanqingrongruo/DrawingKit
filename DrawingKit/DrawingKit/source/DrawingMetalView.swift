//
//  DrawingMetalView.swift
//  DrawingCat
//
//  Created by roni on 2023/2/7.
//

import Foundation
import UIKit
import QuartzCore
import MetalKit

// MARK: - Simulator fix

internal var metalAvaliable: Bool = {
    #if targetEnvironment(simulator)
    if #available(iOS 13.0, *) {
        return true
    } else {
        return false
    }
    #else
    return true
    #endif
}()


final class DrawingMetalView: MTKView {
    let size: CGSize

    private let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    private var pipelineState: MTLRenderPipelineState!

    var drawable: Drawable?

    private var render_target_vertex: MTLBuffer!
    private var render_target_uniform: MTLBuffer!

    private var markerBrush: Brush?
    var chartletBrush: ChartletBrush?
    var rainbowBrush: RainbowBrush?

    private var sources: [UIImage?]
    private var dashSize: CGFloat?
    private var offset: CGFloat = 0
    private var renderStyle: Int
    var style: Style {
        didSet {
            createBrush()
        }
    }

    /// All textures created by this canvas
    private(set) var textures: [MLTexture] = []

    enum Style {
        case marker, chartlet, rainbow
    }

    init?(size: CGSize, sources: [UIImage?], style: Style = .marker, dashSize: CGFloat? = nil, offset: CGFloat = 0, renderStyle: Int = 0) {
        let mainBundle = Bundle(for: DrawingView.self)
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }

        guard let defaultLibrary = try? device.makeDefaultLibrary(bundle: mainBundle) else {
            return nil
        }

        self.library = defaultLibrary
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.commandQueue = commandQueue
        self.size = size
        self.sources = sources
        self.dashSize = dashSize
        self.renderStyle = renderStyle
        self.style = style
        self.offset = offset

        super.init(frame: CGRect(origin: .zero, size: size), device: device)

        self.drawableSize = self.size
        self.autoResizeDrawable = false
        self.isOpaque = false
        self.contentScaleFactor = 1.0
        self.isPaused = true
        self.preferredFramesPerSecond = 60
        self.presentsWithTransaction = true
        self.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)


        sources.forEach { image in
            if let img = image, let data = img.pngData() {
                makeTexture(with: data)
            }
        }

        self.setup()
    }

    override var isHidden: Bool {
        didSet {
            if self.isHidden {
                Queue.mainQueue().after(0.2) {
                    self.isPaused = true
                }
            } else {
                self.isPaused = self.isHidden
            }
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// find texture by textureID
    func findTexture(by id: String) -> MLTexture? {
        return textures.first { $0.id == id }
    }


    @discardableResult
    func makeTexture(with data: Data, id: String? = nil) -> MLTexture? {
        if let id = id, let exists = findTexture(by: id) {
            return exists
        }

        guard metalAvaliable else {
            fatalError("simulator Unsupported")
        }

        let textureLoader = MTKTextureLoader(device: device!)
        if let texture = try? textureLoader.newTexture(data: data, options: [.SRGB : false]) {
            let item = MLTexture(id: id ?? UUID().uuidString, texture: texture)
            textures.append(item)
            return item
        }

        return nil
    }

    func makeTexture(with image: UIImage) -> MLTexture? {
        if let data = image.pngData() {
            return makeTexture(with: data)
        } else {
            return nil
        }
    }

    func makeTexture(with file: URL, id: String? = nil) -> MLTexture? {
        if let data = try? Data(contentsOf: file) {
            return makeTexture(with: data, id: id)
        }

        return nil
    }

    func drawInContext(_ cgContext: CGContext) {
        guard let texture = self.drawable?.texture, let image = texture.createCGImage() else {
            return
        }
        let rect = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
        cgContext.saveGState()
        cgContext.translateBy(x: rect.midX, y: rect.midY)
        cgContext.scaleBy(x: 1.0, y: -1.0)
        cgContext.translateBy(x: -rect.midX, y: -rect.midY)
        cgContext.draw(image, in: rect)
        cgContext.restoreGState()
    }

    private func setup() {
        self.drawable = Drawable(size: self.size, pixelFormat: self.colorPixelFormat, device: device)

        let size = self.size
        let w = size.width, h = size.height
        let vertices = [
            Vertex(position: CGPoint(x: 0 , y: 0), texCoord: CGPoint(x: 0, y: 0)),
            Vertex(position: CGPoint(x: w , y: 0), texCoord: CGPoint(x: 1, y: 0)),
            Vertex(position: CGPoint(x: 0 , y: h), texCoord: CGPoint(x: 0, y: 1)),
            Vertex(position: CGPoint(x: w , y: h), texCoord: CGPoint(x: 1, y: 1)),
        ]
        self.render_target_vertex = self.device?.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: .cpuCacheModeWriteCombined)

        let matrix = Matrix.identity
        matrix.scaling(x: 2.0 / Float(size.width), y: -2.0 / Float(size.height), z: 1)
        matrix.translation(x: -1, y: 1, z: 0)
        self.render_target_uniform = self.device?.makeBuffer(bytes: matrix.m, length: MemoryLayout<Float>.size * 16, options: [])

        let vertexFunction = self.library.makeFunction(name: "vertex_render_target")
        let fragmentFunction = self.library.makeFunction(name: "fragment_render_target")
        let pipelineDescription = MTLRenderPipelineDescriptor()
        pipelineDescription.vertexFunction = vertexFunction
        pipelineDescription.fragmentFunction = fragmentFunction
        pipelineDescription.colorAttachments[0].pixelFormat = colorPixelFormat

        do {
            self.pipelineState = try self.device?.makeRenderPipelineState(descriptor: pipelineDescription)
        } catch {
            fatalError(error.localizedDescription)
        }

        createBrush()

        self.drawable?.clear()

        Queue.mainQueue().after(0.1) {
            switch self.style {
            case .marker:
                self.markerBrush?.pushPoint(CGPoint(x: 100.0, y: 100.0), color: DrawingColor.clear, size: 0.0, isEnd: true)
            case .chartlet:
                self.chartletBrush?.pushPoint(CGPoint(x: 100.0, y: 100.0), color: DrawingColor.clear, size: 0.0, isEnd: true)
            case .rainbow:
                self.rainbowBrush?.pushPoint(CGPoint(x: 100.0, y: 100.0), color: DrawingColor.clear, size: 0.0, isEnd: true)
            }

            Queue.mainQueue().after(0.1) {
                self.clear()
            }
        }
    }

    func createBrush() {
        switch style {
        case .marker:
            if let texture = textures.first {
                self.markerBrush = Brush(texture: texture.texture, target: self, rotation: dashSize == nil ? .fixed(-0.55) : .ahead, dashSize: dashSize)
            }
        case .chartlet:
            if !textures.isEmpty {
                self.chartletBrush = ChartletBrush(name: "chartlet", textures: textures, renderStyle: renderStyle, target: self, rotation: .fixed(-0.55), offset: offset)
            }
        case .rainbow:
            if let texture = textures.first {
                self.rainbowBrush = RainbowBrush(texture: texture.texture, target: self, rotation: .fixed(0))
            }
        }
    }

    /// draw a chartlet to canvas
    ///
    /// - Parameters:
    ///   - point: location where to draw the chartlet
    ///   - size: size of texture
    ///   - textureID: id of texture for drawing
    ///   - rotation: rotation angle of texture for drawing
    func renderChartlet(at point: CGPoint, size: CGSize, textureID: String, rotation: CGFloat = 0) {
        let chartlet = Chartlet(center: point, size: size, textureID: textureID, angle: rotation, canvas: self)
        chartlet.drawSelf(on: drawable)
        drawable?.commit()
    }

    override var frame: CGRect {
        get {
            return super.frame
        } set {
            super.frame = newValue
            self.drawableSize = self.size
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard let drawable = self.drawable, let texture = drawable.texture?.texture else {
            return
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = renderPassDescriptor.colorAttachments[0]
        attachment?.clearColor = self.clearColor
        attachment?.texture = self.currentDrawable?.texture
        attachment?.loadAction = .clear
        attachment?.storeAction = .store

        guard let _ = attachment?.texture else {
            return
        }

        let commandBuffer = self.commandQueue.makeCommandBuffer()
        let commandEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

        commandEncoder?.setRenderPipelineState(self.pipelineState)

        commandEncoder?.setVertexBuffer(self.render_target_vertex, offset: 0, index: 0)
        commandEncoder?.setVertexBuffer(self.render_target_uniform, offset: 0, index: 1)
        commandEncoder?.setFragmentTexture(texture, index: 0)
        commandEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        commandEncoder?.endEncoding()

        if let currentDrawable = currentDrawable {
            commandBuffer?.commit()
            commandBuffer?.waitUntilScheduled()
            currentDrawable.present()
        }
    }

    func reset() {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = renderPassDescriptor.colorAttachments[0]
        attachment?.clearColor = self.clearColor
        attachment?.texture = self.currentDrawable?.texture
        attachment?.loadAction = .clear
        attachment?.storeAction = .store

        let commandBuffer = self.commandQueue.makeCommandBuffer()
        let commandEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

        commandEncoder?.endEncoding()
        commandBuffer?.commit()
        commandBuffer?.waitUntilScheduled()
        self.currentDrawable?.present()
    }

    func clear() {
        guard let drawable = self.drawable else {
            return
        }

        drawable.updateBuffer(with: self.size)
        drawable.clear()
        self.reset()
    }

    enum BrushType {
        case marker, chartlet, rainbow
    }

    func updated(_ point: DrawingPoint, state: DrawingGesturePipeline.DrawingGestureState, brush: BrushType, color: DrawingColor, size: CGFloat, zoomScale: CGFloat) {
        switch brush {
        case .marker:
            self.markerBrush?.updated(point, color: color, state: state, size: size)
        case .chartlet:
            self.chartletBrush?.updated(point, color: color, state: state, size: size)
        case .rainbow:
            self.rainbowBrush?.updated(point, color: color, state: state, size: size)
        }
    }
}

class Drawable {
    public private(set) var texture: Texture?

    internal var pixelFormat: MTLPixelFormat = .bgra8Unorm
    internal var size: CGSize
    internal var uniform_buffer: MTLBuffer!
    internal var transform_buffer: MTLBuffer!
    internal var renderPassDescriptor: MTLRenderPassDescriptor?
    internal var commandBuffer: MTLCommandBuffer?
    internal var commandQueue: MTLCommandQueue?
    internal var device: MTLDevice?

    /// the scale level of view, all things scales
    open var scale: CGFloat = 1 {
        didSet {
            updateTransformBuffer()
        }
    }

    /// the offset of render target with zoomed size
    open var contentOffset: CGPoint = .zero {
        didSet {
            updateTransformBuffer()
        }
    }

    public init(size: CGSize, pixelFormat: MTLPixelFormat, device: MTLDevice?) {
        self.size = size
        self.pixelFormat = pixelFormat
        self.device = device
        self.texture = self.makeTexture()
        self.commandQueue = device?.makeCommandQueue()

        self.renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = self.renderPassDescriptor?.colorAttachments[0]
        attachment?.texture = self.texture?.texture
        attachment?.loadAction = .load
        attachment?.storeAction = .store

        self.updateBuffer(with: size)
    }

    func clear() {
        self.texture?.clear()
        renderPassDescriptor?.colorAttachments[0].texture = texture?.texture
        commit()
    }

    func reset() {
        self.prepareForDraw()

        if let commandEncoder = self.makeCommandEncoder() {
            commandEncoder.endEncoding()
        }

        self.commit(wait: true)
    }

    internal func updateBuffer(with size: CGSize) {
        self.size = size

        let matrix = Matrix.identity
        self.uniform_buffer = device?.makeBuffer(bytes: matrix.m, length: MemoryLayout<Float>.size * 16, options: [])
        updateTransformBuffer()
    }

    internal func updateTransformBuffer() {
        let scaleFactor: CGFloat = 1 // = UIScreen.main.nativeScale
        var transform = ScrollingTransform(offset: .zero * scaleFactor, scale: scale)
        transform_buffer = device?.makeBuffer(bytes: &transform, length: MemoryLayout<ScrollingTransform>.stride, options: [])
    }

    internal func prepareForDraw() {
        if self.commandBuffer == nil {
            self.commandBuffer = self.commandQueue?.makeCommandBuffer()
        }
    }

    internal func makeCommandEncoder() -> MTLRenderCommandEncoder? {
        guard let commandBuffer = self.commandBuffer, let renderPassDescriptor = self.renderPassDescriptor else {
            return nil
        }
        return commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
    }


    internal func commit(wait: Bool = false) {
        self.commandBuffer?.commit()
        if wait {
            self.commandBuffer?.waitUntilCompleted()
        }
        self.commandBuffer = nil
    }

    internal func makeTexture() -> Texture? {
        guard self.size.width * self.size.height > 0, let device = self.device else {
            return nil
        }
        return Texture(device: device, width: Int(self.size.width), height: Int(self.size.height))
    }
}

private func alignUp(size: Int, align: Int) -> Int {
    precondition(((align - 1) & align) == 0, "Align must be a power of two")

    let alignmentMask = align - 1
    return (size + alignmentMask) & ~alignmentMask
}


class Brush {
    private(set) var texture: MTLTexture?
    private(set) var pipelineState: MTLRenderPipelineState!

    weak var target: DrawingMetalView?

    public enum Rotation {
        case fixed(CGFloat)
        case random
        case ahead
    }

    var rotation: Rotation
    private var dashSize: CGFloat? = nil

    required public init(texture: MTLTexture?, target: DrawingMetalView, rotation: Rotation, dashSize: CGFloat? = nil) {
        self.texture = texture
        self.target = target
        self.rotation = rotation
        self.dashSize = dashSize

        self.setupPipeline()
    }

    private func setupPipeline() {
        guard let target = self.target, let device = target.device else {
            return
        }

        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        if let vertex_func = makeShaderVertexFunction(from: target.library) {
            renderPipelineDescriptor.vertexFunction = vertex_func
        }

        if let fragment_func = makeShaderFragmentFunction(from: target.library) {
            renderPipelineDescriptor.fragmentFunction = fragment_func
        }

        renderPipelineDescriptor.colorAttachments[0].pixelFormat = target.colorPixelFormat

        if let attachment = renderPipelineDescriptor.colorAttachments[0] {
            setupBlendOptions(for: attachment)
        }

        self.pipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
    }

    /// make shader vertex function from the library made by makeShaderLibrary()
    /// overrides to provide your own vertex function
    open func makeShaderVertexFunction(from target: MTLLibrary) -> MTLFunction? {
        return target.makeFunction(name: "vertex_point_func")
    }

    /// make shader fragment function from the library made by makeShaderLibrary()
    /// overrides to provide your own fragment function
    open func makeShaderFragmentFunction(from target: MTLLibrary) -> MTLFunction? {
        if texture == nil {
            return target.makeFunction(name: "fragment_point_func_without_texture")
        }
        return target.makeFunction(name: "fragment_point_func")
    }

    /// Blending options for this brush, overrides to implement your own blending options
    open func setupBlendOptions(for attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        attachment.isBlendingEnabled = true

        attachment.rgbBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha

        attachment.alphaBlendOperation = .add
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    func render(stroke: Stroke, in drawable: Drawable? = nil) {
        let drawable = drawable ?? target?.drawable

        guard stroke.lines.count > 0, let target = drawable else {
            return
        }

        target.prepareForDraw()

        let commandEncoder = target.makeCommandEncoder()
        commandEncoder?.setRenderPipelineState(self.pipelineState)

        if let vertex_buffer = stroke.preparedBuffer(rotation: self.rotation) {
            commandEncoder?.setVertexBuffer(vertex_buffer, offset: 0, index: 0)
            commandEncoder?.setVertexBuffer(target.uniform_buffer, offset: 0, index: 1)
            commandEncoder?.setVertexBuffer(target.transform_buffer, offset: 0, index: 2)
            if let texture = texture {
                commandEncoder?.setFragmentTexture(texture, index: 0)
            }
            commandEncoder?.drawPrimitives(type: .point, vertexStart: 0, vertexCount: stroke.vertexCount)
        }

        commandEncoder?.endEncoding()
    }

    private let bezier = BezierGenerator()
    func updated(_ point: DrawingPoint, color: DrawingColor, state: DrawingGesturePipeline.DrawingGestureState, size: CGFloat) {
        let point = point.location
        switch state {
        case .began:
            lastRenderedPoint = point
            self.bezier.begin(with: point)
            let _ = self.pushPoint(point, color: color, size: size, isEnd: false)
        case .changed:
            if self.bezier.points.count > 0 && point != lastRenderedPoint {
                self.pushPoint(point, color: color, size: size, isEnd: false)
            }
        case .ended, .cancelled:
            if self.bezier.points.count >= 3 {
                self.pushPoint(point, color: color, size: size, isEnd: true)
            }
            self.bezier.finish()
            self.lastRenderedPoint = nil
        }
    }

    func getPointSize(size: CGFloat) -> CGFloat {
        return size
    }

    func getPointStep(size: CGFloat) -> CGFloat {
        if let dashSize = dashSize {
            return size * (1 + dashSize)
        }
        var pointStep: CGFloat
        if case .random = self.rotation {
            pointStep = size * 0.1
        } else {
            pointStep = min(size * 0.1, 1)
        }
        return pointStep
    }

    func setup(_ inputPoints: [CGPoint], color: DrawingColor, size: CGFloat) {
        guard inputPoints.count >= 2 else {
            return
        }

        let pointStep: CGFloat = getPointStep(size: size)
        var lines: [Line] = []

        var previousPoint = inputPoints[0]

        var points: [CGPoint] = []
        self.bezier.begin(with: inputPoints.first!)
        for point in inputPoints {
            let smoothPoints = self.bezier.pushPoint(point)
            points.append(contentsOf: smoothPoints)
        }
        self.bezier.finish()

        guard points.count >= 2 else {
            return
        }
        for i in 1 ..< points.count {
            let p = points[i]
            if (i == points.count - 1) || pointStep <= 1 || (pointStep > 1 && previousPoint.distance(to: p) >= pointStep) {
                let line = Line(start: previousPoint, end: p, pointSize: size, pointStep: pointStep)
                lines.append(line)
                previousPoint = p
            }
        }

        if let drawable = self.target?.drawable {
            let stroke = Stroke(color: color, lines: lines, target: drawable)
            self.render(stroke: stroke, in: drawable)
            drawable.commit(wait: true)
        }
    }

    private var lastRenderedPoint: CGPoint?
    func pushPoint(_ point: CGPoint, color: DrawingColor, size: CGFloat, isEnd: Bool) {
        let pointStep: CGFloat = getPointStep(size: size)
        var lines: [Line] = []
        let points = self.bezier.pushPoint(point)
        guard points.count >= 2 else {
            return
        }

        var previousPoint = self.lastRenderedPoint ?? points[0]
        for i in 1 ..< points.count {
            let p = points[i]
            if (isEnd && i == points.count - 1) ||
                pointStep <= 1 ||
                (pointStep > 1 && previousPoint.distance(to: p) >= pointStep) {
                let line = Line(start: previousPoint, end: p, pointSize: getPointSize(size: size), pointStep: pointStep)
                lines.append(line)
                previousPoint = p
                lastRenderedPoint = p
            }
        }

        render(lines: lines, color: color, pointSize: size, on: target)
    }

    open func render(lines: [Line], color: DrawingColor, pointSize: CGFloat, on canvas: DrawingMetalView?) {
        if let drawable = self.target?.drawable {
            let stroke = Stroke(color: color, lines: lines, target: drawable)
            self.render(stroke: stroke, in: drawable)
            drawable.commit()
        }
    }
}

 class Stroke {
    private weak var target: Drawable?

    let color: DrawingColor
    var lines: [Line] = []

    private(set) var vertexCount: Int = 0
    private var vertex_buffer: MTLBuffer?

    init(color: DrawingColor, lines: [Line] = [], target: Drawable) {
        self.color = color
        self.lines = lines
        self.target = target
    }

    func append(_ lines: [Line]) {
        self.lines.append(contentsOf: lines)
        self.vertex_buffer = nil
    }

    func preparedBuffer(rotation: Brush.Rotation) -> MTLBuffer? {
        guard !self.lines.isEmpty else {
            return nil
        }

        var vertexes: [Point] = []

        self.lines.forEach { (line) in
            let step = max(1, line.pointStep)
            let count = max(line.length / step, 1)
            let overlapping = max(1, line.pointSize / line.pointStep)
            var renderingColor = self.color
            renderingColor.alpha = renderingColor.alpha / overlapping * 5.5

            for i in 0 ..< Int(count) {
                let index = CGFloat(i)
                let x = line.start.x + (line.end.x - line.start.x) * (index / count)
                let y = line.start.y + (line.end.y - line.start.y) * (index / count)

                var angle: CGFloat = 0
                switch rotation {
                    case let .fixed(a):
                        angle = a
                    case .random:
                        angle = CGFloat.random(in: -CGFloat.pi ... CGFloat.pi)
                    case .ahead:
                        angle = line.angle
                }
                vertexes.append(Point(x: x, y: y, color: renderingColor, size: line.pointSize, angle: angle))
            }
        }

        self.vertexCount = vertexes.count
        self.vertex_buffer = self.target?.device?.makeBuffer(bytes: vertexes, length: MemoryLayout<Point>.stride * vertexCount, options: .cpuCacheModeWriteCombined)

        return self.vertex_buffer
    }
}

class BezierGenerator {
    init() {
    }

    init(beginPoint: CGPoint) {
        self.begin(with: beginPoint)
    }

    func begin(with point: CGPoint) {
        self.step = 0
        self.points.removeAll()
        self.points.append(point)
    }

    func pushPoint(_ point: CGPoint) -> [CGPoint] {
//        if point == self.points.last {
//            return []
//        }
        self.points.append(point)
        if self.points.count < 3 {
            return []
        }
        self.step += 1
        return self.generateSmoothPathPoints()
    }

    func finish() {
        self.step = 0
        self.points.removeAll()
    }

    var points: [CGPoint] = []

    private var step = 0
    private func generateSmoothPathPoints() -> [CGPoint] {
        var begin: CGPoint
        var control: CGPoint
        let end = CGPoint.middle(p1: self.points[step], p2: self.points[self.step + 1])

        var vertices: [CGPoint] = []
        if self.step == 1 {
            begin = self.points[0]
            let middle1 = CGPoint.middle(p1: self.points[0], p2: self.points[1])
            control = CGPoint.middle(p1: middle1, p2: self.points[1])
        } else {
            begin = CGPoint.middle(p1: self.points[self.step - 1], p2: self.points[self.step])
            control = self.points[self.step]
        }

        let distance = begin.distance(to: end)
        let segements = max(Int(distance / 3), 2)

        for i in 0 ..< segements {
            let t = CGFloat(i) / CGFloat(segements)
            vertices.append(begin.quadBezierPoint(to: end, controlPoint: control, t: t))
        }
        vertices.append(end)
        return vertices
    }
}

struct Line {
    var start: CGPoint
    var end: CGPoint

    var pointSize: CGFloat
    var pointStep: CGFloat

    init(start: CGPoint, end: CGPoint, pointSize: CGFloat, pointStep: CGFloat) {
        self.start = start
        self.end = end
        self.pointSize = pointSize
        self.pointStep = pointStep
    }

    var length: CGFloat {
        return self.start.distance(to: self.end)
    }

    var angle: CGFloat {
        return self.end.angleInMetal(to: self.start)
    }
}

final class Texture {
    let buffer: MTLBuffer?

    let width: Int
    let height: Int
    let bytesPerRow: Int
    let texture: MTLTexture

    init?(device: MTLDevice, width: Int, height: Int) {
        let bytesPerPixel = 4
        let pixelRowAlignment = device.minimumLinearTextureAlignment(for: .bgra8Unorm)
        let bytesPerRow = alignUp(size: width * bytesPerPixel, align: pixelRowAlignment)

        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow

        self.buffer = nil

        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2D
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.width = width
        textureDescriptor.height = height
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        textureDescriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }

        self.texture = texture

        self.clear()
    }

    func clear() {
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: self.width, height: self.height, depth: 1)
        )
        let data = Data(capacity: Int(self.bytesPerRow * self.height))
        if let bytes = data.withUnsafeBytes({ $0.baseAddress }) {
            self.texture.replace(region: region, mipmapLevel: 0, withBytes: bytes, bytesPerRow: self.bytesPerRow)
        }
    }

    func createCGImage() -> CGImage? {
        let dataProvider: CGDataProvider

        guard let data = NSMutableData(capacity: self.bytesPerRow * self.height) else {
            return nil
        }
        data.length = self.bytesPerRow * self.height
        self.texture.getBytes(data.mutableBytes, bytesPerRow: self.bytesPerRow, bytesPerImage: self.bytesPerRow * self.height, from: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: self.width, height: self.height, depth: 1)), mipmapLevel: 0, slice: 0)

        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        dataProvider = provider

        guard let image = CGImage(
            width: Int(self.width),
            height: Int(self.height),
            bitsPerComponent: 8,
            bitsPerPixel: 8 * 4,
            bytesPerRow: self.bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: DeviceGraphicsContextSettings.shared.transparentBitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return image
    }
}

public struct DeviceGraphicsContextSettings {
    public static let shared: DeviceGraphicsContextSettings = getSharedDevideGraphicsContextSettings()

    public let rowAlignment: Int
    public let bitsPerPixel: Int
    public let bitsPerComponent: Int
    public let opaqueBitmapInfo: CGBitmapInfo
    public let transparentBitmapInfo: CGBitmapInfo
    public let colorSpace: CGColorSpace

    public func bytesPerRow(forWidth width: Int) -> Int {
        let baseValue = self.bitsPerPixel * width / 8
        return (baseValue + 31) & ~0x1F
    }
}

public func getSharedDevideGraphicsContextSettings() -> DeviceGraphicsContextSettings {
    struct OpaqueSettings {
        let rowAlignment: Int
        let bitsPerPixel: Int
        let bitsPerComponent: Int
        let opaqueBitmapInfo: CGBitmapInfo
        let colorSpace: CGColorSpace

        init(context: CGContext) {
            self.rowAlignment = context.bytesPerRow
            self.bitsPerPixel = context.bitsPerPixel
            self.bitsPerComponent = context.bitsPerComponent
            self.opaqueBitmapInfo = context.bitmapInfo
            if #available(iOS 10.0, *) {
                if UIScreen.main.traitCollection.displayGamut == .P3 {
                    self.colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? context.colorSpace!
                } else {
                    self.colorSpace = context.colorSpace!
                }
            } else {
                self.colorSpace = context.colorSpace!
            }
            assert(self.rowAlignment == 32)
            assert(self.bitsPerPixel == 32)
            assert(self.bitsPerComponent == 8)
        }
    }

    struct TransparentSettings {
        let transparentBitmapInfo: CGBitmapInfo

        init(context: CGContext) {
            self.transparentBitmapInfo = context.bitmapInfo
        }
    }

    var opaqueSettings: OpaqueSettings?
    var transparentSettings: TransparentSettings?

    if #available(iOS 10.0, *) {
        let opaqueFormat = UIGraphicsImageRendererFormat()
        let transparentFormat = UIGraphicsImageRendererFormat()
        if #available(iOS 12.0, *) {
            opaqueFormat.preferredRange = .standard
            transparentFormat.preferredRange = .standard
        }
        opaqueFormat.opaque = true
        transparentFormat.opaque = false

        let opaqueRenderer = UIGraphicsImageRenderer(bounds: CGRect(origin: CGPoint(), size: CGSize(width: 1.0, height: 1.0)), format: opaqueFormat)
        let _ = opaqueRenderer.image(actions: { context in
            opaqueSettings = OpaqueSettings(context: context.cgContext)
        })

        let transparentRenderer = UIGraphicsImageRenderer(bounds: CGRect(origin: CGPoint(), size: CGSize(width: 1.0, height: 1.0)), format: transparentFormat)
        let _ = transparentRenderer.image(actions: { context in
            transparentSettings = TransparentSettings(context: context.cgContext)
        })
    } else {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 1.0, height: 1.0), true, 1.0)
        let refContext = UIGraphicsGetCurrentContext()!
        opaqueSettings = OpaqueSettings(context: refContext)
        UIGraphicsEndImageContext()

        UIGraphicsBeginImageContextWithOptions(CGSize(width: 1.0, height: 1.0), false, 1.0)
        let refCtxTransparent = UIGraphicsGetCurrentContext()!
        transparentSettings = TransparentSettings(context: refCtxTransparent)
        UIGraphicsEndImageContext()
    }

    return DeviceGraphicsContextSettings(
        rowAlignment: opaqueSettings!.rowAlignment,
        bitsPerPixel: opaqueSettings!.bitsPerPixel,
        bitsPerComponent: opaqueSettings!.bitsPerComponent,
        opaqueBitmapInfo: opaqueSettings!.opaqueBitmapInfo,
        transparentBitmapInfo: transparentSettings!.transparentBitmapInfo,
        colorSpace: opaqueSettings!.colorSpace
    )
}
