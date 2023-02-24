//
//  ChartletBrush.swift
//  DrawingCat
//
//  Created by roni on 2023/2/9.
//

import Foundation
import Metal

/// Printer is a special brush witch can print images to canvas
class Printer: Brush {
    var offset: CGFloat = 0
    convenience public init(texture: MTLTexture?, target: DrawingMetalView, rotation: Rotation, offset: CGFloat = 0) {
        self.init(texture: texture, target: target, rotation: rotation, dashSize: nil)
        self.offset = offset
    }

    /// make shader vertex function from the library made by makeShaderLibrary()
    /// overrides to provide your own vertex function
    public override func makeShaderVertexFunction(from target: MTLLibrary) -> MTLFunction? {
        return target.makeFunction(name: "vertex_printer_func")
    }

    /// make shader fragment function from the library made by makeShaderLibrary()
    /// overrides to provide your own fragment function
    public override func makeShaderFragmentFunction(from target: MTLLibrary) -> MTLFunction? {
        return target.makeFunction(name: "fragment_render_target")
    }

    /// Blending options for this brush, overrides to implement your own blending options
    public override func setupBlendOptions(for attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        attachment.isBlendingEnabled = true

        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add

        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.sourceAlphaBlendFactor = .one

        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    override func getPointSize(size: CGFloat) -> CGFloat {
        return size
    }

    override func getPointStep(size: CGFloat) -> CGFloat {
        return getPointSize(size: size) * (1 + offset)
    }

    internal func render(chartlet: Chartlet, on drawable: Drawable? = nil) {

        guard let target = drawable ?? self.target?.drawable else {
            return
        }

        /// make sure reusable command buffer is ready
        target.prepareForDraw()

        /// get commandEncoder form resuable command buffer
        let commandEncoder = target.makeCommandEncoder()

        commandEncoder?.setRenderPipelineState(pipelineState)

        if let vertex_buffer = chartlet.vertex_buffer, let texture = self.target?.findTexture(by: chartlet.textureID)?.texture {
            commandEncoder?.setVertexBuffer(vertex_buffer, offset: 0, index: 0)
            commandEncoder?.setVertexBuffer(target.uniform_buffer, offset: 0, index: 1)
            commandEncoder?.setVertexBuffer(target.transform_buffer, offset: 0, index: 2)
            commandEncoder?.setFragmentTexture(texture, index: 0)
            commandEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        commandEncoder?.endEncoding()
    }
}

/// A Brush that can draw specified chartlets on canvas
class ChartletBrush: Printer {
    var textures: [MLTexture] = []
    var renderStyle = 0

    convenience public init(
        name: String?,
        textures: [MLTexture],
        renderStyle: Int = 0,
        target: DrawingMetalView,
        rotation: Rotation,
        offset: CGFloat
    ) {
        guard !textures.isEmpty else {
            fatalError("there are not textures.")
        }

        var currentTexture: MLTexture?
        if renderStyle == 0 {
            currentTexture = textures[0]
        } else {
            currentTexture = textures.randomElement()
        }

        self.init(texture: currentTexture?.texture, target: target, rotation: rotation, offset: offset)
        self.textures = textures
        self.renderStyle = renderStyle
    }

    private var lastTextureIndex = 0

    func reset() {
        lastTextureIndex = 0
    }

    private var nextIndex: Int {
        var index = lastTextureIndex + 1
        if index >= textures.count {
            index = 0
        }
        return index
    }

    open func nextTextureID() -> String {
        if renderStyle == 0 {
            let index = nextIndex
            let texture = textures[index]
            lastTextureIndex = index
            return texture.id
        } else {
            return textures.randomElement()!.id
        }
    }


    override func render(lines: [Line], color: DrawingColor, pointSize: CGFloat, on canvas: DrawingMetalView?) {
        lines.forEach { (line) in
            let step = max(1, line.pointStep)
            let count = max(line.length / step, 1)

            for i in 0 ..< Int(count) {
                let index = CGFloat(i)
                let x = line.start.x + (line.end.x - line.start.x) * (index / count)
                let y = line.start.y + (line.end.y - line.start.y) * (index / count)

                var angle: CGFloat = 0
                switch rotation {
                case let .fixed(a): angle = a
                case .random: angle = CGFloat.random(in: -CGFloat.pi ... CGFloat.pi)
                case .ahead: angle = line.angle
                }

                let size = getPointSize(size: pointSize)
                canvas?.renderChartlet(at: CGPoint(x: x, y: y), size: CGSize(width: size, height: size), textureID: nextTextureID(), rotation: angle)
            }
        }
    }
}
