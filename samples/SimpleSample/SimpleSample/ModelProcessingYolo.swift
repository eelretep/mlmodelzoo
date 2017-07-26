//
//  ModelProcessingYolo.swift
//  SimpleSample
//
//  Created by Peter Lee on 7/26/17.
//  Copyright © 2017 MLModelZoo. All rights reserved.
//

import UIKit
import Vision

func sigmoid(_ x: Float) -> Float
{
    return 1.0 / (1 + expf(-x))
}

private struct PredictionBox
{
    var x: Float
    var y: Float
    var w: Float
    var h: Float
    var c: Float
    var rect: CGRect
    var classIndex: Int
    var classProb: Float
    var score: Float
    
    init(data: UnsafeMutablePointer<Double>, stride:Int, cx: Float, cy: Float, pw: Float, ph: Float) {
        let tx = Float(data[0])
        let ty = Float(data[1*stride])
        let tw = Float(data[2*stride])
        let th = Float(data[3*stride])
        let to = Float(data[4*stride])
        
        let W_f = Float(YoloTiny.W)
        let H_f = Float(YoloTiny.H)
        
        self.x = (sigmoid(tx) + cx) / W_f
        self.y = (sigmoid(ty) + cy) / H_f
        self.w = pw * exp(tw) / W_f
        self.h = ph * exp(th) / H_f
        self.c = sigmoid(to)
        
        let left = x - w/2
        let right = x + w/2
        let top = y - h/2
        let bot = y + h/2
        self.rect = CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(right - left), height: CGFloat(bot - top))
        
        var bestClassIndex: Int = 0
        var maxClassLogit: Float = -Float.greatestFiniteMagnitude
        var logits = [Float](repeating: 0, count:YoloTiny.C)
        for i in 0..<YoloTiny.C {
            let logit = Float(data[(i+5)*stride])
            if logit > maxClassLogit {
                bestClassIndex = i
                maxClassLogit = logit
            }
            logits[i] = logit
        }
        // softmax the highest class
        var sum_e: Float = 0
        for i in 0..<YoloTiny.C {
            sum_e = sum_e + exp(logits[i] - maxClassLogit)
        }
        self.classProb = 1 / sum_e
        self.classIndex = bestClassIndex
        self.score = self.classProb * self.c
    }
    
    func rectIntoAspectFilledBounds(_ bounds: CGRect) -> CGRect {
        // going from normalized square coordinates to aspect fill coordinates
        let width = bounds.size.width
        let height = bounds.size.height
        let aspect_ratio = width / height
        let maxDim = max(width, height)

        var x_offset: CGFloat = 0
        var y_offset: CGFloat = 0
        if aspect_ratio < 1 {
            x_offset = (height - width) / 2
        } else {
            y_offset = (width - height) / 2
        }

        let x_afcoord = Int(self.rect.origin.x * maxDim - x_offset)
        let y_afcoord = Int(self.rect.origin.y * maxDim - y_offset)
        let width_afcoord = Int(self.rect.width * maxDim)
        let height_afcoord = Int(self.rect.height * maxDim)
        
        let rect_afcoord = CGRect(x: x_afcoord, y: y_afcoord, width: width_afcoord, height: height_afcoord).intersection(bounds)
    
        return rect_afcoord
    }
}

class YoloTiny {
    static let H: Int = 13 // grid size
    static let W: Int = 13 // grid size
    static let B: Int = 5;  // boxes per grid cell
    static let scoreThreshold: Float = 0.3
    static let iouThreshold: Float = 0.5
    static let maxBoxes = 10
    static let C: Int = 80 // coco classes
    static let classLabels = ["person", "bicycle", "car", "motorbike", "aeroplane", "bus", "train", "truck", "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "sofa", "pottedplant", "bed", "diningtable", "toilet", "tvmonitor", "laptop", "mouse", "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"]
    static let priors: [Float] = [0.738768,0.874946,  2.42204,2.65704,  4.30971,7.04493,  10.246,4.59428,  12.6868,11.8741]
    //static let C: Int = 20 // voc classes
    //static let classLabels = ["airplane", "bicycle", "bird", "boat", "bottle", "bus", "car", "cat", "chair", "cow", "dining table", "dog", "horse", "motorbike", "person", "potted plant", "sheep", "sofa", "train", "tv monitor"]
    //static let priors: [Float] = [1.08,1.19,  3.42,4.41,  6.63,11.38,  9.42,5.11,  16.62,10.52]
    
    static func postprocess(multiArray: MLMultiArray, intoView view: VisualizationView)
    {
        // B ∗ (5 + C) x H × W = (125, 13, 13)
        let channel_stride = multiArray.strides[0].intValue
        let row_stride = multiArray.strides[1].intValue
        let col_stride = multiArray.strides[2].intValue
        let box_stride = (5 + C) * channel_stride
        let data = UnsafeMutablePointer<Double>(OpaquePointer(multiArray.dataPointer))
        
        var boxes = [PredictionBox]()
        for b in 0..<YoloTiny.B {
            for row in 0..<YoloTiny.H {
                let cy = Float(row)
                for col in 0..<YoloTiny.W {
                    let cx = Float(col)
                    let offset = b * box_stride + (row * row_stride) + (col * col_stride)
                    let bx = PredictionBox(data: data + offset, stride: channel_stride, cx: cx, cy: cy, pw: priors[2 * b], ph:priors[2 * b + 1])
                    if bx.score > scoreThreshold {
                        boxes.append(bx)
                    }
                }
            }
        }
        
        boxes = nonMaxSuppression(boxes: boxes)
        
        DispatchQueue.main.async {
            for bx in boxes {
                let rect = bx.rectIntoAspectFilledBounds(view.bounds)
                view.addBox(bounds: rect, classLabel: classLabels[bx.classIndex], score: bx.score)
            }
        }
    }
    
    private static func nonMaxSuppression(boxes: [PredictionBox]) -> [PredictionBox] {
        var sortedBoxes = boxes.sorted {
            return $0.score > $1.score
        }
        
        var filteredBoxes = [PredictionBox]()
        while !sortedBoxes.isEmpty {
            let topBox = sortedBoxes.removeFirst()
            
            var indexesToRemove = [Int]()
            for (i, box) in sortedBoxes.enumerated() {
                if IOU(topBox.rect, box.rect) > CGFloat(YoloTiny.iouThreshold) {
                    indexesToRemove.append(i)
                }
            }
            for i in indexesToRemove.reversed() {
                sortedBoxes.remove(at: i)
            }
            
            filteredBoxes.append(topBox)
            if filteredBoxes.count >= YoloTiny.maxBoxes {
                break
            }
        }
        
        return filteredBoxes
    }
}
