//
//  GenerateImage.swift
//  DrawingCat
//
//  Created by roni on 2023/2/7.
//

import Foundation
import UIKit
import Accelerate
import CoreMedia
@_implementationOnly import mapoc

let deviceScale = UIScreen.main.scale

public enum DrawingContextBltMode {
    case Alpha
}

public func generateImage(_ size: CGSize, contextGenerator: (CGSize, CGContext) -> Void, opaque: Bool = false, scale: CGFloat? = nil) -> UIImage? {
    if size.width.isZero || size.height.isZero {
        return nil
    }
    guard let context = DrawingContext(size: size, scale: scale ?? 0.0, opaque: opaque, clear: false) else {
        return nil
    }
    context.withFlippedContext { c in
        contextGenerator(context.size, c)
    }
    return context.generateImage()
}

// 加速模糊
public func fastBlurMore(imageWidth: Int32, imageHeight: Int32, imageStride: Int32, pixels: UnsafeMutableRawPointer) {
    telegramFastBlurMore(imageWidth, imageHeight, imageStride, pixels)
}

public class DrawingContext {
    public let size: CGSize
    public let scale: CGFloat
    public let scaledSize: CGSize
    public let bytesPerRow: Int
    private let bitmapInfo: CGBitmapInfo
    public let length: Int
    private let imageBuffer: ASCGImageBuffer
    public var bytes: UnsafeMutableRawPointer {
        if self.hasGeneratedImage {
            preconditionFailure()
        }
        return self.imageBuffer.mutableBytes
    }
    private let context: CGContext

    private var hasGeneratedImage = false

    public func withContext(_ f: (CGContext) -> ()) {
        let context = self.context

        context.translateBy(x: self.size.width / 2.0, y: self.size.height / 2.0)
        context.scaleBy(x: 1.0, y: -1.0)
        context.translateBy(x: -self.size.width / 2.0, y: -self.size.height / 2.0)

        f(context)

        context.translateBy(x: self.size.width / 2.0, y: self.size.height / 2.0)
        context.scaleBy(x: 1.0, y: -1.0)
        context.translateBy(x: -self.size.width / 2.0, y: -self.size.height / 2.0)
    }

    public func withFlippedContext(_ f: (CGContext) -> ()) {
        f(self.context)
    }

    public init?(size: CGSize, scale: CGFloat = 0.0, opaque: Bool = false, clear: Bool = false, bytesPerRow: Int? = nil) {
        if size.width <= 0.0 || size.height <= 0.0 {
            return nil
        }

        assert(!size.width.isZero && !size.height.isZero)
        let size: CGSize = CGSize(width: max(1.0, size.width), height: max(1.0, size.height))

        let actualScale: CGFloat
        if scale.isZero {
            actualScale = deviceScale
        } else {
            actualScale = scale
        }
        self.size = size
        self.scale = actualScale
        self.scaledSize = CGSize(width: size.width * actualScale, height: size.height * actualScale)

        self.bytesPerRow = bytesPerRow ?? DeviceGraphicsContextSettings.shared.bytesPerRow(forWidth: Int(scaledSize.width))
        self.length = self.bytesPerRow * Int(scaledSize.height)

        self.imageBuffer = ASCGImageBuffer(length: UInt(self.length))

        if opaque {
            self.bitmapInfo = DeviceGraphicsContextSettings.shared.opaqueBitmapInfo
        } else {
            self.bitmapInfo = DeviceGraphicsContextSettings.shared.transparentBitmapInfo
        }

        guard let context = CGContext(
            data: self.imageBuffer.mutableBytes,
            width: Int(self.scaledSize.width),
            height: Int(self.scaledSize.height),
            bitsPerComponent: DeviceGraphicsContextSettings.shared.bitsPerComponent,
            bytesPerRow: self.bytesPerRow,
            space: DeviceGraphicsContextSettings.shared.colorSpace,
            bitmapInfo: self.bitmapInfo.rawValue,
            releaseCallback: nil,
            releaseInfo: nil
        ) else {
            return nil
        }
        self.context = context
        self.context.scaleBy(x: self.scale, y: self.scale)

        if clear {
            memset(self.bytes, 0, self.length)
        }
    }

