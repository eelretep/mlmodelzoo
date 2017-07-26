//
//  VisualizationView.swift
//  SimpleSample
//
//  Created by Peter Lee on 7/26/17.
//  Copyright © 2017 MLModelZoo. All rights reserved.
//

import UIKit

private struct ColorBox {
    let bounds: CGRect
    let borderColor: UIColor
    let borderWidth: CGFloat
    let text: String
    let timeShown: Date
}

class VisualizationView: UIView {
    
    private var boxes = [ColorBox]()
    private let capacity = 10
    private let defaultBorderColor = UIColor.red
    private let defaultBorderWidth: CGFloat = 5.0
    private var textAttributes: [NSAttributedStringKey:Any]?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        // text attributes for box text
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black
        shadow.shadowOffset = CGSize(width: -1, height: -1)
        textAttributes = [
            NSAttributedStringKey.font: UIFont.preferredFont(forTextStyle: .title3),
            NSAttributedStringKey.foregroundColor : UIColor.white,
            NSAttributedStringKey.shadow : shadow
        ]
    }
    
    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()!
        
        for box in boxes
        {
            ctx.addRect(box.bounds)
            ctx.setStrokeColor(box.borderColor.cgColor)
            ctx.setLineWidth(box.borderWidth)
            
            ctx.strokePath()
    
            let stringSize = box.text.size(withAttributes: textAttributes)
            let textOrigin = CGPoint(x: box.bounds.midX - stringSize.width/2, y: box.bounds.origin.y - stringSize.height)
            let textRect = CGRect(origin: textOrigin, size:stringSize)
            box.text.draw(in:textRect, withAttributes: textAttributes)
        }
    }
    
    func addBox(bounds: CGRect, classLabel: String, score: Float)
    {
        let borderColor = classLabel.count > 0 ? randomColor(seed: classLabel) : defaultBorderColor
        let borderWidth = max(CGFloat(score) * defaultBorderWidth, 1)
        let displayLabel = classLabel
        let colorBox = ColorBox(bounds: bounds, borderColor: borderColor, borderWidth: borderWidth, text: displayLabel, timeShown:Date())
        boxes.insert(colorBox, at: 0)
        
        let overCapacity = boxes.count - capacity
        if overCapacity > 0
        {
            boxes.removeLast(overCapacity)
        }
        
        setNeedsDisplay()
    }
    
    func decayStep()
    {
        if let last = boxes.last, Date().timeIntervalSince(last.timeShown) > 1
        {
            boxes.removeLast()
            setNeedsDisplay()
        }
    }
    
    func clearBoxes()
    {
        boxes.removeAll()
        
        setNeedsDisplay()
    }
}
