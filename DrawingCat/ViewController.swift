//
//  ViewController.swift
//  DrawingCat
//
//  Created by roni on 2023/2/6.
//

import UIKit
import DrawingKit

class ViewController: UIViewController {

    @IBOutlet weak var imageview: UIImageView!
    @IBOutlet weak var heightConstraint: NSLayoutConstraint!
    @IBOutlet weak var widthConstraint: NSLayoutConstraint!
    @IBOutlet weak var slider: UISlider!
    @IBOutlet weak var seg01: UISegmentedControl!
    @IBOutlet weak var seg02: UISegmentedControl!
    private let image = UIImage(named: "2.jpg")!

    var tools = DrawingState.initial
    var drawingView: DrawingView?
    var currentToolState: DrawingToolState = .pen(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xff453a), size: 0.23))
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tools = tools.appendTool(.marker(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.2, images: [UIImage(named: "dash")], dashSize: 0.5)))
        tools = tools.appendTool(.chartlet(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.2, images: [UIImage(named: "brush01"), UIImage(named: "brush02"), UIImage(named: "brush03"), UIImage(named: "brush04")], dashSize: 0)))
        tools = tools.appendTool(.dash(DrawingToolState.BrushState(color: DrawingColor(color: .white), size: 0.2)))

        imageview.image = image

        let size = caculateImageSize()
        let drawingView = DrawingView(size: image.size)

        let origin = CGPoint(x: (UIScreen.main.bounds.width - size.width)/2, y: (UIScreen.main.bounds.height - size.height)/2)
//        imageview.frame = CGRect(origin: origin, size: size)
        heightConstraint.constant = size.height
        widthConstraint.constant = size.width

        drawingView.frame = CGRect(origin: origin, size: size)
        view.addSubview(drawingView)

        drawingView.stateUpdated = { state in

        }
        drawingView.getFullImage = { [weak self] in
            guard let self = self else {
                return nil
            }

            let newSize = size.fitted(CGSize(width: 256.0, height: 256.0))
            if let imageContext = DrawingContext(size: newSize, scale: 1.0, opaque: true, clear: false) {
                imageContext.withFlippedContext { c in
                    
                    let bounds = CGRect(origin: .zero, size: size)
                    if let cgImage = self.image.cgImage {
                        c.draw(cgImage, in: bounds)
                    }
                    if let cgImage = drawingView.drawingImage?.cgImage {
                        c.draw(cgImage, in: bounds)
                    }
                    
                    fastBlurMore(imageWidth: Int32(imageContext.size.width * imageContext.scale), imageHeight: Int32(imageContext.size.height * imageContext.scale), imageStride: Int32(imageContext.bytesPerRow), pixels: imageContext.bytes)
                    fastBlurMore(imageWidth: Int32(imageContext.size.width * imageContext.scale), imageHeight: Int32(imageContext.size.height * imageContext.scale), imageStride: Int32(imageContext.bytesPerRow), pixels: imageContext.bytes)
                }

                return imageContext.generateImage()
            } else {
                return nil
            }

        }


        if let size = currentToolState.size {
            slider.value = Float(size * 100)
        }
        self.drawingView = drawingView
        seg02.selectedSegmentIndex = seg02.numberOfSegments - 1
    }

    @IBAction func changeSegmentControl(_ sender: UISegmentedControl) {
        let state: DrawingToolState? = tools.toolState(for: sender.selectedSegmentIndex)
        if let state = state {
            currentToolState = state
            DispatchQueue.main.async {
                self.drawingView?.updateToolState(state)
            }
        }
    }

    @IBAction func changeSegmentControl02(_ sender: UISegmentedControl) {
        let state: DrawingToolState? = tools.toolState(for: sender.selectedSegmentIndex + 8)
        if let state = state {
            currentToolState = state
            DispatchQueue.main.async {
                self.drawingView?.updateToolState(state)
            }
        }
    }

    @IBAction func onSlider(_ sender: UISlider) {
        currentToolState = currentToolState.withUpdatedSize(CGFloat(sender.value / 100))
        DispatchQueue.main.async {
            self.drawingView?.updateToolState(self.currentToolState)
        }
    }

    private func caculateImageSize() -> CGSize {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height - 300
        var width = screenWidth
        var height = screenHeight
        if image.size.width == 0 || image.size.height == 0 {
            return CGSize(width: width, height: height)
        }
        let ratio = image.size.width / image.size.height
        let theight = width / ratio
        if theight <= screenHeight {
            height = theight
        } else {
            width = height * ratio
        }
        return CGSize(width: width, height: height)
    }
}

