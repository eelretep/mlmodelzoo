//
//  Utilities.swift
//  SimpleSample
//
//  Created by Peter Lee on 7/20/17.
//  Copyright © 2017 MLModelZoo. All rights reserved.
//

import UIKit

extension UIImage {
    func resizedImage(width:Int, height:Int) -> UIImage {
        var resizedImage = self
        let newSize = CGSize(width: width, height: height)
        
        if (size != newSize) {
            let hasAlpha = false
            let scale: CGFloat = 0.0 // Automatically use scale factor of main screen
            
            UIGraphicsBeginImageContextWithOptions(newSize, !hasAlpha, scale)
            draw(in: CGRect(origin: CGPoint(), size: newSize))
            
            if let scaledImage = UIGraphicsGetImageFromCurrentImageContext() {
                resizedImage = scaledImage
            }
        }
        
        return resizedImage
    }
    
    func cgImagePropertyOrientation() -> CGImagePropertyOrientation {
        var cgOrientation: CGImagePropertyOrientation = .up
        switch imageOrientation {
        case .up:
            cgOrientation = .up
        case .down:
            cgOrientation = .down
        case .left:
            cgOrientation = .left
        case .right:
            cgOrientation = .right
        case .upMirrored:
            cgOrientation = .upMirrored
        case .downMirrored:
            cgOrientation = .downMirrored
        case .leftMirrored:
            cgOrientation = .leftMirrored
        case .rightMirrored:
            cgOrientation = .rightMirrored
        }
        
        return cgOrientation
    }
}

public func pixelBufferBGRToImage(_ pixelBuffer: CVPixelBuffer, width outWidth: Int, height outHeight: Int, orientation: UIImageOrientation) -> UIImage? {
    var uiImage: UIImage?
    let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
    assert(format == kCVPixelFormatType_32BGRA)
    
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    let data = CVPixelBufferGetBaseAddress(pixelBuffer)!
    
    if let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue) { // BGRA
        if let cgImage = context.makeImage() {
            uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: orientation).resizedImage(width: outWidth, height: outHeight)
        }
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    
    return uiImage
}

public func CGImageToPixelBufferRGB(_ image: CGImage, width outWidth: Int, height outHeight: Int) -> CVPixelBuffer?
{
    var pixelBuffer: CVPixelBuffer?
    if kCVReturnSuccess == CVPixelBufferCreate(kCFAllocatorDefault, outWidth, outHeight, kCVPixelFormatType_32ARGB, nil, &pixelBuffer) {
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer!)
        
        CVPixelBufferLockBaseAddress(pixelBuffer!, .readOnly);
        let data = CVPixelBufferGetBaseAddress(pixelBuffer!)
        
        if let context = CGContext(data: data, width: outWidth, height: outHeight, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue) { // ARGB
            context.draw(image, in: CGRect(x:0, y:0, width:outWidth, height:outHeight))
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, .readOnly);
    }
    
    return pixelBuffer
}
