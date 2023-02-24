//
//  SimpleLayer.swift
//  DrawingCat
//
//  Created by roni on 2023/2/7.
//

import UIKit

public final class NullActionClass: NSObject, CAAction {
    @objc public func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable : Any]?) {
    }
}

public let nullAction = NullActionClass()

open class SimpleShapeLayer: CAShapeLayer {
    public var didEnterHierarchy: (() -> Void)?
    public var didExitHierarchy: (() -> Void)?

    override open func action(forKey event: String) -> CAAction? {
        if event == kCAOnOrderIn {
            self.didEnterHierarchy?()
        } else if event == kCAOnOrderOut {
            self.didExitHierarchy?()
        }
        return nullAction
    }

    override public init() {
        super.init()
    }

    override public init(layer: Any) {
        super.init(layer: layer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
