//
//  RainbowBrush.swift
//  DrawingKit
//
//  Created by roni on 2023/2/20.
//

import Foundation
import Metal

/// Printer is a special brush witch can print images to canvas
class RainbowBrush: Brush {
    /// make shader fragment function from the library made by makeShaderLibrary()
    /// overrides to provide your own fragment function
    public override func makeShaderFragmentFunction(from target: MTLLibrary) -> MTLFunction? {
        return target.makeFunction(name: "fragment_point_func_noclor")
    }

    override func getPointSize(size: CGFloat) -> CGFloat {
        return size
    }

    override func getPointStep(size: CGFloat) -> CGFloat {
        return size * 0.02
    }
}
