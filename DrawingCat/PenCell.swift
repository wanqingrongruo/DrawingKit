//
//  PenCell.swift
//  DrawingCat
//
//  Created by roni on 2023/2/24.
//

import UIKit

class PenCell: UICollectionViewCell {

    @IBOutlet weak var titleLabel: UILabel!
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    var hasSelected: Bool = false {
        didSet {
            contentView.layer.borderColor = UIColor.red.cgColor
            contentView.layer.borderWidth = hasSelected ? 2 : 0
        }
    }
}