    public func generateImage() -> UIImage? {
        if self.scaledSize.width.isZero || self.scaledSize.height.isZero {
            return nil
        }
        if self.hasGeneratedImage {
            preconditionFailure()
        }
        self.hasGeneratedImage = true

        let dataProvider = self.imageBuffer.createDataProviderAndInvalidate()

        if let image = CGImage(
            width: Int(self.scaledSize.width),
            height: Int(self.scaledSize.height),
            bitsPerComponent: self.context.bitsPerComponent,
            bitsPerPixel: self.context.bitsPerPixel,
            bytesPerRow: self.context.bytesPerRow,
            space: DeviceGraphicsContextSettings.shared.colorSpace,
            bitmapInfo: self.context.bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) {
            return UIImage(cgImage: image, scale: self.scale, orientation: .up)
        } else {
            return nil
        }
    }

    public func generatePixelBuffer() -> CVPixelBuffer? {
        if self.scaledSize.width.isZero || self.scaledSize.height.isZero {
            return nil
        }
        if self.hasGeneratedImage {
            preconditionFailure()
        }

        let ioSurfaceProperties = NSMutableDictionary()
        let options = NSMutableDictionary()
        options.setObject(ioSurfaceProperties, forKey: kCVPixelBufferIOSurfacePropertiesKey as NSString)

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreateWithBytes(nil, Int(self.scaledSize.width), Int(self.scaledSize.height), kCVPixelFormatType_32BGRA, self.bytes, self.bytesPerRow, { pointer, _ in
            if let pointer = pointer {
                Unmanaged<ASCGImageBuffer>.fromOpaque(pointer).release()
            }
        }, Unmanaged.passRetained(self.imageBuffer).toOpaque(), options as CFDictionary, &pixelBuffer)

        self.hasGeneratedImage = true

        return pixelBuffer
    }

    public func colorAt(_ point: CGPoint) -> UIColor {
        let x = Int(point.x * self.scale)
        let y = Int(point.y * self.scale)
        if x >= 0 && x < Int(self.scaledSize.width) && y >= 0 && y < Int(self.scaledSize.height) {
            let srcLine = self.bytes.advanced(by: y * self.bytesPerRow).assumingMemoryBound(to: UInt32.self)
            let pixel = srcLine + x
            let colorValue = pixel.pointee
            return UIColor(rgb: UInt32(colorValue))
        } else {
            return UIColor.clear
        }
    }

    public func blt(_ other: DrawingContext, at: CGPoint, mode: DrawingContextBltMode = .Alpha) {
        if abs(other.scale - self.scale) < CGFloat.ulpOfOne {
            let srcX = 0
            var srcY = 0
            let dstX = Int(at.x * self.scale)
            var dstY = Int(at.y * self.scale)
            if dstX < 0 || dstY < 0 {
                return
            }

            let width = min(Int(self.size.width * self.scale) - dstX, Int(other.size.width * self.scale))
            let height = min(Int(self.size.height * self.scale) - dstY, Int(other.size.height * self.scale))

            let maxDstX = dstX + width
            let maxDstY = dstY + height

            switch mode {
                case .Alpha:
                    while dstY < maxDstY {
                        let srcLine = other.bytes.advanced(by: max(0, srcY) * other.bytesPerRow).assumingMemoryBound(to: UInt32.self)
                        let dstLine = self.bytes.advanced(by: max(0, dstY) * self.bytesPerRow).assumingMemoryBound(to: UInt32.self)

                        var dx = dstX
                        var sx = srcX
                        while dx < maxDstX {
                            let srcPixel = srcLine + sx
                            let dstPixel = dstLine + dx

                            let baseColor = dstPixel.pointee
                            let baseAlpha = (baseColor >> 24) & 0xff
                            let baseR = (baseColor >> 16) & 0xff
                            let baseG = (baseColor >> 8) & 0xff
                            let baseB = baseColor & 0xff

                            let alpha = min(baseAlpha, srcPixel.pointee >> 24)

                            let r = (baseR * alpha) / 255
                            let g = (baseG * alpha) / 255
                            let b = (baseB * alpha) / 255

                            dstPixel.pointee = (alpha << 24) | (r << 16) | (g << 8) | b

                            dx += 1
                            sx += 1
                        }

                        dstY += 1
                        srcY += 1
                    }
            }
        }
    }
}
