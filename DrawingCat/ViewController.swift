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
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var layout: UICollectionViewFlowLayout!
    private let image = UIImage(named: "2.jpg")!

    var drawingView: DrawingView?
    var currentToolState: DrawingToolState = .pen(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xff453a), size: 0.23))
    lazy var dataSource: [(String, DrawingToolState)] = {
        var array = [(String, DrawingToolState)]()
        let tools: [DrawingToolState] = [
            .eraser(DrawingToolState.EraserState(size: 0.5)),
            .pen(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xff453a), size: 0.23)),
            .arrow(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xff8a00), size: 0.23)),
            .pen(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xff453a), size: 0.23, images: [UIImage(named: "pencil")])),
            .marker(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.2)),
            .dash(DrawingToolState.BrushState(color: DrawingColor(color: .white), size: 0.2)),
            .marker(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.2, images: [UIImage(named: "dash")], dashSize: 0.5)),
            .chartlet(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.3)),
            .neon(DrawingToolState.BrushState(color: DrawingColor(rgb: 0x34c759), size: 0.4)),
            .rainbow(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.2)),
            .rainbow(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.2, images: [UIImage(named: "rainbow02")])),
            .rainbow(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.2, images: [UIImage(named: "rainbow03")])),
            .chartlet(DrawingToolState.BrushState(color: DrawingColor(rgb: 0xffd60a), size: 0.2, images: [UIImage(named: "brush01"), UIImage(named: "brush02"), UIImage(named: "brush03"), UIImage(named: "brush04")], dashSize: 0)),
            .blur(DrawingToolState.EraserState(size: 0.5))
        ]
        let titles: [String] =  [
            "eraser",
            "pen",
            "arrow",
            "pencil",
            "marker",
            "dash",
            "dash_circle",
            "chartlet",
            "neon",
            "rainbow1",
            "rainbow2",
            "rainbow3",
            "more chartlet",
            "blur"
        ]

        for (index, title) in titles.enumerated() {
            let tool = tools[index]
            array.append((title, tool))
        }

        return array
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()


        imageview.image = image

        let size = caculateImageSize()
        let drawingView = DrawingView(size: image.size)

        heightConstraint.constant = size.height
        widthConstraint.constant = size.width

        if dataSource.count > 1 {
            currentToolState = dataSource[1].1
        }

        let origin = CGPoint(x: imageview.frame.center.x - size.width/2, y: imageview.frame.center.y - size.height/2)
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

        self.drawingView = drawingView

        let nib = UINib(nibName: "PenCell", bundle: nil)
        collectionView.register(nib, forCellWithReuseIdentifier: "PenCell")
        collectionView.dataSource = self
        collectionView.delegate = self

        updateSliderValue()
        drawingView.updateToolState(currentToolState)
    }


    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = caculateImageSize()
        let origin = CGPoint(x: imageview.frame.center.x - size.width/2, y: imageview.frame.center.y - size.height/2)
        self.drawingView?.frame = CGRect(origin: origin, size: size)
    }


    func updateSliderValue() {
        if let size = currentToolState.size {
            slider.value = Float(size * 100)
        }
    }

    @IBAction func onSlider(_ sender: UISlider) {
        currentToolState = currentToolState.withUpdatedSize(CGFloat(sender.value / 100))
        DispatchQueue.main.async {
            self.drawingView?.updateToolState(self.currentToolState)
        }
    }

    private func caculateImageSize() -> CGSize {
        let screenWidth = UIScreen.main.bounds.width - 40
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

extension ViewController: UICollectionViewDelegateFlowLayout {
    public func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView.frame.size == .zero {
            return CGSize.zero
        }

        let height = 50
        return CGSize(width: height, height: height)
    }
}

extension ViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        return dataSource.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "PenCell", for: indexPath) as! PenCell
        let item = dataSource[indexPath.item]
        cell.titleLabel.text = item.0
        cell.hasSelected = item.1 == currentToolState
        return cell
    }

    public func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = dataSource[indexPath.item]
        let state: DrawingToolState = item.1
        currentToolState = state
        drawingView?.updateToolState(state)
        updateSliderValue()
        collectionView.reloadData()
    }
}
